// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@oz/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@oz/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@oz/contracts/token/ERC721/IERC721Receiver.sol";
import {EIP712} from "@oz/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@oz/contracts/utils/cryptography/ECDSA.sol";
import {CalledToken, ITokenReceiver} from "./CalledToken.sol";

/**
 * @title NFTMarket
 * @dev 使用 CalledToken 买卖 ERC721 NFT 的去中心化市场合约
 * 支持：
 * 1. 传统方式购买：先 approve 授权，再调用 buyNFT(tokenId, amount)
 * 2. 一步回调购买：CalledToken.transferAndCall(market, amount, abi.encode(tokenId)) 自动触发 tokensReceived 入账并完成购买
 * 3. 白名单离线授权购买：permitBuy() 校验管理员符合 EIP-712 标准的离线签名授权后才允许购买
 */
contract NFTMarket is IERC721Receiver, ITokenReceiver, EIP712 {
    using SafeERC20 for IERC20;

    // 自定义错误（Custom Errors）以降低部署字节码和执行 Gas
    error CallerNotAdmin();
    error ZeroAddress();
    error PriceZero();
    error PriceOverflow();
    error NotOwner();
    error NotListed();
    error InsufficientPayment();
    error BuyerCannotBeSeller();
    error InvalidWhitelistSignature();
    error CallerNotPaymentToken();
    error InvalidDataLength();
    error CallerNotSeller();

    // 绑定的支付代币合约（CalledToken）
    CalledToken public immutable paymentToken;
    // 绑定的 NFT 合约（MyERC721）
    IERC721 public immutable nftContract;

    // 管理员地址（负责离线签发白名单授权）
    address public admin;

    // EIP-712 TypeHash: 用于白名单用户购买许可签名
    bytes32 public constant PERMIT_BUY_TYPEHASH =
        keccak256("PermitBuy(address buyer,uint256 tokenId)");
    bytes32 public constant FALLBACK_PERMIT_BUY_TYPEHASH =
        keccak256("PermitBuy(address buyer)");

    // 上架信息结构体：address (160 bits) + uint96 (96 bits) 打包进单槽（节省 20,000+ Gas）
    struct Listing {
        address seller; // 卖家地址 (160 bits)
        uint96 price;   // 出售价格 (96 bits，支持高达约 792 亿个代币)
    }

    // tokenId => 上架信息映射
    mapping(uint256 => Listing) public listings;

    // 事件
    event NFTListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTSold(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTDelisted(address indexed seller, uint256 indexed tokenId);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert CallerNotAdmin();
        _;
    }

    /**
     * @param _paymentToken 绑定的支付代币合约地址（CalledToken）
     * @param _nftContract 绑定的 NFT 合约地址（MyERC721）
     */
    constructor(address _paymentToken, address _nftContract)
        EIP712("NFTMarket", "1")
    {
        if (_paymentToken == address(0) || _nftContract == address(0)) revert ZeroAddress();

        paymentToken = CalledToken(_paymentToken);
        nftContract = IERC721(_nftContract);
        admin = msg.sender;
    }

    /**
     * @notice 设置新的管理员地址
     * @param _admin 新管理员地址
     */
    function setAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        emit AdminChanged(admin, _admin);
        admin = _admin;
    }

    /**
     * @notice NFT 持有者上架 NFT
     * @dev 移除冗余的 nftContract.ownerOf 外部调用，safeTransferFrom 内部强制校验 owner 和 approval
     * @param tokenId 要上架的 NFT ID
     * @param price 出售价格（多少个 paymentToken）
     */
    function list(uint256 tokenId, uint256 price) external {
        if (price == 0) revert PriceZero();
        if (price > type(uint96).max) revert PriceOverflow();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotOwner();

        // 记账：写入单个 Storage Slot
        // forge-lint: disable-next-line(unsafe-typecast)
        listings[tokenId] = Listing({
            seller: msg.sender,
            price: uint96(price)
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
        _executeBuy(tokenId, amount, true);
    }

    /**
     * @notice 白名单用户通过管理员 EIP-712 签名授权购买 NFT
     * @dev 避免在进入 _executeBuy 前多读取一次 listings[tokenId].price 的 SLOAD
     * @param tokenId 购买的 NFT ID
     * @param signature 管理员符合 EIP-712 标准的离线签名
     */
    function permitBuy(uint256 tokenId, bytes calldata signature) external {
        _verifyWhitelist(msg.sender, tokenId, signature);
        _executeBuy(tokenId, 0, false);
    }

    /**
     * @notice 白名单用户通过管理员 EIP-712 签名授权购买 NFT（带传入支付金额）
     * @param tokenId 购买的 NFT ID
     * @param amount 支付代币数量
     * @param signature 管理员符合 EIP-712 标准的离线签名
     */
    function permitBuy(uint256 tokenId, uint256 amount, bytes calldata signature) external {
        _verifyWhitelist(msg.sender, tokenId, signature);
        _executeBuy(tokenId, amount, true);
    }

    /**
     * @notice 重载兼容：支持 (v, r, s) 拆分形式签名的 permitBuy
     * @dev 直接通过 ECDSA.recover(digest, v, r, s) 验签，消除 abi.encodePacked 内存分配
     */
    function permitBuy(uint256 tokenId, uint8 v, bytes32 r, bytes32 s) external {
        _verifyWhitelistVRS(msg.sender, tokenId, v, r, s);
        _executeBuy(tokenId, 0, false);
    }

    /**
     * @notice 重载兼容：支持 (v, r, s) 拆分形式且带 amount 的 permitBuy
     */
    function permitBuy(uint256 tokenId, uint256 amount, uint8 v, bytes32 r, bytes32 s) external {
        _verifyWhitelistVRS(msg.sender, tokenId, v, r, s);
        _executeBuy(tokenId, amount, true);
    }

    /**
     * @dev 校验管理员的 EIP-712 白名单签名授权（bytes calldata 避免内存拷贝）
     */
    function _verifyWhitelist(address buyer, uint256 tokenId, bytes calldata signature) internal view {
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_BUY_TYPEHASH, buyer, tokenId)
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);

        if (signer != admin) {
            bytes32 fallbackStructHash = keccak256(
                abi.encode(FALLBACK_PERMIT_BUY_TYPEHASH, buyer)
            );
            bytes32 fallbackDigest = _hashTypedDataV4(fallbackStructHash);
            if (ECDSA.recover(fallbackDigest, signature) != admin) {
                revert InvalidWhitelistSignature();
            }
        }
    }

    /**
     * @dev 校验管理员的 EIP-712 白名单签名授权（原生 v, r, s 拆分形式）
     */
    function _verifyWhitelistVRS(address buyer, uint256 tokenId, uint8 v, bytes32 r, bytes32 s) internal view {
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_BUY_TYPEHASH, buyer, tokenId)
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, v, r, s);

        if (signer != admin) {
            bytes32 fallbackStructHash = keccak256(
                abi.encode(FALLBACK_PERMIT_BUY_TYPEHASH, buyer)
            );
            bytes32 fallbackDigest = _hashTypedDataV4(fallbackStructHash);
            if (ECDSA.recover(fallbackDigest, v, r, s) != admin) {
                revert InvalidWhitelistSignature();
            }
        }
    }

    /**
     * @dev 执行购买逻辑核心
     */
    function _executeBuy(uint256 tokenId, uint256 amount, bool checkAmount) internal {
        Listing memory item = listings[tokenId];
        if (item.price == 0) revert NotListed();
        if (checkAmount && amount < item.price) revert InsufficientPayment();
        if (msg.sender == item.seller) revert BuyerCannotBeSeller();

        // Checks-Effects-Interactions 原则：先删除上架记录（单 Slot 置零）
        delete listings[tokenId];

        uint256 price = uint256(item.price);

        // 转移代币：从买家向卖家转入对应的代币
        IERC20(address(paymentToken)).safeTransferFrom(msg.sender, item.seller, price);

        // 转移 NFT：从市场合约向买家转出 NFT
        nftContract.safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTSold(msg.sender, item.seller, tokenId, price);
    }

    /**
     * @notice 回调方式购买（一步购买）：由 CalledToken 的 transferAndCall 自动触发
     */
    function tokensReceived(
        address from,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        if (msg.sender != address(paymentToken)) revert CallerNotPaymentToken();
        if (data.length < 32) revert InvalidDataLength();

        // 解码获取购买的目标 tokenId
        uint256 tokenId = abi.decode(data, (uint256));

        Listing memory item = listings[tokenId];
        if (item.price == 0) revert NotListed();
        if (amount < item.price) revert InsufficientPayment();
        if (from == item.seller) revert BuyerCannotBeSeller();

        // 删除上架记录（单槽置零）
        delete listings[tokenId];

        uint256 price = uint256(item.price);

        // 代币在 transferAndCall 中已经转入本合约 (address(this))
        // 将购买价格对应的代币转账给卖家
        IERC20(address(paymentToken)).safeTransfer(item.seller, price);

        // 若买家多付了代币，退还溢出部分给买家
        if (amount > price) {
            IERC20(address(paymentToken)).safeTransfer(from, amount - price);
        }

        // 转移 NFT 给买家
        nftContract.safeTransferFrom(address(this), from, tokenId);

        emit NFTSold(from, item.seller, tokenId, price);

        return true;
    }

    /**
     * @notice 卖家取消上架，赎回 NFT
     * @param tokenId 要取消上架的 NFT ID
     */
    function cancelListing(uint256 tokenId) external {
        Listing memory item = listings[tokenId];
        if (item.price == 0) revert NotListed();
        if (item.seller != msg.sender) revert CallerNotSeller();

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
        return (item.seller, uint256(item.price));
    }

    /**
     * @notice 获取当前市场合约的 EIP-712 DOMAIN_SEPARATOR
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
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
        return IERC721Receiver.onERC721Received.selector;
    }
}
