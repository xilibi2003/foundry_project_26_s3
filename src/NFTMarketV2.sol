// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NFTMarket} from "./NFTMarket.sol";
import {SafeERC20, IERC20} from "@oz/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@oz/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title NFTMarketV2
 * @dev 升级版 NFT 市场合约（V2）：
 * 支持卖家离线签名上架 NFT 功能（采用 Nonce 控制机制）：
 * 1. 卖家只需提前调用一次 nftContract.setApprovalForAll(market, true) 全量授权。
 * 2. 卖家离线签名 (tokenId, price, nonce)。
 * 3. 买家调用 buyWithSellerSig(tokenId, price, nonce, signature) 完成购买结算。
 * 4. 购买成功后自动自增 nonces[seller][tokenId]，当前签名立即失效，彻底防止重放。
 * 5. 卖家可通过 cancelListingSig(tokenId) 随时一键作废当前签名的上架挂单（只需递增 nonce）。
 */
/// @custom:oz-upgrades-from NFTMarket
contract NFTMarketV2 is NFTMarket {
    using SafeERC20 for IERC20;

    // 自定义错误
    error InvalidNonce();
    error InvalidSellerSignature();
    error SellerNotTokenOwner();

    // EIP-712 TypeHash: 卖家离线上架签名（签名内容：tokenId, price, nonce）
    bytes32 public constant SELLER_LISTING_TYPEHASH =
        keccak256("Listing(uint256 tokenId,uint256 price,uint256 nonce)");

    // 记录每个卖家每个 NFT 的当前 nonce：seller => tokenId => nonce
    mapping(address => mapping(uint256 => uint256)) public nonces;

    // 事件
    event NFTSoldWithSig(
        address indexed buyer,
        address indexed seller,
        uint256 indexed tokenId,
        uint256 price,
        uint256 nonce
    );
    event ListingSigCancelled(
        address indexed seller,
        uint256 indexed tokenId,
        uint256 cancelledNonce
    );

    /**
     * @notice 获取当前合约版本
     */
    function version() external pure virtual returns (string memory) {
        return "2.0.0";
    }

    /**
     * @notice 查询指定卖家指定 NFT 的当前 Nonce
     */
    function getNonce(address seller, uint256 tokenId) external view returns (uint256) {
        return nonces[seller][tokenId];
    }

    /**
     * @notice 计算卖家上架签名的 EIP-712 Digest
     * @param tokenId NFT ID
     * @param price 出售价格
     * @param nonce 挂单 Nonce
     */
    function getSellerListingDigest(
        uint256 tokenId,
        uint256 price,
        uint256 nonce
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(SELLER_LISTING_TYPEHASH, tokenId, price, nonce)
        );
        return _hashTypedDataV4(structHash);
    }

    /**
     * @notice 买家通过卖家离线签名购买 NFT（显式指定 nonce）
     * @param tokenId 购买的 NFT ID
     * @param price 卖家在离线签名中指定的售价
     * @param nonce 签名时的 nonce
     * @param signature 卖家符合 EIP-712 标准的离线签名
     */
    function buyWithSellerSig(
        uint256 tokenId,
        uint256 price,
        uint256 nonce,
        bytes memory signature
    ) public {
        if (price == 0) revert PriceZero();

        bytes32 digest = getSellerListingDigest(tokenId, price, nonce);
        address seller = ECDSA.recover(digest, signature);
        if (seller == address(0)) revert InvalidSellerSignature();

        // 校验 Nonce：必须与链上当前记录的 Nonce 一致
        if (nonces[seller][tokenId] != nonce) revert InvalidNonce();

        // 校验卖家是否持有该 NFT
        if (nftContract.ownerOf(tokenId) != seller) revert SellerNotTokenOwner();
        if (msg.sender == seller) revert BuyerCannotBeSeller();

        // 消费当前 Nonce（自增使旧签名立即失效，彻底防止重放）
        nonces[seller][tokenId]++;

        // 1. 买家付款给卖家
        IERC20(address(paymentToken)).safeTransferFrom(msg.sender, seller, price);

        // 2. 将 NFT 从卖家直接转移给买家（需要卖家事先 setApprovalForAll 给市场合约）
        nftContract.safeTransferFrom(seller, msg.sender, tokenId);

        emit NFTSoldWithSig(msg.sender, seller, tokenId, price, nonce);
    }

    /**
     * @notice 重载便捷方法：自动使用当前持有者的当前 Nonce 进行购买
     */
    function buyWithSellerSig(
        uint256 tokenId,
        uint256 price,
        bytes memory signature
    ) external {
        address currentOwner = nftContract.ownerOf(tokenId);
        uint256 currentNonce = nonces[currentOwner][tokenId];
        buyWithSellerSig(tokenId, price, currentNonce, signature);
    }

    /**
     * @notice 重载兼容：支持拆分形式的 (v, r, s) 签名
     */
    function buyWithSellerSig(
        uint256 tokenId,
        uint256 price,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes memory signature = abi.encodePacked(r, s, v);
        buyWithSellerSig(tokenId, price, nonce, signature);
    }

    /**
     * @notice 卖家主动取消/作废指定 NFT 的当前离线上架签名（通过自增 Nonce）
     * @param tokenId 要取消挂单的 NFT ID
     */
    function cancelListingSig(uint256 tokenId) public {
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotOwner();

        uint256 currentNonce = nonces[msg.sender][tokenId];
        nonces[msg.sender][tokenId]++;

        emit ListingSigCancelled(msg.sender, tokenId, currentNonce);
    }

    /**
     * @notice 兼容重载：支持带 price 参数的 cancelListingSig
     */
    function cancelListingSig(uint256 tokenId, uint256 /* price */) external {
        cancelListingSig(tokenId);
    }
}
