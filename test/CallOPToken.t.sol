// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CallOPToken} from "../src/CallOPToken.sol";
import {MyERC20} from "../src/MyERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CallOPTokenTest is Test {
    CallOPToken public optionToken;
    MyERC20 public quoteToken;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant STRIKE_PRICE = 2000 * 1e18; // 2000 MyERC20 per 1 ETH
    uint256 public constant SETTLEMENT_DURATION = 1 days; // 到期日当天窗口为 1 天
    uint256 public settlementTime;

    receive() external payable {}

    function setUp() public {
        vm.deal(owner, 100 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);

        // 项目方部署计价 Token（MyERC20）
        vm.startPrank(owner);
        quoteToken = new MyERC20("Tether USD", "USDT");

        // 设置到期行权时间为 7 天之后
        settlementTime = block.timestamp + 7 days;

        // 部署看涨期权合约
        optionToken = new CallOPToken(
            "ETH Call Option 2000",
            "ETH-2000-CALL",
            address(quoteToken),
            STRIKE_PRICE,
            settlementTime,
            SETTLEMENT_DURATION
        );

        // 分发计价 Token 给 Bob 和 Alice 准备行权
        quoteToken.transfer(bob, 100_000 * 1e18);
        quoteToken.transfer(alice, 100_000 * 1e18);
        vm.stopPrank();
    }

    function test_InitialDeploymentParameters() public view {
        assertEq(address(optionToken.quoteToken()), address(quoteToken));
        assertEq(optionToken.strikePrice(), STRIKE_PRICE);
        assertEq(optionToken.settlementTime(), settlementTime);
        assertEq(optionToken.settlementDuration(), SETTLEMENT_DURATION);
        assertEq(optionToken.owner(), owner);
        assertEq(optionToken.totalSupply(), 0);
    }

    function test_MintByProjectOwner() public {
        uint256 mintAmount = 10 ether;

        vm.startPrank(owner);
        // 项目方存入 10 ETH 标的，mint 10 个 CallOPToken
        optionToken.mint{value: mintAmount}();
        vm.stopPrank();

        assertEq(optionToken.balanceOf(owner), mintAmount);
        assertEq(optionToken.totalSupply(), mintAmount);
        assertEq(address(optionToken).balance, mintAmount);
    }

    function test_RevertWhen_NonOwnerMints() public {
        vm.deal(alice, 5 ether);
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        optionToken.mint{value: 1 ether}();
        vm.stopPrank();
    }

    function test_RevertWhen_MintZeroETH() public {
        vm.startPrank(owner);
        vm.expectRevert(CallOPToken.ZeroAmount.selector);
        optionToken.mint{value: 0}();
        vm.stopPrank();
    }

    function test_RevertWhen_MintAfterSettlementTime() public {
        vm.warp(settlementTime);
        vm.startPrank(owner);
        vm.expectRevert(CallOPToken.SettlementStarted.selector);
        optionToken.mint{value: 1 ether}();
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimBeforeSettlement() public {
        // 项目方 mint 5 ETH
        vm.prank(owner);
        optionToken.mint{value: 5 ether}();

        // 转给 Bob 2 个期权
        vm.prank(owner);
        optionToken.transfer(bob, 2 ether);

        // 在到期日前 Bob 尝试行权，应被拒绝
        vm.startPrank(bob);
        quoteToken.approve(address(optionToken), type(uint256).max);
        vm.expectRevert(CallOPToken.NotInSettlementWindow.selector);
        optionToken.claim(2 ether);
        vm.stopPrank();
    }

    function test_ClaimOnSettlementDay_Success() public {
        uint256 initialETH = 10 ether;
        uint256 bobOptionAmount = 3 ether; // Bob 获得 3 个期权 (对应 3 ETH)

        // 1. 项目方 mint 10 ETH 等量的 CallOPToken
        vm.prank(owner);
        optionToken.mint{value: initialETH}();

        // 2. 将期权 CallOPToken 转给另一个用户 Bob
        vm.prank(owner);
        optionToken.transfer(bob, bobOptionAmount);
        assertEq(optionToken.balanceOf(bob), bobOptionAmount);
        assertEq(optionToken.balanceOf(owner), initialETH - bobOptionAmount);

        // 3. 快进到到期日当天
        vm.warp(settlementTime);
        assertTrue(optionToken.isSettlementWindow());
        assertFalse(optionToken.isExpired());

        // 计算 Bob 行权 3 ETH 所需支付的计价 Token 数量
        // 3 * 2000 = 6000 MyERC20
        uint256 expectedQuotePay = optionToken.calculateQuoteAmount(bobOptionAmount);
        assertEq(expectedQuotePay, 3 * 2000 * 1e18);

        uint256 bobETHBefore = bob.balance;
        uint256 bobQuoteBefore = quoteToken.balanceOf(bob);
        uint256 contractETHBefore = address(optionToken).balance;

        // 4. Bob 授权并按行权价格行权
        vm.startPrank(bob);
        quoteToken.approve(address(optionToken), expectedQuotePay);
        optionToken.claim(bobOptionAmount);
        vm.stopPrank();

        // 5. 校验行权后的状态：
        // Bob 销毁了期权 Token
        assertEq(optionToken.balanceOf(bob), 0);
        // Bob 支付了 6000 MyERC20
        assertEq(quoteToken.balanceOf(bob), bobQuoteBefore - expectedQuotePay);
        // Bob 赎回获得了 3 ETH
        assertEq(bob.balance, bobETHBefore + bobOptionAmount);

        // 合约中的变化
        assertEq(address(optionToken).balance, contractETHBefore - bobOptionAmount);
        assertEq(quoteToken.balanceOf(address(optionToken)), expectedQuotePay);
        assertEq(optionToken.totalSupply(), initialETH - bobOptionAmount);
    }

    function test_PartialClaimOnSettlementDay() public {
        // 项目方 mint 10 ETH
        vm.prank(owner);
        optionToken.mint{value: 10 ether}();

        // 转 4 个期权给 Bob
        vm.prank(owner);
        optionToken.transfer(bob, 4 ether);

        // 到期日当天
        vm.warp(settlementTime + 12 hours);

        // Bob 先行权 1.5 ETH
        uint256 partialAmount = 1.5 ether;
        uint256 quoteRequired = optionToken.calculateQuoteAmount(partialAmount);

        vm.startPrank(bob);
        quoteToken.approve(address(optionToken), quoteRequired);
        optionToken.claim(partialAmount);
        vm.stopPrank();

        assertEq(optionToken.balanceOf(bob), 2.5 ether);
        assertEq(quoteToken.balanceOf(address(optionToken)), quoteRequired);
    }

    function test_RevertWhen_ClaimWithInsufficientOption() public {
        vm.prank(owner);
        optionToken.mint{value: 5 ether}();

        vm.prank(owner);
        optionToken.transfer(bob, 1 ether);

        vm.warp(settlementTime);
        vm.startPrank(bob);
        quoteToken.approve(address(optionToken), type(uint256).max);
        vm.expectRevert(CallOPToken.InsufficientOptionBalance.selector);
        optionToken.claim(2 ether); // Bob 只有 1 ether，尝试行权 2 ether
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimAfterSettlementWindowExpired() public {
        vm.prank(owner);
        optionToken.mint{value: 5 ether}();

        vm.prank(owner);
        optionToken.transfer(bob, 2 ether);

        // 超过到期日当天窗口期（比如 1 天又 1 秒后）
        vm.warp(settlementTime + SETTLEMENT_DURATION + 1);
        assertTrue(optionToken.isExpired());

        vm.startPrank(bob);
        quoteToken.approve(address(optionToken), type(uint256).max);
        vm.expectRevert(CallOPToken.NotInSettlementWindow.selector);
        optionToken.claim(2 ether);
        vm.stopPrank();
    }

    function test_BurnExpired_ProjectOwnerRedeem() public {
        uint256 totalMint = 10 ether;
        uint256 bobClaimAmount = 3 ether;

        // 1. 项目方 mint 10 ETH
        vm.prank(owner);
        optionToken.mint{value: totalMint}();

        // 2. 转给 Bob 3 个期权
        vm.prank(owner);
        optionToken.transfer(bob, bobClaimAmount);

        // 3. 到期日当天 Bob 行权 3 ETH
        vm.warp(settlementTime);
        uint256 quoteForBob = optionToken.calculateQuoteAmount(bobClaimAmount);
        vm.startPrank(bob);
        quoteToken.approve(address(optionToken), quoteForBob);
        optionToken.claim(bobClaimAmount);
        vm.stopPrank();

        // 4. 到期日后（已过期）
        vm.warp(settlementTime + SETTLEMENT_DURATION + 1);
        assertTrue(optionToken.isExpired());

        uint256 ownerEthBefore = owner.balance;
        uint256 ownerQuoteBefore = quoteToken.balanceOf(owner);
        uint256 ownerOptionsBefore = optionToken.balanceOf(owner);
        assertEq(ownerOptionsBefore, totalMint - bobClaimAmount); // 剩余 7 个期权

        // 5. 项目方调用 burn 过期销毁并赎回
        vm.prank(owner);
        optionToken.burn();

        // 6. 验证：
        // 项目方手里的 7 个期权被销毁
        assertEq(optionToken.balanceOf(owner), 0);
        // 合约中剩余的 7 ETH 全部被项目方赎回
        assertEq(address(optionToken).balance, 0);
        assertEq(owner.balance, ownerEthBefore + 7 ether);
        // 合约中的 6000 MyERC20 行权收入全部归项目方所有
        assertEq(quoteToken.balanceOf(address(optionToken)), 0);
        assertEq(quoteToken.balanceOf(owner), ownerQuoteBefore + quoteForBob);
    }

    function test_RevertWhen_NonOwnerCallsBurn() public {
        vm.prank(owner);
        optionToken.mint{value: 2 ether}();

        vm.warp(settlementTime + SETTLEMENT_DURATION + 1);

        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                bob
            )
        );
        optionToken.burn();
        vm.stopPrank();
    }

    function test_RevertWhen_BurnBeforeExpiry() public {
        vm.prank(owner);
        optionToken.mint{value: 2 ether}();

        // 在到期日当天，还未过期
        vm.warp(settlementTime);
        vm.startPrank(owner);
        vm.expectRevert(CallOPToken.NotExpired.selector);
        optionToken.burn();
        vm.stopPrank();
    }
}
