// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {KKToken} from "../src/KKToken.sol";
import {StakingPool} from "../src/StakingPool.sol";
import {IStaking} from "../src/IStaking.sol";

// 用于测试重入攻击的恶意合约
contract MaliciousReentrantReceiver {
    StakingPool public pool;
    bool public hasAttacked;

    constructor(address payable _pool) {
        pool = StakingPool(_pool);
    }

    function deposit() external payable {
        pool.stake{value: msg.value}();
    }

    function attack(uint256 amount) external {
        pool.unstake(amount);
    }

    receive() external payable {
        if (!hasAttacked) {
            hasAttacked = true;
            pool.unstake(1 ether);
        }
    }
}

contract StakingPoolTest is Test {
    KKToken public token;
    StakingPool public pool;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");

    function setUp() public {
        // 部署 KKToken
        token = new KKToken();

        // 部署 StakingPool
        pool = new StakingPool(address(token));

        // 授权 StakingPool 为 minter
        token.setMinter(address(pool), true);

        // 给测试用户充值 ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
    }

    function test_InitialState() public view {
        assertEq(address(pool.kkToken()), address(token));
        assertEq(pool.totalStaked(), 0);
        assertEq(pool.lastRewardBlock(), block.number);
        assertEq(pool.accTokenPerShare(), 0);
        assertEq(token.isMinter(address(pool)), true);
    }

    function test_RevertWhen_StakeZeroETH() public {
        vm.prank(alice);
        vm.expectRevert(StakingPool.ZeroAmount.selector);
        pool.stake{value: 0}();
    }

    function test_Stake_SingleUser() public {
        vm.prank(alice);
        pool.stake{value: 2 ether}();

        assertEq(pool.balanceOf(alice), 2 ether);
        assertEq(pool.totalStaked(), 2 ether);
        assertEq(address(pool).balance, 2 ether);
        assertEq(pool.earned(alice), 0);
    }

    function test_EarnedAndClaim_SingleUser() public {
        uint256 startBlock = block.number;

        vm.prank(alice);
        pool.stake{value: 1 ether}();

        // 推进 5 个区块
        vm.roll(startBlock + 5);

        // 5 个区块 * 每区块 10 KKToken = 50 KKToken
        uint256 expectedReward = 5 * 10 * 1e18;
        assertEq(pool.earned(alice), expectedReward);

        // Alice 领取奖励
        vm.prank(alice);
        pool.claim();

        assertEq(token.balanceOf(alice), expectedReward);
        // 领完后在当前区块待领奖励应为 0
        assertEq(pool.earned(alice), 0);

        // 再过 3 个区块
        vm.roll(startBlock + 8);
        assertEq(pool.earned(alice), 3 * 10 * 1e18);

        vm.prank(alice);
        pool.claim();
        assertEq(token.balanceOf(alice), (5 + 3) * 10 * 1e18);
    }

    function test_MasterChefFairDistribution_TwoUsers() public {
        // 区块 100: Alice 质押 1 ETH
        vm.roll(100);
        vm.prank(alice);
        pool.stake{value: 1 ether}();

        // 区块 110: 经过 10 个区块，Bob 质押 3 ETH
        // 这 10 个区块共产出 10 * 10 = 100 KKToken，由 Alice 独享
        vm.roll(110);
        vm.prank(bob);
        pool.stake{value: 3 ether}();

        // 在区块 110，Alice 此时待领收益为 100 KKToken，Bob 收益为 0
        assertEq(pool.earned(alice), 100 ether);
        assertEq(pool.earned(bob), 0);

        // 区块 120: 又经过 10 个区块，共产出 100 KKToken
        // Alice 份额: 1 / 4, 获得 25 KKToken -> 累计 100 + 25 = 125 KKToken
        // Bob 份额: 3 / 4, 获得 75 KKToken -> 累计 75 KKToken
        vm.roll(120);
        assertEq(pool.earned(alice), 125 ether);
        assertEq(pool.earned(bob), 75 ether);

        // Alice 领取奖励
        vm.prank(alice);
        pool.claim();
        assertEq(token.balanceOf(alice), 125 ether);
        assertEq(pool.earned(alice), 0);

        // Bob 领取奖励
        vm.prank(bob);
        pool.claim();
        assertEq(token.balanceOf(bob), 75 ether);
        assertEq(pool.earned(bob), 0);
    }

    function test_Unstake_PartialAndFull() public {
        vm.roll(100);
        vm.prank(alice);
        pool.stake{value: 5 ether}();

        // 推进到区块 105
        vm.roll(105);
        // 部分提现 2 ETH
        uint256 aliceEthBefore = alice.balance;
        vm.prank(alice);
        pool.unstake(2 ether);

        assertEq(alice.balance, aliceEthBefore + 2 ether);
        assertEq(pool.balanceOf(alice), 3 ether);
        assertEq(pool.totalStaked(), 3 ether);
        // unstake 时已自动发放之前 5 个区块的 50 KKToken 奖励，无需额外发起 claim
        assertEq(token.balanceOf(alice), 5 * 10 * 1e18);
        assertEq(pool.earned(alice), 0);

        // 推进到区块 110 (又过 5 个区块)
        vm.roll(110);
        // 这 5 个区块 Alice 独享新产生的 50 KKToken
        assertApproxEqAbs(pool.earned(alice), 50 ether, 1);

        // 全部提现剩余 3 ETH: 同样自动发放这 50 KKToken
        vm.prank(alice);
        pool.unstake(3 ether);
        assertEq(pool.balanceOf(alice), 0);
        assertEq(pool.totalStaked(), 0);
        assertApproxEqAbs(token.balanceOf(alice), 100 ether, 1);
        assertEq(pool.earned(alice), 0);

        // 推进到区块 120 (又过 10 个区块，此时质押量为 0，无人质押不产生奖励)
        vm.roll(120);
        assertEq(pool.earned(alice), 0);

        // Alice 已全部领取，再次 claim 会 revert NoRewardToClaim
        vm.prank(alice);
        vm.expectRevert(StakingPool.NoRewardToClaim.selector);
        pool.claim();
    }

    function test_NoRewardDuringEmptyPool() public {
        // 部署在区块 100，直到区块 150 都没有人质押
        vm.roll(150);

        // Alice 在区块 150 质押
        vm.prank(alice);
        pool.stake{value: 1 ether}();

        // 区块 151 时，Alice 应该只有 1 个区块的奖励 (10 KKToken)，而不是前 50 个区块
        vm.roll(151);
        assertEq(pool.earned(alice), 10 ether);
    }

    function test_AdditionalStake_UpdatesPendingCorrectly() public {
        vm.roll(100);
        vm.prank(alice);
        pool.stake{value: 1 ether}();

        // 推进到区块 105
        vm.roll(105);
        // 此时产生 50 ether 奖励，Alice 追加质押 1 ETH
        vm.prank(alice);
        pool.stake{value: 1 ether}();

        assertEq(pool.balanceOf(alice), 2 ether);
        assertEq(pool.earned(alice), 50 ether);

        // 推进到区块 110 (又过 5 个区块)
        vm.roll(110);
        // 5 * 10 = 50 ether, 加上之前的 50 ether = 100 ether
        assertEq(pool.earned(alice), 100 ether);

        vm.prank(alice);
        pool.claim();
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function test_RevertWhen_UnstakeMoreThanBalance() public {
        vm.prank(alice);
        pool.stake{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(StakingPool.InsufficientBalance.selector);
        pool.unstake(2 ether);
    }

    function test_RevertWhen_UnstakeZero() public {
        vm.prank(alice);
        pool.stake{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(StakingPool.ZeroAmount.selector);
        pool.unstake(0);
    }

    function test_RevertWhen_ClaimWithZeroReward() public {
        vm.prank(alice);
        vm.expectRevert(StakingPool.NoRewardToClaim.selector);
        pool.claim();
    }

    function test_RevertWhen_DirectETHTransfer() public {
        vm.prank(alice);
        (bool ok, ) = address(pool).call{value: 1 ether}("");
        assertFalse(ok);
    }

    function test_ReentrancyProtection_OnUnstake() public {
        MaliciousReentrantReceiver attacker = new MaliciousReentrantReceiver(payable(address(pool)));
        vm.deal(address(attacker), 10 ether);

        attacker.deposit{value: 2 ether}();

        // 攻击者尝试重入 unstake 会因为 ReentrancyGuard 而 revert
        vm.expectRevert();
        attacker.attack(1 ether);
    }

    function test_KKToken_OnlyMinterCanMint() public {
        vm.prank(alice);
        vm.expectRevert(KKToken.NotAuthorizedMinter.selector);
        token.mint(alice, 100 ether);

        // Owner 可以铸造
        token.mint(alice, 50 ether);
        assertEq(token.balanceOf(alice), 50 ether);
    }
}
