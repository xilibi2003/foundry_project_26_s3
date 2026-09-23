// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MyPermitToken} from "../src/MyPermitToken.sol";
import {IERC20Errors} from "@oz/contracts/interfaces/draft-IERC6093.sol";

contract MyPermitTokenTest is Test {
    MyPermitToken public token;

    address public owner;
    uint256 public ownerPrivateKey;

    address public spender = makeAddr("spender");
    address public recipient = makeAddr("recipient");

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        (owner, ownerPrivateKey) = makeAddrAndKey("owner");

        vm.prank(owner);
        token = new MyPermitToken("MyPermitToken", "MPT");
    }

    /// @notice 辅助函数：构造并对 EIP-2612 permit 进行签名
    function _getPermitSignature(
        uint256 privateKey,
        address tokenOwner,
        address tokenSpender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                tokenOwner,
                tokenSpender,
                value,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (v, r, s) = vm.sign(privateKey, digest);
    }

    /// @dev 测试基础元数据与初始供应量
    function test_InitialState() public view {
        assertEq(token.name(), "MyPermitToken");
        assertEq(token.symbol(), "MPT");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000 * 10 ** 18);
        assertEq(token.balanceOf(owner), 1_000_000 * 10 ** 18);
        assertEq(token.nonces(owner), 0);
        assertTrue(token.DOMAIN_SEPARATOR() != bytes32(0));
    }

    /// @dev 测试成功的 permit 授权及后续 transferFrom
    function test_Permit_Success() public {
        uint256 permitAmount = 500 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(owner);

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            ownerPrivateKey,
            owner,
            spender,
            permitAmount,
            nonce,
            deadline
        );

        // 调用 permit
        token.permit(owner, spender, permitAmount, deadline, v, r, s);

        // 验证 allowance 和 nonce 状态更新
        assertEq(token.allowance(owner, spender), permitAmount);
        assertEq(token.nonces(owner), 1);

        // spender 执行 transferFrom
        vm.prank(spender);
        token.transferFrom(owner, recipient, permitAmount);

        assertEq(token.balanceOf(recipient), permitAmount);
        assertEq(token.allowance(owner, spender), 0);
    }

    /// @dev 测试 permit 签名过期时 revert
    function test_RevertWhen_DeadlineExpired() public {
        uint256 permitAmount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp - 1; // 已过期
        uint256 nonce = token.nonces(owner);

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            ownerPrivateKey,
            owner,
            spender,
            permitAmount,
            nonce,
            deadline
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC2612ExpiredSignature(uint256)")),
                deadline
            )
        );
        token.permit(owner, spender, permitAmount, deadline, v, r, s);
    }

    /// @dev 测试签名者与 owner 不匹配时 revert
    function test_RevertWhen_InvalidSigner() public {
        (, uint256 wrongPrivateKey) = makeAddrAndKey("wrongSigner");
        uint256 permitAmount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(owner);

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            wrongPrivateKey,
            owner,
            spender,
            permitAmount,
            nonce,
            deadline
        );

        vm.expectRevert();
        token.permit(owner, spender, permitAmount, deadline, v, r, s);
    }

    /// @dev 测试重放攻击（重复使用相同签名时因为 nonce 已递增而 revert）
    function test_RevertWhen_SignatureReplay() public {
        uint256 permitAmount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(owner);

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            ownerPrivateKey,
            owner,
            spender,
            permitAmount,
            nonce,
            deadline
        );

        // 第一次成功
        token.permit(owner, spender, permitAmount, deadline, v, r, s);

        // 第二次使用同一签名，因为 nonce 改变，签名恢复出的地址不再是 owner，触发 revert
        vm.expectRevert();
        token.permit(owner, spender, permitAmount, deadline, v, r, s);
    }

    /// @dev 测试增发 mint 函数
    function test_Mint() public {
        uint256 mintAmount = 200 * 10 ** 18;
        address alice = makeAddr("alice");

        token.mint(alice, mintAmount);
        assertEq(token.balanceOf(alice), mintAmount);
    }
}
