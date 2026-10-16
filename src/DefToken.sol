// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title DefToken
 * @dev Rebase 型通缩 ERC20 代币，发行量每一年在上一年的基础上减少 1%
 * 1. rebase 方法进行通缩
 * 2. balanceOf() 反映通缩后的余额
 */
contract DefToken is IERC20, IERC20Metadata {
    string private _name;
    string private _symbol;
    uint8 public constant override decimals = 18;

    // 当前名义总发行量 (随 rebase 缩减)
    uint256 private _totalSupply;
    // 内部恒定总份额
    uint256 private _totalShares;

    // 用户内部份额
    mapping(address => uint256) private _shares;
    // 授权额度 (以名义 token 数量计)
    mapping(address => mapping(address => uint256)) private _allowances;

    // 上一次 rebase 的基准时间戳
    uint256 public lastRebaseTime;
    // 1 年的周期
    uint256 public constant REBASE_INTERVAL = 365 days;
    // 通缩比例：99 / 100 (每年在前一年基础上减少 1%)
    uint256 public constant DEFLATION_NUMERATOR = 99;
    uint256 public constant DEFLATION_DENOMINATOR = 100;

    // 事件
    event Rebase(uint256 indexed elapsedYears, uint256 newTotalSupply, uint256 timestamp);

    // 错误定义
    error InsufficientBalance();
    error InsufficientAllowance();
    error ZeroAddress();
    error RebaseNotDue();

    constructor(string memory tokenName, string memory tokenSymbol, uint256 initialSupply) {
        _name = tokenName;
        _symbol = tokenSymbol;

        uint256 supply = initialSupply * 10 ** decimals;
        _totalSupply = supply;
        _totalShares = supply;

        _shares[msg.sender] = _totalShares;
        lastRebaseTime = block.timestamp;

        emit Transfer(address(0), msg.sender, supply);
    }

    // ==========================================
    // ERC20 元数据与视图
    // ==========================================

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice 反映通缩后的名义余额
     * @dev balance = (shares * totalSupply) / totalShares
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (_totalShares == 0) return 0;
        return (_shares[account] * _totalSupply) / _totalShares;
    }

    /**
     * @notice 查询账户底层的内部 shares
     */
    function sharesOf(address account) external view returns (uint256) {
        return _shares[account];
    }

    /**
     * @notice 查询全网总 shares
     */
    function totalShares() external view returns (uint256) {
        return _totalShares;
    }

    // ==========================================
    // Rebase 核心通缩逻辑
    // ==========================================

    /**
     * @notice 执行 Rebase 通缩
     * @dev 至少经过 1 年方可触发，若超过多年未触发，支持按年复利计算
     * @return newSupply 缩减后的新总供应量
     */
    function rebase() external returns (uint256 newSupply) {
        uint256 timePassed = block.timestamp - lastRebaseTime;
        uint256 elapsedYears = timePassed / REBASE_INTERVAL;

        if (elapsedYears == 0) {
            revert RebaseNotDue();
        }

        uint256 currentSupply = _totalSupply;
        for (uint256 i = 0; i < elapsedYears; i++) {
            currentSupply = (currentSupply * DEFLATION_NUMERATOR) / DEFLATION_DENOMINATOR;
        }

        _totalSupply = currentSupply;
        lastRebaseTime += elapsedYears * REBASE_INTERVAL;

        emit Rebase(elapsedYears, currentSupply, block.timestamp);
        return currentSupply;
    }

    // ==========================================
    // ERC20 标准交互
    // ==========================================

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InsufficientAllowance();
            unchecked {
                _approve(from, msg.sender, currentAllowance - amount);
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    // ==========================================
    // 内部帮助函数
    // ==========================================

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();

        uint256 fromBalance = balanceOf(from);
        if (fromBalance < amount) revert InsufficientBalance();

        uint256 sharesToTransfer;
        if (amount == fromBalance) {
            // 全额转账时直接转移全部 shares，防止精度除法产生 dust 残留
            sharesToTransfer = _shares[from];
        } else {
            sharesToTransfer = getSharesByTokens(amount);
        }

        _shares[from] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;

        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @notice 名义 Token 转换为底层 Shares
     */
    function getSharesByTokens(uint256 tokenAmount) public view returns (uint256) {
        if (_totalSupply == 0) return 0;
        return (tokenAmount * _totalShares) / _totalSupply;
    }

    /**
     * @notice 底层 Shares 转换为名义 Token
     */
    function getTokensByShares(uint256 sharesAmount) public view returns (uint256) {
        if (_totalShares == 0) return 0;
        return (sharesAmount * _totalSupply) / _totalShares;
    }
}
