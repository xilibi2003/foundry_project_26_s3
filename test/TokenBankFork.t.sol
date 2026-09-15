// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {TokenBank} from "../src/TokenBank.sol";
import {IERC20} from "@oz/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice 以太坊主网 USDT 接口（主网 USDT 未实现标准 ERC20 的返回值 bool，调用时不校验返回值）
 */
interface IERC20Usdt {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external;
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external;
}

/**
 * @title TokenBankForkTest
 * @notice 以太坊主网 Fork 测试：测试使用主网真实 USDT（0xdAC17F958D2ee523a2206206994597C13D831ec7）进行存款与提取
 */
contract TokenBankForkTest is Test {
    using SafeERC20 for IERC20;

    // 主网 USDT 真实地址
    address public constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    // 默认主网 RPC URL
    string public constant DEFAULT_RPC_URL = "https://ethereum-mainnet.gateway.tatum.io";

    TokenBank public tokenBank;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function setUp() public {
        // 优先从环境变量 MAINNET_RPC_URL 读取，其次读取 foundry.toml 中的 mainnet rpc，最后兜底默认 URL
        string memory rpcUrl;
        try vm.envString("MAINNET_RPC_URL") returns (string memory envUrl) {
            rpcUrl = envUrl;
        } catch {
            try vm.rpcUrl("mainnet") returns (string memory configUrl) {
                rpcUrl = configUrl;
            } catch {
                rpcUrl = DEFAULT_RPC_URL;
            }
        }

        // 创建并选中主网 Fork
        vm.createSelectFork(rpcUrl);

        // 部署绑定主网 USDT 的 TokenBank 合约
        tokenBank = new TokenBank(USDT_ADDRESS);
    }

    /// @dev 测试主网 USDT 基础存款功能及账本记录
    function test_ForkDepositUSDT() public {
        uint256 depositAmount = 1000 * 1e6; // 1000 USDT (USDT 为 6 位精度)

        // 使用 deal 给 Alice 分配 1000 USDT
        deal(USDT_ADDRESS, alice, depositAmount);
        assertEq(IERC20(USDT_ADDRESS).balanceOf(alice), depositAmount, "Alice initial balance mismatch");

        // Alice 授权并存入 TokenBank
        vm.startPrank(alice);
        IERC20Usdt(USDT_ADDRESS).approve(address(tokenBank), depositAmount);

        // 期待触发 Deposit 事件
        vm.expectEmit(true, false, false, true, address(tokenBank));
        emit Deposit(alice, depositAmount);
        tokenBank.deposit(depositAmount);
        vm.stopPrank();

        // 验证 TokenBank 内部记账
        assertEq(tokenBank.balances(alice), depositAmount, "Alice TokenBank balance mismatch");
        assertEq(tokenBank.getBalance(alice), depositAmount, "Alice getBalance mismatch");

        // 验证链上实际 USDT 余额转移
        assertEq(IERC20(USDT_ADDRESS).balanceOf(address(tokenBank)), depositAmount, "TokenBank USDT balance mismatch");
        assertEq(IERC20(USDT_ADDRESS).balanceOf(alice), 0, "Alice final USDT balance mismatch");
    }

    /// @dev 测试多次追加存款，验证余额正确累加
    function test_ForkDepositUSDT_MultipleTimes() public {
        uint256 firstAmount = 500 * 1e6;
        uint256 secondAmount = 700 * 1e6;
        uint256 totalAmount = firstAmount + secondAmount;

        deal(USDT_ADDRESS, alice, totalAmount);

        vm.startPrank(alice);
        IERC20Usdt(USDT_ADDRESS).approve(address(tokenBank), totalAmount);

        // 第一次存款
        tokenBank.deposit(firstAmount);
        assertEq(tokenBank.balances(alice), firstAmount);

        // 第二次追加存款
        tokenBank.deposit(secondAmount);
        assertEq(tokenBank.balances(alice), totalAmount);
        vm.stopPrank();

        assertEq(IERC20(USDT_ADDRESS).balanceOf(address(tokenBank)), totalAmount);
    }

    /// @dev 测试存款金额为 0 时回滚
    function test_RevertWhen_DepositZero() public {
        vm.prank(alice);
        vm.expectRevert("TokenBank: deposit amount must be > 0");
        tokenBank.deposit(0);
    }

    /// @dev 测试未授权额度直接存款时回滚
    function test_RevertWhen_DepositWithoutApproval() public {
        uint256 depositAmount = 100 * 1e6;
        deal(USDT_ADDRESS, alice, depositAmount);

        vm.prank(alice);
        // 未执行 approve 直接 deposit，底层 transferFrom 应回滚
        vm.expectRevert();
        tokenBank.deposit(depositAmount);
    }

    /// @dev 测试存款后提取 USDT，验证 SafeERC20 同样支持 USDT 的非标 transfer
    function test_ForkWithdrawUSDT() public {
        uint256 depositAmount = 1000 * 1e6;
        uint256 withdrawAmount = 400 * 1e6;

        deal(USDT_ADDRESS, alice, depositAmount);

        vm.startPrank(alice);
        IERC20Usdt(USDT_ADDRESS).approve(address(tokenBank), depositAmount);
        tokenBank.deposit(depositAmount);

        // 提取 400 USDT
        vm.expectEmit(true, false, false, true, address(tokenBank));
        emit Withdraw(alice, withdrawAmount);
        tokenBank.withdraw(withdrawAmount);
        vm.stopPrank();

        // 验证余额与记账
        assertEq(tokenBank.balances(alice), depositAmount - withdrawAmount);
        assertEq(IERC20(USDT_ADDRESS).balanceOf(alice), withdrawAmount);
        assertEq(IERC20(USDT_ADDRESS).balanceOf(address(tokenBank)), depositAmount - withdrawAmount);
    }
}
