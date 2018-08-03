pragma solidity ^0.4.23;

contract LANDbase {

    uint256 constant clearLow = 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000;
    uint256 constant clearHigh = 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff;
    uint256 constant factor = 0x100000000000000000000000000000000;

    // encode
    function _encodeTokenId(int x, int y) pure internal returns (uint result) {
        require(-90 < x && x < 90 && -90 < y && y < 90);
        return _unsafeEncodeTokenId(x, y);
    }
    function _unsafeEncodeTokenId(int x, int y) pure internal returns (uint) {
        return ((uint(x) * factor) & clearLow) | (uint(y) & clearHigh);
    }

    function _decodeTokenId(uint value) pure internal returns (int x, int y) {
        (x, y) = _unsafeDecodeTokenId(value);
        require(-90 < x && x < 90 && -90 < y && y < 90);
    }

    function _unsafeDecodeTokenId(uint value) pure internal returns (int x, int y) {
        x = expandNegative128BitCast((value & clearLow) >> 128);
        y = expandNegative128BitCast(value & clearHigh);
    }

    function expandNegative128BitCast(uint value) pure internal returns (int) {
        if (value & (1<<127) != 0) {
            return int(value | clearLow);
        }
        return int(value);
    }

}
