// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./OwnerManager.sol";

contract MultisigWallet is OwnerManager {

    // Transaction
    mapping(uint256 => Spend) internal spends;

    // Transaction structure
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

    // Initiating a transfer transaction
    event InitiateTransferEvent (
        address sponsor, 
        address ERC20Address,
        address targetAddress,
        uint256 amount,
        uint256 expiredBlock,
        uint256 spendId,
        bytes data
    );

    // Revoke a transfer
    event RevocationTransfer (
        address sponsor, 
        address ERC20Address,
        address targetAddress,
        uint256 amount,
        uint256 spendId
    );

    // Approve for a transaction
    event ApprovedEvent (
        address assentient, 
        uint256 spendId,
        bytes data
    );

    // Transfer transaction
    event TransferEvent (
        address targetAddress, 
        uint256 amount, 
        uint256 spendId
    );

    /**
     * Initialization
     */
    constructor(address[] memory _owners, uint256 _threshold, uint256 _validBlockNumber) {
        initOwnerManager(_owners, _threshold, _validBlockNumber);
    }

    /**
     * Initiate a transfer transaction
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

        // Check if the transfer transaction meets the requirement and execute it.
        _checkTransferAndExecute(id);
    }

    /**
     * Revoke a transfer transaction
     */
    function revokeTransfer(uint256 _spendId) public onlyOwner {
        Spend storage spend = spends[_spendId];
        require(spend.sponsor != address(0x0), "not exist");
        require(spend.sponsor == msg.sender, "insufficient permissions");
        require(spend.status == SpendStatus.init, "already accomplish");
        require(block.number <= spend.expiredBlock, "expired");

        delete spends[_spendId];
        emit RevocationTransfer(msg.sender, spend.ERC20Address, spend.targetAddress, spend.amount, _spendId);
    }

    /**
     * Approve for the transfer transaction
     */
    function approve(uint256 _spendId, address _targetAddress, address _ERC20Address, uint256 _amount, bytes memory _data) public onlyOwner {
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

        // Check whether the transfer transaction meets the requirement and execute it.
        _checkTransferAndExecute(_spendId);
    }

    /**
     * Get the transfer information
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
     * Check whether the transfer transaction meets the requirement and execute it.
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
     * Check whether the transfer transaction meets the requirement.
     */
    function _checkTransfer(Spend storage _spend) internal view returns(bool) {
        if(_spend.assentients.length >= threshold) {
            return true;
        }
        return false;
    } 

    /**
     * ERC20 transfer
     */
    function _ERC20Transfer(address _ERC20Address, address _to, uint256 _amount) internal returns(bool) {
        IERC20 erc20 = IERC20(_ERC20Address);
        bool success = erc20.transfer(_to, _amount);
        
        return success;
    } 

    /**
     * Get the amount of ERC20 tokens in the specified wallet address
     */
     function _getBalance(address _ERC20Address, address _addr) view private returns(uint256) {
         IERC20 erc20 = IERC20(_ERC20Address);
         uint256 balance = erc20.balanceOf(_addr);
         return balance;
     }


}