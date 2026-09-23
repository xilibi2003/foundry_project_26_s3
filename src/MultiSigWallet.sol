// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MultiSigWallet
 * @notice 简单的多签钱包合约，构造时使用 2/3 多签门槛
 * @dev 支持提案、确认以及达到门槛后任何人均可触发执行
 */
contract MultiSigWallet {
    // 交易/提案结构体
    struct Transaction {
        address to;                 // 目标执行地址
        uint256 value;              // 发送的以太币数量 (wei)
        bytes data;                 // 交易执行的 CallData
        bool executed;              // 是否已被执行
        uint256 confirmationCount;  // 当前确认数
    }

    // 多签持有人列表
    address[] public owners;
    // 地址是否为多签持有人映射
    mapping(address => bool) public isOwner;
    // 2/3 多签所要求的确认门槛
    uint256 public requiredConfirmations;

    // 交易列表
    Transaction[] public transactions;
    // 交易确认状态映射: txId => owner => 是否已确认
    mapping(uint256 => mapping(address => bool)) public isConfirmed;

    // 事件定义
    event Deposit(address indexed sender, uint256 amount, uint256 balance);
    event ProposalSubmitted(
        uint256 indexed txId,
        address indexed proposer,
        address indexed to,
        uint256 value,
        bytes data
    );
    event TransactionConfirmed(uint256 indexed txId, address indexed owner);
    event TransactionExecuted(uint256 indexed txId, address indexed executor);

    // 修饰器：仅多签持有人可调用
    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not an owner");
        _;
    }

    // 修饰器：交易必须存在
    modifier txExists(uint256 _txId) {
        require(_txId < transactions.length, "Transaction does not exist");
        _;
    }

    // 修饰器：交易尚未被执行
    modifier notExecuted(uint256 _txId) {
        require(!transactions[_txId].executed, "Transaction already executed");
        _;
    }

    // 修饰器：当前持有人未确认过该交易
    modifier notConfirmed(uint256 _txId) {
        require(!isConfirmed[_txId][msg.sender], "Transaction already confirmed");
        _;
    }

    /**
     * @notice 构造函数初始化多签持有人并计算 2/3 门槛
     * @param _owners 多签持有人地址数组
     */
    constructor(address[] memory _owners) {
        require(_owners.length > 0, "Owners required");

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner address");
            require(!isOwner[owner], "Owner not unique");

            isOwner[owner] = true;
            owners.push(owner);
        }

        // 构造时采用三分之二多签门槛 (向上取整: ceil(2 * n / 3))
        // 公式: (n * 2 + 2) / 3
        requiredConfirmations = (_owners.length * 2 + 2) / 3;
    }

    /**
     * @notice 接收以太币
     */
    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    /**
     * @notice 多签持有人提交提案交易
     * @param _to 目标地址
     * @param _value 转账以太币金额 (wei)
     * @param _data 调用数据
     * @return txId 提案交易索引
     */
    function proposal(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external onlyOwner returns (uint256 txId) {
        txId = transactions.length;

        transactions.push(
            Transaction({
                to: _to,
                value: _value,
                data: _data,
                executed: false,
                confirmationCount: 1 // 提议人默认确认该交易
            })
        );

        isConfirmed[txId][msg.sender] = true;

        emit ProposalSubmitted(txId, msg.sender, _to, _value, _data);
        emit TransactionConfirmed(txId, msg.sender);
    }

    /**
     * @notice 其他多签持有人确认交易
     * @param _txId 交易索引
     */
    function comfirm(uint256 _txId)
        external
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
        notConfirmed(_txId)
    {
        isConfirmed[_txId][msg.sender] = true;
        transactions[_txId].confirmationCount += 1;

        emit TransactionConfirmed(_txId, msg.sender);
    }

    /**
     * @notice 达到多签门槛后，任何人都可以执行交易
     * @param _txId 交易索引
     */
    function execute(uint256 _txId)
        external
        txExists(_txId)
        notExecuted(_txId)
    {
        Transaction storage txn = transactions[_txId];

        require(
            txn.confirmationCount >= requiredConfirmations,
            "Cannot execute: threshold not reached"
        );

        // 先标记已执行，防止重入攻击 (Checks-Effects-Interactions)
        txn.executed = true;

        (bool success, bytes memory returnData) = txn.to.call{value: txn.value}(txn.data);
        require(success, string(abi.encodePacked("Execution failed: ", returnData)));

        emit TransactionExecuted(_txId, msg.sender);
    }

    /**
     * @notice 获取交易总数
     */
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    /**
     * @notice 获取指定交易详情
     */
    function getTransaction(uint256 _txId)
        external
        view
        txExists(_txId)
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 confirmationCount
        )
    {
        Transaction storage txn = transactions[_txId];
        return (
            txn.to,
            txn.value,
            txn.data,
            txn.executed,
            txn.confirmationCount
        );
    }

    /**
     * @notice 获取所有多签持有人地址
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }
}
