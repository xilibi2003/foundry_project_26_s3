// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@oz/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@oz/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@oz/contracts/token/ERC721/IERC721Receiver.sol";
import {CalledToken, ITokenReceiver} from "./CalledToken.sol";

/**
 * @title NFTMarket
 * @dev 使用 CalledToken 买卖 ERC721 NFT 的去中心化市场合约
 * 支持：
 * 1. 传统方式购买：先 approve 授权，再调用 buyNFT(tokenId, amount)
 * 2. 一步回调购买：CalledToken.transferAndCall(market, amount, abi.encode(tokenId)) 自动触发 tokensReceived 入账并完成购买
 */
contract NFTMarket is IERC721Receiver, ITokenReceiver {
    using SafeERC20 for IERC20;

    // 绑定的支付代币合约（CalledToken）
    CalledToken public immutable paymentToken;
    // 绑定的 NFT 合约（MyERC721）
    IERC721 public immutable nftContract;

    // 上架信息结构体
    struct Listing {
        address seller; // 卖家地址
        uint256 price;  // 出售价格（CalledToken 代币数量）
    }

    // tokenId => 上架信息映射
    mapping(uint256 => Listing) public listings;

    // 事件
    event NFTListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTSold(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTDelisted(address indexed seller, uint256 indexed tokenId);

    /**
     * @param _paymentToken 绑定的支付代币合约地址（CalledToken）
     * @param _nftContract 绑定的 NFT 合约地址（MyERC721）
     */
    constructor(address _paymentToken, address _nftContract) {
        require(_paymentToken != address(0), "NFTMarket: zero token address");
        require(_nftContract != address(0), "NFTMarket: zero NFT address");

        paymentToken = CalledToken(_paymentToken);
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
     * @notice 传统方式购买已上架的 NFT（需先 approve 给市场合约）
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
        IERC20(address(paymentToken)).safeTransferFrom(msg.sender, item.seller, item.price);

        // 转移 NFT：从市场合约向买家转出 NFT
        nftContract.safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTSold(msg.sender, item.seller, tokenId, item.price);
    }

    /**
     * @notice 回调方式购买（一步购买）：由 CalledToken 的 transferAndCall 自动触发
     * @dev 安全要求：
     * 1. 严格校验 msg.sender 必须是绑定的 paymentToken 合约，防止伪造调用
     * 2. data 必须包含以 abi.encode 编码的 tokenId
     * 3. 此时代币已经通过 transferAndCall 转入本合约 (address(this))，因此需将售价转给卖家，多余部分退还买家
     * @param from 实际转出代币的用户（买家）
     * @param amount 支付的代币数量
     * @param data 附加数据（编码的 tokenId）
     * @return 成功返回 true
     */
    function tokensReceived(
        address from,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        // 关键安全校验：调用者必须是绑定的 paymentToken 代币合约！
        require(
            msg.sender == address(paymentToken),
            "NFTMarket: caller must be payment token"
        );
        require(data.length >= 32, "NFTMarket: data must contain tokenId");

        // 解码获取购买的目标 tokenId
        uint256 tokenId = abi.decode(data, (uint256));

        Listing memory item = listings[tokenId];
        require(item.price > 0, "NFTMarket: NFT not listed");
        require(amount >= item.price, "NFTMarket: payment amount too low");
        require(from != item.seller, "NFTMarket: buyer cannot be seller");

        // 删除上架记录
        delete listings[tokenId];

        // 代币在 transferAndCall 中已经转入本合约 (address(this))
        // 将购买价格对应的代币转账给卖家
        IERC20(address(paymentToken)).safeTransfer(item.seller, item.price);

        // 若买家多付了代币，退还溢出部分给买家
        if (amount > item.price) {
            IERC20(address(paymentToken)).safeTransfer(from, amount - item.price);
        }

        // 转移 NFT 给买家
        nftContract.safeTransferFrom(address(this), from, tokenId);

        emit NFTSold(from, item.seller, tokenId, item.price);

        return true;
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
