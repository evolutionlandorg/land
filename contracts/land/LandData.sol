pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./LandBase.sol";

contract LandData is Ownable, LandBase {

    struct LandPixel {
        int64 x;  // position on the x-axis
        int64 y;  // position on the y-axis
        int64 z;  // position on the z-axis
        uint64 goldRate; // maximum of gold's generation per pixel and per day
        uint64 woodRate;
        uint64 waterRate;
        uint64 fireRate;
        uint64 soilRate;
        // consider flag a binary array with the index starting at 0.
        // the rightmost one is the 0th element and the leftmost one is 255th element.
        // from the right to the left:
        // flag[0] - is this land reserved. 1 for reserved and 0 for not reserved.
        // flag[1] - is the land special. special here means that you can not buy it with RING or KTON

        uint256 flag;
    }

    mapping(uint256 => LandPixel) tokenId2LandPixel;

    function addLandPixel(
        int64 _x,
        int64 _y,
        int64 _z,
        uint64 _goldRate,
        uint64 _woodRate,
        uint64 _waterRate,
        uint64 _fireRate,
        uint64 _soilRate,
        uint256 _flag)
    public onlyOwner {
        LandPixel memory landPixel = LandPixel(_x,_y,_z,_goldRate,_woodRate,_waterRate,_fireRate,_soilRate,_flag);

        // TODO: move encode token id outside of the contract
        uint tokenId = _encodeTokenId(_x,_y);
        tokenId2LandPixel[tokenId] = landPixel;
    }

    function getPixelInfoWithPosition(int64 _x, int64 _y)
    public
    view
    returns (uint64,uint64,uint64,uint64,uint64,uint256) {
        uint256 tokenId = _encodeTokenId(_x, _y);
        LandPixel storage landPixel = tokenId2LandPixel[tokenId];
        return (landPixel.goldRate,
                landPixel.woodRate,
                landPixel.waterRate,
                landPixel.fireRate,
                landPixel.soilRate,
                landPixel.flag);
    }

    function getPixelInfoWithTokenId(uint256 _tokenId)
    public
    view
    returns (int64,int64,int64,uint64,uint64,uint64,uint64,uint64,uint256) {
        LandPixel storage landPixel = tokenId2LandPixel[_tokenId];
        return (
            landPixel.x,
            landPixel.y,
            landPixel.z,
            landPixel.goldRate,
            landPixel.woodRate,
            landPixel.waterRate,
            landPixel.fireRate,
            landPixel.soilRate,
            landPixel.flag);
    }

    /**
    * @dev get specific snippet of info from _flag
    * @param _flag - LandPixel.flag
    * @param _rightAt - where the snippet start from the right
    * @param _leftAt - where the snippet end to the left
    * for example, uint(000...010100), because of the index starting at 0.
    * the '101' part's _rightAt is 2, and _leftAt is 4.
    */
    function getInfoFromFlag(uint256 _flag, uint _rightAt, uint _leftAt) public returns (uint) {
        uint leftShift = _flag << (255 - _leftAt);
        uint rightShift = leftShift >> (_rightAt + 255 - _leftAt);
        return rightShift;
    }

    function isReserved(uint256 _tokenId) public returns (bool) {
        LandPixel storage landPixel = tokenId2LandPixel[_tokenId];
        uint flag = landPixel.flag;
        return (getInfoFromFlag(flag,0,0) == 1);
    }

    function isSpecial(uint256 _tokenId) public returns (bool) {
        LandPixel storage landPixel = tokenId2LandPixel[_tokenId];
        uint flag = landPixel.flag;
        return (getInfoFromFlag(flag,1,1) == 1);
    }

}
