// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UUNFT} from "../src/UUNFT.sol";
import "./BaseScript.s.sol";

contract DeployUUNFTScript is BaseScript {
    function run() public broadcaster {
        // 1. Encode initializer data
        bytes memory initData = abi.encodeWithSignature(
            "initialize(string,string,address)",
            unicode"集训营可升级学员卡",
            "UUNFT",
            deployer
        );

        // 2. Deploy UUPS proxy using openzeppelin-foundry-upgrades
        address proxy = Upgrades.deployUUPSProxy("UUNFT.sol:UUNFT", initData);
        console.log("UUNFT Proxy deployed at: %s", proxy);

        // 3. Get implementation address
        address implementation = Upgrades.getImplementationAddress(proxy);
        console.log("UUNFT Implementation deployed at: %s", implementation);

        // 4. Save deployment info
        saveContract("UUNFT_Implementation", implementation);
        saveContract("UUNFT_Proxy", proxy);
    }
}
