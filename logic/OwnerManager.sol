// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "../utils/ArrayForAddressUtils.sol";

contract OwnerManager { 

    // 提案
    mapping(uint256 => Proposal) internal proposals;

    // 最新的提案标识
    uint256 internal newProposal;

    // 提案对应的投票
    mapping(uint256 => address[]) internal voters;

    // 钱包拥有者
    address[] internal owners;

    // 通过的数量
    uint256 internal threshold;

    // 过期的块数量
    uint256 internal validBlockNumber;

    // 自增唯一标识
    using Counters for Counters.Counter;
    Counters.Counter internal _tokenIdCounter;

    // 提案结构体
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

    // 创建提案事件
    event CreateProposalEvent (
        address sponsor,
        address owner, 
        uint256 temp, 
        ManageFunctionType manageType,
        uint256 proposalId,
        uint256 expiredBlock,
        bytes data
    );

    // 投票事件
    event VoteEvent (
        address voter, 
        bool decision, 
        uint256 proposalId,
        bytes data
    );

    // 提案结果事件
    event ProposalResultEvent (
        uint256 proposalId,
        ProposalStatus status
    );

    // 管理方法枚举
    enum ManageFunctionType {
        AddOwner,
        DeleteOwner,
        ChangValidBlockNumber,
        ChangThreshold 
    }

    // 提案状态枚举
    enum ProposalStatus {
        init,
        pass
    }

    // 交易状态枚举
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
     * @dev 创建提案 
     * 
     * Requirements: 
     * - `` 
     * - `` 
     */
    function createProposal(ManageFunctionType _manageType, address _owner, uint256 _temp, bytes memory _data) public onlyOwner {
        
        // 当前是否有提案在进行中
        require(!_checkProposal(newProposal), "underway");

        // 增加拥有者 修改通过的数量
        if (_manageType == ManageFunctionType.AddOwner) {
            _addOwnerAndChangThresholdVerify(_owner, _temp);
            saveProposalAndEmit(_manageType, _owner, _temp, _data);
            return;
        }

        // 删除拥有者 修改通过的数量
        if (_manageType == ManageFunctionType.DeleteOwner) {
            _delOwnerAndChangThresholdVerify(_owner, _temp);
            saveProposalAndEmit(_manageType, _owner, _temp, _data);
            return;
        }

        // 修改过期的块
        if(_manageType == ManageFunctionType.ChangValidBlockNumber) {
            _changeValidBlockNumberVerify(_temp);
            saveProposalAndEmit(_manageType, _owner, _temp, _data);
            return;
        }

        // 修改通过的数量
        if (_manageType == ManageFunctionType.ChangThreshold) {
            _changThresholdVerify(_temp);
            saveProposalAndEmit(_manageType, _owner, _temp, _data);
            return;
        }  

    }

    /**
     * 投票
     */
    function vote(uint256 _proposalId, bool _decision, bytes memory _data) public onlyOwner {
        
        // 检查提案是否存在
        require(_existsProposal(_proposalId), "proposal not exist");

        // 检查提案是否正在进行中
        require(_checkProposal(_proposalId), "expired");

        // 检查无效投票
        require(_checkVote(_proposalId, msg.sender, _decision),"Repeat voting");

        address[] storage _voters = voters[_proposalId];

        // 记录赞成投票
        if(_decision) {
            _voters.push(msg.sender);
        } 
        // 删除赞成投票
        else {
            ArrayForAddressUtils.removeByValue(_voters, msg.sender);
        }

        emit VoteEvent(msg.sender, _decision, _proposalId, _data);

        // 检查提案是否通过并执行
        _checkProposalResultAndExecute(_proposalId);        
    }

    /**
     * 获取提案信息
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
        // 检查提案是否存在
        require(_existsProposal(_proposalId), "proposal not exist");
        Proposal memory proposal = proposals[_proposalId];
        return (proposal.sponsor, proposal.owner, proposal.temp, proposal.manageType, proposal.data, proposal.expiredBlock, proposal.status);
    }

    /**
     * 获取提案赞成者列表
     */
     function getProposalAssentients(uint256 _proposalId) public view onlyOwner returns(address[] memory assentients) {
         require(_existsProposal(_proposalId), "proposal not exist");
         return voters[_proposalId];
     }

    /**
      * 查询钱包拥有者列表
      */
    function getOwners() public view onlyOwner returns(address[] memory) {
        return owners;
    }

    /**
     * 查询通过的数量
     */
    function getThreshold() public view onlyOwner returns(uint256) {
        return threshold;
    }

    /**
     * 查询转账有效期(块)
     */
    function getValidBlockNumber() public view onlyOwner returns(uint256) {
        return validBlockNumber;
    }

    /**
     * 查询账户地址是否存在拥有者列表
     */
    function existAddr(address _addr) public view onlyOwner returns(bool) {
        return existOwners(_addr);
    }

    /**
     * 检查提案是否通过并执行
     */
    function _checkProposalResultAndExecute(uint256 _proposalId) internal {

        address[] storage _voters = voters[_proposalId];

        // 判断提案是否通过
        if(_voters.length >= threshold) {

            Proposal storage proposal = proposals[_proposalId];

            proposal.status = ProposalStatus.pass;

            emit ProposalResultEvent(_proposalId, ProposalStatus.pass);

            // 增加拥有者 修改通过的数量
            if (proposal.manageType == ManageFunctionType.AddOwner) {
                _addOwnerAndChangThreshold(proposal.owner, proposal.temp);
                return;
            }

            // 删除拥有者 修改通过的数量
            if (proposal.manageType == ManageFunctionType.DeleteOwner) {
                _delOwnerAndChangThreshold(proposal.owner, proposal.temp);
                return;
            }

            // 修改过期的块
            if(proposal.manageType == ManageFunctionType.ChangValidBlockNumber) {
                _changeValidBlockNumber(proposal.temp);
                return;
            }

            // 修改通过的数量
            if (proposal.manageType == ManageFunctionType.ChangThreshold) {
                _changThreshold(proposal.temp);
                return;
            }
        }
    }

    /**
     * 检查sender和_vote, 判断该投票是否为有效投票
     * 有效投票, 是指可能改变投票结果的投票，例如：1. 首次投了赞成票；2. 将已经投的赞成票改为反对
     * 无效投票, 例如：1. 重复投了反对票(默认反对票)；2. 重复投赞成票
     */
    function _checkVote(uint256 _proposalId, address _sender, bool _decision) internal view returns(bool) {
        
        address[] storage _voters = voters[_proposalId];
        
        // 检查重复投赞成票
        bool _has = _hasVoted(_voters, _sender);
        if(_decision && _has) {
            return false;
        }

        // 检查重复投了反对票
        if(_decision == false && _has == false) {
            return false;
        }

        return true;
    }

    /**
     * 保存提案信息并触发事件
     */
    function saveProposalAndEmit(ManageFunctionType _manageType, address _owner, uint256 _temp, bytes memory _data) private {
        // 生成唯一标识并保存信息
        uint256 id = incrementAndGetId();
        proposals[id] = Proposal(msg.sender, _owner, _temp, _manageType, _data, block.number + validBlockNumber, block.timestamp, ProposalStatus.init);
        newProposal = id;
        emit CreateProposalEvent(msg.sender, _owner, _temp, _manageType, id, block.number + validBlockNumber, _data);

        // 发起提案默认投赞成
        voters[id].push(msg.sender);
        emit VoteEvent(msg.sender, true, id, _data);

        // 检查提案是否通过并执行
        _checkProposalResultAndExecute(id); 
    }

    /**
     * 增加拥有者并修改通过数量入参校验
     */
    function _addOwnerAndChangThresholdVerify(address _owner, uint256 _threshold) internal view {
        require(_owner != address(0x0), "owner is null");
        require(!existOwners(_owner), "owner already exist");
        require(_owner != address(this), "owner");
        require(_threshold > 0 && _threshold <= owners.length + 1, "_threshold");
    }

    /**
     * 删除拥有者并修改通过数量入参校验
     */
    function _delOwnerAndChangThresholdVerify(address _owner, uint256 _threshold) internal view {
        require(existOwners(_owner), "owner not exist");
        require(_threshold > 0 && _threshold <= owners.length - 1, "_threshold");
    }

    /**
     * 修改过期的块入参校验
     */
    function _changeValidBlockNumberVerify(uint256 _validBlockNumber) internal pure {
        require(_validBlockNumber > 0, "_validBlockNumber");
    }

    /**
     * 修改通过的数量入参校验
     */
    function _changThresholdVerify(uint256 _threshold) internal view {
        require(_threshold > 0 && _threshold <= owners.length, "_threshold");
    }

    /**
     * 增加拥有者并修改通过数量
     */
    function _addOwnerAndChangThreshold(address _owner, uint256 _threshold) internal {
        owners.push(_owner);
        threshold = _threshold;
    }

    /**
     * 删除拥有者并修改通过数量
     */
    function _delOwnerAndChangThreshold(address _owner, uint256 _threshold) internal {
        ArrayForAddressUtils.removeByValue(owners, _owner);
        threshold = _threshold;
    }

    /**
     * 修改过期的块
     */
    function _changeValidBlockNumber(uint256 _validBlockNumber) internal {
        validBlockNumber = _validBlockNumber;
    }

    /**
     * 修改通过的数量
     */
    function _changThreshold(uint256 _threshold) internal {
        threshold = _threshold;
    }

    /**
     * 判断sender是不是钱包拥有者
     */
    modifier onlyOwner() {
        require(existOwners(msg.sender), "caller is not the owner");
        _;
    }

    /**
     * 判断当前用户是否已经确认转账过了
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
     * 查询地址存不存在于拥有者列表
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
     * 获取一个唯一标识并自增
     */
    function incrementAndGetId() internal returns(uint256) {
        uint256 id = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        return id;
    }

    /**
     * 检查提案是否在进行中
     */
     function _checkProposal(uint256 _proposalId) internal view returns(bool) {
         Proposal memory proposal = proposals[_proposalId];
         return proposal.sponsor != address(0x0) && proposal.status == ProposalStatus.init && proposal.expiredBlock >= block.number;
     }

     /**
      * 判断提案存不存在
      */
    function _existsProposal(uint256 _proposalId) internal view returns(bool) {
        Proposal memory proposal = proposals[_proposalId];
        if(proposal.sponsor != address(0x0)) {
            return true;
        }
        return false;
    }

    /**
     * 检查是否存在有效投票
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