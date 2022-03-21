pragma solidity ^0.4.24;

contract LandBaseAuthority {

    constructor(address[] _whitelists) public {
        for (uint i = 0; i < _whitelists.length; i ++) {
            whiteList[_whitelists[i]] = true;
        }
    }

    mapping (address => bool) public whiteList;

    function canCall(
        address _src, address /*_dst*/, bytes4 _sig
    ) public view returns (bool) {
        return ( whiteList[_src] && _sig == bytes4(keccak256("setResourceRateAttr(uint256,uint256)")) ) ||
               ( whiteList[_src] && _sig == bytes4(keccak256("setResourceRate(uint256,address,uint16)")) ) ||
               ( whiteList[_src] && _sig == bytes4(keccak256("setHasBox(uint256,bool)"))) ||
                ( whiteList[_src] && _sig == bytes4(keccak256("assignNewLand(int256,int256,address,uint256,uint256)")));
    }
}
