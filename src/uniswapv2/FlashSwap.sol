// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IUniswapV2Callee.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IERC20.sol";
import "./libraries/UniswapV2Library.sol";

/**
 * @title FlashSwap
 * @notice Uniswap V2 闪电兑换合约：
 *         从借贷池 (PoolA) 借出 TokenA，并在回调函数 uniswapV2Call 中，
 *         将 TokenA 拿到兑换池 (PoolB) 兑换为 TokenB，
 *         再将所需的 TokenB 偿还给借贷池 (PoolA)，将剩余利润转给接收者。
 */
contract FlashSwap is IUniswapV2Callee {
    /// @notice 闪电兑换执行成功事件
    event FlashSwapExecuted(
        address indexed poolBorrow,
        address indexed poolSwap,
        address tokenBorrow,
        address tokenRepay,
        uint256 amountBorrow,
        uint256 amountRepayOut,
        uint256 amountRepayRequired,
        uint256 profit
    );

    error InvalidCaller();
    error InvalidSender();
    error InvalidTokens();
    error Unprofitable(uint256 amountRepayOut, uint256 amountRepayRequired);

    /// @notice 记录最近一次套利获得的利润
    uint256 public lastProfit;

    /**
     * @notice 发起闪电兑换
     * @param poolBorrow 借出代币的池子（如 PoolA）
     * @param poolSwap 兑换代币的池子（如 PoolB）
     * @param tokenBorrow 借出的代币（如 TokenA）
     * @param amountBorrow 借出的代币数量
     * @param recipient 利润接收地址
     */
    function executeFlashSwap(
        address poolBorrow,
        address poolSwap,
        address tokenBorrow,
        uint256 amountBorrow,
        address recipient
    ) external returns (uint256 profit) {
        address token0 = IUniswapV2Pair(poolBorrow).token0();
        address token1 = IUniswapV2Pair(poolBorrow).token1();
        if (tokenBorrow != token0 && tokenBorrow != token1) {
            revert InvalidTokens();
        }

        address tokenRepay = tokenBorrow == token0 ? token1 : token0;

        uint256 amount0Out = tokenBorrow == token0 ? amountBorrow : 0;
        uint256 amount1Out = tokenBorrow == token1 ? amountBorrow : 0;

        bytes memory data = abi.encode(
            poolBorrow,
            poolSwap,
            tokenBorrow,
            tokenRepay,
            amountBorrow,
            recipient
        );

        // 触发 PoolBorrow 的 swap 并传入非空 data 触发回调 uniswapV2Call
        IUniswapV2Pair(poolBorrow).swap(
            amount0Out,
            amount1Out,
            address(this),
            data
        );

        profit = lastProfit;
    }

    /**
     * @notice Uniswap V2 闪电兑换回调函数
     * @param sender 发起 swap 的地址
     * @param data 附加数据
     */
    function uniswapV2Call(
        address sender,
        uint256 /* amount0 */,
        uint256 /* amount1 */,
        bytes calldata data
    ) external override {
        (
            address poolBorrow,
            address poolSwap,
            address tokenBorrow,
            address tokenRepay,
            uint256 amountBorrow,
            address recipient
        ) = abi.decode(
                data,
                (address, address, address, address, uint256, address)
            );

        // 安全检查：必须由借贷池调用，且发起者必须为本合约
        if (msg.sender != poolBorrow) revert InvalidCaller();
        if (sender != address(this)) revert InvalidSender();

        // 1. 将借得的 tokenBorrow (TokenA) 发送给 poolSwap (PoolB) 执行兑换
        IERC20(tokenBorrow).transfer(poolSwap, amountBorrow);

        // 2. 计算在 poolSwap 兑换能够换取的 tokenRepay (TokenB) 数量
        (
            uint112 reserve0_Swap,
            uint112 reserve1_Swap,

        ) = IUniswapV2Pair(poolSwap).getReserves();
        address swapToken0 = IUniswapV2Pair(poolSwap).token0();
        (uint256 reserveIn_Swap, uint256 reserveOut_Swap) = tokenBorrow ==
            swapToken0
            ? (uint256(reserve0_Swap), uint256(reserve1_Swap))
            : (uint256(reserve1_Swap), uint256(reserve0_Swap));

        uint256 amountRepayOut = UniswapV2Library.getAmountOut(
            amountBorrow,
            reserveIn_Swap,
            reserveOut_Swap
        );

        // 3. 在 poolSwap 上调用 swap，将换取的 tokenRepay (TokenB) 转回本合约
        uint256 swapAmount0Out = tokenRepay == swapToken0 ? amountRepayOut : 0;
        uint256 swapAmount1Out = tokenRepay == swapToken0 ? 0 : amountRepayOut;
        IUniswapV2Pair(poolSwap).swap(
            swapAmount0Out,
            swapAmount1Out,
            address(this),
            new bytes(0)
        );

        // 4. 计算需偿还给 poolBorrow (PoolA) 的 tokenRepay (TokenB) 数量
        // 需满足借贷池的恒定乘积 K 值检查：(reserveBorrow - amountBorrow) * (reserveRepay + amountRepayRequired * 0.997) >= reserveBorrow * reserveRepay
        (
            uint112 reserve0_Borrow,
            uint112 reserve1_Borrow,

        ) = IUniswapV2Pair(poolBorrow).getReserves();
        address borrowToken0 = IUniswapV2Pair(poolBorrow).token0();
        (
            uint256 reserveBorrow_Borrow,
            uint256 reserveRepay_Borrow
        ) = tokenBorrow == borrowToken0
                ? (uint256(reserve0_Borrow), uint256(reserve1_Borrow))
                : (uint256(reserve1_Borrow), uint256(reserve0_Borrow));

        uint256 amountRepayRequired = UniswapV2Library.getAmountIn(
            amountBorrow,
            reserveRepay_Borrow,
            reserveBorrow_Borrow
        );

        // 5. 校验套利是否能够覆盖偿还成本
        if (amountRepayOut < amountRepayRequired) {
            revert Unprofitable(amountRepayOut, amountRepayRequired);
        }

        // 6. 将所需偿还的 tokenRepay 还回到借贷池 poolBorrow (PoolA)
        IERC20(tokenRepay).transfer(poolBorrow, amountRepayRequired);

        // 7. 计算纯利润并转给 recipient
        uint256 profit = amountRepayOut - amountRepayRequired;
        lastProfit = profit;

        if (profit > 0 && recipient != address(0)) {
            IERC20(tokenRepay).transfer(recipient, profit);
        }

        emit FlashSwapExecuted(
            poolBorrow,
            poolSwap,
            tokenBorrow,
            tokenRepay,
            amountBorrow,
            amountRepayOut,
            amountRepayRequired,
            profit
        );
    }
}
