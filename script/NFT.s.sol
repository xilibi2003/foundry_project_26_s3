// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import "./BaseScript.s.sol";
import {MyERC721} from "../src/MyERC721.sol";

contract NFTScript is BaseScript {
    MyERC721 public nft;

    function run() public broadcaster {
        nft = new MyERC721();
        console.log("MyERC721 deployed on %s", address(nft));
        saveContract("MyERC721", address(nft));

        nft.mint(
            deployer,
            "ipfs://bafkreidztoogyu7uccbgm2vx7mhp5m3n25qwy4jnp7cep7ckos23g4lk7a"
        );
    }
}
