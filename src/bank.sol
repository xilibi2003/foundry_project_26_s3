// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Bank {
    address public admin;

    mapping(address => uint256) public balances; // all  top3
    address[3] public topDepositors;

    event Deposited(
        address indexed depositor,
        uint256 amount,
        uint256 totalAmount
    );
    event Withdrawn(address indexed admin, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Bank: caller is not admin");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable virtual {
        require(msg.value > 0, "Bank: deposit amount is zero");

        balances[msg.sender] += msg.value;
        _updateTopDepositors(msg.sender);

        emit Deposited(msg.sender, msg.value, balances[msg.sender]);
    }

    // withdraw 收钱  -> 发出
    function withdraw(uint amount) external onlyAdmin {
        // uint256 amount = address(this).balance;
        require(amount > 0, "Bank: no ETH to withdraw");

        (bool success, ) = payable(admin).call{value: amount}("");
        require(success, "Bank: withdraw failed");

        emit Withdrawn(admin, amount);
    }

    function getTopDepositors() external view returns (address[3] memory) {
        return topDepositors;
    }

    function _updateTopDepositors(address depositor) private {
        for (uint256 i = 0; i < topDepositors.length; i++) {
            if (topDepositors[i] == depositor) {
                _sortTopDepositors();
                return;
            }
        }

        for (uint256 i = 0; i < topDepositors.length; i++) {
            if (
                topDepositors[i] == address(0) ||
                balances[depositor] > balances[topDepositors[i]]
            ) {
                for (uint256 j = topDepositors.length - 1; j > i; j--) {
                    topDepositors[j] = topDepositors[j - 1];
                }
                topDepositors[i] = depositor;
                return;
            }
        }
    }

    function _sortTopDepositors() private {
        for (uint256 i = 0; i < topDepositors.length; i++) {
            for (uint256 j = i + 1; j < topDepositors.length; j++) {
                if (balances[topDepositors[j]] > balances[topDepositors[i]]) {
                    address temp = topDepositors[i];
                    topDepositors[i] = topDepositors[j];
                    topDepositors[j] = temp;
                }
            }
        }
    }
}
