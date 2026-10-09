// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@oz/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Permit
} from "@oz/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@oz/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@oz/contracts/access/Ownable.sol";
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
contract TokenBank is ITokenReceiver, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    // Uniswap Permit2 官方合约地址（全网统一：0x000000000022D473030F116dDEE9F6B43aC78BA3）
    address public permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // 记录每个用户存入的 token 数量
    mapping(address => uint256) public balances;

    // 可迭代链表：按存款金额降序维护前 10 名存款人
    address public constant GUARD = address(1);
    uint256 public constant MAX_TOP = 10;
    uint256 public listSize;

    mapping(address => address) public nextDepositors;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Permit2AddressUpdated(
        address indexed oldPermit2,
        address indexed newPermit2
    );
    event TopDepositorUpdated(address indexed depositor, uint256 newBalance);
    event TopDepositorEvicted(address indexed depositor);

    /**
     * @param _tokenAddress 绑定的 ERC20 Token 地址
     */
    constructor(address _tokenAddress) Ownable(msg.sender) {
        require(
            _tokenAddress != address(0),
            "TokenBank: token address cannot be zero"
        );
        token = IERC20(_tokenAddress);
        nextDepositors[GUARD] = GUARD;
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
        _updateTopDepositors(msg.sender);

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
        _updateTopDepositors(owner);

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
        require(
            permit.permitted.token == address(token),
            "TokenBank: token mismatch"
        );
        require(
            permit.permitted.amount > 0,
            "TokenBank: deposit amount must be > 0"
        );

        // 构造转入明细：接收地址为当前 TokenBank 合约，转入金额为 permit.permitted.amount
        ISignatureTransfer.SignatureTransferDetails
            memory transferDetails = ISignatureTransfer
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
        _updateTopDepositors(owner);

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

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer
            .PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: address(token),
                    amount: amount
                }),
                nonce: nonce,
                deadline: deadline
            });

        ISignatureTransfer.SignatureTransferDetails
            memory transferDetails = ISignatureTransfer
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
        _updateTopDepositors(owner);

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
        _updateTopDepositors(from);

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
        _updateTopDepositors(msg.sender);

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

    /**
     * @notice 判断 TokenBank 合约的代币余额是否大于 1000
     * @return 当 token 余额大于 1000 时返回 true，否则返回 false
     */
    function shouldWithdraw() public view returns (bool) {
        return token.balanceOf(address(this)) > 1000;
    }

    /**
     * @notice 当 token 的余额大于 1000 时，提取一半的余额到 owner
     */
    function withdrawhalf() external {
        require(shouldWithdraw(), "TokenBank: balance <= 1000");
        uint256 totalBalance = token.balanceOf(address(this));
        uint256 amountToWithdraw = totalBalance / 2;
        token.safeTransfer(owner(), amountToWithdraw);
    }

    // ========================================================
    //               Top 10 可迭代链表核心方法
    // ========================================================

    /**
     * @notice 获取前 k 名存款人地址列表（按存款金额从高到低排序）
     * @param k 获取的数量，必须小于或等于当前链表大小 listSize
     */
    function getTop(uint256 k) public view returns (address[] memory) {
        require(k <= listSize, "TokenBank: k exceeds listSize");
        address[] memory topList = new address[](k);
        address currentAddress = nextDepositors[GUARD];
        for (uint256 i = 0; i < k; ++i) {
            topList[i] = currentAddress;
            currentAddress = nextDepositors[currentAddress];
        }
        return topList;
    }

    /**
     * @notice 获取当前前 10 名存款人地址列表（若不足 10 名则返回当前全部存款人）
     */
    function getTop10() public view returns (address[] memory) {
        uint256 count = listSize > MAX_TOP ? MAX_TOP : listSize;
        return getTop(count);
    }

    /**
     * @notice 别名兼容：获取前 10 名存款人地址列表
     */
    function getTopDepositors() external view returns (address[] memory) {
        return getTop10();
    }

    /**
     * @notice 别名兼容：获取下一个存款人（兼容 _nextStudents 风格查询）
     */
    function _nextDepositors(
        address depositor
    ) external view returns (address) {
        return nextDepositors[depositor];
    }

    /**
     * @notice 判断用户是否在前 10 名链表中
     */
    function isTopDepositor(address depositor) external view returns (bool) {
        return
            depositor != GUARD &&
            depositor != address(0) &&
            nextDepositors[depositor] != address(0);
    }

    /**
     * @dev 更新用户在 Top 10 链表中的排位
     * @param depositor 发生存款或取款变化的用户
     */
    function _updateTopDepositors(address depositor) internal {
        if (depositor == address(0) || depositor == GUARD) {
            return;
        }

        uint256 newBalance = balances[depositor];

        // 1. 如果该用户已在链表中，先从旧位置断开移除
        if (nextDepositors[depositor] != address(0)) {
            address prev = GUARD;
            while (
                nextDepositors[prev] != depositor &&
                nextDepositors[prev] != GUARD
            ) {
                prev = nextDepositors[prev];
            }
            if (nextDepositors[prev] == depositor) {
                nextDepositors[prev] = nextDepositors[depositor];
                nextDepositors[depositor] = address(0);
                listSize--;
            }
        }

        // 2. 如果用户最新余额为 0，不再进入排行榜
        if (newBalance == 0) {
            return;
        }

        // 3. 如果链表已有 MAX_TOP (10) 个元素，检查是否有资格进入
        if (listSize >= MAX_TOP) {
            // 定位到当前第 10 名
            address tail = GUARD;
            for (uint256 i = 0; i < MAX_TOP; i++) {
                tail = nextDepositors[tail];
            }
            // 若新余额不大于当前第 10 名的余额，则无法挤进前 10
            if (newBalance <= balances[tail]) {
                return;
            }
        }

        // 4. 从 GUARD 出发，寻找新节点的插入前驱（按余额降序）
        address candidate = GUARD;
        while (
            nextDepositors[candidate] != GUARD &&
            balances[nextDepositors[candidate]] >= newBalance
        ) {
            candidate = nextDepositors[candidate];
        }

        // 5. 链入新节点
        nextDepositors[depositor] = nextDepositors[candidate];
        nextDepositors[candidate] = depositor;
        listSize++;
        emit TopDepositorUpdated(depositor, newBalance);

        // 6. 若节点总数超过 MAX_TOP (10)，淘汰第 11 名（多出的末尾节点）
        if (listSize > MAX_TOP) {
            address cur = GUARD;
            for (uint256 i = 0; i < MAX_TOP; i++) {
                cur = nextDepositors[cur];
            }
            address evicted = nextDepositors[cur];
            if (evicted != GUARD && evicted != address(0)) {
                nextDepositors[cur] = GUARD;
                nextDepositors[evicted] = address(0);
                listSize--;
                emit TopDepositorEvicted(evicted);
            }
        }
    }

    /**
     * @notice 校验插入位置索引正确性
     */
    function _verifyIndex(
        address prevDepositor,
        uint256 newValue,
        address nextDepositor
    ) internal view returns (bool) {
        return
            (prevDepositor == GUARD || balances[prevDepositor] >= newValue) &&
            (nextDepositor == GUARD || newValue > balances[nextDepositor]);
    }

    /**
     * @notice 检查 prevDepositor 的下一个节点是否为 depositor
     */
    function _isPrevDepositor(
        address depositor,
        address prevDepositor
    ) internal view returns (bool) {
        return nextDepositors[prevDepositor] == depositor;
    }
}
