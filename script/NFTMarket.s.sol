// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import "./BaseScript.s.sol";
import {NFTMarket} from "../src/NFTMarket.sol";
import {CalledToken} from "../src/CalledToken.sol";
import {MyERC721} from "../src/MyERC721.sol";

contract NFTMarketScript is BaseScript {
    CalledToken public token;
    MyERC721 public nft;
    NFTMarket public market;

    function run() public broadcaster {
        console.log("Deployer address: %s", deployer);

        // 1. 直接 new CalledToken 合约
        token = new CalledToken("MyCalledToken", "MCTK");
        console.log("CalledToken deployed on %s", address(token));
        saveContract("CalledToken", address(token));

        // 2. 直接 new MyERC721 合约
        nft = new MyERC721();
        console.log("MyERC721 deployed on %s", address(nft));
        saveContract("MyERC721", address(nft));

        // 3. 部署 NFTMarket 合约并关联上述代币和 NFT
        market = new NFTMarket(address(token), address(nft));
        console.log("NFTMarket deployed on %s", address(market));
        saveContract("NFTMarket", address(market));
    }
}
