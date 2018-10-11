pragma solidity ^0.4.23;

contract LandBase {

    uint256 constant CLEAR_LOW = 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000;
    uint256 constant CLEAR_HIGH = 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff;
    uint256 constant FACTOR = 0x100000000000000000000000000000000;

    // tokenId => encode(x,y)
    mapping (uint256 => uint256) public tokenId2positionId;
    //encode(x,y) => tokenId
    mapping (uint256 => uint256) public positionId2tokenId;

    // encode

    function encodePositionId(int _x, int _y) pure public returns (uint result) {
        return _encodePositionId(_x, _y);
    }

    function _encodePositionId(int _x, int _y) pure internal returns (uint result) {
        return _unsafeEncodeTokenId(_x, _y) + 1;
    }
    function _unsafeEncodeTokenId(int _x, int _y) pure internal returns (uint) {
        return ((uint(_x) * FACTOR) & CLEAR_LOW) | (uint(_y) & CLEAR_HIGH);
    }

    function decodePositionId(uint _positionId) pure public returns (int, int) {
        return _decodePositionId(_positionId);
    }
    function _decodePositionId(uint _positionId) pure internal returns (int x, int y) {
        require(_positionId > 0, "Position Id is start from 1, should larger than zero");
        (x, y) = _unsafeDecodePositionId(_positionId - 1);
    }

    function _unsafeDecodePositionId(uint _value) pure internal returns (int x, int y) {
        x = expandNegative128BitCast((_value & CLEAR_LOW) >> 128);
        y = expandNegative128BitCast(_value & CLEAR_HIGH);
    }

    function expandNegative128BitCast(uint _value) pure internal returns (int) {
        if (_value & (1<<127) != 0) {
            return int(_value | CLEAR_LOW);
        }
        return int(_value);
    }

}
