// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MemeFactory} from "../src/MemeFactory.sol";
import {MemeToken} from "../src/MemeToken.sol";
import {Initializable} from "@oz/contracts/proxy/utils/Initializable.sol";
import {UniswapV2Factory} from "../src/uniswapv2/UniswapV2Factory.sol";
import {UniswapV2Router02} from "../src/uniswapv2/UniswapV2Router02.sol";
import {UniswapV2Pair} from "../src/uniswapv2/UniswapV2Pair.sol";
import {WETH9} from "../src/uniswapv2/test/WETH9.sol";

contract MemeFactoryTest is Test {
    MemeFactory public factory;
    UniswapV2Factory public uniswapFactory;
    UniswapV2Router02 public router;
    WETH9 public weth;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        weth = new WETH9();
        uniswapFactory = new UniswapV2Factory(address(this));
        router = new UniswapV2Router02(address(uniswapFactory), address(weth));
        factory = new MemeFactory(address(router));

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function test_DeployMeme_Success() public {
        string memory symbol = "DOGE";
        uint256 maxSupply = 1_000_000 ether;
        uint256 perMint = 1_000 ether;
        uint256 price = 0.01 ether;

        address tokenAddr = factory.deployMeme(symbol, maxSupply, perMint, price);
        assertTrue(tokenAddr != address(0));
        assertTrue(factory.isMeme(tokenAddr));
        assertEq(factory.totalMemes(), 1);
        assertEq(factory.getAllMemes()[0], tokenAddr);

        MemeToken token = MemeToken(tokenAddr);
        assertEq(token.name(), "DOGE");
        assertEq(token.symbol(), "DOGE");
        assertEq(token.maxSupply(), maxSupply);
        assertEq(token.perMint(), perMint);
        assertEq(token.price(), price);
        assertEq(token.factory(), address(factory));
        assertEq(token.totalSupply(), 0);

        // 验证克隆合约大小远小于完整合约（EIP-1167 代理字节码约为 45 字节）
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(tokenAddr)
        }
        assertEq(codeSize, 45);
    }

    function test_RevertWhen_DeployWithZeroPrice() public {
        vm.expectRevert(MemeFactory.InvalidPrice.selector);
        factory.deployMeme("ZERO", 1000, 100, 0);
    }

    function test_ImplementationCannotBeInitialized() public {
        address impl = factory.tokenImplementation();
        MemeToken token = MemeToken(impl);

        // 实现合约在构造函数中已经禁用初始化器
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initialize("FAIL", "FAIL", 1000, 10, address(this), 0.1 ether);
    }

    function test_CloneCannotBeReinitialized() public {
        address tokenAddr = factory.deployMeme("PEPE", 1000, 100, 0.01 ether);
        MemeToken token = MemeToken(tokenAddr);

        // 克隆实例已被 factory 初始化，无法再次调用 initialize
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initialize("PEPE2", "PEPE2", 2000, 200, address(this), 0.02 ether);
    }

    function test_RevertWhen_DeployWithEmptySymbol() public {
        vm.expectRevert(MemeFactory.InvalidSymbol.selector);
        factory.deployMeme("", 1000, 100, 0.01 ether);
    }

    function test_RevertWhen_DeployWithZeroTotalSupply() public {
        vm.expectRevert(MemeFactory.InvalidTotalSupply.selector);
        factory.deployMeme("SHIB", 0, 100, 0.01 ether);
    }

    function test_RevertWhen_DeployWithZeroPerMint() public {
        vm.expectRevert(MemeFactory.InvalidPerMint.selector);
        factory.deployMeme("SHIB", 1000, 0, 0.01 ether);
    }

    function test_RevertWhen_DeployWithPerMintExceedingTotalSupply() public {
        vm.expectRevert(MemeFactory.InvalidPerMint.selector);
        factory.deployMeme("SHIB", 1000, 1001, 0.01 ether);
    }

    function test_MintMeme_Success_InitialLiquidityAtMintPrice() public {
        uint256 maxSupply = 10_000 ether;
        uint256 perMint = 1_000 ether;
        uint256 price = 1 ether;

        address tokenAddr = factory.deployMeme("MOON", maxSupply, perMint, price);
        MemeToken token = MemeToken(tokenAddr);

        uint256 aliceBalBefore = alice.balance;

        // Alice 按设定价格 mint
        vm.prank(alice);
        factory.mintMeme{value: 1 ether}(tokenAddr);

        // Alice 支付 1 ETH，收到 1000 ether 代币
        assertEq(token.balanceOf(alice), perMint);
        assertEq(aliceBalBefore - alice.balance, 1 ether);

        // 首次 mint 注入流动性：5% 价格 (0.05 ETH) 和 5% perMint (50 Token)
        address pair = uniswapFactory.getPair(tokenAddr, address(weth));
        assertTrue(pair != address(0), "Pair should be created");

        (uint112 reserve0, uint112 reserve1, ) = UniswapV2Pair(pair).getReserves();
        (uint256 reserveToken, uint256 reserveETH) = tokenAddr < address(weth)
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));

        assertEq(reserveETH, 0.05 ether, "ETH reserve should be 5% of price");
        assertEq(reserveToken, 50 ether, "Token reserve should match mint price ratio");
        assertEq(token.totalSupply(), 1050 ether);

        // Bob 进行第二次 mint，按现有池子比例追加流动性
        vm.prank(bob);
        factory.mintMeme{value: 1 ether}(tokenAddr);
        assertEq(token.balanceOf(bob), perMint);

        (reserve0, reserve1, ) = UniswapV2Pair(pair).getReserves();
        (reserveToken, reserveETH) = tokenAddr < address(weth)
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));

        assertEq(reserveETH, 0.1 ether);
        assertEq(reserveToken, 100 ether);
        assertEq(token.totalSupply(), 2100 ether);
    }

    function test_MintMeme_RefundExcessETH() public {
        uint256 maxSupply = 10_000 ether;
        uint256 perMint = 1_000 ether;
        uint256 price = 1 ether;

        address tokenAddr = factory.deployMeme("REFUND", maxSupply, perMint, price);
        MemeToken token = MemeToken(tokenAddr);

        uint256 aliceBalBefore = alice.balance;

        // Alice 支付了 1.5 ETH（超出 0.5 ETH）
        vm.prank(alice);
        factory.mintMeme{value: 1.5 ether}(tokenAddr);

        assertEq(token.balanceOf(alice), perMint);
        // Alice 只被扣除了 1 ETH，多出的 0.5 ETH 被退回
        assertEq(aliceBalBefore - alice.balance, 1 ether);
    }

    function test_MintMeme_RevertWhen_InsufficientPayment() public {
        uint256 maxSupply = 10_000 ether;
        uint256 perMint = 1_000 ether;
        uint256 price = 1 ether;

        address tokenAddr = factory.deployMeme("FAILPAY", maxSupply, perMint, price);

        vm.prank(alice);
        vm.expectRevert(MemeFactory.InsufficientPayment.selector);
        factory.mintMeme{value: 0.5 ether}(tokenAddr);
    }

    function test_MintMeme_UntilMaxSupply() public {
        uint256 maxSupply = 315;
        uint256 perMint = 100;
        uint256 price = 0.01 ether;
        address tokenAddr = factory.deployMeme("CAP", maxSupply, perMint, price);
        MemeToken token = MemeToken(tokenAddr);

        // 铸造 3 次：每次 100 用户 + 5 流动性 = 105，3 次达到 315
        factory.mintMeme{value: price}(tokenAddr);
        factory.mintMeme{value: price}(tokenAddr);
        factory.mintMeme{value: price}(tokenAddr);

        assertEq(token.totalSupply(), 315);

        // 第 4 次铸造应因为超过 maxSupply 而失败
        vm.expectRevert(
            abi.encodeWithSelector(MemeToken.ExceedsMaxSupply.selector, perMint, 0)
        );
        factory.mintMeme{value: price}(tokenAddr);
    }

    function test_RevertWhen_MintUnregisteredToken() public {
        address fakeToken = makeAddr("fakeToken");
        vm.expectRevert(MemeFactory.NotAValidMemeToken.selector);
        factory.mintMeme{value: 1 ether}(fakeToken);
    }

    function test_RevertWhen_DirectMintBypassingFactory() public {
        address tokenAddr = factory.deployMeme("BYPASS", 1000, 100, 0.01 ether);
        MemeToken token = MemeToken(tokenAddr);

        // 试图绕过工厂直接调用 token.mint 应当被阻止
        vm.expectRevert(MemeToken.OnlyFactory.selector);
        token.mint(alice, 100);
    }

    function test_MemeToken_TransferAndApprove() public {
        address tokenAddr = factory.deployMeme("MOVE", 10_000 ether, 100 ether, 0.01 ether);
        MemeToken token = MemeToken(tokenAddr);

        vm.prank(alice);
        factory.mintMeme{value: 0.01 ether}(tokenAddr);

        // Alice 转账给 Bob
        vm.prank(alice);
        token.transfer(bob, 40 ether);
        assertEq(token.balanceOf(alice), 60 ether);
        assertEq(token.balanceOf(bob), 40 ether);

        // Bob approve 授权给 Alice 并通过 transferFrom 转账
        vm.prank(bob);
        token.approve(alice, 10 ether);
        assertEq(token.allowance(bob, alice), 10 ether);

        vm.prank(alice);
        token.transferFrom(bob, alice, 10 ether);
        assertEq(token.balanceOf(alice), 70 ether);
        assertEq(token.balanceOf(bob), 30 ether);
    }

    // ==========================================
    // buyMeme 测试（通过 UniswapV2Router swapExactETHForTokens 购买）
    // ==========================================

    function test_BuyMeme_ViaFactory_WhenPriceBetter_Success() public {
        uint256 maxSupply = 100_000 ether;
        uint256 perMint = 1_000 ether;
        uint256 price = 1 ether; // 初始价格: 1 ETH = 1000 Token

        address tokenAddr = factory.deployMeme("CHEAP1", maxSupply, perMint, price);
        MemeToken token = MemeToken(tokenAddr);

        // 1. 先 mint 两次建立 Uniswap 流动性池 (0.1 ETH : 100 Token)
        vm.prank(alice);
        factory.mintMeme{value: 1 ether}(tokenAddr);
        vm.prank(alice);
        factory.mintMeme{value: 1 ether}(tokenAddr);

        // 2. Alice 卖出大量 Token，使得 Uniswap 上的 Token 价格大幅下跌（更便宜）
        vm.startPrank(alice);
        token.approve(address(router), type(uint256).max);
        address[] memory sellPath = new address[](2);
        sellPath[0] = tokenAddr;
        sellPath[1] = address(weth);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            1500 ether,
            0,
            sellPath,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        // 3. Bob 调用 factory.buyMeme 用 0.01 ETH 在 Uniswap 购买
        uint256 bobTokenBefore = token.balanceOf(bob);
        vm.prank(bob);
        factory.buyMeme{value: 0.01 ether}(tokenAddr);

        uint256 bobTokenAfter = token.balanceOf(bob);
        uint256 tokensReceived = bobTokenAfter - bobTokenBefore;

        // 起始价格下 0.01 ETH 只能买 10 Token，Uniswap 价格优于起始价格，因此收到远大于 10 Token
        assertTrue(
            tokensReceived > 10 ether,
            "Bob should receive more tokens than initial price"
        );
    }

    function test_BuyMeme_ViaFactory_RevertWhen_PriceNotBetter() public {
        uint256 maxSupply = 100_000 ether;
        uint256 perMint = 1_000 ether;
        uint256 price = 1 ether;

        address tokenAddr = factory.deployMeme("EXP1", maxSupply, perMint, price);

        // mint 一次建立初始池子 (0.05 ETH : 50 Token)
        vm.prank(alice);
        factory.mintMeme{value: 1 ether}(tokenAddr);

        // 此时池子比例等于起始价格，经过 Uniswap 手续费与滑点后输出必然少于起始价格数量
        vm.prank(bob);
        vm.expectRevert(MemeFactory.PriceNotBetter.selector);
        factory.buyMeme{value: 0.01 ether}(tokenAddr);
    }

    function test_BuyMeme_ViaFactory_RevertWhen_NoLiquidity() public {
        address tokenAddr = factory.deployMeme("NOLIQ1", 10_000 ether, 1_000 ether, 1 ether);

        vm.prank(bob);
        vm.expectRevert(MemeFactory.NoLiquidity.selector);
        factory.buyMeme{value: 0.01 ether}(tokenAddr);
    }

    function test_BuyMeme_ViaFactory_WithMinTokensOut() public {
        uint256 maxSupply = 100_000 ether;
        uint256 perMint = 1_000 ether;
        uint256 price = 1 ether;

        address tokenAddr = factory.deployMeme("CHEAP2", maxSupply, perMint, price);
        MemeToken token = MemeToken(tokenAddr);

        vm.prank(alice);
        factory.mintMeme{value: 1 ether}(tokenAddr);
        vm.prank(alice);
        factory.mintMeme{value: 1 ether}(tokenAddr);

        vm.startPrank(alice);
        token.approve(address(router), type(uint256).max);
        address[] memory sellPath = new address[](2);
        sellPath[0] = tokenAddr;
        sellPath[1] = address(weth);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            1500 ether,
            0,
            sellPath,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        uint256 bobTokenBefore = token.balanceOf(bob);
        vm.prank(bob);
        // 指定 minTokensOut 进行滑点保护购买
        factory.buyMeme{value: 0.01 ether}(tokenAddr, 10 ether);

        uint256 bobTokenAfter = token.balanceOf(bob);
        assertTrue(bobTokenAfter - bobTokenBefore >= 10 ether);
    }

    function test_BuyMeme_ViaFactory_RevertWhen_ZeroValue() public {
        address tokenAddr = factory.deployMeme("ZEROVAL", 10_000 ether, 1_000 ether, 1 ether);

        vm.prank(bob);
        vm.expectRevert(MemeFactory.InsufficientPayment.selector);
        factory.buyMeme{value: 0}(tokenAddr);
    }
}
