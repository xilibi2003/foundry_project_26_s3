// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CalledToken} from "../src/CalledToken.sol";
import {TokenBank} from "../src/TokenBank.sol";

contract TokenBankTop10Test is Test {
    CalledToken public token;
    TokenBank public bank;

    address public owner = makeAddr("owner");
    address[] public users;

    function setUp() public {
        vm.startPrank(owner);
        token = new CalledToken("MyCalledToken", "MCTK");
        bank = new TokenBank(address(token));

        // 创建 15 个测试用户并分发代币
        for (uint256 i = 0; i < 15; i++) {
            address u = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            users.push(u);
            token.transfer(u, 10_000 ether);
        }
        vm.stopPrank();
    }

    /// @dev 验证按不同顺序存入 10 个用户，链表保持降序排列
    function test_Top10_Ordering() public {
        // 用户 0~9 分别存入 (i + 1) * 10 ether
        // 存入顺序打乱以验证排序能力
        uint256[10] memory depositAmounts = [
            uint256(50 ether),
            20 ether,
            80 ether,
            10 ether,
            100 ether,
            30 ether,
            70 ether,
            40 ether,
            90 ether,
            60 ether
        ];

        for (uint256 i = 0; i < 10; i++) {
            address u = users[i];
            uint256 amt = depositAmounts[i];
            vm.startPrank(u);
            token.approve(address(bank), amt);
            bank.deposit(amt);
            vm.stopPrank();
        }

        assertEq(bank.listSize(), 10, "List size should be 10");

        address[] memory top10 = bank.getTop10();
        assertEq(top10.length, 10, "Top 10 length should be 10");

        // 验证链表严格降序: 100, 90, 80, 70, 60, 50, 40, 30, 20, 10
        assertEq(top10[0], users[4], "Rank 1: 100 ETH (user4)");
        assertEq(top10[1], users[8], "Rank 2: 90 ETH (user8)");
        assertEq(top10[2], users[2], "Rank 3: 80 ETH (user2)");
        assertEq(top10[3], users[6], "Rank 4: 70 ETH (user6)");
        assertEq(top10[4], users[9], "Rank 5: 60 ETH (user9)");
        assertEq(top10[5], users[0], "Rank 6: 50 ETH (user0)");
        assertEq(top10[6], users[7], "Rank 7: 40 ETH (user7)");
        assertEq(top10[7], users[5], "Rank 8: 30 ETH (user5)");
        assertEq(top10[8], users[1], "Rank 9: 20 ETH (user1)");
        assertEq(top10[9], users[3], "Rank 10: 10 ETH (user3)");

        // 验证每个用户都在链表中
        for (uint256 i = 0; i < 10; i++) {
            assertTrue(bank.isTopDepositor(users[i]), "User should be in top 10");
        }
    }

    /// @dev 验证第 11 名存款人金额不足以进入前 10
    function test_11thUser_InsufficientDeposit() public {
        test_Top10_Ordering();

        // user10 存入 5 ether（第 10 名 user3 是 10 ether）
        address user10 = users[10];
        vm.startPrank(user10);
        token.approve(address(bank), 5 ether);
        bank.deposit(5 ether);
        vm.stopPrank();

        assertEq(bank.listSize(), 10, "List size should still be 10");
        assertFalse(bank.isTopDepositor(user10), "user10 should not be in top 10");

        // 尾部第 10 名依然是 user3 (10 ether)
        address[] memory top10 = bank.getTop10();
        assertEq(top10[9], users[3], "Rank 10 should still be user3");
    }

    /// @dev 验证第 11 名存款人金额超过第 10 名时成功挤入前 10，并淘汰原第 10 名
    function test_11thUser_EvictsLast() public {
        test_Top10_Ordering();

        // 原第 10 名为 users[3] (10 ETH)
        address user10 = users[10];
        // user10 存入 55 ether，应排在第 5 名（在 60 ETH 和 50 ETH 之间）
        vm.startPrank(user10);
        token.approve(address(bank), 55 ether);
        bank.deposit(55 ether);
        vm.stopPrank();

        assertEq(bank.listSize(), 10, "List size should remain 10 after eviction");
        assertTrue(bank.isTopDepositor(user10), "user10 should be in top 10");
        assertFalse(bank.isTopDepositor(users[3]), "users[3] should be evicted");

        address[] memory top10 = bank.getTop10();
        assertEq(top10[5], user10, "user10 should be rank 6 (55 ETH)");
        assertEq(top10[9], users[1], "Rank 10 should now be user1 (20 ETH)");
    }

    /// @dev 验证已有排名的用户追加存款后名次上升
    function test_TopDepositor_DepositMoreToClimb() public {
        test_Top10_Ordering();

        // users[1] 原本排第 9 (20 ETH)，追加 90 ETH -> 总计 110 ETH，升为第 1 名
        address u1 = users[1];
        vm.startPrank(u1);
        token.approve(address(bank), 90 ether);
        bank.deposit(90 ether);
        vm.stopPrank();

        assertEq(bank.listSize(), 10, "List size should remain 10");
        address[] memory top10 = bank.getTop10();
        assertEq(top10[0], u1, "users[1] should now be Rank 1 with 110 ETH");
        assertEq(top10[1], users[4], "users[4] should now be Rank 2 with 100 ETH");
    }

    /// @dev 验证提款后名次下降
    function test_TopDepositor_WithdrawToDrop() public {
        test_Top10_Ordering();

        // users[4] 原本第 1 名 (100 ETH)，提款 65 ETH -> 剩余 35 ETH，应降至第 8 名 (40 ETH 与 30 ETH 之间)
        address u4 = users[4];
        vm.startPrank(u4);
        bank.withdraw(65 ether);
        vm.stopPrank();

        assertEq(bank.listSize(), 10, "List size should remain 10");
        address[] memory top10 = bank.getTop10();
        assertEq(top10[6], u4, "u4 should drop to Rank 7 (index 6) with 35 ETH");
        assertEq(top10[7], users[5], "Rank 8 should be user5 (30 ETH)");
    }

    /// @dev 验证全部提款后从前 10 链表中移除
    function test_TopDepositor_FullWithdrawalRemoves() public {
        test_Top10_Ordering();

        // users[3] (Rank 10, 10 ETH) 全部提款
        address u3 = users[3];
        vm.startPrank(u3);
        bank.withdraw(10 ether);
        vm.stopPrank();

        assertEq(bank.listSize(), 9, "List size should become 9");
        assertFalse(bank.isTopDepositor(u3), "u3 should be removed from top 10");

        address[] memory top = bank.getTop10();
        assertEq(top.length, 9, "Top list length should be 9");
    }

    /// @dev 验证被淘汰的用户追加存款重新进入前 10
    function test_EvictedUser_ReentersTop10() public {
        test_11thUser_EvictsLast();

        // users[3] 之前被淘汰，当前余额依然有 10 ETH
        // users[3] 追加存入 200 ETH，总额 210 ETH -> 冲上第 1 名！
        address u3 = users[3];
        vm.startPrank(u3);
        token.approve(address(bank), 200 ether);
        bank.deposit(200 ether);
        vm.stopPrank();

        assertEq(bank.listSize(), 10, "List size should still be 10");
        assertTrue(bank.isTopDepositor(u3), "u3 should re-enter top 10");

        address[] memory top10 = bank.getTop10();
        assertEq(top10[0], u3, "u3 should be Rank 1 with 210 ETH");
    }

    /// @dev 验证 transferAndCall 触发的存款也能正确更新链表
    function test_TransferAndCall_UpdatesTop10() public {
        address u0 = users[0];
        vm.startPrank(u0);
        token.transferAndCall(address(bank), 100 ether);
        vm.stopPrank();

        assertEq(bank.listSize(), 1);
        address[] memory top = bank.getTop10();
        assertEq(top[0], u0);
        assertTrue(bank.isTopDepositor(u0));
    }

    /// @dev 验证 getTop(k) 越界时 revert
    function test_RevertWhen_GetTopExceedsListSize() public {
        vm.startPrank(users[0]);
        token.approve(address(bank), 10 ether);
        bank.deposit(10 ether);
        vm.stopPrank();

        assertEq(bank.listSize(), 1);
        vm.expectRevert("TokenBank: k exceeds listSize");
        bank.getTop(2);
    }
}
