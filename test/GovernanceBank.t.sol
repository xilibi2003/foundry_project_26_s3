// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Bank} from "../src/bank.sol";
import {MyVoteToken} from "../src/MyVoteToken.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract GovernanceBankTest is Test {
    MyVoteToken public voteToken;
    MyGovernor public governor;
    Bank public bank;

    address public proposer = makeAddr("proposer");
    address public voter1 = makeAddr("voter1");
    address public voter2 = makeAddr("voter2");
    address public depositor = makeAddr("depositor");

    uint256 public constant VOTING_DELAY = 1; // 1 block
    uint256 public constant VOTING_PERIOD = 5; // 5 blocks
    uint256 public constant PROPOSAL_THRESHOLD = 0; // 0 tokens required to propose
    uint256 public constant QUORUM_PERCENTAGE = 4; // 4%

    function setUp() public {
        // 1. 部署治理代币 MyVoteToken
        voteToken = new MyVoteToken("Governance Vote Token", "MVT");

        // 2. 部署治理合约 MyGovernor
        governor = new MyGovernor(
            voteToken,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            QUORUM_PERCENTAGE
        );

        // 3. 由 MyGovernor 作为部署者创建 Bank，使其成为 Bank 的 admin
        vm.prank(address(governor));
        bank = new Bank();
        assertEq(bank.admin(), address(governor), "Governor should be Bank admin");

        // 4. 分配投票代币并委托投票权
        voteToken.mint(voter1, 1000 ether);
        voteToken.mint(voter2, 500 ether);

        // ERC20Votes 必须显式委托才能激活票数 Checkpoints
        vm.prank(voter1);
        voteToken.delegate(voter1);

        vm.prank(voter2);
        voteToken.delegate(voter2);

        // 5. 推进一个区块，使委托产生的检查点生效
        vm.roll(block.number + 1);

        // 6. 模拟储户向 Bank 存入 10 ETH
        vm.deal(depositor, 20 ether);
        vm.prank(depositor);
        bank.deposit{value: 10 ether}();
        assertEq(address(bank).balance, 10 ether, "Bank should have 10 ETH");
    }

    /// @dev 测试完整的提案 -> 投票 -> 统计通过 -> 执行 Bank.withdraw() 提取资金流程
    function test_ProposalVoteAndWithdrawSuccess() public {
        uint256 withdrawAmount = 4 ether;

        // 1. 准备提案参数
        address[] memory targets = new address[](1);
        targets[0] = address(bank);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(Bank.withdraw.selector, withdrawAmount);

        string memory description = "Proposal #1: Withdraw 4 ETH from Bank";

        // 2. 发起提案
        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // 提案初始状态为 Pending
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Pending),
            "State should be Pending"
        );

        // 3. 推进区块度过 votingDelay
        vm.roll(block.number + VOTING_DELAY + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Active),
            "State should be Active"
        );

        // 4. 投票 (1 = For)
        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        // 5. 推进区块直到投票期结束
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 状态应变为 Succeeded
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Succeeded),
            "State should be Succeeded"
        );

        // 6. 记录执行前余额
        uint256 bankBalanceBefore = address(bank).balance;
        uint256 governorBalanceBefore = address(governor).balance;

        // 7. 执行提案
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.execute(targets, values, calldatas, descriptionHash);

        // 验证提案状态为 Executed
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Executed),
            "State should be Executed"
        );

        // 8. 验证资金成功从 Bank 提取到 admin (MyGovernor) 合约
        assertEq(
            address(bank).balance,
            bankBalanceBefore - withdrawAmount,
            "Bank balance should decrease by withdrawAmount"
        );
        assertEq(
            address(governor).balance,
            governorBalanceBefore + withdrawAmount,
            "Governor balance should increase by withdrawAmount"
        );
    }

    /// @dev 测试非 Admin 直接调用 Bank.withdraw() 会被拒绝
    function test_DirectWithdrawRevertsForNonAdmin() public {
        vm.prank(voter1);
        vm.expectRevert("Bank: caller is not admin");
        bank.withdraw(1 ether);
    }

    /// @dev 测试投票反对票多于赞成票时提案失败，无法执行 withdraw
    function test_ProposalDefeatedWhenAgainstWins() public {
        uint256 withdrawAmount = 2 ether;

        address[] memory targets = new address[](1);
        targets[0] = address(bank);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(Bank.withdraw.selector, withdrawAmount);
        string memory description = "Proposal #2: Defeated withdraw";

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // 进入投票期
        vm.roll(block.number + VOTING_DELAY + 1);

        // voter1 (1000 票) 投反对票 (0 = Against)
        // voter2 (500 票) 投赞成票 (1 = For)
        vm.prank(voter1);
        governor.castVote(proposalId, 0);

        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        // 推进到投票期结束
        vm.roll(block.number + VOTING_PERIOD + 1);

        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Defeated),
            "State should be Defeated"
        );

        // 尝试执行被否决的提案应该 revert
        bytes32 descriptionHash = keccak256(bytes(description));
        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
    }
}
