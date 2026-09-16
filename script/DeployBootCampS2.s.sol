// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {BootCampS2} from "../src/BootCampS2.sol";

// deploy by account mytoken-sepolia
contract DeployBootCampS2Script is Script {
    function run() external returns (BootCampS2 nft, uint256 tokenId) {
        address recipient = 0x1f35B7b2CaB4b3dFEA7AE56F40D6c7B531940f40;
        string
            memory tokenUri = "ipfs://bafkreib2woyjoqcyabnisqyx3rnwfo3bafphxroxve6lh4q5iwnyujxkli";

        vm.startBroadcast();
        nft = new BootCampS2();

        tokenId = nft.mint(recipient, tokenUri);
        vm.stopBroadcast();
    }
}
