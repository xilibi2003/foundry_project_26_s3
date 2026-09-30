// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUNFT} from "../src/UUNFT.sol";

// V2 implementation for upgrade testing
contract UUNFTV2 is UUNFT {
    function version() external pure returns (string memory) {
        return "2.0.0";
    }

    // Example of a new feature in V2
    function batchMint(address to, string[] calldata uris) external returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](uris.length);
        for (uint256 i = 0; i < uris.length; i++) {
            ids[i] = mint(to, uris[i]);
        }
        return ids;
    }
}

contract UUNFTTest is Test {
    UUNFT public implementation;
    ERC1967Proxy public proxy;
    UUNFT public nft;

    address public owner;
    address public alice;
    address public bob;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // 1. Deploy implementation
        implementation = new UUNFT();

        // 2. Encode initializer call
        bytes memory initData = abi.encodeWithSignature(
            "initialize(string,string,address)",
            "Upgradeable NFT",
            "UUNFT",
            owner
        );

        // 3. Deploy ERC1967Proxy pointing to implementation
        proxy = new ERC1967Proxy(address(implementation), initData);

        // 4. Wrap proxy in UUNFT interface
        nft = UUNFT(address(proxy));
    }

    function test_Initialization() public view {
        assertEq(nft.name(), "Upgradeable NFT");
        assertEq(nft.symbol(), "UUNFT");
        assertEq(nft.owner(), owner);
        assertEq(nft.nextTokenId(), 1);
    }

    function test_DefaultInitialization() public {
        UUNFT impl2 = new UUNFT();
        bytes memory initData = abi.encodeWithSignature("initialize(address)", owner);
        ERC1967Proxy proxy2 = new ERC1967Proxy(address(impl2), initData);
        UUNFT nft2 = UUNFT(address(proxy2));

        assertEq(nft2.name(), "UUNFT");
        assertEq(nft2.symbol(), "UU");
        assertEq(nft2.owner(), owner);
    }

    function test_CannotInitializeImplementationDirectly() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(owner);
    }

    function test_CannotReinitializeProxy() public {
        vm.prank(owner);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        nft.initialize(owner);
    }

    function test_MintAndTokenURI() public {
        string memory uri = "ipfs://QmTest123456789";

        uint256 tokenId = nft.mint(alice, uri);
        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.tokenURI(1), uri);
        assertEq(nft.nextTokenId(), 2);
    }

    function test_MintWithoutURI() public {
        uint256 tokenId = nft.mint(bob);
        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.tokenURI(1), "");
    }

    function test_SafeMint() public {
        string memory uri = "ipfs://QmSafeMint";
        uint256 tokenId = nft.safeMint(alice, uri);
        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.tokenURI(1), uri);
    }

    function test_TransferAndApproval() public {
        uint256 tokenId = nft.mint(alice, "ipfs://token1");

        // Alice approves Bob
        vm.prank(alice);
        nft.approve(bob, tokenId);
        assertEq(nft.getApproved(tokenId), bob);

        // Bob transfers token to owner
        vm.prank(bob);
        nft.transferFrom(alice, owner, tokenId);
        assertEq(nft.ownerOf(tokenId), owner);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(nft.balanceOf(owner), 1);
    }

    function test_NonOwnerCannotUpgrade() public {
        UUNFTV2 v2Impl = new UUNFTV2();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice)
        );
        nft.upgradeToAndCall(address(v2Impl), "");
    }

    function test_OwnerCanUpgradeAndPreserveState() public {
        // 1. Mint token in V1
        string memory uri1 = "ipfs://nft-v1-token-1";
        uint256 id1 = nft.mint(alice, uri1);
        assertEq(id1, 1);

        // 2. Deploy V2 implementation
        UUNFTV2 v2Impl = new UUNFTV2();

        // 3. Upgrade to V2 by owner
        vm.prank(owner);
        nft.upgradeToAndCall(address(v2Impl), "");

        // 4. Wrap proxy into V2 interface
        UUNFTV2 nftV2 = UUNFTV2(address(proxy));

        // Verify new V2 method
        assertEq(nftV2.version(), "2.0.0");

        // Verify V1 state is preserved
        assertEq(nftV2.name(), "Upgradeable NFT");
        assertEq(nftV2.symbol(), "UUNFT");
        assertEq(nftV2.owner(), owner);
        assertEq(nftV2.ownerOf(1), alice);
        assertEq(nftV2.tokenURI(1), uri1);
        assertEq(nftV2.nextTokenId(), 2);

        // 5. Test new V2 feature: batchMint
        string[] memory uris = new string[](2);
        uris[0] = "ipfs://nft-v2-token-2";
        uris[1] = "ipfs://nft-v2-token-3";

        uint256[] memory mintedIds = nftV2.batchMint(bob, uris);
        assertEq(mintedIds.length, 2);
        assertEq(mintedIds[0], 2);
        assertEq(mintedIds[1], 3);

        assertEq(nftV2.ownerOf(2), bob);
        assertEq(nftV2.ownerOf(3), bob);
        assertEq(nftV2.tokenURI(2), uris[0]);
        assertEq(nftV2.tokenURI(3), uris[1]);
        assertEq(nftV2.nextTokenId(), 4);
    }
}
