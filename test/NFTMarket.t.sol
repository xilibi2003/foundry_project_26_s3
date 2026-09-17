// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {NFTMarket} from "../src/NFTMarket.sol";
import {CalledToken} from "../src/CalledToken.sol";
import {MyERC721} from "../src/MyERC721.sol";

contract NFTMarketTest is Test {
    NFTMarket public market;
    CalledToken public token;
    MyERC721 public nft;

    address public seller = makeAddr("seller");
    address public buyer = makeAddr("buyer");

    uint256 public constant INITIAL_BALANCE = 10000 * 1e18;
    uint256 public constant NFT_PRICE = 100 * 1e18; // 100 tokens

    event NFTListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTSold(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTDelisted(address indexed seller, uint256 indexed tokenId);

    function setUp() public {
        // 部署 CalledToken 和 MyERC721 NFT 合约
        token = new CalledToken("CalledToken", "CTK");
        nft = new MyERC721();

        // 部署市场合约，使用 CalledToken 作为支付代币
        market = new NFTMarket(address(token), address(nft));

        // 给买家分配代币
        token.transfer(buyer, INITIAL_BALANCE);

        // 给卖家铸造 NFT（tokenId = 1）
        vm.prank(seller);
        nft.mint(seller, "ipfs://sample-metadata-uri");
    }

    /// @dev 验证卖家成功上架 NFT
    function test_ListNFT_Success() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);

        vm.expectEmit(true, true, false, true, address(market));
        emit NFTListed(seller, 1, NFT_PRICE);
        market.list(1, NFT_PRICE);
        vm.stopPrank();

        // 验证 NFT 已经托管到市场合约
        assertEq(nft.ownerOf(1), address(market), "NFT should be in market escrow");

        // 验证上架信息
        (address listedSeller, uint256 listedPrice) = market.getListing(1);
        assertEq(listedSeller, seller);
        assertEq(listedPrice, NFT_PRICE);
    }

    /// @dev 验证上架价格为 0 时回滚
    function test_RevertWhen_ListWithZeroPrice() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);

        vm.expectRevert("NFTMarket: price must be greater than 0");
        market.list(1, 0);
        vm.stopPrank();
    }

    /// @dev 验证非持有者上架时回滚
    function test_RevertWhen_ListNotOwner() public {
        vm.startPrank(buyer);
        vm.expectRevert("NFTMarket: caller is not NFT owner");
        market.list(1, NFT_PRICE);
        vm.stopPrank();
    }

    /// @dev 验证买家通过 transferAndCall 一步购买 NFT（无需提前 approve）
    function test_BuyNFT_ViaTransferAndCall_Success() public {
        // 1. 卖家上架
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(1, NFT_PRICE);
        vm.stopPrank();

        // 2. 买家调用 transferAndCall(market, price, abi.encode(tokenId)) 一步购买
        vm.startPrank(buyer);
        vm.expectEmit(true, true, true, true, address(market));
        emit NFTSold(buyer, seller, 1, NFT_PRICE);

        bytes memory data = abi.encode(uint256(1));
        bool success = token.transferAndCall(address(market), NFT_PRICE, data);
        assertTrue(success, "transferAndCall failed");
        vm.stopPrank();

        // 验证 NFT 所有权转移给买家
        assertEq(nft.ownerOf(1), buyer, "Buyer should own the NFT");

        // 验证代币转账：卖家获得代币，买家扣除代币
        assertEq(token.balanceOf(seller), NFT_PRICE, "Seller should receive tokens");
        assertEq(token.balanceOf(buyer), INITIAL_BALANCE - NFT_PRICE, "Buyer token balance mismatch");
        assertEq(token.balanceOf(address(market)), 0, "Market should have zero token balance");

        // 验证上架记录已清除
        (address listedSeller, uint256 listedPrice) = market.getListing(1);
        assertEq(listedSeller, address(0));
        assertEq(listedPrice, 0);
    }

    /// @dev 验证买家通过 transferAndCall 多付代币时，市场自动退还多余代币
    function test_BuyNFT_ViaTransferAndCall_WithRefund() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(1, NFT_PRICE);
        vm.stopPrank();

        uint256 overpayAmount = NFT_PRICE + 20 * 1e18; // 多付 20 个代币

        vm.startPrank(buyer);
        bytes memory data = abi.encode(uint256(1));
        token.transferAndCall(address(market), overpayAmount, data);
        vm.stopPrank();

        // 卖家获得定价值
        assertEq(token.balanceOf(seller), NFT_PRICE);
        // 买家只扣除定价值，多余 20 个代币已被退还
        assertEq(token.balanceOf(buyer), INITIAL_BALANCE - NFT_PRICE);
        assertEq(token.balanceOf(address(market)), 0);
        assertEq(nft.ownerOf(1), buyer);
    }

    /// @dev 验证 transferAndCall 支付金额不足时回滚
    function test_RevertWhen_TransferAndCallInsufficientAmount() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(1, NFT_PRICE);
        vm.stopPrank();

        vm.startPrank(buyer);
        bytes memory data = abi.encode(uint256(1));
        vm.expectRevert("CalledToken: tokensReceived call failed");
        token.transferAndCall(address(market), 50 * 1e18, data);
        vm.stopPrank();
    }

    /// @dev 验证非代币合约直接调用 tokensReceived 时回滚
    function test_RevertWhen_NonTokenCallsTokensReceived() public {
        vm.prank(buyer);
        vm.expectRevert("NFTMarket: caller must be payment token");
        market.tokensReceived(buyer, NFT_PRICE, abi.encode(1));
    }

    /// @dev 验证传统方式买家成功购买 NFT (approve + buyNFT)
    function test_BuyNFT_Traditional_Success() public {
        // 1. 卖家上架
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(1, NFT_PRICE);
        vm.stopPrank();

        // 2. 买家授权并购买
        vm.startPrank(buyer);
        token.approve(address(market), NFT_PRICE);

        vm.expectEmit(true, true, true, true, address(market));
        emit NFTSold(buyer, seller, 1, NFT_PRICE);
        market.buyNFT(1, NFT_PRICE);
        vm.stopPrank();

        // 验证所有权和代币流转
        assertEq(nft.ownerOf(1), buyer, "Buyer should own the NFT");
        assertEq(token.balanceOf(seller), NFT_PRICE, "Seller should receive tokens");
        assertEq(token.balanceOf(buyer), INITIAL_BALANCE - NFT_PRICE, "Buyer token balance mismatch");

        // 验证上架状态已清除
        (address listedSeller, uint256 listedPrice) = market.getListing(1);
        assertEq(listedSeller, address(0));
        assertEq(listedPrice, 0);
    }

    /// @dev 验证传统购买金额不足时回滚
    function test_RevertWhen_BuyWithInsufficientAmount() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(1, NFT_PRICE);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), NFT_PRICE);

        vm.expectRevert("NFTMarket: payment amount too low");
        market.buyNFT(1, 50 * 1e18);
        vm.stopPrank();
    }

    /// @dev 验证购买未上架的 NFT 时回滚
    function test_RevertWhen_BuyUnlistedNFT() public {
        vm.startPrank(buyer);
        token.approve(address(market), NFT_PRICE);

        vm.expectRevert("NFTMarket: NFT not listed");
        market.buyNFT(1, NFT_PRICE);
        vm.stopPrank();
    }

    /// @dev 验证卖家不能购买自己上架的 NFT
    function test_RevertWhen_SellerBuysOwnNFT() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(1, NFT_PRICE);
        vm.stopPrank();

        // 分配代币给卖家并尝试自买
        token.transfer(seller, NFT_PRICE);

        vm.startPrank(seller);
        token.approve(address(market), NFT_PRICE);

        vm.expectRevert("NFTMarket: buyer cannot be seller");
        market.buyNFT(1, NFT_PRICE);
        vm.stopPrank();
    }

    /// @dev 验证卖家取消上架并退还 NFT
    function test_CancelListing_Success() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(1, NFT_PRICE);

        vm.expectEmit(true, true, false, false, address(market));
        emit NFTDelisted(seller, 1);
        market.cancelListing(1);
        vm.stopPrank();

        // 验证 NFT 已退回给卖家
        assertEq(nft.ownerOf(1), seller, "NFT should be returned to seller");

        // 验证上架记录已清除
        (address listedSeller, uint256 listedPrice) = market.getListing(1);
        assertEq(listedSeller, address(0));
        assertEq(listedPrice, 0);
    }

    /// @dev 验证非卖家无法取消上架
    function test_RevertWhen_CancelListingNotSeller() public {
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(1, NFT_PRICE);
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert("NFTMarket: caller is not seller");
        market.cancelListing(1);
        vm.stopPrank();
    }
}
