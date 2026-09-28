// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Clones} from "@oz/contracts/proxy/Clones.sol";
import {MemeToken} from "./MemeToken.sol";

/**
 * @title MemeFactory
 * @dev 使用 EIP-1167 最小代理（Minimal Proxy / Clone）创建 Meme ERC20 代币的工厂合约
 */
contract MemeFactory {
    using Clones for address;

    /// @notice 最小代理所指向的模板实现合约地址
    address public immutable tokenImplementation;

    /// @notice 记录通过此工厂创建的 Meme 代币列表
    address[] public allMemes;

    /// @notice 校验是否是由当前工厂部署的合法 Meme 代币
    mapping(address => bool) public isMeme;

    /// @notice 创建代币事件
    event MemeDeployed(
        address indexed tokenAddr,
        string symbol,
        uint256 totalSupply,
        uint256 perMint,
        address indexed creator
    );

    /// @notice 铸造代币事件
    event MemeMinted(
        address indexed tokenAddr,
        address indexed minter,
        uint256 amount
    );

    error InvalidSymbol();
    error InvalidTotalSupply();
    error InvalidPerMint();
    error NotAValidMemeToken();

    /**
     * @notice 工厂构造函数，自动部署一份 MemeToken 模板实现合约
     */
    constructor() {
        tokenImplementation = address(new MemeToken());
    }

    /**
     * @notice 使用最小代理部署新的 Meme ERC20 代币
     * @param symbol 代币符号（同时作为代币名称）
     * @param totalSupply 最大发行总量
     * @param perMint 每次 mint 的固定数量
     * @return tokenAddr 创建出的最小代理代币合约地址
     */
    function deployMeme(
        string memory symbol,
        uint256 totalSupply,
        uint256 perMint
    ) external returns (address tokenAddr) {
        if (bytes(symbol).length == 0) {
            revert InvalidSymbol();
        }
        if (totalSupply == 0) {
            revert InvalidTotalSupply();
        }
        if (perMint == 0 || perMint > totalSupply) {
            revert InvalidPerMint();
        }

        // 使用 EIP-1167 最小代理克隆实现合约
        tokenAddr = tokenImplementation.clone();

        // 对克隆代理合约进行初始化
        MemeToken(tokenAddr).initialize(
            symbol,
            symbol,
            totalSupply,
            perMint,
            address(this)
        );

        isMeme[tokenAddr] = true;
        allMemes.push(tokenAddr);

        emit MemeDeployed(tokenAddr, symbol, totalSupply, perMint, msg.sender);
    }

    /**
     * @notice 为调用者铸造指定 Meme 代币，铸造数量为该代币设定的 perMint
     * @param tokenAddr 目标代币合约地址
     */
    function mintMeme(address tokenAddr) external {
        if (!isMeme[tokenAddr]) {
            revert NotAValidMemeToken();
        }

        MemeToken token = MemeToken(tokenAddr);
        uint256 amount = token.perMint();

        // 铸造给调用者 msg.sender
        token.mint(msg.sender, amount);

        emit MemeMinted(tokenAddr, msg.sender, amount);
    }

    /**
     * @notice 获取已部署的 Meme 代币总数量
     */
    function totalMemes() external view returns (uint256) {
        return allMemes.length;
    }

    /**
     * @notice 获取已部署的全部 Meme 代币地址列表
     */
    function getAllMemes() external view returns (address[] memory) {
        return allMemes;
    }
}
