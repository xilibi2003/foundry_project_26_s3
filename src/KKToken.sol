// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@oz/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@oz/contracts/access/Ownable.sol";
import {IToken} from "./IToken.sol";

/**
 * @title KKToken
 * @dev 质押奖励代币，每个区块产出 10 个 KK Token。
 * 遵循 ERC20 标准，实现 IToken 接口，允许授权的 minter (如 StakingPool) 铸造代币。
 */
contract KKToken is ERC20, Ownable, IToken {
    /// @notice 授权铸币权限映射 (例如 StakingPool)
    mapping(address => bool) public isMinter;

    event MinterUpdated(address indexed minter, bool status);

    error NotAuthorizedMinter();

    modifier onlyMinter() {
        if (!isMinter[msg.sender] && msg.sender != owner()) {
            revert NotAuthorizedMinter();
        }
        _;
    }

    constructor() ERC20("KK Token", "KK") Ownable(msg.sender) {
        // 部署者默认拥有铸币权限
        isMinter[msg.sender] = true;
    }

    /**
     * @notice 设置/撤销指定地址的铸币权限
     * @param minter 目标地址
     * @param status 是否允许铸币
     */
    function setMinter(address minter, bool status) external onlyOwner {
        isMinter[minter] = status;
        emit MinterUpdated(minter, status);
    }

    /**
     * @notice 为指定地址铸造 KK Token
     * @param to 接收地址
     * @param amount 铸造数量
     */
    function mint(address to, uint256 amount) external override onlyMinter {
        _mint(to, amount);
    }
}
