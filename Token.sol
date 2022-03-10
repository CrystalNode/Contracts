// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './utils/ERC20.sol';
import './utils/Ownable.sol';
import './utils/PoolOwnable.sol';

contract Prospect is ERC20, Ownable, PoolOwnable {
    mapping(address => bool) public _isBlacklisted;

    constructor() ERC20("Prospect", "PECT") {}

    function transfer(address to, uint256 amount) public override returns (bool) {       
        _transfer(msg.sender, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(!_isBlacklisted[from] && !_isBlacklisted[to],"Blacklisted address");
        super._transfer(from, to, amount);
    }

    function blacklist(address account, bool value) external onlyOwner {
        _isBlacklisted[account] = value;
    }

    function setPool(address pool) public onlyOwner {
        emit PoolOwnershipAdded(pool);
        _poolContracts[pool] = true;
    }

    function removePool(address pool) public onlyOwner {
        emit PoolOwnershipRevoked(pool);
        _poolContracts[pool] = false;
    }

    function mint(address account, uint256 amount) external onlyPool {
        require(account != address(0), "ERC20: mint to the zero address");
        _mint(account, amount);
    }


}