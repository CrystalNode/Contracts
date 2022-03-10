// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './utils/Ownable.sol';
import './utils/HelperOwnable.sol';

interface IToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external returns (uint256);
    function mint(address account, uint256 amount) external;
}

contract Pool is Ownable, HelperOwnable {
    IToken public token;

    constructor(address _token) {
        token = IToken(_token);
    }

    function pay(address _to, uint _amount) external onlyHelper {
        if(token.balanceOf(address(this)) >= _amount) {
            token.transfer(_to, _amount);
        }
        else {
            token.mint(_to, _amount);
        }
    }

    function transferHelperOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit HelperOwnershipTransferred(_helperContract, newOwner);
        _helperContract = newOwner;
    }

}
