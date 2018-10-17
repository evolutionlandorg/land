pragma solidity ^0.4.24;

import "./interfaces/ILandBase.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "@evolutionland/common/contracts/interfaces/IObjectOwnership.sol";
import "@evolutionland/common/contracts/RBACWithAuth.sol";
import "@evolutionland/common/contracts/interfaces/ITokenLocation.sol";
import "@evolutionland/common/contracts/interfaces/ISettingsRegistry.sol";
import "@evolutionland/common/contracts/ObjectOwnership.sol";
import "@evolutionland/common/contracts/SettingIds.sol";
import "@evolutionland/common/contracts/LocationCoder.sol";

contract LandBase is RBACWithAuth, ILandBase, SettingIds {

    uint256 constant internal RESERVED = uint256(1);
    uint256 constant internal SPECIAL = uint256(2);
    uint256 constant internal HASBOX = uint256(4);

    uint256 constant internal CLEAR_RATE_HIGH = 0x000000000000000000000000000000000000000000000000000000000000ffff;

    struct LandAttr {
        uint256 resourceRateAttr;
        uint256 mask;
    }

    bool private singletonLock = false;

    ISettingsRegistry public registry;

    /**
     * @dev mapping from resource token address to resource atrribute rate id.
     * atrribute rate id starts from 1 to 16, NAN is 0.
     * goldrate is 1, woodrate is 2, waterrate is 3, firerate is 4, soilrate is 5
     */
    mapping (address => uint8) public resourceToken2RateAttrId;

    /**
     * @dev mapping from token id to land resource atrribute.
     */
    mapping (uint256 => LandAttr) public tokenId2LandAttr;

    // mapping from position in map to token id.
    mapping (uint256 => uint256) public locationId2TokenId;

    uint256 public lastLandObjectId;

    /*
     *  Modifiers
     */
    modifier singletonLockCall() {
        require(!singletonLock, "Only can call once");
        _;
        singletonLock = true;
    }

    modifier xAtlantisRangeLimit(int _x) {
        require(_x >= -112 && _x <= -68, "Invalid range.");
        _;
    }

    modifier yAtlantisRangeLimit(int _y) {
        require(_y >= -22 && _y <= 22, "Invalid range.");
        _;
    }

    /**
     * @dev Same with constructor, but is used and called by storage proxy as logic contract.
     */
    function initializeContract(address _registry) public singletonLockCall {
        // Ownable constructor
        addRole(msg.sender, ROLE_ADMIN);
        addRole(msg.sender, ROLE_AUTH_CONTROLLER);
        registry = ISettingsRegistry(_registry);

         // update attributes.
        resourceToken2RateAttrId[registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN)] = 1;
        resourceToken2RateAttrId[registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN)] = 2;
        resourceToken2RateAttrId[registry.addressOf(CONTRACT_WATER_ERC20_TOKEN)] = 3;
        resourceToken2RateAttrId[registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN)] = 4;
        resourceToken2RateAttrId[registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN)] = 5;
    }

    /*
     * @dev assign new land
     */
    function assignNewLand(
        int _x, int _y, address _beneficiary, uint256 _resourceRateAttr, uint256 _mask
        ) public isAuth xAtlantisRangeLimit(_x) yAtlantisRangeLimit(_y) returns (uint _tokenId) {

        // auto increase object id, start from 1
        lastLandObjectId += 1;
        require(lastLandObjectId <= 340282366920938463463374607431768211455, "Can not be stored with 128 bits.");

        _tokenId = IObjectOwnership(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).mintObject(_beneficiary, uint128(lastLandObjectId));

        // update locations.
        uint256 locationId = LocationCoder.encodeLocationIdHM(_x, _y);
        require(locationId2TokenId[locationId] == 0, "Land in this position already been mint.");
        locationId2TokenId[locationId] = _tokenId;
        ITokenLocation(registry.addressOf(CONTRACT_TOKEN_LOCATION)).setTokenLocationHM(_tokenId, _x, _y);

        tokenId2LandAttr[_tokenId].resourceRateAttr = _resourceRateAttr;
        tokenId2LandAttr[_tokenId].mask = _mask;
    }

    function assignMultipleLands(
        int[] _xs, int[] _ys, address _beneficiary, uint256[] _resourceRateAttrs, uint256[] _masks
        ) public isAuth returns (uint[]){
        require(_xs.length == _ys.length, "Length of xs didn't match length of ys");
        require(_xs.length == _resourceRateAttrs.length, "Length of postions didn't match length of land attributes");
        require(_xs.length == _masks.length, "Length of masks didn't match length of ys");

        uint[] memory _tokenIds = new uint[](_xs.length);

        for (uint i = 0; i < _xs.length; i++) {
            _tokenIds[i] = assignNewLand(_xs[i], _ys[i], _beneficiary, _resourceRateAttrs[i], _masks[i]);
        }

        return _tokenIds;
    }

    function defineResouceTokenRateAttrId(address _resourceToken, uint8 _attrId) public isAuth {
        require(_attrId > 0 && _attrId <= 16, "Invalid Attr Id.");

        resourceToken2RateAttrId[_resourceToken] = _attrId;
    }

    // encode (x,y) to get tokenId
    function getTokenIdByLocation(int _x, int _y) public view returns (uint256) {
        uint locationId = LocationCoder.encodeLocationIdHM(_x, _y);
        return locationId2TokenId[locationId];
    }

    function exists(int _x, int _y) public view returns (bool) {
        uint locationId = LocationCoder.encodeLocationIdHM(_x, _y);
        uint tokenId = locationId2TokenId[locationId];
        return ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).exists(tokenId);
    }

    function ownerOfLand(int _x, int _y) public view returns (address) {
        uint locationId = LocationCoder.encodeLocationIdHM(_x, _y);
        uint tokenId = locationId2TokenId[locationId];
        return ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(tokenId);
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
        address objectOwnership = registry.addressOf(CONTRACT_OBJECT_OWNERSHIP);
        uint256 length = ERC721(objectOwnership).balanceOf(_landholder);
        int[] memory x = new int[](length);
        int[] memory y = new int[](length);

        ITokenLocation tokenLocation = ITokenLocation(registry.addressOf(CONTRACT_TOKEN_LOCATION));

        for(uint i = 0; i < length; i++) {
            uint tokenId = ERC721(objectOwnership).tokenOfOwnerByIndex(_landholder, i);
            (x[i], y[i]) = tokenLocation.getTokenLocationHM(tokenId);
        }

        return (x, y);
    }

    function isHasBox(uint256 _landTokenID) public view returns (bool) {
        return (tokenId2LandAttr[_landTokenID].mask & HASBOX) != 0;
    }

    function isReserved(uint256 _landTokenID) public view returns (bool) {
        return (tokenId2LandAttr[_landTokenID].mask & RESERVED) != 0;
    }

    function isSpecial(uint256 _landTokenID) public view returns (bool) {
        return (tokenId2LandAttr[_landTokenID].mask & SPECIAL) != 0;
    }

    function setHasBox(uint _landTokenID, bool _isHasBox) public isAuth {
        if (_isHasBox) {
            tokenId2LandAttr[_landTokenID].mask |= HASBOX;
        } else {
            tokenId2LandAttr[_landTokenID].mask &= ~HASBOX;
        }

        emit HasboxSetted(_landTokenID, _isHasBox);
    }

    function getResourceRateAttr(uint _landTokenId) public view returns (uint256) {
        return tokenId2LandAttr[_landTokenId].resourceRateAttr;
    }

    function setResourceRateAttr(uint _landTokenId, uint256 _newResourceRateAttr) public isAuth {
        tokenId2LandAttr[_landTokenId].resourceRateAttr = _newResourceRateAttr;
    }

    function getResourceRate(uint _landTokenId, address _resourceToken) public view returns (uint16) {
        require(resourceToken2RateAttrId[_resourceToken] > 0, "Reource token doesn't exist.");

        uint moveRight = (16 * (resourceToken2RateAttrId[_resourceToken] - 1));
        return uint16((tokenId2LandAttr[_landTokenId].resourceRateAttr >> moveRight) & CLEAR_RATE_HIGH);
    }

    function setResourceRate(uint _landTokenId, address _resourceToken, uint16 _newResouceRate) public isAuth {
        require(resourceToken2RateAttrId[_resourceToken] > 0, "Reource token doesn't exist.");
        uint moveLeft = 16 * (resourceToken2RateAttrId[_resourceToken] - 1);
        tokenId2LandAttr[_landTokenId].resourceRateAttr &= (~(CLEAR_RATE_HIGH << moveLeft));
        tokenId2LandAttr[_landTokenId].resourceRateAttr |= (uint256(_newResouceRate) << moveLeft);
        emit ModifiedResourceRate(_landTokenId, _resourceToken, _newResouceRate);
    }
}
