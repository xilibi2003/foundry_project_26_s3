// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MyWallet} from "../src/MyWallet.sol";

contract MyWalletTest is Test {
    MyWallet public wallet;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        vm.prank(alice);
        wallet = new MyWallet("AliceWallet");
    }

    function test_InitialOwner() public view {
        assertEq(wallet.owner(), alice);
        assertEq(wallet.name(), "AliceWallet");
    }

    function test_TransferOwnership_Success() public {
        vm.prank(alice);
        wallet.transferOwernship(bob);
        assertEq(wallet.owner(), bob);

        // 新 owner 可以继续转移
        vm.prank(bob);
        wallet.transferOwernship(alice);
        assertEq(wallet.owner(), alice);
    }

    function test_RevertWhen_NotAuthorized() public {
        vm.prank(bob);
        vm.expectRevert("Not authorized");
        wallet.transferOwernship(bob);
    }

    function test_RevertWhen_ZeroAddress() public {
        vm.prank(alice);
        vm.expectRevert("New owner is the zero address");
        wallet.transferOwernship(address(0));
    }

    function test_RevertWhen_SameOwner() public {
        vm.prank(alice);
        vm.expectRevert("New owner is the same as the old owner");
        wallet.transferOwernship(alice);
    }

    function test_PrintSlots() public view {
        uint256 ownerSlot = wallet.printOwnerSlot();
        assertEq(ownerSlot, 2);

        (uint256 nameSlot, uint256 approvedSlot, uint256 oSlot) = wallet.printAllSlots();
        assertEq(nameSlot, 0);
        assertEq(approvedSlot, 1);
        assertEq(oSlot, 2);
    }
}
