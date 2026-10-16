// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CallOPToken
 * @dev 欧式看涨期权（Call Option）ERC20 代币合约
 *      标的资产（Underlying）：ETH
 *      计价资产（Quote）：ERC20 代币（如 MyERC20）
 *      1 个 CallOPToken 代表在到期日以行权价格（strikePrice）购买 1 个 ETH 的权利。
 */
contract CallOPToken is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice 计价 Token（如 MyERC20）
    IERC20 public immutable quoteToken;

    /// @notice 行权价格（每 1 ETH (1e18 wei) 所需的计价 Token 数量，按其自身精度表示，如 2000 * 1e18）
    uint256 public immutable strikePrice;

    /// @notice 行权开始时间戳（到期日开始时间）
    uint256 public immutable settlementTime;

    /// @notice 行权窗口持续时间（例如 1 天）
    uint256 public immutable settlementDuration;

    /// @notice 事件定义
    event Mint(address indexed projectOwner, uint256 ethAmount, uint256 tokenMinted);
    event Claim(address indexed user, uint256 ethExercised, uint256 quoteAmountPaid);
    event ExpiredBurnAndWithdraw(
        address indexed projectOwner,
        uint256 ethWithdrawn,
        uint256 quoteWithdrawn,
        uint256 optionsBurned
    );

    /// @notice 自定义错误
    error InvalidZeroAddress();
    error InvalidPrice();
    error InvalidSettlementTime();
    error InvalidDuration();
    error ZeroAmount();
    error SettlementStarted();
    error NotInSettlementWindow();
    error NotExpired();
    error InsufficientOptionBalance();
    error ETHTransferFailed();

    /**
     * @param _name 期权代币名称
     * @param _symbol 期权代币符号
     * @param _quoteToken 计价 Token 地址（如 MyERC20）
     * @param _strikePrice 行权价格（例如 2000 * 1e18 表示 2000 个计价Token / 1 ETH）
     * @param _settlementTime 到期行权日开始时间戳（秒）
     * @param _settlementDuration 行权窗口期持续秒数（例如 1 days = 86400）
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _quoteToken,
        uint256 _strikePrice,
        uint256 _settlementTime,
        uint256 _settlementDuration
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        if (_quoteToken == address(0)) revert InvalidZeroAddress();
        if (_strikePrice == 0) revert InvalidPrice();
        if (_settlementTime <= block.timestamp) revert InvalidSettlementTime();
        if (_settlementDuration == 0) revert InvalidDuration();

        quoteToken = IERC20(_quoteToken);
        strikePrice = _strikePrice;
        settlementTime = _settlementTime;
        settlementDuration = _settlementDuration;
    }

    /**
     * @notice mint 发行方法（项目方角色）
     * @dev 项目方存入标的（ETH），发行等量的看涨期权 CallOPToken
     *      只有在到期行权开始前可以发行
     */
    function mint() external payable onlyOwner {
        if (block.timestamp >= settlementTime) revert SettlementStarted();
        if (msg.value == 0) revert ZeroAmount();

        // 1 ETH (1e18 wei) 对应发行 1 CallOPToken (1e18 wei)
        _mint(msg.sender, msg.value);

        emit Mint(msg.sender, msg.value, msg.value);
    }

    /**
     * @notice claim 行权方法（用户角色）
     * @dev 在到期日当天，用户按指定行权价格支付计价 Token，兑换标的资产（ETH），并销毁其期权 Token
     * @param amount 行权数量（单位：wei，对应要行权的期权数量以及赎回的 ETH 数量）
     */
    function claim(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp < settlementTime || block.timestamp > settlementTime + settlementDuration) {
            revert NotInSettlementWindow();
        }
        if (balanceOf(msg.sender) < amount) revert InsufficientOptionBalance();

        // 计算需要支付的计价 Token 数量：amount * strikePrice / 1e18
        uint256 quoteAmount = calculateQuoteAmount(amount);

        // 1. 销毁用户的期权 Token
        _burn(msg.sender, amount);

        // 2. 从用户扣除计价 Token 转入合约存储
        quoteToken.safeTransferFrom(msg.sender, address(this), quoteAmount);

        // 3. 将标的资产 ETH 转给用户
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        emit Claim(msg.sender, amount, quoteAmount);
    }

    /**
     * @notice burn 过期销毁（项目方角色）
     * @dev 期权过期后，项目方销毁自身持有的所有期权 Token，并赎回未行权的标的资产（ETH）及收到的计价资产
     */
    function burn() external onlyOwner nonReentrant {
        if (block.timestamp <= settlementTime + settlementDuration) revert NotExpired();

        // 1. 销毁项目方持有的剩余期权 Token
        uint256 ownerOptions = balanceOf(msg.sender);
        if (ownerOptions > 0) {
            _burn(msg.sender, ownerOptions);
        }

        // 2. 赎回合约内剩余的全部标的 ETH
        uint256 remainingETH = address(this).balance;
        if (remainingETH > 0) {
            (bool success, ) = msg.sender.call{value: remainingETH}("");
            if (!success) revert ETHTransferFailed();
        }

        // 3. 将合约中已收到的计价 Token（行权收入）转给项目方
        uint256 quoteBalance = quoteToken.balanceOf(address(this));
        if (quoteBalance > 0) {
            quoteToken.safeTransfer(msg.sender, quoteBalance);
        }

        emit ExpiredBurnAndWithdraw(msg.sender, remainingETH, quoteBalance, ownerOptions);
    }

    /**
     * @notice 计算行权指定数量 ETH 所需的计价 Token
     * @param ethAmount 行权的 ETH 数量（wei）
     * @return 计价 Token 数量
     */
    function calculateQuoteAmount(uint256 ethAmount) public view returns (uint256) {
        return (ethAmount * strikePrice) / 1e18;
    }

    /**
     * @notice 查询当前是否处于行权窗口期
     */
    function isSettlementWindow() external view returns (bool) {
        return block.timestamp >= settlementTime && block.timestamp <= settlementTime + settlementDuration;
    }

    /**
     * @notice 查询期权是否已过期
     */
    function isExpired() external view returns (bool) {
        return block.timestamp > settlementTime + settlementDuration;
    }
}
