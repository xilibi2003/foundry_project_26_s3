// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@oz/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/contracts/token/ERC20/utils/SafeERC20.sol";


/**
 * @title ITokenReceiver
 * @dev 代币转账回调接收接口（配合 CalledToken / ERC1363 模式）
 */
interface ITokenReceiver {
    function tokensReceived(
        address from,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}

/**
 * @title TokenBank
 * @dev 允许存入和提取指定 ERC20 代币的银行合约
 * 扩展支持 ERC1363 风格的 transferAndCall 回调入账（tokensReceived）
 */
contract TokenBank is ITokenReceiver {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    // 记录每个用户存入的 token 数量
    mapping(address => uint256) public balances;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    /**
     * @param _tokenAddress 绑定的 ERC20 Token 地址
     */
    constructor(address _tokenAddress) {
        require(
            _tokenAddress != address(0),
            "TokenBank: token address cannot be zero"
        );
        token = IERC20(_tokenAddress);
    }

    /**
     * @notice 传统方式存款：用户先调用 Token 的 approve，再调用本 deposit 方法
     * @param amount 存入的代币数量（wei 单位）
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "TokenBank: deposit amount must be > 0");

        // 记账：增加用户在 TokenBank 中的存款
        balances[msg.sender] += amount;

        // 转账：从用户账户转入 TokenBank 合约 (使用 SafeERC20 兼容 USDT 等非标 ERC20)
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice 回调方式存款（一步存款）：由 CalledToken 的 transferAndCall 自动触发
     * @dev 安全要求：
     * 1. 严格校验 msg.sender 必须是绑定的 token 合约，防止非授权外部地址伪造存款
     * 2. 此时 token 已经通过 CalledToken 的 _transfer 进入 TokenBank，因此只需记账，不可再次 transferFrom
     * @param from 实际转出代币的用户地址（存款人）
     * @param amount 存入的代币数量
     * @param data 附加数据
     * @return 成功返回 true
     */
    function tokensReceived(
        address from,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        data; // 静音未使用变量警告
        return _handleTokensReceived(from, amount);
    }

    /**
     * @notice 重载兼容：支持两参数版本的 tokensReceived(address, uint256)
     */
    function tokensReceived(
        address from,
        uint256 amount
    ) external returns (bool) {
        return _handleTokensReceived(from, amount);
    }

    /**
     * @notice 别名兼容：支持 onTokensReceived 命名的回调
     */
    function onTokensReceived(
        address from,
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        data; // 静音未使用变量警告
        return _handleTokensReceived(from, amount);
    }

    /**
     * @dev 处理转账回调记账的核心内部函数
     */
    function _handleTokensReceived(
        address from,
        uint256 amount
    ) internal returns (bool) {
        // 关键安全校验：调用者必须是绑定的代币合约！

        require(
            msg.sender == address(token),
            "TokenBank: caller must be the bound token"
        );

        require(amount > 0, "TokenBank: deposit amount must be > 0");

        // 将存款记在实际扣款用户 from 名下
        balances[from] += amount;

        emit Deposit(from, amount);
        return true;
    }

    /**
     * @notice 用户提取自己之前存入的 token
     * @param amount 提取的代币数量（wei 单位）
     */
    function withdraw(uint256 amount) external {
        require(amount > 0, "TokenBank: withdraw amount must be > 0");
        require(
            balances[msg.sender] >= amount,
            "TokenBank: insufficient balance"
        );

        // 遵循 Checks-Effects-Interactions 原则
        balances[msg.sender] -= amount;

        // 转账：从 TokenBank 转回用户 (使用 SafeERC20 兼容 USDT 等非标 ERC20)
        token.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @notice 查询指定用户的存款总额
     * @param user 用户地址
     */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }
}
