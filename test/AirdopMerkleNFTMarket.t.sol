// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MyPermitToken} from "../src/MyPermitToken.sol";
import {MyERC721} from "../src/MyERC721.sol";
import {AirdopMerkleNFTMarket} from "../src/AirdopMerkleNFTMarket.sol";

contract AirdopMerkleNFTMarketTest is Test {
    MyPermitToken public token;
    MyERC721 public nft;
    AirdopMerkleNFTMarket public market;

    address public admin;
    uint256 public adminKey;

    address public seller;
    uint256 public sellerKey;

    address public alice;
    uint256 public aliceKey;

    address public bob;
    uint256 public bobKey;

    address public charlie;
    uint256 public charlieKey;

    address public david;
    uint256 public davidKey;

    uint256 public constant INITIAL_BALANCE = 10_000 * 1e18;
    uint256 public constant NFT_PRICE = 200 * 1e18;
    uint256 public tokenId;

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // 默克尔树数据结构
    bytes32 public merkleRoot;
    bytes32[] public aliceProof;
    bytes32[] public bobProof;
    bytes32[] public charlieProof;

    function setUp() public {
        (admin, adminKey) = makeAddrAndKey("admin");
        (seller, sellerKey) = makeAddrAndKey("seller");
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        (charlie, charlieKey) = makeAddrAndKey("charlie");
        (david, davidKey) = makeAddrAndKey("david"); // david 不在白名单中

        // 1. 构建包含 alice, bob, charlie 的 Merkle Tree（4 节点平衡树，填补第 4 个占位地址）
        address user4 = makeAddr("user4");
        bytes32 leaf0 = keccak256(abi.encodePacked(alice));
        bytes32 leaf1 = keccak256(abi.encodePacked(bob));
        bytes32 leaf2 = keccak256(abi.encodePacked(charlie));
        bytes32 leaf3 = keccak256(abi.encodePacked(user4));

        bytes32 node01 = _hashPair(leaf0, leaf1);
        bytes32 node23 = _hashPair(leaf2, leaf3);
        merkleRoot = _hashPair(node01, node23);

        // 构建各自的 Proof (两层)
        aliceProof = new bytes32[](2);
        aliceProof[0] = leaf1;
        aliceProof[1] = node23;

        bobProof = new bytes32[](2);
        bobProof[0] = leaf0;
        bobProof[1] = node23;

        charlieProof = new bytes32[](2);
        charlieProof[0] = leaf3;
        charlieProof[1] = node01;

        // 2. 部署代币、NFT 与市场合约
        vm.startPrank(admin);
        token = new MyPermitToken("MyPermitToken", "MPT");
        nft = new MyERC721();
        market = new AirdopMerkleNFTMarket(address(token), address(nft), merkleRoot);

        // 分发代币
        token.transfer(alice, INITIAL_BALANCE);
        token.transfer(bob, INITIAL_BALANCE);
        token.transfer(charlie, INITIAL_BALANCE);
        token.transfer(david, INITIAL_BALANCE);
        vm.stopPrank();

        // 3. 卖家铸造并上架 NFT (tokenId = 1)
        vm.startPrank(seller);
        tokenId = nft.mint(seller, "ipfs://nft-camp-card-1");
        nft.approve(address(market), tokenId);
        market.list(tokenId, NFT_PRICE);
        vm.stopPrank();
    }

    /// @notice 辅助函数：根据两个哈希节点计算父哈希（有序排序以匹配 OpenZeppelin MerkleProof）
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /// @notice 辅助函数：生成 EIP-2612 permit 签名
    function _signPermit(
        uint256 signerKey,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );
        (v, r, s) = vm.sign(signerKey, digest);
    }

    /// @dev 验证白名单用户通过传统 approve 方式购买 NFT
    function test_BuyNFT_TraditionalApprove_Success() public {
        vm.startPrank(alice);
        token.approve(address(market), NFT_PRICE);
        market.buyNFT(tokenId, aliceProof);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), alice, "Alice should own the NFT");
        assertEq(token.balanceOf(seller), NFT_PRICE, "Seller should receive tokens");
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - NFT_PRICE, "Alice balance should deduct");
    }

    /// @dev 验证非白名单用户 (David) 购买 NFT 会被 revert
    function test_BuyNFT_RevertWhen_NotWhitelisted() public {
        // David 用空 proof 或随机 proof 尝试购买
        bytes32[] memory fakeProof = new bytes32[](2);
        fakeProof[0] = bytes32(uint256(1));
        fakeProof[1] = bytes32(uint256(2));

        vm.startPrank(david);
        token.approve(address(market), NFT_PRICE);
        vm.expectRevert(AirdopMerkleNFTMarket.NotWhitelisted.selector);
        market.buyNFT(tokenId, fakeProof);
        vm.stopPrank();
    }

    /// @dev 验证白名单用户提交错误 Merkle Proof 会被 revert
    function test_BuyNFT_RevertWhen_InvalidProof() public {
        vm.startPrank(alice);
        token.approve(address(market), NFT_PRICE);
        // Alice 提交错误的 proof (比如提交 Bob 的 proof)
        vm.expectRevert(AirdopMerkleNFTMarket.NotWhitelisted.selector);
        market.buyNFT(tokenId, bobProof);
        vm.stopPrank();
    }

    /// @dev 核心测试：验证通过 multicall 打包 [permitPrePay, buyNFT] 一步完成购买
    function test_Multicall_PermitPrePayAndBuyNFT_Success() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(alice);

        // 1. Alice 链下签名 EIP-2612 Permit，授权 market 消费 NFT_PRICE
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceKey,
            alice,
            address(market),
            NFT_PRICE,
            nonce,
            deadline
        );

        // 2. 构造 multicall 数据包
        bytes[] memory callData = new bytes[](2);
        // 调用 1: permitPrePay(amount, deadline, v, r, s)
        callData[0] = abi.encodeWithSignature(
            "permitPrePay(uint256,uint256,uint8,bytes32,bytes32)",
            NFT_PRICE,
            deadline,
            v,
            r,
            s
        );
        // 调用 2: buyNFT(tokenId, merkleProof)
        callData[1] = abi.encodeWithSignature(
            "buyNFT(uint256,bytes32[])",
            tokenId,
            aliceProof
        );

        // 3. Alice 发起 multicall 单笔交易
        vm.prank(alice);
        bytes[] memory results = market.multicall(callData);

        // 4. 验证执行结果
        assertEq(results.length, 2, "Multicall should return 2 results");
        assertEq(nft.ownerOf(tokenId), alice, "Alice should receive NFT");
        assertEq(token.balanceOf(seller), NFT_PRICE, "Seller should receive payment");
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - NFT_PRICE, "Alice balance deducted");
    }

    /// @dev 验证非白名单用户在 multicall 中尝试购买会被原子回滚
    function test_Multicall_RevertWhen_NotWhitelisted() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(david);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            davidKey,
            david,
            address(market),
            NFT_PRICE,
            nonce,
            deadline
        );

        bytes32[] memory fakeProof = new bytes32[](2);
        bytes[] memory callData = new bytes[](2);
        callData[0] = abi.encodeWithSignature(
            "permitPrePay(uint256,uint256,uint8,bytes32,bytes32)",
            NFT_PRICE,
            deadline,
            v,
            r,
            s
        );
        callData[1] = abi.encodeWithSignature(
            "buyNFT(uint256,bytes32[])",
            tokenId,
            fakeProof
        );

        // 执行 multicall 应该捕获内部 buyNFT 抛出的 NotWhitelisted 并整笔回滚
        vm.prank(david);
        vm.expectRevert(AirdopMerkleNFTMarket.NotWhitelisted.selector);
        market.multicall(callData);

        // 验证 NFT 依然属于市场托管，卖家未收到代币
        assertEq(nft.ownerOf(tokenId), address(market));
        assertEq(token.balanceOf(seller), 0);
    }

    /// @dev 验证卖家自己无法购买自己上架的 NFT
    function test_RevertWhen_BuyerIsSeller() public {
        // 将 seller 加到白名单或重新部署以验证检查
        vm.startPrank(admin);
        bytes32 sellerLeaf = keccak256(abi.encodePacked(seller));
        bytes32 dummyLeaf = keccak256(abi.encodePacked(makeAddr("dummy")));
        bytes32 newRoot = _hashPair(sellerLeaf, dummyLeaf);
        market.setMerkleRoot(newRoot);
        vm.stopPrank();

        bytes32[] memory sellerProof = new bytes32[](1);
        sellerProof[0] = dummyLeaf;

        vm.startPrank(seller);
        token.approve(address(market), NFT_PRICE);
        vm.expectRevert(AirdopMerkleNFTMarket.BuyerCannotBeSeller.selector);
        market.buyNFT(tokenId, sellerProof);
        vm.stopPrank();
    }

    /// @dev 验证卖家取消上架
    function test_CancelListing_Success() public {
        vm.prank(seller);
        market.cancelListing(tokenId);

        assertEq(nft.ownerOf(tokenId), seller, "Seller should retrieve NFT");
        (address s, uint256 p) = market.getListing(tokenId);
        assertEq(s, address(0));
        assertEq(p, 0);
    }
}
