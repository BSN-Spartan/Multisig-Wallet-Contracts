// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "../utils/ArrayForAddressUtils.sol";

contract OwnerManager { 

    // Proposal
    mapping(uint256 => Proposal) internal proposals;

    // Newest proposal ID
    uint256 internal newProposal;

    // The vote corresponding to the proposal
    mapping(uint256 => address[]) internal voters;

    // Wallet owner
    address[] internal owners;

    // The number of approved wallets
    uint256 internal threshold;

    // Valid block number
    uint256 internal validBlockNumber;

    // Self-increasing ID
    using Counters for Counters.Counter;
    Counters.Counter internal _tokenIdCounter;

    // Proposal structure
    struct Proposal {
        address sponsor;
        address owner; 
        uint256 temp;
        ManageFunctionType manageType;
        bytes data;
        uint256 expiredBlock;
        uint256 timestamp;
        ProposalStatus status;
    }

    // Create a proposal
    event CreateProposalEvent (
        address sponsor,
        address owner, 
        uint256 temp, 
        ManageFunctionType manageType,
        uint256 proposalId,
        uint256 expiredBlock,
        bytes data
    );

    // Vote
    event VoteEvent (
        address voter, 
        bool decision, 
        uint256 proposalId,
        bytes data
    );

    // Proposal result
    event ProposalResultEvent (
        uint256 proposalId,
        ProposalStatus status
    );

    // Enumeration of management function
    enum ManageFunctionType {
        AddOwner,
        DeleteOwner,
        ChangValidBlockNumber,
        ChangThreshold 
    }

    // Enumeration of proposal status
    enum ProposalStatus {
        init,
        pass
    }

    // Enumeration of transaction status
    enum SpendStatus {
        init,
        pass
    }

    function initOwnerManager(address[] memory _owners, uint256 _threshold, uint256 _validBlockNumber) internal {
        require(_owners.length != 0, "owners");
        require(_threshold > 0 && _threshold <= _owners.length, "threshold");
        require(_validBlockNumber > 0, "validBlockNumber");

        for (uint i = 0; i < _owners.length; i++) {
            if(_owners[i] == address(0x0)) {
                revert();
            }
            for (uint j = i + 1; j < _owners.length; j++) {
                if(_owners[i] == _owners[j]) {
                    revert();
                }
            }
            owners.push(_owners[i]);
        }

        threshold = _threshold;
        validBlockNumber = _validBlockNumber;
    }

    /**
     * @dev Create a proposal 
     * 
     * Requirements: 
     * - `` 
     * - `` 
     */
    function createProposal(ManageFunctionType _manageType, address _owner, uint256 _temp, bytes memory _data) public onlyOwner {
        
        // Check whether the proposal is in progress
        require(!_checkProposal(newProposal), "In progress");

        // Create a wallet owner, change the threshold number.
        if (_manageType == ManageFunctionType.AddOwner) {
            _addOwnerAndChangThresholdVerify(_owner, _temp);
            saveProposalAndEmit(_manageType, _owner, _temp, _data);
            return;
        }

        // Delete the wallet owner, change the threshold number.
        if (_manageType == ManageFunctionType.DeleteOwner) {
            _delOwnerAndChangThresholdVerify(_owner, _temp);
            saveProposalAndEmit(_manageType, _owner, _temp, _data);
            return;
        }

        // Change the valid block number
        if(_manageType == ManageFunctionType.ChangValidBlockNumber) {
            _changeValidBlockNumberVerify(_temp);
            saveProposalAndEmit(_manageType, _owner, _temp, _data);
            return;
        }

        // Change the threshold number
        if (_manageType == ManageFunctionType.ChangThreshold) {
            _changThresholdVerify(_temp);
            saveProposalAndEmit(_manageType, _owner, _temp, _data);
            return;
        }  

    }

    /**
     * Vote
     */
    function vote(uint256 _proposalId, bool _decision, bytes memory _data) public onlyOwner {
        
        // Check whether the proposal exists.
        require(_existsProposal(_proposalId), "Proposal does not exist");

        // Check whether the proposal is being voted.
        require(_checkProposal(_proposalId), "expired");

        // Check invalid votes.
        require(_checkVote(_proposalId, msg.sender, _decision),"Repeat voting");

        address[] storage _voters = voters[_proposalId];

        // Record approved votes.
        if(_decision) {
            _voters.push(msg.sender);
        } 
        // Delete approved votes.
        else {
            ArrayForAddressUtils.removeByValue(_voters, msg.sender);
        }

        emit VoteEvent(msg.sender, _decision, _proposalId, _data);

        // Check whether the proposal is approved and execute it.
        _checkProposalResultAndExecute(_proposalId);        
    }

    /**
     * Get the proposal information
     */
    function getProposal(uint256 _proposalId) public view onlyOwner returns(
        address sponsor,
        address owner,
        uint256 temp,
        ManageFunctionType manageType,
        bytes memory data,
        uint256 expiredBlock,
        ProposalStatus status
    ) {
        // Check whether the proposal exists.
        require(_existsProposal(_proposalId), "Proposal does not exist");
        Proposal memory proposal = proposals[_proposalId];
        return (proposal.sponsor, proposal.owner, proposal.temp, proposal.manageType, proposal.data, proposal.expiredBlock, proposal.status);
    }

    /**
     * Get the list of assentients of the proposal
     */
     function getProposalAssentients(uint256 _proposalId) public view onlyOwner returns(address[] memory assentients) {
         require(_existsProposal(_proposalId), "Proposal does not exist");
         return voters[_proposalId];
     }

    /**
      * Get the list of the wallet owners.
      */
    function getOwners() public view onlyOwner returns(address[] memory) {
        return owners;
    }

    /**
     * Get the threshold number
     */
    function getThreshold() public view onlyOwner returns(uint256) {
        return threshold;
    }

    /**
     * Get the valid block number
     */
    function getValidBlockNumber() public view onlyOwner returns(uint256) {
        return validBlockNumber;
    }

    /**
     * Check whether there is the list of owners in the specified address.
     */
    function existAddr(address _addr) public view onlyOwner returns(bool) {
        return existOwners(_addr);
    }

    /**
     * Check whether the proposal is approved and execute it.
     */
    function _checkProposalResultAndExecute(uint256 _proposalId) internal {

        address[] storage _voters = voters[_proposalId];

        // Check whether the proposal is approved.
        if(_voters.length >= threshold) {

            Proposal storage proposal = proposals[_proposalId];

            proposal.status = ProposalStatus.pass;

            emit ProposalResultEvent(_proposalId, ProposalStatus.pass);

            // Create a wallet owner, change the threshold number
            if (proposal.manageType == ManageFunctionType.AddOwner) {
                _addOwnerAndChangThreshold(proposal.owner, proposal.temp);
                return;
            }

            // Delete the wallet owner, change the threshold number.
            if (proposal.manageType == ManageFunctionType.DeleteOwner) {
                _delOwnerAndChangThreshold(proposal.owner, proposal.temp);
                return;
            }

            // Change the valid block number
            if(proposal.manageType == ManageFunctionType.ChangValidBlockNumber) {
                _changeValidBlockNumber(proposal.temp);
                return;
            }

            // Change the threshold number
            if (proposal.manageType == ManageFunctionType.ChangThreshold) {
                _changThreshold(proposal.temp);
                return;
            }
        }
    }

    /**
     * Check sender and _vote to see whether the vote is valid
     * Valid vote, the vote that may impact the result. For example: 1. Vote in favor of proposal in the first time; 2. Change the affirmative vote to negative vote
     * Invalid vote. For example: 1. Repeatedly negative votes on the proposal. 2. Repeatedly affirmative votes on the proposal
     */
    function _checkVote(uint256 _proposalId, address _sender, bool _decision) internal view returns(bool) {
        
        address[] storage _voters = voters[_proposalId];
        
        // Check whether the voter has already voted for approval
        bool _has = _hasVoted(_voters, _sender);
        if(_decision && _has) {
            return false;
        }

        // Check whether the voter has already voted for disapproval
        if(_decision == false && _has == false) {
            return false;
        }

        return true;
    }

    /**
     * Save the proposal information and emit an event
     */
    function saveProposalAndEmit(ManageFunctionType _manageType, address _owner, uint256 _temp, bytes memory _data) private {
        // Generate a unique ID and save the information
        uint256 id = incrementAndGetId();
        proposals[id] = Proposal(msg.sender, _owner, _temp, _manageType, _data, block.number + validBlockNumber, block.timestamp, ProposalStatus.init);
        newProposal = id;
        emit CreateProposalEvent(msg.sender, _owner, _temp, _manageType, id, block.number + validBlockNumber, _data);

        // The voter who initiates a proposal will vote for approval by default
        voters[id].push(msg.sender);
        emit VoteEvent(msg.sender, true, id, _data);

        // Check whether the proposal is approved and execute it
        _checkProposalResultAndExecute(id); 
    }

    /**
     * Create a wallet owner, change the threshold number verification
     */
    function _addOwnerAndChangThresholdVerify(address _owner, uint256 _threshold) internal view {
        require(_owner != address(0x0), "owner is null");
        require(!existOwners(_owner), "owner already exist");
        require(_owner != address(this), "owner");
        require(_threshold > 0 && _threshold <= owners.length + 1, "_threshold");
    }

    /**
     * Delete the wallet owner, change the threshold number verification
     */
    function _delOwnerAndChangThresholdVerify(address _owner, uint256 _threshold) internal view {
        require(existOwners(_owner), "owner not exist");
        require(_threshold > 0 && _threshold <= owners.length - 1, "_threshold");
    }

    /**
     * Verify the changed valid block number
     */
    function _changeValidBlockNumberVerify(uint256 _validBlockNumber) internal pure {
        require(_validBlockNumber > 0, "_validBlockNumber");
    }

    /**
     * Verify the changed threshold number
     */
    function _changThresholdVerify(uint256 _threshold) internal view {
        require(_threshold > 0 && _threshold <= owners.length, "_threshold");
    }

    /**
     * Create a wallet owner, change the threshold number
     */
    function _addOwnerAndChangThreshold(address _owner, uint256 _threshold) internal {
        owners.push(_owner);
        threshold = _threshold;
    }

    /**
     * Delete the wallet owner, change the threshold number
     */
    function _delOwnerAndChangThreshold(address _owner, uint256 _threshold) internal {
        ArrayForAddressUtils.removeByValue(owners, _owner);
        threshold = _threshold;
    }

    /**
     * Change the valid block number
     */
    function _changeValidBlockNumber(uint256 _validBlockNumber) internal {
        validBlockNumber = _validBlockNumber;
    }

    /**
     * Change the threshold number
     */
    function _changThreshold(uint256 _threshold) internal {
        threshold = _threshold;
    }

    /**
     * Check whether the sender is a wallet owner
     */
    modifier onlyOwner() {
        require(existOwners(msg.sender), "caller is not the owner");
        _;
    }

    /**
     * Check whether the user has been approved
     */
    function _checkApproved(address[] storage _assentients) internal view returns(bool) {
        for(uint i = 0; i < _assentients.length; i++) {
            if(_assentients[i] == msg.sender) {
                return true;
            }
        }
        return false;
    }

    /**
     * Check whether the address exists in the list of wallet owners
     */
    function existOwners(address _address) internal view returns(bool) {
        for (uint i = 0; i < owners.length; i++) {
            if(_address == owners[i]) {
                return true;
            }
        }
        return false;
    }

    /**
     * Get a unique ID and self-increasing
     */
    function incrementAndGetId() internal returns(uint256) {
        _tokenIdCounter.increment();
        uint256 id = _tokenIdCounter.current();
        return id;
    }

    /**
     * Check whether the proposal is in progress
     */
     function _checkProposal(uint256 _proposalId) internal view returns(bool) {
         Proposal memory proposal = proposals[_proposalId];
         return proposal.sponsor != address(0x0) && proposal.status == ProposalStatus.init && proposal.expiredBlock >= block.number;
     }

     /**
      * Check whether the proposal exists
      */
    function _existsProposal(uint256 _proposalId) internal view returns(bool) {
        Proposal memory proposal = proposals[_proposalId];
        if(proposal.sponsor != address(0x0)) {
            return true;
        }
        return false;
    }

    /**
     * Check if there is a valid vote
     */
    function _hasVoted(address[] memory _voters, address _sender) internal pure returns (bool) {
        for (uint256 i = 0; i < _voters.length; i++) {
            if (_voters[i] == _sender) {
                return true;
            }
        }
        return false;
    }

}