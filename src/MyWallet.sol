// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";

contract MyWallet { 
    string public name;
    mapping(address => bool) private approved;
    address public owner;

    modifier auth() {
        address currentOwner;
        assembly {
            // 使用内联汇编读取 (get) 存储槽中的 owner
            currentOwner := sload(owner.slot)
        }
        require(msg.sender == currentOwner, "Not authorized");
        _;
    }

    constructor(string memory _name) {
        name = _name;
        assembly {
            // 使用内联汇编设置 (set) owner 为 caller()
            sstore(owner.slot, caller())
        }
    } 

    function transferOwernship(address _addr) public auth {
        require(_addr != address(0), "New owner is the zero address");
        address currentOwner;
        assembly {
            // 使用内联汇编读取 (get) 当前 owner
            currentOwner := sload(owner.slot)
        }
        require(currentOwner != _addr, "New owner is the same as the old owner");

        assembly {
            // 使用内联汇编写入 (set) 新的 owner 地址
            sstore(owner.slot, _addr)
        }
    }

    /**
     * @notice 打印并返回 owner 状态变量的 storage slot 位置
     */
    function printOwnerSlot() public pure returns (uint256 slot) {
        assembly {
            slot := owner.slot
        }
        console.log("------------------------------");
        console.log("owner.slot is:", slot);
        console.log("------------------------------");
    }

    /**
     * @notice 打印并返回合约中所有状态变量的 storage slot 位置
     */
    function printAllSlots() public pure returns (uint256 nameSlot, uint256 approvedSlot, uint256 ownerSlot) {
        assembly {
            nameSlot := name.slot
            approvedSlot := approved.slot
            ownerSlot := owner.slot
        }
        console.log("========== Storage Slots ==========");
        console.log("name.slot:    ", nameSlot);
        console.log("approved.slot:", approvedSlot);
        console.log("owner.slot:   ", ownerSlot);
        console.log("===================================");
    }
}
