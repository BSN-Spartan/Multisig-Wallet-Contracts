// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./OwnerManager.sol";

contract MultisigWallet is OwnerManager {

    // 交易
    mapping(uint256 => Spend) internal spends;

    // 交易结构体
    struct Spend {
        address sponsor;
        address ERC20Address;
        address targetAddress;
        uint256 amount;
        uint256 expiredBlock;
        address[] assentients;
        bytes data;
        SpendStatus status;
    }

    // 发起一笔交易事件
    event InitiateTransferEvent (
        address sponsor, 
        address ERC20Address,
        address targetAddress,
        uint256 amount,
        uint256 expiredBlock,
        uint256 spendId,
        bytes data
    );

    // 撤回一笔转账
    event RevocationTransfer (
        address sponsor, 
        address ERC20Address,
        address targetAddress,
        uint256 amount,
        uint256 spendId
    );

    // 确认交易事件
    event ApprovedEvent (
        address assentient, 
        uint256 spendId,
        bytes data
    );

    // 交易事件
    event TransferEvent (
        address targetAddress, 
        uint256 amount, 
        uint256 spendId
    );

    /**
     * 初始化
     */
    constructor(address[] memory _owners, uint256 _threshold, uint256 _validBlockNumber) {
        initOwnerManager(_owners, _threshold, _validBlockNumber);
    }

    /**
     * 发起一笔转账
     */
    function initiateTransfer(address _ERC20Address, address _targetAddress, uint256 _amount, bytes memory _data) public onlyOwner {
        
        require(_ERC20Address != address(0x0), "ERC20Address");
        require(_targetAddress != address(0x0), "targetAddress");
        require(_amount > 0, "amount");
        require(_getBalance(_ERC20Address, address(this)) >= _amount, "Insufficient balance");

        uint256 id = incrementAndGetId();

        address[] memory assentients;
        spends[id] = Spend(msg.sender, _ERC20Address, _targetAddress, _amount, block.number + validBlockNumber, assentients, _data, SpendStatus.init);
        spends[id].assentients.push(msg.sender);
        emit InitiateTransferEvent(msg.sender, _ERC20Address, _targetAddress, _amount, block.number + validBlockNumber, id, _data);
        emit ApprovedEvent(msg.sender, id, _data);

        // 检查是否符合转账条件并执行
        _checkTransferAndExecute(id);
    }

    /**
     * 撤回一笔转账
     */
    function revocationTransfer(uint256 _spendId) public onlyOwner {
        Spend storage spend = spends[_spendId];
        require(spend.sponsor != address(0x0), "not exist");
        require(spend.sponsor == msg.sender, "insufficient permissions");
        require(spend.status == SpendStatus.init, "already accomplish");
        require(block.number <= spend.expiredBlock, "expired");

        delete spends[_spendId];
        emit RevocationTransfer(msg.sender, spend.ERC20Address, spend.targetAddress, spend.amount, _spendId);
    }

    /**
     * 确认转账
     */
    function approved(uint256 _spendId, address _targetAddress, address _ERC20Address, uint256 _amount, bytes memory _data) public onlyOwner {
        Spend storage spend = spends[_spendId];
        require(spend.sponsor != address(0x0), "not exist");
        require(block.number <= spend.expiredBlock, "expired");
        require(spend.targetAddress == _targetAddress, "targetAddress");
        require(spend.ERC20Address == _ERC20Address, "ERC20Address");
        require(spend.amount == _amount, "amount");
        require(!_checkApproved(spend.assentients), "already approved");
        require(spend.status == SpendStatus.init, "already accomplish");

        spend.assentients.push(msg.sender);
        emit ApprovedEvent(msg.sender, _spendId, _data);

        // 检查是否符合转账条件并执行
        _checkTransferAndExecute(_spendId);
    }

    /**
     * 获取转账信息
     */
    function getSpend(uint256 _spendId) public view onlyOwner returns(
            address sponsor,
            address ERC20Address,
            address targetAddress,
            uint256 amount,
            uint256 expiredBlock,
            address[] memory assentients,
            bytes memory data,
            SpendStatus status) {
        Spend storage spend = spends[_spendId];
        require(spend.sponsor != address(0x0), "id");
        return (spend.sponsor, spend.ERC20Address, spend.targetAddress, spend.amount, spend.expiredBlock, spend.assentients, spend.data, spend.status);
    }

    /**
     * 判断是否符合转账条件并执行
     */
    function _checkTransferAndExecute(uint256 _spendId) internal {
        Spend storage spend = spends[_spendId];
        if(_checkTransfer(spend)) {
            bool success = _ERC20Transfer(spend.ERC20Address, spend.targetAddress, spend.amount);
            require(success, "Abnormal transfer");
            spend.status = SpendStatus.pass;
            emit TransferEvent(spend.targetAddress, spend.amount, _spendId);
        }
    }

    /**
     * 判断是否符合转账条件
     */
    function _checkTransfer(Spend storage _spend) internal view returns(bool) {
        if(_spend.assentients.length >= threshold) {
            return true;
        }
        return false;
    } 

    /**
     * ERC20转账
     */
    function _ERC20Transfer(address _ERC20Address, address _to, uint256 _amount) internal returns(bool) {
        IERC20 erc20 = IERC20(_ERC20Address);
        bool success = erc20.transfer(_to, _amount);
        
        return success;
    } 

    /**
     * 查询指定ERC20的指定账户地址中的代币数量
     */
     function _getBalance(address _ERC20Address, address _addr) view private returns(uint256) {
         IERC20 erc20 = IERC20(_ERC20Address);
         uint256 balance = erc20.balanceOf(_addr);
         return balance;
     }


}