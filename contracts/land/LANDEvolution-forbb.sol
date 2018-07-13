pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721Token.sol";


// TODO:
contract LANDEvolution is ERC721Token("OASIS","EVL"), Ownable{

    uint256 constant clearLow = 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000;
    uint256 constant clearHigh = 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff;
    uint256 constant factor = 0x100000000000000000000000000000000;

    /*
     * EVENT
     */

    event LandTrasferred(int64 indexed x, int64 indexed y, address indexed from, address to);

    /*
     * FUNCTION
     */

    function assignNewLand(int64 x, int64 y, address beneficiary) external onlyOwner {
        _mint(beneficiary, _encodeTokenId(x, y));
    }

    function assignMultipleLands(int64[] x, int64[] y, address beneficiary) external onlyOwner {
        for (uint i = 0; i < x.length; i++) {
            _mint(beneficiary, _encodeTokenId(x[i], y[i]));
        }
    }

    // encode
    function _encodeTokenId(int64 x, int64 y) pure internal returns (uint result) {
        require(-90 < x && x < 90 && -90 < y && y < 90);
        return _unsafeEncodeTokenId(x, y);
    }
    function _unsafeEncodeTokenId(int64 x, int64 y) pure internal returns (uint) {
        return ((uint(x) * factor) & clearLow) | (uint(y) & clearHigh);
    }

    // decode
    function decodeTokenId(uint value) pure external returns (int[]) {
        return _decodeTokenId(value);
    }

    function _decodeTokenId(uint value) pure internal returns (int[] location) {
        int[] location = _unsafeDecodeTokenId(value);
        int x = location[0];
        int y = location[1];
        require(-90 < x && x < 90 && -90 < y && y < 90);
    }

    function _unsafeDecodeTokenId(uint value) pure internal returns (int[] location) {
        int x = expandNegative128BitCast((value & clearLow) >> 128);
        int y = expandNegative128BitCast(value & clearHigh);
        location.push(x);
        location.push(y);

    }

    function expandNegative128BitCast(uint value) pure internal returns (int) {
        if (value & (1<<127) != 0) {
            return int(value | clearLow);
        }
        return int(value);
    }

    function exists(int x, int y) view external returns (bool) {
        return super.exists(_encodeTokenId(x, y));
    }

    function ownerOfLand(int x, int y) view public returns (address) {
        return super.ownerOf(_encodeTokenId(x, y));
    }

    function ownerOfLandMany(int[] x, int[] y) view public returns (address[]) {
        require(x.length > 0);
        require(x.length == y.length);

        address[] memory addrs = new address[](x.length);
        for (uint i = 0; i < x.length; i++) {
            addrs[i] = ownerOfLand(x[i], y[i]);
        }
    }

    function landOf(address landholder) external view returns (int[], int[]) {
        require(landholder == msg.sender);
        uint256 length = balanceOf(landholder);
        int[] memory x = new int[](length);
        int[] memory y = new int[](length);

        int landX;
        int landY;
        for(uint i = 0; i < length; i++) {
            (landX, landY) = _decodeTokenId(ownedTokens[landholder][i]);
            x[i] = landX;
            y[i] = landY;
        }

        return (x, y);
    }


    function transferLand(int x, int y, address _to) external canTransfer(_encodeTokenId(x,y)) {
        uint256 _tokenId = _encodeTokenId(x,y);
        address _from = tokenOwner[_tokenId];
        require(_from != address(0));
        require(_to != address(0));

        clearApproval(_from, _tokenId);
        removeTokenFrom(_from, _tokenId);
        addTokenTo(_to, _tokenId);
        require(checkAndCallSafeTransfer(_from, _to, _tokenId, ""));

        emit LandTrasferred(x, y, _from, _to);
    }






}
