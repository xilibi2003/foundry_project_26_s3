// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@oz/contracts/token/ERC20/ERC20.sol";

/**
 * @title ITokenReceiver
 * @dev 仿 ERC1363 / ERC777 标准的代币接收者接口
 */
interface ITokenReceiver {
    function tokensReceived(
        address from,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}

/**
 * @title CalledToken
 * @dev 仿 ERC1363 实现带回调通知的 ERC20 代币合约
 * 核心方法 transferAndCall 在转账成功后，若接收方是合约地址，会自动触发该合约的 tokensReceived 回调
 */
contract CalledToken is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    /**
     * @notice 转账给目标地址，若接收方是合约则触发 tokensReceived 回调（不带附加数据）
     * @param to 接收方地址
     * @param amount 转账代币数量
     * @return 成功返回 true
     */
    function transferAndCall(
        address to,
        uint256 amount
    ) external returns (bool) {
        return transferAndCall(to, amount, "");
    }

    /**
     * @notice 转账给目标地址，若接收方是合约则触发 tokensReceived 回调（附带自定义数据）
     * @param to 接收方地址
     * @param amount 转账代币数量
     * @param data 传递给回调函数的附加数据
     * @return 成功返回 true
     */
    function transferAndCall(
        address to,
        uint256 amount,
        bytes memory data
    ) public returns (bool) {
        // 1. 先进行 ERC20 转账
        _transfer(msg.sender, to, amount);

        // 2. 如果目标是合约地址，则触发回调
        if (_isContract(to)) {
            require(
                _checkTokensReceived(msg.sender, to, amount, data),
                "CalledToken: tokensReceived reverted or failed"
            );
        }

        return true;
    }

    /**
     * @dev 调用目标合约的 tokensReceived 接口
     */
    function _checkTokensReceived(
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) internal returns (bool) {
        try ITokenReceiver(to).tokensReceived(from, amount, data) returns (
            bool success
        ) {
            return success;
        } catch {
            revert("CalledToken: tokensReceived call failed");
        }
    }

    /**
     * @dev 判断目标地址是否是合约地址（code.length > 0）
     */
    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}
