// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CalledToken} from "./CalledToken.sol";
import {ERC20Permit} from "@oz/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title MyPermitToken
 * @dev 继承 CalledToken 并集成 EIP-2612 Permit 扩展的代币合约
 * 既支持 ERC1363 风格的 transferAndCall 回调通知，也支持通过 permit 进行链下签名授权
 */
contract MyPermitToken is CalledToken, ERC20Permit {
    constructor(string memory name, string memory symbol)
        CalledToken(name, symbol)
        ERC20Permit(name)
    {}

    /**
     * @notice 增发/铸造代币（方便测试和增发）
     * @param to 接收代币地址
     * @param amount 铸造数量
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
