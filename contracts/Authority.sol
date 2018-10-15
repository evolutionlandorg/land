pragma solidity ^0.4.24;

import "@evolutionland/common/contracts/interfaces/IAuthority.sol";

contract Authority is IAuthority {
    address public landBase;

    constructor(address _landBase) public
    {
        landBase = _landBase;
    }

    function canCall(
        address _src, address _dst, bytes4 _sig
    ) public view returns (bool) {
        return ( _src == landBase && _sig == bytes4(keccak256("mintObject(address,uint128)")) ) ||
            ( _src == landBase && _sig == bytes4(keccak256("burnObject(address,uint128)")) ) ||
            ( _src == landBase && _sig == bytes4(keccak256("setTokenLocation(uint256,int256,int256)")));
    }
}