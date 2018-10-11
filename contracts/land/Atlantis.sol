pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721Token.sol";
import "@evolutionland/common/contracts/interfaces/ITokenLocation.sol";

contract Atlantis is ERC721Token("Atlantis Land","OASIS"), Ownable, ITokenLocation {
    
    // mapping from position in map to token id.
    mapping (uint256 => uint256) public locationId2TokenId;

    // token id => encode(x,y) postiion in map
    mapping (uint256 => uint256) public tokenId2LocationId;

    uint256 public lastTokenId;

    bool private singletonLock = false;

    /*
     *  Modifiers
     */
    modifier singletonLockCall() {
        require(!singletonLock, "Only can call once");
        _;
        singletonLock = true;
    }

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

        /**
     * @dev Atlantis's constructor 
     */
    constructor () public {
        // initializeContract();
    }

    /**
     * @dev Same with constructor, but is used and called by storage proxy as logic contract.
     */
    function initializeContract() public singletonLockCall {
        // Ownable constructor
        owner = msg.sender;

        // SupportsInterfaceWithLookup constructor
        _registerInterface(InterfaceId_ERC165);

        // ERC721BasicToken constructor
        _registerInterface(InterfaceId_ERC721);
        _registerInterface(InterfaceId_ERC721Exists);

        // ERC721Token constructor
        name_ = "Atlantis Land";
        symbol_ = "OASIS";
        // register the supported interfaces to conform to ERC721 via ERC165
        _registerInterface(InterfaceId_ERC721Enumerable);
        _registerInterface(InterfaceId_ERC721Metadata);
    }

    /*
     * @dev assign new land
     */
    function assignNewLand(int _x, int _y, address beneficiary) public onlyOwner xRangeLimit(_x) yRangeLimit(_y) returns (uint _tokenId) {
        // auto increase token id, start from 1
        _tokenId = lastTokenId + 1;

        uint locationId = encodeLocationId(_x, _y);
        require(locationId2TokenId[locationId] == 0, "Land in this position already been mint.");

        tokenId2LocationId[_tokenId] = locationId;
        locationId2TokenId[locationId] = _tokenId;

        _mint(beneficiary, _tokenId);
    }

    function assignMultipleLands(int[] _xs, int[] _ys, address _beneficiary) public onlyOwner returns (uint[]){
        require(_xs.length == _ys.length, "assignMultipleLands failed because length of xs didnt match length of ys");

        uint[] memory _tokenIds = new uint[](_xs.length);

        for (uint i = 0; i < _xs.length; i++) {
            _tokenIds[i] = assignNewLand(_xs[i], _ys[i], _beneficiary);
        }
        return _tokenIds;
    }

    // decode tokenId to get (x,y)
    function getTokenLocation(uint _tokenId) public view returns (int, int) {
        uint locationId = tokenId2LocationId[_tokenId];
        return decodeLocationId(locationId);
    }

    // encode (x,y) to get tokenId
    function getTokenIdByLocation(int _x, int _y) public view returns (uint256) {
        uint locationId = encodeLocationId(_x, _y);
        return locationId2TokenId[locationId];
    }

    function exists(int _x, int _y) public view returns (bool) {
        uint locationId = encodeLocationId(_x, _y);
        uint tokenId = locationId2TokenId[locationId];
        return super.exists(tokenId);
    }

    function ownerOfLand(int _x, int _y) public view returns (address) {
        uint locationId = encodeLocationId(_x, _y);
        uint tokenId = locationId2TokenId[locationId];
        return super.ownerOf(tokenId);
    }

    function ownerOfLandMany(int[] _xs, int[] _ys) public view returns (address[]) {
        require(_xs.length > 0);
        require(_xs.length == _ys.length);

        address[] memory addrs = new address[](_xs.length);
        for (uint i = 0; i < _xs.length; i++) {
            addrs[i] = ownerOfLand(_xs[i], _ys[i]);
        }

        return addrs;
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
            uint locationId = tokenId2LocationId[tokenId];
            (landX, landY) = decodeLocationId(locationId);
            x[i] = landX;
            y[i] = landY;
        }

        return (x, y);
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
