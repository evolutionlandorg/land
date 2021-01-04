// Root file: contracts/MysteriousTreasureAuthority.sol

pragma solidity ^0.4.24;

contract MysteriousTreasureAuthority {

    constructor(address[] _whitelists) public {
        for (uint i = 0; i < _whitelists.length; i ++) {
            whiteList[_whitelists[i]] = true;
        }
    }

    mapping (address => bool) public whiteList;

    function canCall(
        address _src, address _dst, bytes4 _sig
    ) public view returns (bool) {
        return whiteList[_src];
    }
}