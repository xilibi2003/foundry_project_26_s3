// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title UUNFT
 * @dev Upgradeable ERC721 NFT contract using UUPS (Universal Upgradeable Proxy Standard).
 * Based on OpenZeppelin Contracts Upgradeable v5.
 */
contract UUNFT is Initializable, ERC721URIStorageUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 private _nextTokenId;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with default name and symbol, setting initialOwner as owner.
     * @param initialOwner Address of the initial owner who can authorize upgrades.
     */
    function initialize(address initialOwner) public initializer {
        __UUNFT_init("UUNFT", "UU", initialOwner);
    }

    /**
     * @dev Initializes the contract with custom name, symbol and initial owner.
     * @param name_ Token collection name.
     * @param symbol_ Token collection symbol.
     * @param initialOwner Address of the initial owner who can authorize upgrades.
     */
    function initialize(string memory name_, string memory symbol_, address initialOwner) public initializer {
        __UUNFT_init(name_, symbol_, initialOwner);
    }

    function __UUNFT_init(string memory name_, string memory symbol_, address initialOwner) internal onlyInitializing {
        __ERC721_init(name_, symbol_);
        __ERC721URIStorage_init();
        __Ownable_init(initialOwner);
        _nextTokenId = 1;
    }

    /**
     * @dev Mint a new NFT with tokenURI to `to`.
     * @param to The recipient address of the newly minted token.
     * @param uri The metadata URI of the token.
     * @return The tokenId of the newly minted NFT.
     */
    function mint(address to, string memory uri) public returns (uint256) {
        uint256 newItemId = _nextTokenId++;

        _safeMint(to, newItemId);
        _setTokenURI(newItemId, uri);

        return newItemId;
    }

    /**
     * @dev Mint a new NFT to `to` with empty tokenURI.
     * @param to The recipient address of the newly minted token.
     * @return The tokenId of the newly minted NFT.
     */
    function mint(address to) public returns (uint256) {
        return mint(to, "");
    }

    /**
     * @dev Safe mint alias for compatibility.
     */
    function safeMint(address to, string memory uri) public returns (uint256) {
        return mint(to, uri);
    }

    /**
     * @dev Returns the next tokenId to be minted.
     */
    function nextTokenId() public view returns (uint256) {
        return _nextTokenId;
    }

    /**
     * @dev UUPS upgrade authorization function. Only owner can authorize an upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721URIStorageUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
}
