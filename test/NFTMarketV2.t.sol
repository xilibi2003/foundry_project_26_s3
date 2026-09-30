// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {NFTMarket} from "../src/NFTMarket.sol";
import {NFTMarketV2} from "../src/NFTMarketV2.sol";
import {CalledToken} from "../src/CalledToken.sol";
import {MyERC721} from "../src/MyERC721.sol";

contract NFTMarketV2Test is Test {
    NFTMarket public marketV1;
    NFTMarketV2 public marketV2;
    CalledToken public token;
    MyERC721 public nft;

    address public proxyAdminOwner = makeAddr("proxyAdminOwner");
    address public admin;
    uint256 public adminKey;

    address public seller;
    uint256 public sellerKey;

    address public buyer;
    uint256 public buyerKey;

    address public attacker;
    uint256 public attackerKey;

    address public proxy;

    uint256 public constant INITIAL_BALANCE = 10_000 * 1e18;
    uint256 public constant NFT_PRICE = 200 * 1e18;

    function setUp() public {
        (admin, adminKey) = makeAddrAndKey("admin");
        (seller, sellerKey) = makeAddrAndKey("seller");
        (buyer, buyerKey) = makeAddrAndKey("buyer");
        (attacker, attackerKey) = makeAddrAndKey("attacker");

        // 1. 部署基础代币与 NFT 合约
        token = new CalledToken("CalledToken", "CTK");
        nft = new MyERC721();

        // 2. 初始使用透明代理部署 V1 版本 NFTMarket
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address)",
            address(token),
            address(nft),
            admin
        );
        proxy = Upgrades.deployTransparentProxy(
            "NFTMarket.sol:NFTMarket",
            proxyAdminOwner,
            initData
        );
        marketV1 = NFTMarket(proxy);

        // 3. 升级到 NFTMarketV2
        Upgrades.upgradeProxy(proxy, "NFTMarketV2.sol:NFTMarketV2", "", proxyAdminOwner);
        marketV2 = NFTMarketV2(proxy);

        // 4. 分配测试资产
        token.transfer(buyer, INITIAL_BALANCE);
        token.transfer(attacker, INITIAL_BALANCE);

        // 为卖家铸造多个 NFT
        vm.startPrank(seller);
        nft.mint(seller, "ipfs://nft-token-1");
        nft.mint(seller, "ipfs://nft-token-2");
        nft.mint(seller, "ipfs://nft-token-3");
        nft.mint(seller, "ipfs://nft-token-4");
        vm.stopPrank();
    }

    /// @notice 辅助函数：构造卖家对 (tokenId, price, nonce) 的 EIP-712 离线上架签名
    function _getSellerListingSignature(
        uint256 signerKey,
        uint256 tokenId,
        uint256 price,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                marketV2.SELLER_LISTING_TYPEHASH(),
                tokenId,
                price,
                nonce
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", marketV2.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @notice 辅助函数：构造拆分形式的 (v, r, s) 签名
    function _getSellerListingSignatureVRS(
        uint256 signerKey,
        uint256 tokenId,
        uint256 price,
        uint256 nonce
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                marketV2.SELLER_LISTING_TYPEHASH(),
                tokenId,
                price,
                nonce
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", marketV2.DOMAIN_SEPARATOR(), structHash)
        );
        (v, r, s) = vm.sign(signerKey, digest);
    }

    function test_UpgradeSuccessAndVersion() public view {
        assertEq(marketV2.version(), "2.0.0");
        assertEq(address(marketV2.paymentToken()), address(token));
        assertEq(address(marketV2.nftContract()), address(nft));
        assertEq(marketV2.admin(), admin);
    }

    function test_BuyWithSellerSig_Success() public {
        uint256 tokenId = 1;
        uint256 price = NFT_PRICE;

        // 1. 卖家仅需一次性 setApprovalForAll 给市场合约
        vm.prank(seller);
        nft.setApprovalForAll(address(marketV2), true);

        // 2. 卖家获取当前 nonce 并离线签名 (tokenId, price, nonce)
        uint256 nonce = marketV2.getNonce(seller, tokenId);
        assertEq(nonce, 0);

        bytes memory sig = _getSellerListingSignature(sellerKey, tokenId, price, nonce);

        // 3. 买家授权代币给市场合约并携带卖家离线签名购买
        vm.startPrank(buyer);
        token.approve(address(marketV2), price);

        uint256 sellerBalanceBefore = token.balanceOf(seller);
        uint256 buyerBalanceBefore = token.balanceOf(buyer);

        marketV2.buyWithSellerSig(tokenId, price, nonce, sig);
        vm.stopPrank();

        // 4. 验证结算与资产归属
        assertEq(token.balanceOf(seller), sellerBalanceBefore + price);
        assertEq(token.balanceOf(buyer), buyerBalanceBefore - price);
        assertEq(nft.ownerOf(tokenId), buyer);

        // 5. 验证该 tokenId 的 nonce 已经自增，旧签名永久失效
        assertEq(marketV2.getNonce(seller, tokenId), 1);
    }

    function test_BuyWithSellerSig_VRS_Overload() public {
        uint256 tokenId = 2;
        uint256 price = 150 * 1e18;

        // 卖家一次性授权
        vm.prank(seller);
        nft.setApprovalForAll(address(marketV2), true);

        uint256 nonce = marketV2.getNonce(seller, tokenId);

        // 获取拆分签名
        (uint8 v, bytes32 r, bytes32 s) = _getSellerListingSignatureVRS(sellerKey, tokenId, price, nonce);

        // 买家购买
        vm.startPrank(buyer);
        token.approve(address(marketV2), price);
        marketV2.buyWithSellerSig(tokenId, price, nonce, v, r, s);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(marketV2.getNonce(seller, tokenId), nonce + 1);
    }

    function test_RevertWhen_SignatureReplayed() public {
        uint256 tokenId = 1;
        uint256 price = NFT_PRICE;

        vm.prank(seller);
        nft.setApprovalForAll(address(marketV2), true);

        uint256 nonce = marketV2.getNonce(seller, tokenId);
        bytes memory sig = _getSellerListingSignature(sellerKey, tokenId, price, nonce);

        // 第一次购买成功，nonce 自增为 1
        vm.startPrank(buyer);
        token.approve(address(marketV2), price * 2);
        marketV2.buyWithSellerSig(tokenId, price, nonce, sig);

        // 第二次尝试使用原 nonce 的旧签名重放购买 -> 预期 revert InvalidNonce
        vm.expectRevert(NFTMarketV2.InvalidNonce.selector);
        marketV2.buyWithSellerSig(tokenId, price, nonce, sig);
        vm.stopPrank();
    }

    function test_RevertWhen_NonOwnerSignature() public {
        uint256 tokenId = 1;
        uint256 price = NFT_PRICE;

        // 攻击者伪造签名（试图出售 seller 拥有的 tokenId 1）
        uint256 nonce = marketV2.getNonce(attacker, tokenId);
        bytes memory attackerSig = _getSellerListingSignature(attackerKey, tokenId, price, nonce);

        vm.startPrank(buyer);
        token.approve(address(marketV2), price);

        vm.expectRevert(NFTMarketV2.SellerNotTokenOwner.selector);
        marketV2.buyWithSellerSig(tokenId, price, nonce, attackerSig);
        vm.stopPrank();
    }

    function test_RevertWhen_BuyerIsSeller() public {
        uint256 tokenId = 1;
        uint256 price = NFT_PRICE;

        vm.prank(seller);
        nft.setApprovalForAll(address(marketV2), true);

        uint256 nonce = marketV2.getNonce(seller, tokenId);
        bytes memory sig = _getSellerListingSignature(sellerKey, tokenId, price, nonce);

        // 卖家自己不能购买自己的 NFT
        vm.startPrank(seller);
        token.approve(address(marketV2), price);

        vm.expectRevert(NFTMarket.BuyerCannotBeSeller.selector);
        marketV2.buyWithSellerSig(tokenId, price, nonce, sig);
        vm.stopPrank();
    }

    function test_CancelListingSig_ByIncrementingNonce() public {
        uint256 tokenId = 3;
        uint256 price = NFT_PRICE;

        // 卖家签署了针对当前 nonce (0) 的离线上架
        uint256 nonce = marketV2.getNonce(seller, tokenId);
        assertEq(nonce, 0);
        bytes memory sig = _getSellerListingSignature(sellerKey, tokenId, price, nonce);

        // 卖家主动在链上取消当前挂单（无需传入复杂的签名或价格，只需传入 tokenId）
        vm.prank(seller);
        marketV2.cancelListingSig(tokenId);

        // 验证 nonce 已经变为 1
        assertEq(marketV2.getNonce(seller, tokenId), 1);

        // 买家尝试使用旧 nonce 的签名购买 -> 失败 revert InvalidNonce
        vm.startPrank(buyer);
        token.approve(address(marketV2), price);

        vm.expectRevert(NFTMarketV2.InvalidNonce.selector);
        marketV2.buyWithSellerSig(tokenId, price, nonce, sig);
        vm.stopPrank();
    }

    function test_CancelAndRelistAtNewPrice() public {
        uint256 tokenId = 3;
        uint256 newPrice = 120 * 1e18;

        vm.prank(seller);
        nft.setApprovalForAll(address(marketV2), true);

        // 1. 卖家撤回老价格挂单
        vm.prank(seller);
        marketV2.cancelListingSig(tokenId);
        uint256 newNonce = marketV2.getNonce(seller, tokenId);
        assertEq(newNonce, 1);

        // 2. 卖家以新价格和新 nonce (1) 重新离线签名
        bytes memory newSig = _getSellerListingSignature(sellerKey, tokenId, newPrice, newNonce);

        // 3. 买家以新价格购买成功
        vm.startPrank(buyer);
        token.approve(address(marketV2), newPrice);
        marketV2.buyWithSellerSig(tokenId, newPrice, newNonce, newSig);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(marketV2.getNonce(seller, tokenId), 2);
    }

    function test_V1_ListingAndTraditionalBuy_StillWorksOnV2() public {
        uint256 tokenId = 4;
        uint256 price = 80 * 1e18;

        // V1 传统托管上架流程
        vm.startPrank(seller);
        nft.approve(address(marketV2), tokenId);
        marketV2.list(tokenId, price);
        vm.stopPrank();

        // 传统买家购买
        vm.startPrank(buyer);
        token.approve(address(marketV2), price);
        marketV2.buyNFT(tokenId, price);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), buyer);
    }
}
