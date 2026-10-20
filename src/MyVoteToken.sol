// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title MyVoteToken
 * @dev 继承 ERC20 与 ERC20Votes (并引入 ERC20Permit 支持无 Gas 签名授权与委托)
 */
contract MyVoteToken is ERC20, ERC20Permit, ERC20Votes {
    constructor(string memory name, string memory symbol)
        ERC20(name, symbol)
        ERC20Permit(name)
    {}

    /**
     * @notice 方便测试与分发投票代币的铸造函数
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // 如下函数为 Solidity 多重继承要求的 override

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
