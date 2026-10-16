// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@oz/contracts/token/ERC20/IERC20.sol";

/**
 * @title KK Token 
 */
interface IToken is IERC20 {
    function mint(address to, uint256 amount) external;
}
