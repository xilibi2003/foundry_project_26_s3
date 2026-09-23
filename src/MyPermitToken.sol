// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@oz/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@oz/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title MyPermitToken
 * @dev 基于 OpenZeppelin 实现的符合 EIP-2612 标准的 ERC20 代币合约
 * 支持通过链下签名（permit）完成授权，免除先调用 approve 的交易 Gas 成本
 */
contract MyPermitToken is ERC20, ERC20Permit {
    constructor(string memory name, string memory symbol)
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    /**
     * @notice 增发/铸造代币（方便测试和增发）
     * @param to 接收代币地址
     * @param amount 铸造数量
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
