pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721Token.sol";
import "./LandBase.sol";

contract Atlantis is ERC721Token("Atlantis Land","OASIS"), Ownable, LandBase {

    modifier xRangeLimit(int _x) {
        require( _x >= -112 &&  _x <= -68);
        _;
    }

    modifier yRangeLimit(int _y) {
        require(_y >= -22 && _y <= 22);
        _;
    }

    /**
     * @dev Guarantees msg.sender is owner of the given token
     * @param _tokenId uint256 ID of the token to validate its ownership belongs to msg.sender
     */
    modifier onlyOwnerOf(uint256 _tokenId) {
        require(ownerOf(_tokenId) == msg.sender);
        _;
    }

    /*
     * @dev assign new land
     */
    function assignNewLand(int _x, int _y, address beneficiary) public onlyOwner xRangeLimit(_x) yRangeLimit(_y) returns (uint tokenId) {
        // auto increase token id, start from 1
        tokenId = totalSupply() + 1;

        uint positionId = _encodePositionId(_x, _y);
        require(positionId2tokenId[positionId] == 0, "Land in this position already been mint.");

        tokenId2positionId[_tokenId] = positionId;
        positionId2tokenId[positionId] = _tokenId;

        // TODO add event.
        _mint(beneficiary, _tokenId);
    }

    function assignMultipleLands(int[] _xs, int[] _ys, address _beneficiary) public onlyOwner returns (uint[]) {
        require(_xs.length == _ys.length, "assignMultipleLands failed because length of xs didnt match length of ys");

        int[] memory tokenIds = new int[](_xs.length);

        for (uint i = 0; i < _xs.length; i++) {
            tokenIds[i] = assignNewLand(_xs[i], _ys[i], _beneficiary);
        }
        return tokenIds;
    }

    // encode (x,y) to get tokenId
    function getLocationTokenId(int _x, int _y) public view returns (uint256) {
        uint positionId = _encodePositionId(_x, _y);
        return positionId2tokenId[positionId];
    }

    // decode tokenId to get (x,y)
    function getTokenLocation(uint _tokenId) public view returns (int, int) {
        uint positionId = tokenId2positionId[_tokenId];
        return _decodePositionId(positionId);
    }

    function exists(int _x, int _y) public view returns (bool) {
        uint positionId = _encodePositionId(_x, _y);
        uint tokenId = positionId2tokenId[positionId];
        return super.exists(tokenId);
    }

    function ownerOfLand(int _x, int _y) public view returns (address) {
        uint positionId = _encodePositionId(_x, _y);
        uint tokenId = positionId2tokenId[positionId];
        return super.ownerOf(tokenId);
    }

    function ownerOfLandMany(int[] _xs, int[] _ys) public view returns (address[]) {
        require(_xs.length > 0);
        require(_xs.length == _ys.length);

        address[] memory addrs = new address[](_xs.length);
        for (uint i = 0; i < _xs.length; i++) {
            addrs[i] = ownerOfLand(_xs[i], _ys[i]);
        }
    }

    function landOf(address _landholder) public view returns (int[], int[]) {
        require(_landholder == msg.sender);
        uint256 length = balanceOf(_landholder);
        int[] memory x = new int[](length);
        int[] memory y = new int[](length);

        int landX;
        int landY;
        for(uint i = 0; i < length; i++) {
            uint tokenId = ownedTokens[_landholder][i];
            uint positionId = tokenId2positionId[tokenId];
            (landX, landY) = _decodePositionId(positionId);
            x[i] = landX;
            y[i] = landY;
        }

        return (x, y);
    }

    function indexOfLand(uint _tokenId) public view returns (uint index) {
        index = allTokensIndex[_tokenId];
    }

    //@dev user invoke approveAndCall to create auction
    //@param _to - address of auction contractß
    function approveAndCall(
        address _to,
        uint _tokenId,
        bytes _extraData
    ) public onlyOwnerOf(_tokenId) {
        // set _to to the auction contract
        approve(_to, _tokenId);
        if(!_to.call(bytes4(keccak256("receiveApproval(address,uint256,bytes)")),
            abi.encode(msg.sender, _tokenId, _extraData))) {
            revert();
        }

    }

}
