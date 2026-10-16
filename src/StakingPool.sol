// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@oz/contracts/utils/ReentrancyGuard.sol";
import {IToken} from "./IToken.sol";
import {IStaking} from "./IStaking.sol";

/**
 * @title StakingPool
 * @dev 允许任何人质押 ETH 赚取 KKToken。
 * 参考 Sushiswap MasterChef 模型实现按区块产出与质押份额/时长的公平奖励分配。
 * - 每区块固定产出 10 KKToken (10 * 1e18)。
 * - 按质押的 ETH 比例与区块跨度分配奖励。
 */
contract StakingPool is IStaking, ReentrancyGuard {
    /// @notice 奖励代币 KKToken 接口
    IToken public immutable kkToken;

    /// @notice 每个区块产出的 KKToken 数量 (10 个，精度 18 位)
    uint256 public constant REWARD_PER_BLOCK = 10 * 1e18;

    /// @notice 精度放大系数，避免整除截断 (高精度 1e36 避免精度损失)
    uint256 private constant ACC_TOKEN_PRECISION = 1e36;

    /// @notice 当前池中质押的 ETH 总量
    uint256 public totalStaked;

    /// @notice 上次更新奖励池时的区块号
    uint256 public lastRewardBlock;

    /// @notice 每单位质押 ETH 累积分配的 KKToken 数量 (放大 ACC_TOKEN_PRECISION 倍)
    uint256 public accTokenPerShare;

    /// @notice 用户质押信息结构体
    struct UserInfo {
        uint256 amount;         // 用户质押的 ETH 数量
        uint256 rewardDebt;     // 奖励债务 (MasterChef 算法中的已扣除基数)
        uint256 pendingRewards; // 已结算但尚未领取的 KKToken 收益
    }

    /// @notice 记录每个用户的质押信息
    mapping(address => UserInfo) public userInfo;

    // 自定义错误
    error ZeroAmount();
    error InsufficientBalance();
    error ETHTransferFailed();
    error NoRewardToClaim();
    error ZeroTokenAddress();

    // 事件
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);

    /**
     * @notice 构造函数
     * @param _kkToken KKToken 代币合约地址
     */
    constructor(address _kkToken) {
        if (_kkToken == address(0)) revert ZeroTokenAddress();
        kkToken = IToken(_kkToken);
        lastRewardBlock = block.number;
    }

    /**
     * @notice 更新奖励池状态 (MasterChef updatePool)
     * 计算并累加自上次更新区块以来的每份额奖励
     */
    function updatePool() public {
        if (block.number <= lastRewardBlock) {
            return;
        }

        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 blocks = block.number - lastRewardBlock;
        uint256 tokenReward = blocks * REWARD_PER_BLOCK;
        accTokenPerShare += (tokenReward * ACC_TOKEN_PRECISION) / totalStaked;
        lastRewardBlock = block.number;
    }

    /**
     * @notice 质押 ETH 到合约
     */
    function stake() payable external override nonReentrant {
        if (msg.value == 0) revert ZeroAmount();

        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        if (user.amount > 0) {
            user.pendingRewards += (user.amount * accTokenPerShare) / ACC_TOKEN_PRECISION - user.rewardDebt;
        }

        user.amount += msg.value;
        totalStaked += msg.value;
        user.rewardDebt = (user.amount * accTokenPerShare) / ACC_TOKEN_PRECISION;

        emit Staked(msg.sender, msg.value);
    }

    /**
     * @notice 赎回质押的 ETH，并自动结算领取累积的 KKToken 收益 (一笔交易完成赎回与领奖)
     * @param amount 赎回数量
     */
    function unstake(uint256 amount) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();

        UserInfo storage user = userInfo[msg.sender];
        if (user.amount < amount) revert InsufficientBalance();

        updatePool();

        // 1. 计算待发放的总收益 (历史未领取 + 当前区间新增)
        uint256 reward = user.pendingRewards + (user.amount * accTokenPerShare) / ACC_TOKEN_PRECISION - user.rewardDebt;

        // 2. 更新质押本金、清空未领收益并更新 rewardDebt
        user.amount -= amount;
        totalStaked -= amount;
        user.rewardDebt = (user.amount * accTokenPerShare) / ACC_TOKEN_PRECISION;
        user.pendingRewards = 0;

        // 3. 若有收益，直接一并发放，省去用户额外调用 claim 的交易与 Gas
        if (reward > 0) {
            kkToken.mint(msg.sender, reward);
            emit Claimed(msg.sender, reward);
        }

        // 4. Checks-Effects-Interactions 安全退还 ETH 本金
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert ETHTransferFailed();

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice 领取 KK Token 收益
     */
    function claim() external override nonReentrant {
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        uint256 reward = user.pendingRewards + (user.amount * accTokenPerShare) / ACC_TOKEN_PRECISION - user.rewardDebt;
        if (reward == 0) revert NoRewardToClaim();

        user.pendingRewards = 0;
        user.rewardDebt = (user.amount * accTokenPerShare) / ACC_TOKEN_PRECISION;

        kkToken.mint(msg.sender, reward);

        emit Claimed(msg.sender, reward);
    }

    /**
     * @notice 获取质押的 ETH 数量
     * @param account 质押账户
     * @return 质押的 ETH 数量
     */
    function balanceOf(address account) external view override returns (uint256) {
        return userInfo[account].amount;
    }

    /**
     * @notice 获取待领取的 KK Token 收益
     * @param account 质押账户
     * @return 待领取的 KK Token 收益
     */
    function earned(address account) public view override returns (uint256) {
        UserInfo memory user = userInfo[account];
        uint256 _accTokenPerShare = accTokenPerShare;

        if (block.number > lastRewardBlock && totalStaked != 0) {
            uint256 blocks = block.number - lastRewardBlock;
            uint256 tokenReward = blocks * REWARD_PER_BLOCK;
            _accTokenPerShare += (tokenReward * ACC_TOKEN_PRECISION) / totalStaked;
        }

        return user.pendingRewards + (user.amount * _accTokenPerShare) / ACC_TOKEN_PRECISION - user.rewardDebt;
    }

    /**
     * @dev 防止直接转入 ETH 导致资金未通过 stake() 记账
     */
    receive() external payable {
        revert("Use stake() to deposit ETH");
    }

    fallback() external payable {
        revert("Invalid call");
    }
}
