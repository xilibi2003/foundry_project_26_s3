// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ISignatureTransfer
 * @notice Uniswap Permit2 SignatureTransfer 接口
 * 规范参考: https://github.com/Uniswap/permit2/blob/main/src/interfaces/ISignatureTransfer.sol
 */
interface ISignatureTransfer {
    /// @notice 授权的代币与额度结构
    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    /// @notice 签名授权转账信息
    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }

    /// @notice 目标转账明细
    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }

    /**
     * @notice 通过 Permit2 签名授权执行代币转账
     * @param permit 包含代币、金额、nonce 以及有效期的许可信息
     * @param transferDetails 转账接收地址以及扣款金额
     * @param owner 代币所有者（签名者）
     * @param signature 符合 EIP-712 标准的签名 (65 字节)
     */
    function permitTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails memory transferDetails,
        address owner,
        bytes memory signature
    ) external;

    /**
     * @notice 查询指定用户的 nonce 位图（防重放）
     */
    function nonceBitmap(address owner, uint256 wordPos) external view returns (uint256);

    /**
     * @notice 获取 Permit2 合约的 EIP-712 DOMAIN_SEPARATOR
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
