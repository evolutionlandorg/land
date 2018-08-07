pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./LandBase.sol";

contract LandData is Ownable, LandBase{

    struct LandPixel {
        int x;  // position on the x-axis
        int y;  // position on the y-axis
        int z;  // position on the z-axis
        uint64 goldRate; // maximum of gold's generation per pixel and per day
        uint64 woodRate;
        uint64 waterRate;
        uint64 fireRate;
        uint64 soilRate;
        bool isReserved; // is this land reserved. it means not for sale.
    }

    mapping(uint256 => LandPixel) tokenId2LandPixel;

    function addLandPixel(
        int _x,
        int _y,
        int _z,
        uint64 _goldRate,
        uint64 _woodRate,
        uint64 _waterRate,
        uint64 _fireRate,
        uint64 _soilRate,
        bool _isReserved)
    public onlyOwner {
        LandPixel memory landPixel = LandPixel(_x,_y,_z,_goldRate,_woodRate,_waterRate,_fireRate,_soilRate,_isReserved);

        // TODO: move encode token id outside of the contract
        uint tokenId = _encodeTokenId(_x,_y);
        tokenId2LandPixel[tokenId] = landPixel;
    }

    function getPixelResources(int _x, int _y) public view returns (uint64,uint64,uint64,uint64,uint64,bool) {
        uint256 tokenId = _encodeTokenId(_x, _y);
        LandPixel storage landPixel = tokenId2LandPixel[tokenId];
        return (landPixel.goldRate,
                landPixel.woodRate,
                landPixel.waterRate,
                landPixel.fireRate,
                landPixel.soilRate,
                landPixel.isReserved);
    }

}
