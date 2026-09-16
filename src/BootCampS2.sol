// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@oz/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@oz/contracts/access/Ownable.sol";

contract BootCampS2 is ERC721, Ownable {
    uint256 private _nextTokenId = 1;
    mapping(uint256 tokenId => string) private _tokenURIs;

    constructor() ERC721("BootCampS2", "BootCampS2") Ownable(msg.sender) {}

    function mint(
        address to,
        string memory uri
    ) external onlyOwner returns (uint256 tokenId) {
        require(to != address(0), "BootCampS2: to is zero address");

        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _tokenURIs[tokenId] = uri;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _tokenURIs[tokenId];
    }
}
