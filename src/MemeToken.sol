// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@oz/contracts/token/ERC20/ERC20.sol";
import {Initializable} from "@oz/contracts/proxy/utils/Initializable.sol";

/**
 * @title MemeToken
 * @dev 最小代理（EIP-1167）所指向的实现合约
 * 继承 ERC20 和 Initializable，通过 initialize 方法完成状态初始化
 */
contract MemeToken is ERC20, Initializable {
    string private _tokenName;
    string private _tokenSymbol;

    uint256 public maxSupply;
    uint256 public perMint;
    address public factory;
    uint256 public price;

    error OnlyFactory();
    error ExceedsMaxSupply(uint256 requested, uint256 available);

    /**
     * @dev 构造函数中禁用实现合约本身的初始化器，防止实现合约被恶意初始化
     */
    constructor() ERC20("", "") {
        _disableInitializers();
    }

    /**
     * @notice 初始化克隆出来的 Meme 代币实例
     * @param name_ 代币名称
     * @param symbol_ 代币符号
     * @param maxSupply_ 最大发行总量
     * @param perMint_ 单次铸造数量
     * @param factory_ 工厂合约地址（具有 mint 权限）
     * @param price_ 铸造/购买价格（ETH）
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        uint256 perMint_,
        address factory_,
        uint256 price_
    ) external initializer {
        _tokenName = name_;
        _tokenSymbol = symbol_;
        maxSupply = maxSupply_;
        perMint = perMint_;
        factory = factory_;
        price = price_;
    }

    /**
     * @dev 返回代币名称
     */
    function name() public view virtual override returns (string memory) {
        return _tokenName;
    }

    /**
     * @dev 返回代币符号
     */
    function symbol() public view virtual override returns (string memory) {
        return _tokenSymbol;
    }

    /**
     * @notice 铸造代币，仅允许工厂合约调用
     * @param to 接收代币地址
     * @param amount 铸造数量
     */
    function mint(address to, uint256 amount) external {
        if (msg.sender != factory) {
            revert OnlyFactory();
        }
        if (totalSupply() + amount > maxSupply) {
            revert ExceedsMaxSupply(amount, maxSupply - totalSupply());
        }
        _mint(to, amount);
    }
}
