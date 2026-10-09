// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MyERC20} from "../src/MyERC20.sol";
import {TokenVesting} from "../src/TokenVesting.sol";

contract DeployTokenVestingScript is Script {
    MyERC20 public token;
    TokenVesting public vesting;

    function run() public returns (MyERC20, TokenVesting) {
        // 读取可选配置，默认使用调用者作为受益人或指定地址
        address beneficiary = vm.envOr("BENEFICIARY", msg.sender);
        console.log("Beneficiary address:", beneficiary);

        vm.startBroadcast();

        // 1. 部署 MyERC20（初始铸造 100 万代币至部署者账户）
        token = new MyERC20("MyERC20", "MERC");
        console.log("MyERC20 deployed at:", address(token));

        // 2. 部署 TokenVesting，开始计算 Cliff
        vesting = new TokenVesting(beneficiary, address(token));
        console.log("TokenVesting deployed at:", address(vesting));
        console.log("Vesting Start:", vesting.start());
        console.log("Cliff End:", vesting.cliff());
        console.log("Vesting End:", vesting.end());

        // 3. 转入 100 万 MyERC20 资产
        uint256 amount = 1_000_000 * 10 ** 18;
        token.transfer(address(vesting), amount);
        console.log("Transferred 1,000,000 MyERC20 to TokenVesting. Balance:", token.balanceOf(address(vesting)));

        vm.stopBroadcast();

        return (token, vesting);
    }
}
