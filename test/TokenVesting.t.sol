// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MyERC20} from "../src/MyERC20.sol";
import {TokenVesting} from "../src/TokenVesting.sol";

contract TokenVestingTest is Test {
    MyERC20 public token;
    TokenVesting public vesting;

    address public deployer;
    address public beneficiary = makeAddr("beneficiary");
    address public caller = makeAddr("caller");

    uint256 public constant TOTAL_TOKENS = 1_000_000 * 10 ** 18;
    uint64 public constant MONTH = 30 days;

    function setUp() public {
        deployer = address(this);

        // 1. 部署 MyERC20（初始铸造 100 万代币给 deployer）
        token = new MyERC20("MyERC20", "MERC");

        // 2. 部署 TokenVesting，指定受益人与锁定的 ERC20 地址
        vesting = new TokenVesting(beneficiary, address(token));

        // 3. 将 100 万 MyERC20 代币转入 Vesting 合约
        token.transfer(address(vesting), TOTAL_TOKENS);
    }

    /// @dev 测试基础参数配置正确性
    function test_InitialParameters() public view {
        assertEq(vesting.beneficiary(), beneficiary);
        assertEq(vesting.owner(), beneficiary);
        assertEq(address(vesting.token()), address(token));

        assertEq(vesting.duration(), 36 * MONTH);
        assertEq(vesting.cliff(), vesting.start() + 12 * MONTH);
        assertEq(vesting.end(), vesting.start() + 36 * MONTH);

        assertEq(token.balanceOf(address(vesting)), TOTAL_TOKENS);
        assertEq(token.balanceOf(beneficiary), 0);
    }

    /// @dev 测试 Cliff 期间（前 12 个月）无代币解锁
    function test_CliffPeriod_NoTokensVested() public {
        // Month 0
        assertEq(vesting.vestedAmount(uint64(block.timestamp)), 0);
        assertEq(vesting.releasable(), 0);

        // Month 6
        vm.warp(vesting.start() + 6 * MONTH);
        assertEq(vesting.vestedAmount(uint64(block.timestamp)), 0);
        assertEq(vesting.releasable(), 0);

        // Month 12 前夕 (12 months - 1 second)
        vm.warp(vesting.cliff() - 1);
        assertEq(vesting.vestedAmount(uint64(block.timestamp)), 0);
        assertEq(vesting.releasable(), 0);

        // Month 12 整（刚达到 Cliff 时间戳点）
        vm.warp(vesting.cliff());
        assertEq(vesting.vestedAmount(uint64(block.timestamp)), 0);
        assertEq(vesting.releasable(), 0);

        // 尝试调用 release，释放数量应为 0
        vesting.release();
        assertEq(token.balanceOf(beneficiary), 0);
        assertEq(vesting.released(), 0);
    }

    /// @dev 测试从第 13 个月起解锁 1/24
    function test_Month13_UnlocksOneTwentyFourth() public {
        // 跳转到第 13 个月（Cliff 满 1 个月之后）
        vm.warp(vesting.cliff() + 1 * MONTH);

        uint256 expectedMonth13 = TOTAL_TOKENS / 24;
        assertEq(vesting.vestedAmount(uint64(block.timestamp)), expectedMonth13);
        assertEq(vesting.releasable(), expectedMonth13);

        // 执行 release() 释放给受益人
        vesting.release();

        assertEq(token.balanceOf(beneficiary), expectedMonth13);
        assertEq(vesting.released(), expectedMonth13);
        assertEq(vesting.releasable(), 0);
    }

    /// @dev 测试第 14 个月累计解锁 2/24，并支持分步提取
    function test_Month14_UnlocksTwoTwentyFourths() public {
        // 第 13 个月提款 1/24
        vm.warp(vesting.cliff() + 1 * MONTH);
        vesting.release();
        uint256 releasedMonth13 = vesting.released();

        // 跳转到第 14 个月
        vm.warp(vesting.cliff() + 2 * MONTH);

        uint256 totalVested = (TOTAL_TOKENS * 2) / 24;
        uint256 expectedReleasable = totalVested - releasedMonth13;

        assertEq(vesting.vestedAmount(uint64(block.timestamp)), totalVested);
        assertEq(vesting.releasable(), expectedReleasable);

        // 第三方 caller 触发 release()，代币依然正确打入 beneficiary
        vm.prank(caller);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), totalVested);
        assertEq(vesting.released(), totalVested);
        assertEq(vesting.releasable(), 0);
    }

    /// @dev 测试第 24 个月（线性释放中点，共计经过 24 个月）累计解锁 50%
    function test_HalfwayVesting_50Percent() public {
        // Cliff 12 个月 + 线性释放 12 个月 = 24 个月
        vm.warp(vesting.cliff() + 12 * MONTH);

        uint256 expectedVested = TOTAL_TOKENS / 2; // 500,000 代币
        assertEq(vesting.vestedAmount(uint64(block.timestamp)), expectedVested);
        assertEq(vesting.releasable(), expectedVested);

        vesting.release();
        assertEq(token.balanceOf(beneficiary), expectedVested);
    }

    /// @dev 测试满 36 个月（第 36 个月末）100% 全部解锁
    function test_FullVesting_100Percent() public {
        // 跳转到 end 时间戳
        vm.warp(vesting.end());

        assertEq(vesting.vestedAmount(uint64(block.timestamp)), TOTAL_TOKENS);
        assertEq(vesting.releasable(), TOTAL_TOKENS);

        vesting.release();

        assertEq(token.balanceOf(beneficiary), TOTAL_TOKENS);
        assertEq(token.balanceOf(address(vesting)), 0);
        assertEq(vesting.released(), TOTAL_TOKENS);
        assertEq(vesting.releasable(), 0);

        // 超过 36 个月后再调用 release 不会重复释放
        vm.warp(vesting.end() + 100 * MONTH);
        assertEq(vesting.releasable(), 0);
        vesting.release();
        assertEq(token.balanceOf(beneficiary), TOTAL_TOKENS);
    }

    /// @dev 测试 deposit 辅助函数向合约存入代币
    function test_DepositHelper() public {
        // 部署新的代币和 Vesting 合约
        MyERC20 newToken = new MyERC20("NewToken", "NTK");
        TokenVesting newVesting = new TokenVesting(beneficiary, address(newToken));

        // 部署者先 approve 再通过 deposit 存入
        newToken.approve(address(newVesting), TOTAL_TOKENS);
        newVesting.deposit(TOTAL_TOKENS);

        assertEq(newToken.balanceOf(address(newVesting)), TOTAL_TOKENS);
    }
}
