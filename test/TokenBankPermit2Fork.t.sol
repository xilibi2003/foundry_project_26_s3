// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {TokenBank} from "../src/TokenBank.sol";
import {MyPermitToken} from "../src/MyPermitToken.sol";
import {ISignatureTransfer} from "../src/ISignatureTransfer.sol";

/**
 * @title TokenBankPermit2ForkTest
 * @notice Fork Sepolia 测试：使用链上真实 Uniswap Permit2 合约测试 TokenBank.depositWithPermit2
 */
contract TokenBankPermit2ForkTest is Test {
    // Uniswap Permit2 官方 Canonical 统一地址
    address public constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    string public constant DEFAULT_SEPOLIA_RPC_URL = "https://ethereum-sepolia-rpc.publicnode.com";

    // Permit2 EIP-712 TypeHashes
    bytes32 public constant TOKEN_PERMISSIONS_TYPEHASH =
        keccak256("TokenPermissions(address token,uint256 amount)");

    bytes32 public constant PERMIT_TRANSFER_FROM_TYPEHASH =
        keccak256(
            "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );

    TokenBank public bank;
    MyPermitToken public token;
    ISignatureTransfer public permit2;

    address public deployer = makeAddr("deployer");
    address public alice;
    uint256 public alicePrivateKey;
    address public relayer = makeAddr("relayer");

    uint256 public constant ALICE_INITIAL_BALANCE = 10_000 * 10 ** 18;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function setUp() public {
        // 读取 Sepolia RPC 并创建 Fork
        string memory rpcUrl;
        try vm.envString("SEPOLIA_RPC_URL") returns (string memory envUrl) {
            rpcUrl = envUrl;
        } catch {
            try vm.rpcUrl("sepolia") returns (string memory configUrl) {
                rpcUrl = configUrl;
            } catch {
                rpcUrl = DEFAULT_SEPOLIA_RPC_URL;
            }
        }

        vm.createSelectFork(rpcUrl);

        alicePrivateKey = 0x7b5874c9384918efbd9a27221087e22138947209182374981729384719283741;
        alice = vm.addr(alicePrivateKey);
        vm.etch(alice, ""); // 确保作为标准 EOA 账户测试，避免 Sepolia 链上同地址存在合约代码

        // 部署代币和 TokenBank
        vm.startPrank(deployer);
        token = new MyPermitToken("MyPermitToken", "MPT");
        bank = new TokenBank(address(token));
        token.transfer(alice, ALICE_INITIAL_BALANCE);
        vm.stopPrank();

        permit2 = ISignatureTransfer(PERMIT2_ADDRESS);

        // Alice 预先将代币最大额度 approve 给 Permit2 合约（Permit2 的设计核心：全协议只授权一次 Permit2）
        vm.prank(alice);
        token.approve(PERMIT2_ADDRESS, type(uint256).max);
    }

    /// @notice 辅助函数：构造并生成符合 Permit2 规范的 EIP-712 签名
    function _signPermit2(
        uint256 privateKey,
        address tokenAddress,
        uint256 amount,
        address spender,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 tokenPermissionsHash = keccak256(
            abi.encode(
                TOKEN_PERMISSIONS_TYPEHASH,
                tokenAddress,
                amount
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TRANSFER_FROM_TYPEHASH,
                tokenPermissionsHash,
                spender,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                permit2.DOMAIN_SEPARATOR(),
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev 验证 Alice 使用 Permit2 签名直接存款（简化参数版本）
    function test_Fork_Permit2_DirectDeposit() public {
        uint256 depositAmt = 500 * 10 ** 18;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory signature = _signPermit2(
            alicePrivateKey,
            address(token),
            depositAmt,
            address(bank),
            nonce,
            deadline
        );

        vm.startPrank(alice);
        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, depositAmt);

        bank.depositWithPermit2(depositAmt, nonce, deadline, signature);
        vm.stopPrank();

        assertEq(bank.balances(alice), depositAmt, "Alice deposit mismatch");
        assertEq(token.balanceOf(address(bank)), depositAmt, "Bank token mismatch");
        assertEq(token.balanceOf(alice), ALICE_INITIAL_BALANCE - depositAmt, "Alice remaining token mismatch");
    }

    /// @dev 验证使用 PermitTransferFrom 结构体参数版本的 depositWithPermit2
    function test_Fork_Permit2_StructDeposit() public {
        uint256 depositAmt = 800 * 10 ** 18;
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory signature = _signPermit2(
            alicePrivateKey,
            address(token),
            depositAmt,
            address(bank),
            nonce,
            deadline
        );

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: address(token),
                amount: depositAmt
            }),
            nonce: nonce,
            deadline: deadline
        });

        vm.prank(alice);
        bank.depositWithPermit2(permit, signature);

        assertEq(bank.balances(alice), depositAmt);
        assertEq(token.balanceOf(address(bank)), depositAmt);
    }

    /// @dev 验证第三方 Relayer 提交 Alice 的 Permit2 签名入账
    function test_Fork_Permit2_RelayerDeposit() public {
        uint256 depositAmt = 1200 * 10 ** 18;
        uint256 nonce = 2;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory signature = _signPermit2(
            alicePrivateKey,
            address(token),
            depositAmt,
            address(bank),
            nonce,
            deadline
        );

        // 由 relayer 地址发起交易代为提交
        vm.prank(relayer);
        bank.depositWithPermit2(alice, depositAmt, nonce, deadline, signature);

        // 验证资金存入 alice 账户
        assertEq(bank.balances(alice), depositAmt);
        assertEq(token.balanceOf(alice), ALICE_INITIAL_BALANCE - depositAmt);
    }

    /// @dev 验证 Permit2 存入后正常执行 TokenBank 取款
    function test_Fork_Permit2_WithdrawAfterDeposit() public {
        uint256 depositAmt = 600 * 10 ** 18;
        uint256 withdrawAmt = 250 * 10 ** 18;
        uint256 nonce = 3;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory signature = _signPermit2(
            alicePrivateKey,
            address(token),
            depositAmt,
            address(bank),
            nonce,
            deadline
        );

        vm.startPrank(alice);
        bank.depositWithPermit2(depositAmt, nonce, deadline, signature);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(alice, withdrawAmt);
        bank.withdraw(withdrawAmt);
        vm.stopPrank();

        assertEq(bank.balances(alice), depositAmt - withdrawAmt);
        assertEq(token.balanceOf(alice), ALICE_INITIAL_BALANCE - depositAmt + withdrawAmt);
    }

    /// @dev 验证 Permit2 签名过期时 revert
    function test_Fork_RevertWhen_Permit2DeadlineExpired() public {
        uint256 depositAmt = 100 * 10 ** 18;
        uint256 nonce = 4;
        uint256 deadline = block.timestamp - 1; // 已过期

        bytes memory signature = _signPermit2(
            alicePrivateKey,
            address(token),
            depositAmt,
            address(bank),
            nonce,
            deadline
        );

        vm.prank(alice);
        vm.expectRevert();
        bank.depositWithPermit2(depositAmt, nonce, deadline, signature);
    }

    /// @dev 验证 Permit2 相同 nonce 重放时 revert
    function test_Fork_RevertWhen_Permit2NonceReused() public {
        uint256 depositAmt = 100 * 10 ** 18;
        uint256 nonce = 5;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory signature = _signPermit2(
            alicePrivateKey,
            address(token),
            depositAmt,
            address(bank),
            nonce,
            deadline
        );

        // 第一次成功
        vm.prank(alice);
        bank.depositWithPermit2(depositAmt, nonce, deadline, signature);

        // 第二次使用相同 nonce，Permit2 判定 nonce 已消耗触发 revert
        vm.prank(alice);
        vm.expectRevert();
        bank.depositWithPermit2(depositAmt, nonce, deadline, signature);
    }
}
