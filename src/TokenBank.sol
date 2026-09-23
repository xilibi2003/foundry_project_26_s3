// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@oz/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@oz/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@oz/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISignatureTransfer} from "./ISignatureTransfer.sol";


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
 * 扩展支持：
 * 1. ERC1363 风格的 transferAndCall 回调入账（tokensReceived）
 * 2. EIP-2612 permit 签名授权入账（permitDeposit）
 * 3. Uniswap Permit2 SignatureTransfer 签名授权入账（depositWithPermit2）
 */
contract TokenBank is ITokenReceiver {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    // Uniswap Permit2 官方合约地址（全网统一：0x000000000022D473030F116dDEE9F6B43aC78BA3）
    address public permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // 记录每个用户存入的 token 数量
    mapping(address => uint256) public balances;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Permit2AddressUpdated(address indexed oldPermit2, address indexed newPermit2);

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
     * @notice 设置自定义 permit2 合约地址
     * @param _permit2 新的 permit2 合约地址
     */
    function setPermit2(address _permit2) external {
        require(_permit2 != address(0), "TokenBank: zero permit2 address");
        emit Permit2AddressUpdated(permit2, _permit2);
        permit2 = _permit2;
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
     * @notice 通过 EIP-2612 permit 签名授权并完成存款（一步操作，调用方即为存款人）
     * @param amount 存入的代币数量
     * @param deadline 签名截止时间
     * @param v 签名参数 v
     * @param r 签名参数 r
     * @param s 签名参数 s
     */
    function permitDeposit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        permitDeposit(msg.sender, amount, deadline, v, r, s);
    }

    /**
     * @notice 支持指定存款人（owner）的 permit 存款，支持第三方 Relayer 提交
     * @param owner 实际扣款和入账的存款人地址
     * @param amount 存入的代币数量
     * @param deadline 签名截止时间
     * @param v 签名参数 v
     * @param r 签名参数 r
     * @param s 签名参数 s
     */
    function permitDeposit(
        address owner,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        require(amount > 0, "TokenBank: deposit amount must be > 0");

        // 1. 调用代币的 permit 进行签名授权，将当前 TokenBank 合约设为 spender
        IERC20Permit(address(token)).permit(
            owner,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );

        // 2. 记账
        balances[owner] += amount;

        // 3. 将代币从 owner 转入 TokenBank 合约
        token.safeTransferFrom(owner, address(this), amount);

        emit Deposit(owner, amount);
    }

    /**
     * @notice 使用 Uniswap Permit2 SignatureTransfer 一步签名授权并存入代币
     * @param permit 包含代币、存款金额、nonce 与有效期的 PermitTransferFrom 结构体
     * @param signature 用户针对 Permit2 签发的 EIP-712 签名
     */
    function depositWithPermit2(
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external {
        depositWithPermit2(msg.sender, permit, signature);
    }

    /**
     * @notice 支持指定存款人（owner）的 Permit2 签名存款
     * @param owner 存款人（代币所有者及签名者）
     * @param permit 包含代币、存款金额、nonce 与有效期的 PermitTransferFrom 结构体
     * @param signature 用户针对 Permit2 签发的 EIP-712 签名
     */
    function depositWithPermit2(
        address owner,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) public {
        require(permit.permitted.token == address(token), "TokenBank: token mismatch");
        require(permit.permitted.amount > 0, "TokenBank: deposit amount must be > 0");

        // 构造转入明细：接收地址为当前 TokenBank 合约，转入金额为 permit.permitted.amount
        ISignatureTransfer.SignatureTransferDetails memory transferDetails = ISignatureTransfer
            .SignatureTransferDetails({
                to: address(this),
                requestedAmount: permit.permitted.amount
            });

        // 调用 permit2 合约的 permitTransferFrom 执行代币划转 (SignatureTransfer)
        ISignatureTransfer(permit2).permitTransferFrom(
            permit,
            transferDetails,
            owner,
            signature
        );

        // 记账
        balances[owner] += permit.permitted.amount;

        emit Deposit(owner, permit.permitted.amount);
    }

    /**
     * @notice 便捷传参重载：直接传入金额、nonce、截止时间及签名
     * @param amount 存入的代币数量
     * @param nonce Permit2 防重放 nonce
     * @param deadline 签名截止有效时间
     * @param signature 用户针对 Permit2 签发的 EIP-712 签名
     */
    function depositWithPermit2(
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external {
        depositWithPermit2(msg.sender, amount, nonce, deadline, signature);
    }

    /**
     * @notice 便捷传参重载（指定 owner）：直接传入 owner、金额、nonce、截止时间及签名
     */
    function depositWithPermit2(
        address owner,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) public {
        require(amount > 0, "TokenBank: deposit amount must be > 0");

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: address(token),
                amount: amount
            }),
            nonce: nonce,
            deadline: deadline
        });

        ISignatureTransfer.SignatureTransferDetails memory transferDetails = ISignatureTransfer
            .SignatureTransferDetails({
                to: address(this),
                requestedAmount: amount
            });

        ISignatureTransfer(permit2).permitTransferFrom(
            permit,
            transferDetails,
            owner,
            signature
        );

        balances[owner] += amount;

        emit Deposit(owner, amount);
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
