// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MyPermitToken} from "../src/MyPermitToken.sol";
import {TokenBank} from "../src/TokenBank.sol";

contract TokenBankPermitTest is Test {
    MyPermitToken public token;
    TokenBank public bank;

    address public deployer;
    uint256 public deployerKey;

    address public alice;
    uint256 public aliceKey;

    address public relayer = makeAddr("relayer");

    uint256 public constant ALICE_INITIAL_BALANCE = 10_000 * 10 ** 18;

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function setUp() public {
        (deployer, deployerKey) = makeAddrAndKey("deployer");
        (alice, aliceKey) = makeAddrAndKey("alice");

        vm.startPrank(deployer);
        // 部署 MyPermitToken（继承 CalledToken 并支持 EIP-2612）
        token = new MyPermitToken("MyPermitToken", "MPT");
        // 部署 TokenBank 绑定 MyPermitToken
        bank = new TokenBank(address(token));

        // 向 alice 分发测试代币
        token.transfer(alice, ALICE_INITIAL_BALANCE);
        vm.stopPrank();
    }

    /// @notice 辅助函数：生成 EIP-2612 签名
    function _signPermit(
        uint256 privateKey,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (v, r, s) = vm.sign(privateKey, digest);
    }

    /// @dev 测试 Alice 自己调用 permitDeposit（单参数重载，msg.sender 为存款人）
    function test_PermitDeposit_ByAlice() public {
        uint256 depositAmt = 500 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(alice);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceKey,
            alice,
            address(bank),
            depositAmt,
            nonce,
            deadline
        );

        vm.startPrank(alice);
        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, depositAmt);

        // 调用 permitDeposit 完成一步存款
        bank.permitDeposit(depositAmt, deadline, v, r, s);
        vm.stopPrank();

        // 验证账本与余额
        assertEq(bank.balances(alice), depositAmt);
        assertEq(token.balanceOf(address(bank)), depositAmt);
        assertEq(token.balanceOf(alice), ALICE_INITIAL_BALANCE - depositAmt);
        assertEq(token.nonces(alice), 1);
    }

    /// @dev 测试由第三方 Relayer 提交 Alice 的 permitDeposit（多参数重载，指定 owner 为 alice）
    function test_PermitDeposit_ByRelayer() public {
        uint256 depositAmt = 800 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(alice);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceKey,
            alice,
            address(bank),
            depositAmt,
            nonce,
            deadline
        );

        // 由 relayer 地址发起交易代为提交
        vm.prank(relayer);
        bank.permitDeposit(alice, depositAmt, deadline, v, r, s);

        // 验证存款记在 alice 名下，从 alice 扣款
        assertEq(bank.balances(alice), depositAmt);
        assertEq(token.balanceOf(address(bank)), depositAmt);
        assertEq(token.balanceOf(alice), ALICE_INITIAL_BALANCE - depositAmt);
    }

    /// @dev 测试签名过期时 permitDeposit 失败回滚
    function test_RevertWhen_PermitDeadlineExpired() public {
        uint256 depositAmt = 100 * 10 ** 18;
        uint256 deadline = block.timestamp - 1; // 已过期
        uint256 nonce = token.nonces(alice);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceKey,
            alice,
            address(bank),
            depositAmt,
            nonce,
            deadline
        );

        vm.prank(alice);
        vm.expectRevert();
        bank.permitDeposit(depositAmt, deadline, v, r, s);
    }

    /// @dev 测试重放签名时失败回滚
    function test_RevertWhen_PermitSignatureReplay() public {
        uint256 depositAmt = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(alice);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceKey,
            alice,
            address(bank),
            depositAmt,
            nonce,
            deadline
        );

        // 第一次成功
        vm.prank(alice);
        bank.permitDeposit(depositAmt, deadline, v, r, s);

        // 第二次使用同一签名尝试再次存款，应触发 revert
        vm.prank(alice);
        vm.expectRevert();
        bank.permitDeposit(depositAmt, deadline, v, r, s);
    }

    /// @dev 测试 permitDeposit 存入后正常 withdraw 提取
    function test_WithdrawAfterPermitDeposit() public {
        uint256 depositAmt = 1000 * 10 ** 18;
        uint256 withdrawAmt = 600 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(alice);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceKey,
            alice,
            address(bank),
            depositAmt,
            nonce,
            deadline
        );

        vm.startPrank(alice);
        bank.permitDeposit(depositAmt, deadline, v, r, s);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(alice, withdrawAmt);
        bank.withdraw(withdrawAmt);
        vm.stopPrank();

        assertEq(bank.balances(alice), depositAmt - withdrawAmt);
        assertEq(token.balanceOf(alice), ALICE_INITIAL_BALANCE - depositAmt + withdrawAmt);
    }

    /// @dev 测试 MyPermitToken 同时具备 CalledToken 的 transferAndCall 能力
    function test_TransferAndCall_StillWorksWithMyPermitToken() public {
        uint256 depositAmt = 300 * 10 ** 18;

        vm.startPrank(alice);
        token.transferAndCall(address(bank), depositAmt);
        vm.stopPrank();

        assertEq(bank.balances(alice), depositAmt);
        assertEq(token.balanceOf(address(bank)), depositAmt);
    }
}
