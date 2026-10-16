// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DefToken} from "../src/DefToken.sol";

contract DefTokenTest is Test {
    DefToken public token;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_SUPPLY = 1_000_000; // 1,000,000 tokens

    function setUp() public {
        vm.prank(owner);
        token = new DefToken("Deflation Token", "DEFT", INITIAL_SUPPLY);
    }

    // 1. 测试初始化状态
    function test_InitialState() public view {
        assertEq(token.name(), "Deflation Token");
        assertEq(token.symbol(), "DEFT");
        assertEq(token.decimals(), 18);

        uint256 expectedSupply = INITIAL_SUPPLY * 1e18;
        assertEq(token.totalSupply(), expectedSupply);
        assertEq(token.balanceOf(owner), expectedSupply);
        assertEq(token.sharesOf(owner), expectedSupply);
        assertEq(token.totalShares(), expectedSupply);
    }

    // 2. 测试不满 1 年调用 rebase 应该 revert
    function test_RevertWhen_RebaseNotDue() public {
        // 快进 364 天（未满 365 天）
        vm.warp(block.timestamp + 364 days);

        vm.expectRevert(DefToken.RebaseNotDue.selector);
        token.rebase();
    }

    // 3. 测试满 1 年后 rebase：发行量和余额均下降 1%
    function test_RebaseOneYear() public {
        uint256 supplyBefore = token.totalSupply();
        uint256 sharesBefore = token.sharesOf(owner);

        // 快进 365 天
        vm.warp(block.timestamp + 365 days);

        // 触发 rebase
        token.rebase();

        uint256 expectedSupply = (supplyBefore * 99) / 100; // 下降 1%
        assertEq(token.totalSupply(), expectedSupply);
        // balanceOf 应该准确反映通缩后的余额
        assertEq(token.balanceOf(owner), expectedSupply);
        // 底层 shares 应该保持不变
        assertEq(token.sharesOf(owner), sharesBefore);
        assertEq(token.totalShares(), sharesBefore);
    }

    // 4. 测试多年未 rebase 时，按年复利计算（隔 2 年下降：第 1 年 99%，第 2 年在第 1 年基础上再降 1%）
    function test_RebaseMultiYearCompound() public {
        uint256 supply0 = token.totalSupply();

        // 快进 2 年
        vm.warp(block.timestamp + 365 days * 2);
        token.rebase();

        uint256 supplyYear1 = (supply0 * 99) / 100;
        uint256 supplyYear2 = (supplyYear1 * 99) / 100;

        assertEq(token.totalSupply(), supplyYear2);
        assertEq(token.balanceOf(owner), supplyYear2);
    }

    // 5. 测试多用户持币情况下 rebase 通缩
    function test_RebaseMultipleUsers() public {
        // owner 分别转账 400,000 给 Alice，600,000 给 Bob
        uint256 aliceAmount = 400_000 * 1e18;
        uint256 bobAmount = 600_000 * 1e18;

        vm.startPrank(owner);
        token.transfer(alice, aliceAmount);
        token.transfer(bob, bobAmount);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), aliceAmount);
        assertEq(token.balanceOf(bob), bobAmount);
        assertEq(token.balanceOf(owner), 0);

        // 快进 1 年并 rebase
        vm.warp(block.timestamp + 365 days);
        token.rebase();

        uint256 expectedAliceBalance = (aliceAmount * 99) / 100;
        uint256 expectedBobBalance = (bobAmount * 99) / 100;

        assertEq(token.balanceOf(alice), expectedAliceBalance);
        assertEq(token.balanceOf(bob), expectedBobBalance);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), token.totalSupply());
    }

    // 6. 测试全额转账无精度灰尘残留 (No dust left)
    function test_TransferFullBalance() public {
        vm.prank(owner);
        token.transfer(alice, 100_000 * 1e18);

        // 经过 1 年通缩
        vm.warp(block.timestamp + 365 days);
        token.rebase();

        uint256 aliceBal = token.balanceOf(alice);
        assertTrue(aliceBal > 0);

        // Alice 全额转给 Bob
        vm.prank(alice);
        token.transfer(bob, aliceBal);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.sharesOf(alice), 0);
        assertEq(token.balanceOf(bob), aliceBal);
    }

    // 7. 测试 approve & transferFrom
    function test_ApproveAndTransferFrom() public {
        uint256 transferAmount = 50_000 * 1e18;

        vm.prank(owner);
        token.approve(alice, transferAmount);
        assertEq(token.allowance(owner, alice), transferAmount);

        // Alice 代为转账给 Bob
        vm.prank(alice);
        token.transferFrom(owner, bob, transferAmount);

        assertEq(token.balanceOf(bob), transferAmount);
        assertEq(token.allowance(owner, alice), 0);
    }

    // 8. 异常情况：余额不足
    function test_RevertWhen_InsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(DefToken.InsufficientBalance.selector);
        token.transfer(bob, 100 * 1e18);
    }

    // 9. 异常情况：转给零地址
    function test_RevertWhen_TransferToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DefToken.ZeroAddress.selector);
        token.transfer(address(0), 100 * 1e18);
    }
}
