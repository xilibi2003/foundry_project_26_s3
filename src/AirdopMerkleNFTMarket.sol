// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@oz/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@oz/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC721} from "@oz/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@oz/contracts/token/ERC721/IERC721Receiver.sol";
import {MerkleProof} from "@oz/contracts/utils/cryptography/MerkleProof.sol";
import {MyPermitToken} from "./MyPermitToken.sol";

/**
 * @title AirdopMerkleNFTMarket
 * @dev 基于默克尔树白名单验证的 NFT 市场合约
 * 特性：
 * 1. 默克尔树白名单：只有白名单用户（提交有效 Merkle Proof）才能调用 buyNFT 购买 NFT
 * 2. 支付代币使用集成 EIP-2612 Permit 的 MyPermitToken
 * 3. 预授权接口 permitPrePay：内部调用 MyPermitToken.permit 完成授权，无需额外预先发送 approve 交易
 * 4. 内置基于 delegatecall 的 multicall：支持在单笔交易内原子组合执行 [permitPrePay, buyNFT]
 */
contract AirdopMerkleNFTMarket is IERC721Receiver {
    using SafeERC20 for IERC20;
    using SafeERC20 for MyPermitToken;

    // 自定义错误（Custom Errors）以降低 Gas 消耗
    error CallerNotAdmin();
    error ZeroAddress();
    error PriceZero();
    error PriceOverflow();
    error NotOwner();
    error NotListed();
    error InsufficientPayment();
    error BuyerCannotBeSeller();
    error NotWhitelisted();
    error CallerNotSeller();

    // 绑定的支付代币（MyPermitToken）
    MyPermitToken public immutable paymentToken;
    // 绑定的 NFT 合约
    IERC721 public immutable nftContract;

    // 管理员地址
    address public admin;
    // 默克尔树根哈希
    bytes32 public merkleRoot;

    // 上架信息结构体：单槽打包 (160 bits address + 96 bits uint96 price)
    struct Listing {
        address seller; // 卖家地址
        uint96 price;   // 出售价格
    }

    // tokenId => 上架信息
    mapping(uint256 => Listing) public listings;

    // 事件
    event NFTListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTSold(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTDelisted(address indexed seller, uint256 indexed tokenId);
    event MerkleRootUpdated(bytes32 indexed oldRoot, bytes32 indexed newRoot);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert CallerNotAdmin();
        _;
    }

    /**
     * @param _paymentToken 绑定的支付代币地址（MyPermitToken）
     * @param _nftContract 绑定的 NFT 合约地址
     * @param _merkleRoot 默克尔树根哈希（白名单）
     */
    constructor(
        address _paymentToken,
        address _nftContract,
        bytes32 _merkleRoot
    ) {
        if (_paymentToken == address(0) || _nftContract == address(0)) {
            revert ZeroAddress();
        }
        paymentToken = MyPermitToken(_paymentToken);
        nftContract = IERC721(_nftContract);
        merkleRoot = _merkleRoot;
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
     * @notice 更新默克尔树根（更新白名单）
     * @param _merkleRoot 新的 Merkle Root
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyAdmin {
        emit MerkleRootUpdated(merkleRoot, _merkleRoot);
        merkleRoot = _merkleRoot;
    }

    /**
     * @notice NFT 持有者上架 NFT
     * @param tokenId 要上架的 NFT ID
     * @param price 出售价格（以 paymentToken 为单位）
     */
    function list(uint256 tokenId, uint256 price) external {
        if (price == 0) revert PriceZero();
        if (price > type(uint96).max) revert PriceOverflow();
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotOwner();

        listings[tokenId] = Listing({
            seller: msg.sender,
            price: uint96(price)
        });

        // 托管 NFT 至本合约
        nftContract.safeTransferFrom(msg.sender, address(this), tokenId);

        emit NFTListed(msg.sender, tokenId, price);
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

        nftContract.safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTDelisted(msg.sender, tokenId);
    }

    /**
     * @notice 预授权方法：调用 MyPermitToken 的 permit 进行签名授权
     * @dev 授权当前市场合约 (address(this)) 为 spender
     * @param amount 授权代币数量
     * @param deadline 签名有效截止时间
     * @param v 签名参数 v
     * @param r 签名参数 r
     * @param s 签名参数 s
     */
    function permitPrePay(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        permitPrePay(msg.sender, amount, deadline, v, r, s);
    }

    /**
     * @notice 预授权方法（显式指定 owner）
     */
    function permitPrePay(
        address owner,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        IERC20Permit(address(paymentToken)).permit(
            owner,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );
    }

    /**
     * @notice 预授权方法（传入打包的 bytes signature 签名）
     */
    function permitPrePay(
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) public {
        require(signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        permitPrePay(msg.sender, amount, deadline, v, r, s);
    }

    /**
     * @notice 白名单用户通过默克尔树证明购买指定 NFT
     * @param tokenId 购买的目标 NFT ID
     * @param merkleProof 默克尔树白名单证明
     */
    function buyNFT(uint256 tokenId, bytes32[] calldata merkleProof) public {
        if (!_verifyWhitelist(msg.sender, merkleProof)) revert NotWhitelisted();
        _executeBuy(tokenId);
    }

    /**
     * @notice 白名单用户购买 NFT（带支付金额校验）
     * @param tokenId 购买的目标 NFT ID
     * @param amount 支付代币数量
     * @param merkleProof 默克尔树白名单证明
     */
    function buyNFT(
        uint256 tokenId,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) public {
        if (!_verifyWhitelist(msg.sender, merkleProof)) revert NotWhitelisted();
        Listing memory item = listings[tokenId];
        if (amount < item.price) revert InsufficientPayment();
        _executeBuy(tokenId);
    }

    /**
     * @dev 执行购买核心逻辑
     */
    function _executeBuy(uint256 tokenId) internal {
        Listing memory item = listings[tokenId];
        if (item.price == 0) revert NotListed();
        if (msg.sender == item.seller) revert BuyerCannotBeSeller();

        delete listings[tokenId];

        uint256 price = uint256(item.price);

        // 从买家向卖家转出代币
        paymentToken.safeTransferFrom(msg.sender, item.seller, price);

        // 将 NFT 从市场转移给买家
        nftContract.safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTSold(msg.sender, item.seller, tokenId, price);
    }

    /**
     * @notice 基于 delegatecall 的批量调用方法（multicall）
     * @dev 保持 msg.sender 不变，允许原子打包 [permitPrePay, buyNFT] 操作
     * @param data 子调用的编码 calldata 数组
     * @return results 各子调用的返回数据数组
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                if (result.length > 0) {
                    assembly {
                        revert(add(result, 32), mload(result))
                    }
                } else {
                    revert("Multicall: call failed");
                }
            }
            results[i] = result;
        }
        return results;
    }

    /**
     * @notice 查询指定 NFT 上架信息
     */
    function getListing(uint256 tokenId) external view returns (address seller, uint256 price) {
        Listing memory item = listings[tokenId];
        return (item.seller, uint256(item.price));
    }

    /**
     * @notice 校验用户是否在默克尔树白名单中
     * @param account 待验证的用户地址
     * @param merkleProof 默克尔证明
     */
    function isWhitelisted(
        address account,
        bytes32[] calldata merkleProof
    ) external view returns (bool) {
        return _verifyWhitelist(account, merkleProof);
    }

    /**
     * @dev 校验用户是否在默克尔树白名单中
     * 兼容 OpenZeppelin 标准 double-hash 与常见 single-hash 两种叶子节点编码方式
     */
    function _verifyWhitelist(
        address account,
        bytes32[] calldata merkleProof
    ) internal view returns (bool) {
        // 1. 标准 OpenZeppelin 格式: keccak256(bytes.concat(keccak256(abi.encode(account))))
        bytes32 leafDouble = keccak256(bytes.concat(keccak256(abi.encode(account))));
        if (MerkleProof.verify(merkleProof, merkleRoot, leafDouble)) {
            return true;
        }

        // 2. 经典单一哈希格式: keccak256(abi.encodePacked(account))
        bytes32 leafSingle = keccak256(abi.encodePacked(account));
        if (MerkleProof.verify(merkleProof, merkleRoot, leafSingle)) {
            return true;
        }

        return false;
    }

    /**
     * @dev 实现 IERC721Receiver 接口以安全接收 ERC721 代币
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
