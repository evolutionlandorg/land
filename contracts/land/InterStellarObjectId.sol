pragma solidity ^0.4.24;

contract InterstellarObjectId {

    // todo using hash as key for indexing.
    struct ObjectId {
        uint256 a;
        uint256 b;
        uint256 c;
    }

    mapping (bytes32 => ObjectId) objectIdIndex;

    // TODO: Fix the warnings.
    function keyOfObjectId(uint256 _a, uint256 _b, uint256 _c) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_a, _b, _c));
    }

    function getObjectId(bytes32 _key) public view returns (uint256 a, uint256 b, uint256 c) {
        require(exists(_key));
        a = objectIdIndex[_key].a;
        b = objectIdIndex[_key].b;
        c = objectIdIndex[_key].c;
    }

    function exists(bytes32 _key) public view returns (bool) {
        return !(objectIdIndex[_key].a == 0 && objectIdIndex[_key].b == 0 && objectIdIndex[_key].c == 0);
    }

    function storeObjectId(uint256 _a, uint256 _b, uint256 _c) public {
        bytes32 key = keyOfObjectId(_a, _b, _c);
        objectIdIndex[key].a = _a;
        objectIdIndex[key].b = _b;
        objectIdIndex[key].b = _b;
    }
}