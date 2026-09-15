// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Bank} from "../src/bank.sol";

contract BankTest is Test {
    Bank public bank;

    address public admin = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public david = makeAddr("david");
    address public eva = makeAddr("eva");

    function setUp() public {
        bank = new Bank();

        // 给测试账户分配测试资金
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(david, 100 ether);
        vm.deal(eva, 100 ether);
    }

    /// @dev 验证单一地址存款后余额与合约总额是否被正确记录
    function test_DepositRecordsBalance() public {
        uint256 depositAmount = 1 ether;

        vm.prank(alice);
        bank.deposit{value: depositAmount}();

        // 验证 balances 映射
        assertEq(bank.balances(alice), depositAmount, "Alice balance mismatch");
        // 验证合约自身 ETH 余额
        assertEq(
            address(bank).balance,
            depositAmount,
            "Bank contract balance mismatch"
        );
    }

    /// @dev 验证同一地址多次存款累加记录
    function test_MultipleDepositsAccumulate() public {
        vm.startPrank(alice);
        bank.deposit{value: 1 ether}();
        bank.deposit{value: 2 ether}();
        vm.stopPrank();

        assertEq(
            bank.balances(alice),
            3 ether,
            "Alice cumulative balance mismatch"
        );
        assertEq(address(bank).balance, 3 ether, "Contract balance mismatch");
    }

    /// @dev 验证通过 receive() 转账存款也能被正确记录
    function test_ReceiveDeposit() public {
        vm.prank(alice);
        (bool success, ) = address(bank).call{value: 1.5 ether}("");
        assertTrue(success, "Receive transfer failed");

        assertEq(bank.balances(alice), 1.5 ether);
        address[3] memory top = bank.getTopDepositors();
        assertEq(top[0], alice);
    }

    /// @dev 验证存款金额为 0 时回滚
    function test_RevertWhen_DepositZero() public {
        vm.prank(alice);
        vm.expectRevert("Bank: deposit amount is zero");
        bank.deposit{value: 0}();
    }

    /// @dev 验证不同钱包地址存款，前三名排序及更新逻辑
    function test_Top3DepositorsOrdering() public {
        // 1. Alice 存 1 ETH -> top: [Alice, 0, 0]
        vm.prank(alice);
        bank.deposit{value: 1 ether}();

        address[3] memory top1 = bank.getTopDepositors();
        assertEq(top1[0], alice, "Top 1 should be Alice");
        assertEq(top1[1], address(0));
        assertEq(top1[2], address(0));

        // 2. Bob 存 3 ETH -> top: [Bob, Alice, 0]
        vm.prank(bob);
        bank.deposit{value: 3 ether}();

        address[3] memory top2 = bank.getTopDepositors();
        assertEq(top2[0], bob, "Top 1 should be Bob");
        assertEq(top2[1], alice, "Top 2 should be Alice");
        assertEq(top2[2], address(0));

        // 3. Charlie 存 2 ETH -> top: [Bob(3), Charlie(2), Alice(1)]
        vm.prank(charlie);
        bank.deposit{value: 2 ether}();

        address[3] memory top3 = bank.getTopDepositors();
        assertEq(top3[0], bob, "Top 1 should be Bob (3 ETH)");
        assertEq(top3[1], charlie, "Top 2 should be Charlie (2 ETH)");
        assertEq(top3[2], alice, "Top 3 should be Alice (1 ETH)");

        // 4. David 存 0.5 ETH (不足以进入前三) -> 前三名保持不变
        vm.prank(david);
        bank.deposit{value: 0.5 ether}();

        // 验证 David 的存款被正确记录在 balances
        assertEq(
            bank.balances(david),
            0.5 ether,
            "David balance should be recorded"
        );

        address[3] memory top4 = bank.getTopDepositors();
        assertEq(top4[0], bob, "Top 1 should still be Bob");
        assertEq(top4[1], charlie, "Top 2 should still be Charlie");
        assertEq(top4[2], alice, "Top 3 should still be Alice");

        // 5. Eva 存 2.5 ETH (挤掉第三名 Alice，排在第二) -> top: [Bob(3), Eva(2.5), Charlie(2)]
        vm.prank(eva);
        bank.deposit{value: 2.5 ether}();

        // 验证 Eva 存款被正确记录
        assertEq(
            bank.balances(eva),
            2.5 ether,
            "Eva balance should be recorded"
        );

        address[3] memory top5 = bank.getTopDepositors();
        assertEq(top5[0], bob, "Top 1 should be Bob (3 ETH)");
        assertEq(top5[1], eva, "Top 2 should be Eva (2.5 ETH)");
        assertEq(top5[2], charlie, "Top 3 should be Charlie (2 ETH)");

        // 6. 已有存款者再次存款：Charlie 追加 2 ETH (总额变为 4 ETH)
        // 应该重新排序并升至第一名 -> top: [Charlie(4), Bob(3), Eva(2.5)]
        vm.prank(charlie);
        bank.deposit{value: 2 ether}();

        assertEq(
            bank.balances(charlie),
            4 ether,
            "Charlie new balance should be 4 ETH"
        );

        address[3] memory top6 = bank.getTopDepositors();
        assertEq(top6[0], charlie, "Top 1 should be Charlie (4 ETH)");
        assertEq(top6[1], bob, "Top 2 should be Bob (3 ETH)");
        assertEq(top6[2], eva, "Top 3 should be Eva (2.5 ETH)");
    }

    /// @dev 验证被挤出前三的用户，追加存款超过前三后能够重新进入前三
    function test_PushedOutUserCanReenterTop3() public {
        // 初始化 3 位存款人
        vm.prank(alice);
        bank.deposit{value: 1 ether}();

        vm.prank(bob);
        bank.deposit{value: 2 ether}();
        vm.prank(charlie);
        bank.deposit{value: 3 ether}();
        // 当前 top: [Charlie(3), Bob(2), Alice(1)]

        // David 存 2.5 ether，将 Alice 挤出
        vm.prank(david);
        bank.deposit{value: 2.5 ether}();
        // 当前 top: [Charlie(3), David(2.5), Bob(2)]

        address[3] memory top = bank.getTopDepositors();
        assertEq(top[0], charlie);
        assertEq(top[1], david);
        assertEq(top[2], bob);

        // Alice 再次存 4 ether，总余额变为 5 ether，重新回到第一名
        vm.prank(alice);
        bank.deposit{value: 4 ether}();
        assertEq(bank.balances(alice), 5 ether);

        address[3] memory topAfter = bank.getTopDepositors();
        assertEq(topAfter[0], alice, "Alice should be 1st with 5 ETH");
        assertEq(topAfter[1], charlie, "Charlie should be 2nd with 3 ETH");
        assertEq(topAfter[2], david, "David should be 3rd with 2.5 ETH");
    }
}
