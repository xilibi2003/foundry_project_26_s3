// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import "./BaseScript.s.sol";
import {CalledToken} from "../src/CalledToken.sol";

contract CalledScript is BaseScript {
    CalledToken public token;

    function run() public broadcaster {
        token = new CalledToken("MyCalledToken", "MCTK");
        console.log("CalledToken deployed on %s", address(token));
        saveContract("CalledToken", address(token));
    }
}
