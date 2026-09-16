// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {BootCampS2} from "../src/BootCampS2.sol";

// 0xfc206ed73857553098da69af5a63d170f6a62181 on optimism
// owner is mytoken-sepolia
contract MintNFTScript is Script {
    function run() public {
        vm.startBroadcast();
        address recipient = 0x1f35B7b2CaB4b3dFEA7AE56F40D6c7B531940f40;
        string
            memory tokenUri = "ipfs://bafkreifb4z5dy2ls4dvx4fphwuhv434gvl5xer6si33g75x4at4t624jke";

        BootCampS2(0xFC206Ed73857553098Da69Af5a63D170f6a62181).mint(
            recipient,
            tokenUri
        );

        vm.stopBroadcast();
    }
}
