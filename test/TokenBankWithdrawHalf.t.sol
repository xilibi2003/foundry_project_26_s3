// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MyPermitToken} from "../src/MyPermitToken.sol";
import {TokenBank} from "../src/TokenBank.sol";

contract TokenBankWithdrawHalfTest is Test {
    MyPermitToken public token;
    TokenBank public bank;

    address public owner;
    address public alice;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");

        // 部署 Token & Bank
        token = new MyPermitToken("MyPermitToken", "MPT");
        bank = new TokenBank(address(token));

        // 给 alice 一些代币
        token.transfer(alice, 10_000);
    }

    function test_ShouldWithdraw_ReturnsFalseWhenBalanceSubOrEq1000() public view {
        // 初始 Bank 没有任何余额 (0)
        assertFalse(bank.shouldWithdraw());
    }

    function test_ShouldWithdraw_ReturnsTrueWhenBalanceGreaterThan1000() public {
        // Alice 向 Bank 存入 1001 代币
        vm.startPrank(alice);
        token.approve(address(bank), 1001);
        bank.deposit(1001);
        vm.stopPrank();

        assertTrue(bank.shouldWithdraw());
    }

    function test_Withdrawhalf_RevertsWhenBalanceSubOrEq1000() public {
        // Bank 余额为 0
        vm.expectRevert("TokenBank: balance <= 1000");
        bank.withdrawhalf();

        // Bank 余额刚好等于 1000
        vm.startPrank(alice);
        token.approve(address(bank), 1000);
        bank.deposit(1000);
        vm.stopPrank();

        assertFalse(bank.shouldWithdraw());
        vm.expectRevert("TokenBank: balance <= 1000");
        bank.withdrawhalf();
    }

    function test_Withdrawhalf_SuccessWhenBalanceGreaterThan1000() public {
        // Alice 向 Bank 存入 2000 代币
        vm.startPrank(alice);
        token.approve(address(bank), 2000);
        bank.deposit(2000);
        vm.stopPrank();

        assertTrue(bank.shouldWithdraw());
        uint256 ownerInitialBalance = token.balanceOf(owner);

        // 调用 withdrawhalf 提取一半到 owner
        bank.withdrawhalf();

        // 验证 Bank 剩余余额 = 1000 (2000 - 1000)
        assertEq(token.balanceOf(address(bank)), 1000);
        // 验证 owner 收到 1000 代币
        assertEq(token.balanceOf(owner), ownerInitialBalance + 1000);
    }
}
