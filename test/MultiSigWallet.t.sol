// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";

// 辅助测试合约：用于测试通过多签 CallData 调用的场景
contract MockTarget {
    uint256 public count;
    string public message;

    function increment() external payable {
        count += 1;
    }

    function setMessage(string calldata _msg) external {
        message = _msg;
    }

    function failingFunction() external pure {
        revert("Target call failed");
    }
}

contract MultiSigWalletTest is Test {
    MultiSigWallet public wallet;
    MockTarget public target;

    address public owner1 = address(0x101);
    address public owner2 = address(0x102);
    address public owner3 = address(0x103);
    address public nonOwner = address(0x999);

    address[] public initialOwners;

    // 事件声明用于 vm.expectEmit
    event ProposalSubmitted(
        uint256 indexed txId,
        address indexed proposer,
        address indexed to,
        uint256 value,
        bytes data
    );
    event TransactionConfirmed(uint256 indexed txId, address indexed owner);
    event TransactionExecuted(uint256 indexed txId, address indexed executor);

    function setUp() public {
        initialOwners.push(owner1);
        initialOwners.push(owner2);
        initialOwners.push(owner3);

        wallet = new MultiSigWallet(initialOwners);
        target = new MockTarget();

        // 为钱包注入 10 ETH
        vm.deal(address(wallet), 10 ether);
        // 为测试账户注入 ETH
        vm.deal(owner1, 1 ether);
        vm.deal(owner2, 1 ether);
        vm.deal(owner3, 1 ether);
        vm.deal(nonOwner, 1 ether);
    }

    // ==========================================
    // 1. 构造函数与门槛测试
    // ==========================================

    function test_Constructor_Threshold_ThreeOwners() public view {
        // 3 个人 -> ceil(2 * 3 / 3) = 2
        assertEq(wallet.requiredConfirmations(), 2);
        assertEq(wallet.getOwners().length, 3);
        assertTrue(wallet.isOwner(owner1));
        assertTrue(wallet.isOwner(owner2));
        assertTrue(wallet.isOwner(owner3));
        assertFalse(wallet.isOwner(nonOwner));
    }

    function test_ThresholdCalculation_VariousOwnerCounts() public {
        // 1 个人 -> 2/3 向上取整为 1
        address[] memory owners1 = new address[](1);
        owners1[0] = address(0x1);
        MultiSigWallet w1 = new MultiSigWallet(owners1);
        assertEq(w1.requiredConfirmations(), 1);

        // 2 个人 -> 2/3 向上取整为 2
        address[] memory owners2 = new address[](2);
        owners2[0] = address(0x1);
        owners2[1] = address(0x2);
        MultiSigWallet w2 = new MultiSigWallet(owners2);
        assertEq(w2.requiredConfirmations(), 2);

        // 4 个人 -> 2/3 向上取整为 3
        address[] memory owners4 = new address[](4);
        owners4[0] = address(0x1);
        owners4[1] = address(0x2);
        owners4[2] = address(0x3);
        owners4[3] = address(0x4);
        MultiSigWallet w4 = new MultiSigWallet(owners4);
        assertEq(w4.requiredConfirmations(), 3);

        // 5 个人 -> 2/3 向上取整为 4
        address[] memory owners5 = new address[](5);
        owners5[0] = address(0x1);
        owners5[1] = address(0x2);
        owners5[2] = address(0x3);
        owners5[3] = address(0x4);
        owners5[4] = address(0x5);
        MultiSigWallet w5 = new MultiSigWallet(owners5);
        assertEq(w5.requiredConfirmations(), 4);

        // 6 个人 -> 2/3 向上取整为 4
        address[] memory owners6 = new address[](6);
        for (uint160 i = 0; i < 6; i++) {
            owners6[i] = address(i + 1);
        }
        MultiSigWallet w6 = new MultiSigWallet(owners6);
        assertEq(w6.requiredConfirmations(), 4);
    }

    function test_RevertWhen_EmptyOwners() public {
        address[] memory empty = new address[](0);
        vm.expectRevert("Owners required");
        new MultiSigWallet(empty);
    }

    function test_RevertWhen_ZeroAddressOwner() public {
        address[] memory invalid = new address[](2);
        invalid[0] = address(0x1);
        invalid[1] = address(0);
        vm.expectRevert("Invalid owner address");
        new MultiSigWallet(invalid);
    }

    function test_RevertWhen_DuplicateOwner() public {
        address[] memory duplicate = new address[](2);
        duplicate[0] = address(0x1);
        duplicate[1] = address(0x1);
        vm.expectRevert("Owner not unique");
        new MultiSigWallet(duplicate);
    }

    // ==========================================
    // 2. proposal 测试
    // ==========================================

    function test_Proposal_Success() public {
        vm.startPrank(owner1);
        uint256 txId = wallet.proposal(address(0x888), 1 ether, "");
        vm.stopPrank();

        assertEq(txId, 0);
        assertEq(wallet.getTransactionCount(), 1);

        (address to, uint256 value, bytes memory data, bool executed, uint256 confirmationCount) =
            wallet.getTransaction(0);

        assertEq(to, address(0x888));
        assertEq(value, 1 ether);
        assertEq(data.length, 0);
        assertFalse(executed);
        // 提议人默认自动确认 1 票
        assertEq(confirmationCount, 1);
        assertTrue(wallet.isConfirmed(0, owner1));
    }

    function test_RevertWhen_ProposalNotOwner() public {
        vm.startPrank(nonOwner);
        vm.expectRevert("Not an owner");
        wallet.proposal(address(0x888), 1 ether, "");
        vm.stopPrank();
    }

    // ==========================================
    // 3. comfirm 测试
    // ==========================================

    function test_Comfirm_Success() public {
        vm.prank(owner1);
        uint256 txId = wallet.proposal(address(0x888), 1 ether, "");

        // owner2 确认
        vm.expectEmit(true, true, false, false);
        emit TransactionConfirmed(txId, owner2);

        vm.prank(owner2);
        wallet.comfirm(txId);

        (, , , , uint256 confirmationCount) = wallet.getTransaction(txId);
        assertEq(confirmationCount, 2);
        assertTrue(wallet.isConfirmed(txId, owner2));
    }

    function test_RevertWhen_ComfirmDuplicate() public {
        vm.prank(owner1);
        uint256 txId = wallet.proposal(address(0x888), 1 ether, "");

        // 提议人 owner1 已经默认确认过了
        vm.prank(owner1);
        vm.expectRevert("Transaction already confirmed");
        wallet.comfirm(txId);

        // owner2 确认一次后再次确认应该 revert
        vm.prank(owner2);
        wallet.comfirm(txId);

        vm.prank(owner2);
        vm.expectRevert("Transaction already confirmed");
        wallet.comfirm(txId);
    }

    function test_RevertWhen_ComfirmNonOwner() public {
        vm.prank(owner1);
        uint256 txId = wallet.proposal(address(0x888), 1 ether, "");

        vm.prank(nonOwner);
        vm.expectRevert("Not an owner");
        wallet.comfirm(txId);
    }

    function test_RevertWhen_ComfirmNonexistentTx() public {
        vm.prank(owner1);
        vm.expectRevert("Transaction does not exist");
        wallet.comfirm(999);
    }

    // ==========================================
    // 4. execute 测试
    // ==========================================

    function test_RevertWhen_ExecuteThresholdNotReached() public {
        vm.prank(owner1);
        uint256 txId = wallet.proposal(address(0x888), 1 ether, "");

        // 当前只有 1 票，未达到 2/3 门槛 (需要 2 票)
        vm.prank(nonOwner);
        vm.expectRevert("Cannot execute: threshold not reached");
        wallet.execute(txId);
    }

    function test_Execute_TransferETH_ByAnyone() public {
        address recipient = address(0x777);
        uint256 initialRecipientBalance = recipient.balance;
        uint256 transferAmount = 2 ether;

        // 1. owner1 提案
        vm.prank(owner1);
        uint256 txId = wallet.proposal(recipient, transferAmount, "");

        // 2. owner2 确认达到 2 票门槛
        vm.prank(owner2);
        wallet.comfirm(txId);

        // 3. 任何人（即使是 nonOwner）都可以触发执行
        vm.expectEmit(true, true, false, false);
        emit TransactionExecuted(txId, nonOwner);

        vm.prank(nonOwner);
        wallet.execute(txId);

        // 验证结果
        assertEq(recipient.balance, initialRecipientBalance + transferAmount);
        assertEq(address(wallet).balance, 8 ether);

        (, , , bool executed, ) = wallet.getTransaction(txId);
        assertTrue(executed);
    }

    function test_Execute_ExternalContractCall() public {
        // 调用 target.setMessage("Hello Multigig")
        bytes memory callData = abi.encodeWithSelector(MockTarget.setMessage.selector, "Hello Multisig");

        vm.prank(owner1);
        uint256 txId = wallet.proposal(address(target), 0, callData);

        vm.prank(owner3);
        wallet.comfirm(txId);

        // 执行交易
        vm.prank(owner2);
        wallet.execute(txId);

        assertEq(target.message(), "Hello Multisig");
    }

    function test_Execute_WithEtherAndCallData() public {
        // 调用 target.increment 并附带 1 ETH
        bytes memory callData = abi.encodeWithSelector(MockTarget.increment.selector);

        vm.prank(owner1);
        uint256 txId = wallet.proposal(address(target), 1 ether, callData);

        vm.prank(owner2);
        wallet.comfirm(txId);

        vm.prank(nonOwner);
        wallet.execute(txId);

        assertEq(target.count(), 1);
        assertEq(address(target).balance, 1 ether);
    }

    function test_RevertWhen_ExecuteAlreadyExecuted() public {
        vm.prank(owner1);
        uint256 txId = wallet.proposal(address(0x888), 1 ether, "");

        vm.prank(owner2);
        wallet.comfirm(txId);

        // 首次执行成功
        wallet.execute(txId);

        // 再次执行应该 revert
        vm.expectRevert("Transaction already executed");
        wallet.execute(txId);
    }

    function test_RevertWhen_ComfirmAlreadyExecuted() public {
        vm.prank(owner1);
        uint256 txId = wallet.proposal(address(0x888), 1 ether, "");

        vm.prank(owner2);
        wallet.comfirm(txId);

        wallet.execute(txId);

        // 已执行后再让 owner3 确认应该 revert
        vm.prank(owner3);
        vm.expectRevert("Transaction already executed");
        wallet.comfirm(txId);
    }

    function test_RevertWhen_TargetCallReverts() public {
        bytes memory callData = abi.encodeWithSelector(MockTarget.failingFunction.selector);

        vm.prank(owner1);
        uint256 txId = wallet.proposal(address(target), 0, callData);

        vm.prank(owner2);
        wallet.comfirm(txId);

        vm.expectRevert();
        wallet.execute(txId);
    }

    function test_ReceiveDeposit() public {
        uint256 initialBal = address(wallet).balance;
        vm.prank(nonOwner);
        (bool success, ) = address(wallet).call{value: 0.5 ether}("");
        assertTrue(success);
        assertEq(address(wallet).balance, initialBal + 0.5 ether);
    }
}
