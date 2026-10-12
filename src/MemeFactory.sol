// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Clones} from "@oz/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@oz/contracts/utils/ReentrancyGuard.sol";
import {MemeToken} from "./MemeToken.sol";
import {IUniswapV2Router02} from "./uniswapv2/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./uniswapv2/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "./uniswapv2/interfaces/IUniswapV2Pair.sol";

/**
 * @title MemeFactory
 * @dev 使用 EIP-1167 最小代理（Minimal Proxy / Clone）创建 Meme ERC20 代币的工厂合约
 */
contract MemeFactory is ReentrancyGuard {
    using Clones for address;

    /// @notice 最小代理所指向的模板实现合约地址
    address public immutable tokenImplementation;

    /// @notice Uniswap V2 Router 路由合约地址
    IUniswapV2Router02 public immutable uniswapV2Router;

    /// @notice 记录通过此工厂创建的 Meme 代币列表
    address[] public allMemes;

    /// @notice 校验是否是由当前工厂部署的合法 Meme 代币
    mapping(address => bool) public isMeme;

    /// @notice 记录每个 Meme 代币的创建者
    mapping(address => address) public memeCreators;

    /// @notice 创建代币事件
    event MemeDeployed(
        address indexed tokenAddr,
        string symbol,
        uint256 totalSupply,
        uint256 perMint,
        uint256 price,
        address indexed creator
    );

    /// @notice 铸造代币事件
    event MemeMinted(
        address indexed tokenAddr,
        address indexed minter,
        uint256 amount
    );

    /// @notice 添加 Uniswap 流动性事件
    event LiquidityAdded(
        address indexed tokenAddr,
        uint256 tokenAmount,
        uint256 ethAmount
    );

    error InvalidSymbol();
    error InvalidTotalSupply();
    error InvalidPerMint();
    error InvalidPrice();
    error NotAValidMemeToken();
    error InsufficientPayment();
    error RefundFailed();
    error NoLiquidity();
    error PriceNotBetter();

    /**
     * @notice 工厂构造函数，自动部署一份 MemeToken 模板实现合约并配置 Uniswap Router
     * @param router_ Uniswap V2 Router 合约地址
     */
    constructor(address router_) {
        tokenImplementation = address(new MemeToken());
        uniswapV2Router = IUniswapV2Router02(router_);
    }

    /**
     * @notice 获取 Uniswap Router 地址
     */
    function router() external view returns (address) {
        return address(uniswapV2Router);
    }

    /**
     * @notice 使用最小代理部署新的 Meme ERC20 代币并指定 mint 价格
     * @param symbol 代币符号（同时作为代币名称）
     * @param totalSupply 最大发行总量
     * @param perMint 每次 mint 的固定数量
     * @param price 每次 mint 所需支付的 ETH 价格
     * @return tokenAddr 创建出的最小代理代币合约地址
     */
    function deployMeme(
        string memory symbol,
        uint256 totalSupply,
        uint256 perMint,
        uint256 price
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
        if (price == 0) {
            revert InvalidPrice();
        }

        // 使用 EIP-1167 最小代理克隆实现合约
        tokenAddr = tokenImplementation.clone();

        // 对克隆代理合约进行初始化
        MemeToken(tokenAddr).initialize(
            symbol,
            symbol,
            totalSupply,
            perMint,
            address(this),
            price
        );

        isMeme[tokenAddr] = true;
        allMemes.push(tokenAddr);
        memeCreators[tokenAddr] = msg.sender;

        emit MemeDeployed(tokenAddr, symbol, totalSupply, perMint, price, msg.sender);
    }

    /**
     * @notice 为调用者按设定价格铸造指定 Meme 代币，并抽取 5% price 与对应代币添加 Uniswap 流动性
     * @param tokenAddr 目标代币合约地址
     */
    function mintMeme(address tokenAddr) external payable nonReentrant {
        if (!isMeme[tokenAddr]) {
            revert NotAValidMemeToken();
        }

        MemeToken token = MemeToken(tokenAddr);
        uint256 price = token.price();
        uint256 amount = token.perMint();

        if (msg.value < price) {
            revert InsufficientPayment();
        }

        // 铸造给购买者 msg.sender
        token.mint(msg.sender, amount);

        // 如果配置了 Uniswap Router，提取 5% price 手续费与相应代币添加流动性
        if (address(uniswapV2Router) != address(0)) {
            uint256 feeEth = (price * 5) / 100;
            if (feeEth > 0) {
                _addLiquidityForMeme(tokenAddr, token, feeEth, price, amount);
            }
        }

        // 退还多余支付的 ETH
        if (msg.value > price) {
            uint256 refund = msg.value - price;
            (bool success, ) = msg.sender.call{value: refund}("");
            if (!success) {
                revert RefundFailed();
            }
        }

        emit MemeMinted(tokenAddr, msg.sender, amount);
    }

    /**
     * @notice 通过 Uniswap V2 Router swapExactETHForTokens 购买 Meme 代币
     * @param tokenAddr 目标代币合约地址
     * @return amounts Uniswap 交换输出的各资产数量
     */
    function buyMeme(address tokenAddr) external payable returns (uint256[] memory amounts) {
        return buyMeme(tokenAddr, 0);
    }

    /**
     * @notice 通过 Uniswap V2 Router swapExactETHForTokens 购买 Meme 代币
     * @param tokenAddr 目标代币合约地址
     * @param minTokensOut 最低期望获得的代币数量（滑点保护）
     * @return amounts Uniswap 交换输出的各资产数量
     */
    function buyMeme(address tokenAddr, uint256 minTokensOut) public payable returns (uint256[] memory amounts) {
        if (!isMeme[tokenAddr]) {
            revert NotAValidMemeToken();
        }
        if (msg.value == 0) {
            revert InsufficientPayment();
        }

        MemeToken token = MemeToken(tokenAddr);
        uint256 price = token.price();
        uint256 perMint = token.perMint();

        address weth = uniswapV2Router.WETH();
        address pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(tokenAddr, weth);
        if (pair == address(0)) {
            revert NoLiquidity();
        }

        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = tokenAddr;

        uint256[] memory amountsOut = uniswapV2Router.getAmountsOut(msg.value, path);
        uint256 tokensOut = amountsOut[1];

        // 设定的起始价格所能换取的代币数量
        uint256 expectedTokens = (msg.value * perMint) / price;

        // 仅当 Uniswap 的价格优于设定的起始价格（即能获得更多代币）时允许购买
        if (tokensOut <= expectedTokens) {
            revert PriceNotBetter();
        }

        uint256 amountOutMin = minTokensOut > 0 ? minTokensOut : expectedTokens;

        amounts = uniswapV2Router.swapExactETHForTokens{value: msg.value}(
            amountOutMin,
            path,
            msg.sender,
            block.timestamp
        );
    }

    /**
     * @notice 内部方法：使用 5% ETH 和对应代币调用 Uniswap V2 Router 添加流动性
     */
    function _addLiquidityForMeme(
        address tokenAddr,
        MemeToken token,
        uint256 feeEth,
        uint256 price,
        uint256 perMint
    ) internal {
        address weth = uniswapV2Router.WETH();
        address uniswapFactory = uniswapV2Router.factory();
        address pair = IUniswapV2Factory(uniswapFactory).getPair(tokenAddr, weth);

        uint256 tokenLiquidity;
        bool isFirstTime = false;

        if (pair == address(0)) {
            isFirstTime = true;
        } else {
            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();
            if (reserve0 == 0 && reserve1 == 0) {
                isFirstTime = true;
            } else {
                (uint256 reserveToken, uint256 reserveETH) = tokenAddr < weth
                    ? (uint256(reserve0), uint256(reserve1))
                    : (uint256(reserve1), uint256(reserve0));

                if (reserveETH == 0) {
                    isFirstTime = true;
                } else {
                    // 非第一次添加流动性：按当前池子比例计算所需的代币数量
                    tokenLiquidity = (feeEth * reserveToken) / reserveETH;
                }
            }
        }

        if (isFirstTime) {
            // 如果是第一次添加流动性按 mint 价格作为流动性价格
            // mint 价格为 price ETH 对应 perMint 代币
            // feeEth 对应的代币数量为：(feeEth * perMint) / price
            tokenLiquidity = (feeEth * perMint) / price;
        }

        if (tokenLiquidity > 0) {
            // 确保不会超过代币的最大发行总量
            uint256 available = token.maxSupply() - token.totalSupply();
            if (tokenLiquidity > available) {
                tokenLiquidity = available;
            }
        }

        if (tokenLiquidity > 0) {
            token.mint(address(this), tokenLiquidity);
            token.approve(address(uniswapV2Router), tokenLiquidity);

            uniswapV2Router.addLiquidityETH{value: feeEth}(
                tokenAddr,
                tokenLiquidity,
                0,
                0,
                address(this),
                block.timestamp
            );

            emit LiquidityAdded(tokenAddr, tokenLiquidity, feeEth);
        }
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

    receive() external payable {}
}
