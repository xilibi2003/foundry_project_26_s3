// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title MyGovernor
 * @dev 基于 OpenZeppelin Governor 模块实现的链上治理合约，使用 MyVoteToken 进行投票，
 *      支持作为 Bank.sol 的 admin 执行提取资金等治理提案。
 */
contract MyGovernor is
    Governor,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction
{
    uint256 private _votingDelay;
    uint256 private _votingPeriod;
    uint256 private _proposalThreshold;

    constructor(
        IVotes _token,
        uint256 initialVotingDelay,
        uint256 initialVotingPeriod,
        uint256 initialProposalThreshold,
        uint256 quorumNumeratorValue
    )
        Governor("MyGovernor")
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(quorumNumeratorValue)
    {
        _votingDelay = initialVotingDelay;
        _votingPeriod = initialVotingPeriod;
        _proposalThreshold = initialProposalThreshold;
    }

    /**
     * @notice 提案创建到可以开始投票之间的等待区块数
     */
    function votingDelay() public view virtual override returns (uint256) {
        return _votingDelay;
    }

    /**
     * @notice 投票持续区块数
     */
    function votingPeriod() public view virtual override returns (uint256) {
        return _votingPeriod;
    }

    /**
     * @notice 发起提案所需的最低代币门槛
     */
    function proposalThreshold() public view virtual override returns (uint256) {
        return _proposalThreshold;
    }

    /**
     * @notice 计算指定区块/时间点的法定人数（Quorum）
     */
    function quorum(uint256 blockNumber)
        public
        view
        virtual
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }


}
