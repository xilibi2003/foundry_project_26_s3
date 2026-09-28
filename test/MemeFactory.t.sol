// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MemeFactory} from "../src/MemeFactory.sol";
import {MemeToken} from "../src/MemeToken.sol";
import {Initializable} from "@oz/contracts/proxy/utils/Initializable.sol";

contract MemeFactoryTest is Test {
    MemeFactory public factory;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        factory = new MemeFactory();
    }

    function test_DeployMeme_Success() public {
        string memory symbol = "DOGE";
        uint256 maxSupply = 1_000_000 ether;
        uint256 perMint = 1_000 ether;

        address tokenAddr = factory.deployMeme(symbol, maxSupply, perMint);
        assertTrue(tokenAddr != address(0));
        assertTrue(factory.isMeme(tokenAddr));
        assertEq(factory.totalMemes(), 1);
        assertEq(factory.getAllMemes()[0], tokenAddr);

        MemeToken token = MemeToken(tokenAddr);
        assertEq(token.name(), "DOGE");
        assertEq(token.symbol(), "DOGE");
        assertEq(token.maxSupply(), maxSupply);
        assertEq(token.perMint(), perMint);
        assertEq(token.factory(), address(factory));
        assertEq(token.totalSupply(), 0);

        // 验证克隆合约大小远小于完整合约（EIP-1167 代理字节码约为 45 字节）
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(tokenAddr)
        }
        assertEq(codeSize, 45);
    }

    function test_ImplementationCannotBeInitialized() public {
        address impl = factory.tokenImplementation();
        MemeToken token = MemeToken(impl);

        // 实现合约在构造函数中已经禁用初始化器
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initialize("FAIL", "FAIL", 1000, 10, address(this));
    }

    function test_CloneCannotBeReinitialized() public {
        address tokenAddr = factory.deployMeme("PEPE", 1000, 100);
        MemeToken token = MemeToken(tokenAddr);

        // 克隆实例已被 factory 初始化，无法再次调用 initialize
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initialize("PEPE2", "PEPE2", 2000, 200, address(this));
    }

    function test_RevertWhen_DeployWithEmptySymbol() public {
        vm.expectRevert(MemeFactory.InvalidSymbol.selector);
        factory.deployMeme("", 1000, 100);
    }

    function test_RevertWhen_DeployWithZeroTotalSupply() public {
        vm.expectRevert(MemeFactory.InvalidTotalSupply.selector);
        factory.deployMeme("SHIB", 0, 100);
    }

    function test_RevertWhen_DeployWithZeroPerMint() public {
        vm.expectRevert(MemeFactory.InvalidPerMint.selector);
        factory.deployMeme("SHIB", 1000, 0);
    }

    function test_RevertWhen_DeployWithPerMintExceedingTotalSupply() public {
        vm.expectRevert(MemeFactory.InvalidPerMint.selector);
        factory.deployMeme("SHIB", 1000, 1001);
    }

    function test_MintMeme_Success() public {
        uint256 maxSupply = 1000 ether;
        uint256 perMint = 100 ether;
        address tokenAddr = factory.deployMeme("MOON", maxSupply, perMint);
        MemeToken token = MemeToken(tokenAddr);

        // Alice 进行 mint
        vm.prank(alice);
        factory.mintMeme(tokenAddr);
        assertEq(token.balanceOf(alice), perMint);
        assertEq(token.totalSupply(), perMint);

        // Bob 进行 mint
        vm.prank(bob);
        factory.mintMeme(tokenAddr);
        assertEq(token.balanceOf(bob), perMint);
        assertEq(token.totalSupply(), perMint * 2);
    }

    function test_MintMeme_UntilMaxSupply() public {
        uint256 maxSupply = 300;
        uint256 perMint = 100;
        address tokenAddr = factory.deployMeme("CAP", maxSupply, perMint);
        MemeToken token = MemeToken(tokenAddr);

        // 铸造 3 次达到最大供应量 300
        factory.mintMeme(tokenAddr);
        factory.mintMeme(tokenAddr);
        factory.mintMeme(tokenAddr);

        assertEq(token.totalSupply(), 300);

        // 第 4 次铸造应因为超过 maxSupply 而失败
        vm.expectRevert(
            abi.encodeWithSelector(MemeToken.ExceedsMaxSupply.selector, perMint, 0)
        );
        factory.mintMeme(tokenAddr);
    }

    function test_RevertWhen_MintUnregisteredToken() public {
        address fakeToken = makeAddr("fakeToken");
        vm.expectRevert(MemeFactory.NotAValidMemeToken.selector);
        factory.mintMeme(fakeToken);
    }

    function test_RevertWhen_DirectMintBypassingFactory() public {
        address tokenAddr = factory.deployMeme("BYPASS", 1000, 100);
        MemeToken token = MemeToken(tokenAddr);

        // 试图绕过工厂直接调用 token.mint 应当被阻止
        vm.expectRevert(MemeToken.OnlyFactory.selector);
        token.mint(alice, 100);
    }

    function test_MemeToken_TransferAndApprove() public {
        address tokenAddr = factory.deployMeme("MOVE", 1000 ether, 100 ether);
        MemeToken token = MemeToken(tokenAddr);

        vm.prank(alice);
        factory.mintMeme(tokenAddr);

        // Alice 转账给 Bob
        vm.prank(alice);
        token.transfer(bob, 40 ether);
        assertEq(token.balanceOf(alice), 60 ether);
        assertEq(token.balanceOf(bob), 40 ether);

        // Bob approve 授权给 Alice 并通过 transferFrom 转账
        vm.prank(bob);
        token.approve(alice, 10 ether);
        assertEq(token.allowance(bob, alice), 10 ether);

        vm.prank(alice);
        token.transferFrom(bob, alice, 10 ether);
        assertEq(token.balanceOf(alice), 70 ether);
        assertEq(token.balanceOf(bob), 30 ether);
    }
}
