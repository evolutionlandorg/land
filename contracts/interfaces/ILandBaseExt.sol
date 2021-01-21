pragma solidity ^0.4.24;

interface ILandBaseExt {
    function getResourceRate(uint _landTokenId, address _resouceToken) external view returns (uint16);
    function resourceToken2RateAttrId(address _resourceToken) external view returns (uint256);
}
