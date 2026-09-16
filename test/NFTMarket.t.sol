// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {NFTMarket} from "../src/NFTMarket.sol";
import {MyERC20} from "../src/MyERC20.sol";
import {MyERC721} from "../src/MyERC721.sol";

contract NFTMarketTest is Test {
    NFTMarket public market;
    MyERC20 public token;
    MyERC721 public nft;

    address public seller = makeAddr("seller");
    address public buyer = makeAddr("buyer");

    uint256 public constant INITIAL_BALANCE = 10000 * 1e18;
    uint256 public constant NFT_PRICE = 100 * 1e18; // 100 tokens

    event NFTListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTSold(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTDelisted(address indexed seller, uint256 indexed tokenId);

    function setUp() public {
        // 部署代币和 NFT 合约
        token = new MyERC20("MyToken", "MTK");
        nft = new MyERC721();

        // 部署市场合约
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

    /// @dev 验证买家成功购买 NFT
    function test_BuyNFT_Success() public {
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

        // 验证 NFT 所有权转移给买家
        assertEq(nft.ownerOf(1), buyer, "Buyer should own the NFT");

        // 验证代币转账
        assertEq(token.balanceOf(seller), NFT_PRICE, "Seller should receive tokens");
        assertEq(token.balanceOf(buyer), INITIAL_BALANCE - NFT_PRICE, "Buyer token balance mismatch");

        // 验证上架状态已清除
        (address listedSeller, uint256 listedPrice) = market.getListing(1);
        assertEq(listedSeller, address(0));
        assertEq(listedPrice, 0);
    }

    /// @dev 验证购买金额不足时回滚
    function test_RevertWhen_BuyWithInsufficientAmount() public {
        // 卖家上架 100 token
        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(1, NFT_PRICE);
        vm.stopPrank();

        // 买家只付 50 token
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

        // 给 seller 分配代币并尝试购买自己上架的 NFT
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
