// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import "./BaseScript.s.sol";
import {CalledToken} from "../src/CalledToken.sol";
import {TokenBank} from "../src/TokenBank.sol";

contract DeployTokenBankScript is BaseScript {
    CalledToken public token;
    TokenBank public bank;

    function run() public broadcaster {
        console.log("=== Deploying CalledToken & TokenBank ===");
        console.log("Deployer address:", deployer);

        // 1. 部署 CalledToken
        token = new CalledToken("MyCalledToken", "MCTK");
        console.log("CalledToken deployed at:", address(token));
        saveContract("CalledToken", address(token));

        // 2. 部署 TokenBank，绑定该 CalledToken
        bank = new TokenBank(address(token));
        console.log("TokenBank deployed at:", address(bank));
        saveContract("TokenBank", address(bank));

        // 3. 预先向 Anvil Account 1 和 Account 2 分发测试代币，便于用户切换多账号测试
        address account1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address account2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        uint256 transferAmt = 50000 * 10 ** 18; // 50,000 MCTK

        token.transfer(account1, transferAmt);
        console.log("Transferred 50,000 MCTK to Account 1:", account1);

        token.transfer(account2, transferAmt);
        console.log("Transferred 50,000 MCTK to Account 2:", account2);

        console.log("Deployer remaining balance:", token.balanceOf(deployer));
        console.log("=== Deployment Completed Successfully ===");
    }
}
