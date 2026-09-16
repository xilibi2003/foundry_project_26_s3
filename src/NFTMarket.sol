// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@oz/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@oz/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@oz/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title NFTMarket
 * @dev 使用 ERC20 Token 买卖 ERC721 NFT 的去中心化市场合约
 */
contract NFTMarket is IERC721Receiver {
    using SafeERC20 for IERC20;

    // 支付代币合约（MyERC20）
    IERC20 public immutable paymentToken;
    // NFT 合约（MyERC721）
    IERC721 public immutable nftContract;

    // 上架信息结构体
    struct Listing {
        address seller; // 卖家地址
        uint256 price;  // 出售价格（ERC20 代币数量）
    }

    // tokenId => 上架信息映射
    mapping(uint256 => Listing) public listings;

    // 事件
    event NFTListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTSold(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTDelisted(address indexed seller, uint256 indexed tokenId);

    /**
     * @param _paymentToken 绑定的支付代币合约地址（MyERC20）
     * @param _nftContract 绑定的 NFT 合约地址（MyERC721）
     */
    constructor(address _paymentToken, address _nftContract) {
        require(_paymentToken != address(0), "NFTMarket: zero token address");
        require(_nftContract != address(0), "NFTMarket: zero NFT address");

        paymentToken = IERC20(_paymentToken);
        nftContract = IERC721(_nftContract);
    }

    /**
     * @notice NFT 持有者上架 NFT
     * @param tokenId 要上架的 NFT ID
     * @param price 出售价格（多少个 paymentToken）
     */
    function list(uint256 tokenId, uint256 price) external {
        require(price > 0, "NFTMarket: price must be greater than 0");
        require(nftContract.ownerOf(tokenId) == msg.sender, "NFTMarket: caller is not NFT owner");

        // 记账：记录上架信息
        listings[tokenId] = Listing({
            seller: msg.sender,
            price: price
        });

        // 将 NFT 托管转移到市场合约
        nftContract.safeTransferFrom(msg.sender, address(this), tokenId);

        emit NFTListed(msg.sender, tokenId, price);
    }

    /**
     * @notice 购买已上架的 NFT
     * @param tokenId 购买的 NFT ID
     * @param amount 支付的代币数量
     */
    function buyNFT(uint256 tokenId, uint256 amount) external {
        Listing memory item = listings[tokenId];
        require(item.price > 0, "NFTMarket: NFT not listed");
        require(amount >= item.price, "NFTMarket: payment amount too low");
        require(msg.sender != item.seller, "NFTMarket: buyer cannot be seller");

        // Checks-Effects-Interactions 原则：先删除上架记录
        delete listings[tokenId];

        // 转移代币：从买家向卖家转入对应的代币
        paymentToken.safeTransferFrom(msg.sender, item.seller, item.price);

        // 转移 NFT：从市场合约向买家转出 NFT
        nftContract.safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTSold(msg.sender, item.seller, tokenId, item.price);
    }

    /**
     * @notice 卖家取消上架，赎回 NFT
     * @param tokenId 要取消上架的 NFT ID
     */
    function cancelListing(uint256 tokenId) external {
        Listing memory item = listings[tokenId];
        require(item.price > 0, "NFTMarket: NFT not listed");
        require(item.seller == msg.sender, "NFTMarket: caller is not seller");

        delete listings[tokenId];

        // 将 NFT 退回给卖家
        nftContract.safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTDelisted(msg.sender, tokenId);
    }

    /**
     * @notice 查询指定 NFT 的上架信息
     * @param tokenId NFT ID
     */
    function getListing(uint256 tokenId) external view returns (address seller, uint256 price) {
        Listing memory item = listings[tokenId];
        return (item.seller, item.price);
    }

    /**
     * @dev 实现 IERC721Receiver 接口以接收安全转账 safeTransferFrom
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
