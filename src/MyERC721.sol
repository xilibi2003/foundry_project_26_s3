// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721URIStorage, ERC721} from "@oz/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract MyERC721 is ERC721URIStorage {
    uint256 private _nextTokenId = 1;

    constructor() ERC721(unicode"集训营学员卡", "CAMP") {}

    function mint(address to, string memory tokenURI) public returns (uint256) {
        uint256 newItemId = _nextTokenId++;

        _safeMint(to, newItemId);
        _setTokenURI(newItemId, tokenURI);

        return newItemId;
    }
}
