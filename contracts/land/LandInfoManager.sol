pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract LandInfoManager is Ownable {
    struct LandInfo {
        uint256 industryIndex;
        uint256[] objectIdKeys;
        uint256 lastUpdateTime;
    }

    mapping(uint256 => LandInfo) public tokenId2Infos;
}