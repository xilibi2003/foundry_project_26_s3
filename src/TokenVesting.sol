// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@oz/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/contracts/token/ERC20/utils/SafeERC20.sol";
import {VestingWallet} from "@oz/contracts/finance/VestingWallet.sol";
import {VestingWalletCliff} from "@oz/contracts/finance/VestingWalletCliff.sol";

/**
 * @title TokenVesting
 * @dev 基于 OpenZeppelin VestingWalletCliff 的代币线性释放合约。
 * 
 * 规则：
 * 1. beneficiary：受益人（也是 VestingWallet 的 owner）
 * 2. 锁定的 ERC20 地址：MyERC20 合约地址
 * 3. Cliff：12 个月（前 12 个月锁定期，释放 0 代币）
 * 4. 线性释放：接下来的 24 个月
 * 5. 从第 13 个月起开始每月解锁 1/24 的 MyERC20
 * 6. release()：释放当前已解锁的 MyERC20 给受益人
 * 7. 合约部署后，立即开始计算 Cliff，并支持转入 100 万 MyERC20 资产
 */
contract TokenVesting is VestingWalletCliff {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    // 时间常量定义（以 30 天为一个自然月）
    uint64 public constant MONTH = 30 days;
    uint64 public constant CLIFF_MONTHS = 12;
    uint64 public constant VESTING_MONTHS = 24;
    uint64 public constant CLIFF_DURATION = CLIFF_MONTHS * MONTH; // 12 个月 (360 天)
    uint64 public constant VESTING_DURATION = VESTING_MONTHS * MONTH; // 24 个月 (720 天)
    uint64 public constant TOTAL_DURATION = CLIFF_DURATION + VESTING_DURATION; // 36 个月 (1080 天)

    uint256 public constant TOTAL_ALLOCATION = 1_000_000 * 10 ** 18; // 100 万枚代币

    event TokensDeposited(address indexed sender, uint256 amount);

    /**
     * @notice 构造函数
     * @param _beneficiary 受益人地址
     * @param _tokenAddress 锁定的 ERC20 代币地址（MyERC20）
     */
    constructor(
        address _beneficiary,
        address _tokenAddress
    )
        VestingWallet(
            _beneficiary,
            uint64(block.timestamp),
            TOTAL_DURATION
        )
        VestingWalletCliff(CLIFF_DURATION)
    {
        require(
            _beneficiary != address(0),
            "TokenVesting: beneficiary is zero address"
        );
        require(
            _tokenAddress != address(0),
            "TokenVesting: token is zero address"
        );
        token = IERC20(_tokenAddress);
    }

    /**
     * @notice 受益人地址（别名，对应 Ownable 的 owner()）
     */
    function beneficiary() public view virtual returns (address) {
        return owner();
    }

    /**
     * @notice 存入代币到 Vesting 合约（调用方需预先调用 token.approve）
     * @param amount 存入代币数量
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "TokenVesting: deposit amount must be > 0");
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit TokensDeposited(msg.sender, amount);
    }

    /**
     * @notice 重载 release()：默认释放已解锁的 MyERC20 给受益人
     */
    function release() public virtual override {
        super.release(address(token));
    }

    /**
     * @notice 原生代币 (ETH) 释放方法
     */
    function releaseEther() public virtual {
        super.release();
    }

    /**
     * @notice 查询当前可释放的 MyERC20 数量
     */
    function releasable() public view virtual override returns (uint256) {
        return releasable(address(token));
    }

    /**
     * @notice 查询已释放给受益人的 MyERC20 数量
     */
    function released() public view virtual override returns (uint256) {
        return released(address(token));
    }

    /**
     * @notice 查询截至指定时间戳已解锁的 MyERC20 代币总量
     */
    function vestedAmount(uint64 timestamp) public view virtual override returns (uint256) {
        return vestedAmount(address(token), timestamp);
    }

    /**
     * @dev 释放计划计算公式：
     * - timestamp < cliff() (前 12 个月)：返回 0（锁定期，不释放）
     * - timestamp >= end() (第 36 个月及之后)：返回 100% totalAllocation
     * - cliff() <= timestamp < end() (第 13 个月至第 36 个月)：
     *   在接下来的 24 个月中线性释放，每月解锁 1/24
     */
    function _vestingSchedule(
        uint256 totalAllocation,
        uint64 timestamp
    ) internal view virtual override returns (uint256) {
        if (timestamp < cliff()) {
            return 0;
        } else if (timestamp >= end()) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - cliff())) / (end() - cliff());
        }
    }
}
