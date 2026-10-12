// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/uniswapv2/UniswapV2Factory.sol";
import "../src/uniswapv2/UniswapV2Router02.sol";
import "../src/uniswapv2/UniswapV2Pair.sol";
import "../src/uniswapv2/libraries/UniswapV2Library.sol";
import "../src/uniswapv2/test/ERC20.sol";
import "../src/uniswapv2/test/WETH9.sol";

contract UniswapV2Test is Test {
    UniswapV2Factory factory;
    UniswapV2Router02 router;
    WETH9 weth;
    ERC20 tokenA;
    ERC20 tokenB;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        weth = new WETH9();
        factory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02(address(factory), address(weth));

        tokenA = new ERC20(1_000_000 ether);
        tokenB = new ERC20(1_000_000 ether);

        // Distribute tokens to alice and bob
        tokenA.transfer(alice, 100_000 ether);
        tokenB.transfer(alice, 100_000 ether);
        tokenA.transfer(bob, 10_000 ether);
        tokenB.transfer(bob, 10_000 ether);

        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);

        // Alice approvals
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint).max);
        tokenB.approve(address(router), type(uint).max);
        vm.stopPrank();

        // Bob approvals
        vm.startPrank(bob);
        tokenA.approve(address(router), type(uint).max);
        tokenB.approve(address(router), type(uint).max);
        vm.stopPrank();
    }

    // ==========================================
    // 1. InitCodeHash & Pair Address Check
    // ==========================================
    function test_InitCodeHash() public pure {
        bytes32 pairInitCodeHash = keccak256(type(UniswapV2Pair).creationCode);
        assertEq(
            pairInitCodeHash,
            hex"ea120ea9530c8e386eb6d8d408a6e28aa2d018230a600ebb94ef3b973852cf18",
            "Init code hash should match UniswapV2Library"
        );
    }

    function test_PairFor_Matches_Factory() public {
        address pairFromFactory = factory.createPair(address(tokenA), address(tokenB));
        address pairFromLibrary = UniswapV2Library.pairFor(
            address(factory),
            address(tokenA),
            address(tokenB)
        );
        assertEq(pairFromLibrary, pairFromFactory, "pairFor must match factory created address");
    }

    // ==========================================
    // 2. Factory Tests
    // ==========================================
    function test_Factory_CreatePair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0), "Pair address should not be zero");
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), pair);
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
    }

    function test_Factory_RevertWhen_PairAlreadyExists() public {
        factory.createPair(address(tokenA), address(tokenB));
        vm.expectRevert("UniswapV2: PAIR_EXISTS");
        factory.createPair(address(tokenA), address(tokenB));
    }

    function test_Factory_RevertWhen_IdenticalAddresses() public {
        vm.expectRevert("UniswapV2: IDENTICAL_ADDRESSES");
        factory.createPair(address(tokenA), address(tokenA));
    }

    function test_Factory_SetFeeToAndFeeToSetter() public {
        address feeRecipient = makeAddr("feeRecipient");
        address newSetter = makeAddr("newSetter");

        factory.setFeeTo(feeRecipient);
        assertEq(factory.feeTo(), feeRecipient);

        factory.setFeeToSetter(newSetter);
        assertEq(factory.feeToSetter(), newSetter);

        // Non-setter cannot change
        vm.prank(alice);
        vm.expectRevert("UniswapV2: FORBIDDEN");
        factory.setFeeTo(alice);
    }

    // ==========================================
    // 3. Router Tests: Add & Remove Liquidity
    // ==========================================
    function test_Router_AddLiquidity() public {
        vm.prank(alice);
        (uint amountA, uint amountB, uint liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );

        assertEq(amountA, 1000 ether);
        assertEq(amountB, 1000 ether);
        assertTrue(liquidity > 0, "Liquidity should be greater than zero");

        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertEq(UniswapV2Pair(pair).balanceOf(alice), liquidity);

        (uint112 reserve0, uint112 reserve1, ) = UniswapV2Pair(pair).getReserves();
        assertEq(reserve0, 1000 ether);
        assertEq(reserve1, 1000 ether);
    }

    function test_Router_AddLiquidityETH() public {
        vm.prank(alice);
        (uint amountToken, uint amountETH, uint liquidity) = router.addLiquidityETH{value: 10 ether}(
            address(tokenA),
            100 ether,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );

        assertEq(amountToken, 100 ether);
        assertEq(amountETH, 10 ether);
        assertTrue(liquidity > 0);

        address pair = factory.getPair(address(tokenA), address(weth));
        assertEq(UniswapV2Pair(pair).balanceOf(alice), liquidity);
    }

    function test_Router_RemoveLiquidity() public {
        // Alice adds liquidity
        vm.startPrank(alice);
        (, , uint liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000 ether,
            1000 ether,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );

        address pair = factory.getPair(address(tokenA), address(tokenB));
        UniswapV2Pair(pair).approve(address(router), liquidity);

        uint balABefore = tokenA.balanceOf(alice);
        uint balBBefore = tokenB.balanceOf(alice);

        (uint amountA, uint amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        // 1000 wei is locked as MINIMUM_LIQUIDITY in Uniswap V2
        assertEq(amountA, 1000 ether - 1000);
        assertEq(amountB, 1000 ether - 1000);
        assertEq(tokenA.balanceOf(alice), balABefore + amountA);
        assertEq(tokenB.balanceOf(alice), balBBefore + amountB);
    }

    function test_Router_RemoveLiquidityETH() public {
        vm.startPrank(alice);
        (, , uint liquidity) = router.addLiquidityETH{value: 10 ether}(
            address(tokenA),
            100 ether,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );

        address pair = factory.getPair(address(tokenA), address(weth));
        UniswapV2Pair(pair).approve(address(router), liquidity);

        uint ethBefore = alice.balance;
        uint tokenABefore = tokenA.balanceOf(alice);

        (uint amountToken, uint amountETH) = router.removeLiquidityETH(
            address(tokenA),
            liquidity,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        assertTrue(amountToken > 0);
        assertTrue(amountETH > 0);
        assertEq(alice.balance, ethBefore + amountETH);
        assertEq(tokenA.balanceOf(alice), tokenABefore + amountToken);
    }

    // ==========================================
    // 4. Router Tests: Token Swaps
    // ==========================================
    function test_Router_SwapExactTokensForTokens() public {
        // Alice adds initial liquidity 10,000 A : 10,000 B
        vm.prank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000 ether,
            10_000 ether,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );

        // Bob swaps 100 TokenA for TokenB
        uint bobBBefore = tokenB.balanceOf(bob);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.prank(bob);
        uint[] memory amounts = router.swapExactTokensForTokens(
            100 ether,
            0, // min amount out
            path,
            bob,
            block.timestamp + 1 hours
        );

        uint bobBAfter = tokenB.balanceOf(bob);
        assertEq(amounts[0], 100 ether);
        assertTrue(amounts[1] > 0);
        assertEq(bobBAfter - bobBBefore, amounts[1]);
    }

    function test_Router_SwapExactETHForTokens_And_SwapExactTokensForETH() public {
        // Alice adds initial liquidity: 100 ETH : 10,000 TokenA
        vm.prank(alice);
        router.addLiquidityETH{value: 100 ether}(
            address(tokenA),
            10_000 ether,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );

        // 1. Bob swaps 1 ETH for TokenA
        address[] memory ethToTokenPath = new address[](2);
        ethToTokenPath[0] = address(weth);
        ethToTokenPath[1] = address(tokenA);

        uint bobTokenABefore = tokenA.balanceOf(bob);

        vm.prank(bob);
        uint[] memory amountsOut = router.swapExactETHForTokens{value: 1 ether}(
            0,
            ethToTokenPath,
            bob,
            block.timestamp + 1 hours
        );

        uint bobTokenAAfter = tokenA.balanceOf(bob);
        assertTrue(amountsOut[1] > 0);
        assertEq(bobTokenAAfter - bobTokenABefore, amountsOut[1]);

        // 2. Bob swaps TokenA back for ETH
        address[] memory tokenToETHPath = new address[](2);
        tokenToETHPath[0] = address(tokenA);
        tokenToETHPath[1] = address(weth);

        uint bobETHBefore = bob.balance;
        uint swapTokenAmount = amountsOut[1] / 2;

        vm.prank(bob);
        uint[] memory amountsETH = router.swapExactTokensForETH(
            swapTokenAmount,
            0,
            tokenToETHPath,
            bob,
            block.timestamp + 1 hours
        );

        uint bobETHAfter = bob.balance;
        assertTrue(amountsETH[1] > 0);
        assertEq(bobETHAfter - bobETHBefore, amountsETH[1]);
    }
}
