// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './interface/IManager.sol';
import './library/Address.sol';
import './interface/IERC721Metadata.sol';
import './interface/IERC721Receiver.sol';
import './utils/Ownable.sol';
import './utils/HelperOwnable.sol';
import './utils/WeigthOwnable.sol';

contract Manager is IERC721, IERC721Metadata, Ownable, HelperOwnable, IManager {
    using Address for address;

    struct Crystal {
        uint id;
        string name;
        uint64 mintTimestamp;
        uint64 claimTimestamp;
        uint8 tier;
        uint compounded;
        uint64 bonusReward;
    }

    mapping(address => uint) public _balances;
    mapping(uint => address) public _owners;
    mapping(uint => Crystal) public _nodes;
    mapping(address => uint[]) public _nodeIndexes;

    mapping(uint8 => uint64) public _baseRewardPercentByTier;
    uint public precisionReward = 10**8;

    mapping(uint8 => uint64) public _bonusRewardPercentPerTimelapseByTier;
    mapping(uint8 => uint64) public _maxBonusRewardPercentPerTimelapseByTier;

    uint8 tierCount;

    mapping(uint => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint64 public claimTimelapse = 86400;

    string public defaultUri;
    string public defaultUriExt;

    uint private nodeCounter = 1;

    constructor (string memory _defaultUri, string memory _defaultUriExt, uint64[] memory baseRewardPercentByTier,
    uint64[] memory bonusRewardPercentPerTimelapseByTier, uint64[] memory maxBonusRewardPercentPerTimelapseByTier){

        require(baseRewardPercentByTier.length == bonusRewardPercentPerTimelapseByTier.length &&
        baseRewardPercentByTier.length == maxBonusRewardPercentPerTimelapseByTier.length, "Tier arrays length not matching");

        defaultUri = _defaultUri;
        defaultUriExt = _defaultUriExt;
        
        for (uint8 i = 0; i < baseRewardPercentByTier.length; i++){
            _baseRewardPercentByTier[i + 1] = baseRewardPercentByTier[i];
        }
        for (uint8 i = 0; i < bonusRewardPercentPerTimelapseByTier.length; i++){
            _bonusRewardPercentPerTimelapseByTier[i + 1] = bonusRewardPercentPerTimelapseByTier[i];
        }
        for (uint8 i = 0; i < maxBonusRewardPercentPerTimelapseByTier.length; i++){
            _maxBonusRewardPercentPerTimelapseByTier[i + 1] = maxBonusRewardPercentPerTimelapseByTier[i];
        }
        tierCount = uint8(baseRewardPercentByTier.length);
    }

    function name() external override pure returns (string memory) {
        return "Crystal";
    }

    function symbol() external override pure returns (string memory) {
        return "CRSTL";
    }

    modifier onlyIfExists(uint _id) {
        require(_exists(_id), "ERC721: operator query for nonexistent token");
        _;
    }

    function createNode(address account, string memory nodeName, uint8 tier, uint paidAmount) onlyHelper override external {
        uint nodeId = nodeCounter;
        nodeCounter += 1;

        _createNode(nodeId, nodeName, uint64(block.timestamp), uint64(block.timestamp), tier, paidAmount, 0, account);
    }

    function getRewardsNode(Crystal memory node) internal view returns (uint) {
        return (node.compounded * (_baseRewardPercentByTier[node.tier] + node.bonusReward) * (block.timestamp - node.claimTimestamp))
         / precisionReward / claimTimelapse;
    }

    function claim(address account, uint id) external onlyIfExists(id) onlyHelper override returns (uint) {
        require(ownerOf(id) == account, "MANAGER: account not the owner");
        Crystal storage node = _nodes[id];

        uint rewardNode = getRewardsNode(node);

        if(rewardNode > 0) {
            node.claimTimestamp = uint64(block.timestamp);
            return rewardNode;
        } else {
            return 0;
        }
    }

    function claimAndCompound(address account, uint id) external onlyIfExists(id) onlyHelper override {
        require(ownerOf(id) == account, "MANAGER: account not the owner");
        Crystal storage node = _nodes[id];

        uint rewardNode = getRewardsNode(node);

        if(rewardNode > 0) {
            compoundNode(node, rewardNode);
        }
    }

    function compoundNode(Crystal storage node, uint rewardNode) internal {

        if(node.bonusReward < _maxBonusRewardPercentPerTimelapseByTier[node.tier]){
            node.bonusReward = node.bonusReward + (uint64(block.timestamp) - node.claimTimestamp) * _bonusRewardPercentPerTimelapseByTier[node.tier] / claimTimelapse;
            if(node.bonusReward > _maxBonusRewardPercentPerTimelapseByTier[node.tier])
                node.bonusReward = _maxBonusRewardPercentPerTimelapseByTier[node.tier];
        }

        node.claimTimestamp = uint64(block.timestamp);
        node.compounded = node.compounded + rewardNode;
    }

    function stake(address account, uint id, uint amountToStake) external onlyIfExists(id) onlyHelper override {
        require(ownerOf(id) == account, "MANAGER: account not the owner");
        claimAndCompoundInternal(id);
        Crystal storage node = _nodes[id];
        node.compounded = node.compounded + amountToStake;
    }

    function claimAll(address account) external onlyHelper override returns (uint) {
        uint rewards = 0;
        for (uint i = 0; i < _nodeIndexes[account].length; i++) {
            rewards += claimInternal(_nodeIndexes[account][i]);
        }
        return rewards;
    }

    function claimAndCompoundAll(address account) external onlyHelper override {
        for (uint i = 0; i < _nodeIndexes[account].length; i++) {
            claimAndCompoundInternal(_nodeIndexes[account][i]);
        }
    }

    function claimInternal(uint id) internal returns (uint) {
        Crystal storage node = _nodes[id];

        uint rewardNode = getRewardsNode(node);

        node.claimTimestamp = uint64(block.timestamp);
        return rewardNode;
    }
    
    function claimAndCompoundInternal(uint id) internal {
        Crystal storage node = _nodes[id];

        uint rewardNode = getRewardsNode(node);

        if(rewardNode > 0) {
            compoundNode(node, rewardNode);
        }
    }

    function adminCreateNode(address account, string memory nodeName, uint8 tier, uint paidAmount) onlyOwner external {
        uint nodeId = nodeCounter;
        nodeCounter += 1;
        _createNode(nodeId, nodeName, uint64(block.timestamp), uint64(block.timestamp), tier, paidAmount, 0, account);
    }

    function transferHelperOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit HelperOwnershipTransferred(_helperContract, newOwner);
        _helperContract = newOwner;
    }

    function totalSupply() view external returns (uint) {
        return nodeCounter;
    }

    function getNodesByAccount(address account) public view returns (Crystal [] memory){
        Crystal[] memory Crystals = new Crystal[](_nodeIndexes[account].length);

        for (uint i = 0; i < _nodeIndexes[account].length; i++) {
            uint nodeId = _nodeIndexes[account][i];
            Crystals[i] = _nodes[nodeId];
        }
        return Crystals;
    }

    function getNode(uint _id) public view onlyIfExists(_id) returns (Crystal memory) {
        return _nodes[_id];
    }

    function balanceOf(address owner) public override view returns (uint balance){
        require(owner != address(0), "ERC721: balance query for the zero address");
        return _balances[owner];
    }

    function ownerOf(uint tokenId) public override view onlyIfExists(tokenId) returns (address owner) {
        address theOwner = _owners[tokenId];
        return theOwner;
    }

    function getNodesOf(address _account) public view returns (uint[] memory) {
        return _nodeIndexes[_account];
    }

    function tokenURI(uint tokenId) external override view returns (string memory) {
        return string(abi.encodePacked(defaultUri, uint2str(_nodes[tokenId].tier), defaultUriExt));
    }

    function setDefaultTokenUri(string memory uri) external onlyOwner {
        defaultUri = uri;
    }
    function setDefaultTokenUriExt(string memory uri) external onlyOwner {
        defaultUriExt = uri;
    }

    function _deleteNode(uint _id) onlyOwner external {
        address owner = ownerOf(_id);
        _balances[owner] -= 1;
        delete _owners[_id];
        delete _nodes[_id];
        _remove(_id, owner); 
    }

    function _deleteMultipleNode(uint[] calldata _ids) onlyOwner external {
        for (uint i = 0; i < _ids.length; i++) {
            uint _id = _ids[i];
            address owner = ownerOf(_id);
            _balances[owner] -= 1;
            delete _owners[_id];
            delete _nodes[_id];
            _remove(_id, owner);
        }
    }

    function _createNode(uint _id, string memory _name, uint64 _mint, uint64 _claim, uint8 _tier, uint _compounded, uint16 _bonusReward, address _to) internal {
        require(!_exists(_id), "MANAGER: Crystal already exist");
        require(_tier <= tierCount && _tier != 0, "MANAGER: Tier isn't valid");

        _nodes[_id] = Crystal({
            id: _id,
            name: _name,
            mintTimestamp: _mint,
            claimTimestamp: _claim,
            tier: _tier,
            compounded: _compounded,
            bonusReward: _bonusReward
        });
        _owners[_id] = _to;
        _balances[_to] += 1;
        _nodeIndexes[_to].push(_id);

        emit Transfer(address(0), _to, _id);
    }

    function _remove(uint _id, address _account) internal {
        uint[] storage _ownerNodes = _nodeIndexes[_account];
        uint length = _ownerNodes.length;

        uint _index = length;
        
        for (uint i = 0; i < length; i++) {
            if(_ownerNodes[i] == _id) {
                _index = i;
            }
        }
        if (_index >= _ownerNodes.length) return;
        
        _ownerNodes[_index] = _ownerNodes[length - 1];
        _ownerNodes.pop();
    }

    function renameNode(uint id, string memory newName) external {
        require(ownerOf(id) == msg.sender, "MANAGER: You are not the owner");
        Crystal storage crystal = _nodes[id];
        crystal.name = newName;
    }

    function safeTransferFrom(address from, address to, uint tokenId ) external override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function transferFrom(address from, address to,uint tokenId) external override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _transfer(from, to, tokenId);
    }

    function approve(address to, uint tokenId) external override {
        address owner = ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    function getApproved(uint tokenId) public override view onlyIfExists(tokenId) returns (address operator){
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool _approved) external override {
        _setApprovalForAll(_msgSender(), operator, _approved);
    }

    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function safeTransferFrom(address from, address to, uint tokenId, bytes memory _data) public override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(from, to, tokenId, _data);
    }

    function supportsInterface(bytes4 interfaceId) external override pure returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId;
    }

    function _transfer(
        address from,
        address to,
        uint tokenId
    ) internal {
        require(ownerOf(tokenId) == from, "ERC721: transfer from incorrect owner");
        require(to != address(0), "ERC721: transfer to the zero address");

        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        _nodeIndexes[to].push(tokenId);
        _remove(tokenId, from);

        emit Transfer(from, to, tokenId);
    }

    function _approve(address to, uint tokenId) internal {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint tokenId) internal view onlyIfExists(tokenId) returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _exists(uint tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _safeTransfer(address from, address to, uint tokenId, bytes memory _data) internal {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal {
        require(owner != operator, "ERC721: approve to caller");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    function _checkOnERC721Received(address from, address to, uint tokenId, bytes memory _data) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    function _burn(uint tokenId) internal virtual {
        address owner = ownerOf(tokenId);
        _approve(address(0), tokenId);
        _balances[owner] -= 1;
        delete _owners[tokenId];
        delete _nodes[tokenId];
        _remove(tokenId, owner);
        emit Transfer(owner, address(0), tokenId);
    }

    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}