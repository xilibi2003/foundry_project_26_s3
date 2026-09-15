// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MyERC20} from "../src/MyERC20.sol";

contract MyERC20Script is Script {
    MyERC20 public myToken;

    function setUp() public {}

    function run() public returns (MyERC20) {
        vm.startBroadcast();

        myToken = new MyERC20("MyToken", "MTK");

        vm.stopBroadcast();

        console.log("MyERC20 deployed to:", address(myToken));
        return myToken;
    }
}
