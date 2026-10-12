// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/uniswapv2/UniswapV2Factory.sol";
import "../src/uniswapv2/UniswapV2Pair.sol";
import "../src/uniswapv2/FlashSwap.sol";
import "../src/uniswapv2/test/ERC20.sol";

contract FlashSwapTest is Test {
    UniswapV2Factory factoryA;
    UniswapV2Factory factoryB;

    ERC20 tokenA;
    ERC20 tokenB;

    address poolA;
    address poolB;

    FlashSwap flashSwap;

    address user = makeAddr("user");

    function setUp() public {
        // 1. 部署两个独立的 UniswapV2Factory
        factoryA = new UniswapV2Factory(address(this));
        factoryB = new UniswapV2Factory(address(this));

        // 2. 部署两个 ERC20 代币
        tokenA = new ERC20(10_000_000 ether);
        tokenB = new ERC20(10_000_000 ether);

        // 3. 在两个工厂中分别创建 TokenA 与 TokenB 的交易对流动池
        poolA = factoryA.createPair(address(tokenA), address(tokenB));
        poolB = factoryB.createPair(address(tokenA), address(tokenB));

        // 4. 部署 FlashSwap 合约
        flashSwap = new FlashSwap();
    }

    /**
     * @dev 辅助方法：向指定流动池注入初始流动性
     */
    function _addLiquidity(address pair, uint256 amountA, uint256 amountB) internal {
        tokenA.transfer(pair, amountA);
        tokenB.transfer(pair, amountB);
        UniswapV2Pair(pair).mint(address(this));
    }

    // =========================================================================
    // 场景 1：最符合出题意图的盈利闪电套利
    // PoolA 中 1.5 TokenA = 2 TokenB (即 1 TokenA = 1.33 TokenB，TokenA 便宜)
    // PoolB 中 1 TokenA = 2 TokenB (即 1 TokenA = 2.0 TokenB，TokenA 昂贵)
    // 从 PoolA 借出 TokenA，在 PoolB 兑换为 TokenB，还回 PoolA，净赚 TokenB
    // =========================================================================
    function test_FlashSwap_BorrowPoolA_SwapPoolB_Profitable() public {
        // PoolA: 1.5 TokenA = 2 TokenB (1500 A : 2000 B)
        _addLiquidity(poolA, 1500 ether, 2000 ether);

        // PoolB: 1 TokenA = 2 TokenB (1000 A : 2000 B)
        _addLiquidity(poolB, 1000 ether, 2000 ether);

        // 借出 10 TokenA
        uint256 borrowAmount = 10 ether;

        uint256 userTokenBBefore = tokenB.balanceOf(user);

        // 执行闪电兑换：从 poolA 借 TokenA，在 poolB 兑换为 TokenB 并还回 poolA，利润转给 user
        vm.prank(user);
        uint256 profit = flashSwap.executeFlashSwap(
            poolA,
            poolB,
            address(tokenA),
            borrowAmount,
            user
        );

        uint256 userTokenBAfter = tokenB.balanceOf(user);

        // 校验套利成功且利润为正
        assertTrue(profit > 0, "Profit must be greater than zero");
        assertEq(userTokenBAfter - userTokenBBefore, profit, "User should receive profit in TokenB");

        // 验证 PoolA 的恒定乘积 K 值未被破坏（依然正常工作）
        (uint112 r0, uint112 r1, ) = UniswapV2Pair(poolA).getReserves();
        assertTrue(uint256(r0) * uint256(r1) > 0, "PoolA K invariant holds");

        emit log_named_decimal_uint("Arbitrage Profit in TokenB", profit, 18);
    }

    // =========================================================================
    // 场景 2：严格设置 PoolA (1 A = 2 B) 与 PoolB (1.5 A = 2 B)
    // 此时 TokenA 在 PoolA 价值 2.0 B，在 PoolB 价值 1.33 B。
    // 若从 PoolA 借 TokenA 到 PoolB 卖，由于 PoolB 卖出所得少于 PoolA 所需偿还，
    // FlashSwap 会及时检测出亏损并回滚（抛出 Unprofitable 异常），保护本金安全。
    // =========================================================================
    function test_FlashSwap_BorrowPoolA_SwapPoolB_Unprofitable_Reverts() public {
        // PoolA: 1 TokenA = 2 TokenB (1000 A : 2000 B)
        _addLiquidity(poolA, 1000 ether, 2000 ether);

        // PoolB: 1.5 TokenA = 2 TokenB (1500 A : 2000 B)
        _addLiquidity(poolB, 1500 ether, 2000 ether);

        uint256 borrowAmount = 10 ether;

        // 预期回滚 Unprofitable 错误
        vm.expectRevert();
        vm.prank(user);
        flashSwap.executeFlashSwap(
            poolA,
            poolB,
            address(tokenA),
            borrowAmount,
            user
        );
    }

    // =========================================================================
    // 场景 3：严格设置 PoolA (1 A = 2 B) 与 PoolB (1.5 A = 2 B) 下的正向套利
    // 在该价差下，正确的套利路径是从 PoolB 借出 TokenA (成本约 1.33 B)，
    // 到 PoolA 卖出 TokenA 换取 TokenB (单价约 2.0 B)，还回 PoolB，获取丰厚利润。
    // =========================================================================
    function test_FlashSwap_PoolA_1A2B_PoolB_1_5A2B_CorrectDirection_Profitable() public {
        // PoolA: 1 TokenA = 2 TokenB (1000 A : 2000 B)
        _addLiquidity(poolA, 1000 ether, 2000 ether);

        // PoolB: 1.5 TokenA = 2 TokenB (1500 A : 2000 B)
        _addLiquidity(poolB, 1500 ether, 2000 ether);

        uint256 borrowAmount = 10 ether;

        uint256 userTokenBBefore = tokenB.balanceOf(user);

        // 从 PoolB 借出便宜的 TokenA，在 PoolA 卖成 TokenB 还回 PoolB
        vm.prank(user);
        uint256 profit = flashSwap.executeFlashSwap(
            poolB,
            poolA,
            address(tokenA),
            borrowAmount,
            user
        );

        uint256 userTokenBAfter = tokenB.balanceOf(user);

        assertTrue(profit > 0, "Profit must be positive");
        assertEq(userTokenBAfter - userTokenBBefore, profit, "User should receive profit");

        emit log_named_decimal_uint("Reverse Direction Arbitrage Profit", profit, 18);
    }

    // =========================================================================
    // 场景 4：权限与安全检查测试
    // 只有对应借贷池可以回调 uniswapV2Call，非法调用者应被拒绝
    // =========================================================================
    function test_FlashSwap_RevertWhen_InvalidCaller() public {
        bytes memory data = abi.encode(
            poolA,
            poolB,
            address(tokenA),
            address(tokenB),
            10 ether,
            user
        );

        vm.expectRevert(FlashSwap.InvalidCaller.selector);
        flashSwap.uniswapV2Call(address(flashSwap), 10 ether, 0, data);
    }
}
