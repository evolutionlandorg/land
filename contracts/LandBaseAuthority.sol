pragma solidity ^0.4.24;

import "@evolutionland/common/contracts/interfaces/IAuthority.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract LandBaseAuthority is Ownable, IAuthority {

    mapping (address => bool) public whiteList;

    function setWhitelist(address _address, bool _flag) public onlyOwner {
        whiteList[_address] = _flag;
    }

    function canCall(
        address _src, address _dst, bytes4 _sig
    ) public view returns (bool) {
        return ( whiteList[_src] && _sig == bytes4(keccak256("setResourceRateAttr(uint256,uint256)")) ) ||
               ( whiteList[_src] && _sig == bytes4(keccak256("setResourceRate(uint256,address,uint16)")) ) ||
               ( whiteList[_src] && _sig == bytes4(keccak256("setHasBox(uint256,bool)")));
    }
}