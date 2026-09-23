// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CalledToken} from "../src/CalledToken.sol";
import {TokenBank} from "../src/TokenBank.sol";

contract TokenBankCalledTokenTest is Test {
    CalledToken public token;
    TokenBank public bank;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_MINT = 1_000_000 * 10 ** 18;
    uint256 public constant ALICE_AMOUNT = 10_000 * 10 ** 18;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function setUp() public {
        vm.startPrank(owner);
        token = new CalledToken("MyCalledToken", "MCTK");
        bank = new TokenBank(address(token));

        // 转账代币给 alice
        token.transfer(alice, ALICE_AMOUNT);
        vm.stopPrank();
    }

    /// @dev 测试传统方式：approve + deposit
    function test_TraditionalDeposit() public {
        uint256 depositAmt = 100 * 10 ** 18;

        vm.startPrank(alice);
        token.approve(address(bank), depositAmt);

        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, depositAmt);
        bank.deposit(depositAmt);
        vm.stopPrank();

        assertEq(bank.balances(alice), depositAmt, "Alice deposit mismatch");
        assertEq(token.balanceOf(address(bank)), depositAmt, "Bank token mismatch");
        assertEq(token.balanceOf(alice), ALICE_AMOUNT - depositAmt, "Alice balance mismatch");
    }

    /// @dev 测试 CalledToken 的 transferAndCall 一步回调存入
    function test_TransferAndCallDeposit() public {
        uint256 depositAmt = 500 * 10 ** 18;

        vm.startPrank(alice);
        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, depositAmt);
        
        bool success = token.transferAndCall(address(bank), depositAmt);
        vm.stopPrank();

        assertTrue(success, "transferAndCall should succeed");
        assertEq(bank.balances(alice), depositAmt, "Bank balance mismatch");
        assertEq(token.balanceOf(address(bank)), depositAmt, "Bank token mismatch");
        assertEq(token.balanceOf(alice), ALICE_AMOUNT - depositAmt, "Alice token mismatch");
    }

    /// @dev 测试存入后取款功能
    function test_Withdraw() public {
        uint256 depositAmt = 1000 * 10 ** 18;
        uint256 withdrawAmt = 400 * 10 ** 18;

        vm.startPrank(alice);
        token.transferAndCall(address(bank), depositAmt);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(alice, withdrawAmt);
        bank.withdraw(withdrawAmt);
        vm.stopPrank();

        assertEq(bank.balances(alice), depositAmt - withdrawAmt, "Bank balance after withdraw mismatch");
        assertEq(token.balanceOf(alice), ALICE_AMOUNT - depositAmt + withdrawAmt, "Alice token balance after withdraw mismatch");
        assertEq(token.balanceOf(address(bank)), depositAmt - withdrawAmt, "Bank contract balance mismatch");
    }

    /// @dev 验证提款超过存入金额时 revert
    function test_RevertWithdrawExceedsBalance() public {
        uint256 depositAmt = 100 * 10 ** 18;

        vm.startPrank(alice);
        token.transferAndCall(address(bank), depositAmt);

        vm.expectRevert("TokenBank: insufficient balance");
        bank.withdraw(depositAmt + 1);
        vm.stopPrank();
    }

    /// @dev 验证直接外部调用 tokensReceived 且调用者非 token 合约时 revert
    function test_RevertDirectTokensReceived() public {
        vm.startPrank(alice);
        vm.expectRevert("TokenBank: caller must be the bound token");
        bank.tokensReceived(alice, 100 * 10 ** 18, "");
        vm.stopPrank();
    }
}
