pragma solidity ^0.4.24;

import "./interfaces/ILandBase.sol";
import "@evolutionland/common/contracts/RBACWithAdmin.sol";
import "@evolutionland/common/contracts/interfaces/ITokenLocation.sol";
import "@evolutionland/common/contracts/interfaces/IInterstellarEncoder.sol";
import "@evolutionland/common/contracts/interfaces/ISettingsRegistry.sol";
import "@evolutionland/common/contracts/TokenOwnership.sol";
import "@evolutionland/common/contracts/SettingIds.sol";

contract LandBase is RBACWithAdmin, ILandBase, SettingIds {

    uint256 constant internal RESERVED = uint256(1);

    uint256 constant internal SPECIAL = uint256(2);

    uint256 constant internal HASBOX = uint256(4);

    ISettingsRegistry public registry;

    ITokenLocation public tokenLocation;

    TokenOwnership public tokenOwership;

    struct LandAttr {
        // goldrate, woodrate, waterrate, firerate, soilrate
        mapping(address => uint16) fungibleResouceRate;
        uint256 mask;
    }

    /**
     * @dev mapping from token id to land resource atrribute.
     */
    mapping (uint256 => LandAttr) public tokenId2LandAttr;

    // mapping from position in map to token id.
    mapping (uint256 => uint256) public locationId2TokenId;

    mapping (uint256 => uint256) public industryIndex;

    mapping (uint256 => uint256) public lastUpdateTime;

    uint256 public lastTokenId;

    modifier xAtlantisRangeLimit(int _x) {
        require( _x >= -112 &&  _x <= -68);
        _;
    }

    modifier yAtlantisRangeLimit(int _y) {
        require(_y >= -22 && _y <= 22);
        _;
    }

    /*
     * @dev assign new land
     */
    function assignNewLand(
        int _x, int _y, address _beneficiary, uint16 _goldRate, uint16 _woodRate, uint16 _waterRate, uint16 _fireRate, uint16 _soilRate, uint256 _mask
        ) public onlyAdmin xAtlantisRangeLimit(_x) yAtlantisRangeLimit(_y) returns (uint _tokenId) {
        // auto increase token id, start from 1
        lastTokenId += 1;
        require(lastTokenId <= 340282366920938463463374607431768211455, "Can not be stored with 128 bits.");

        address interstellarEncoder = registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER);
        require(interstellarEncoder != address(0), "Contract Interstellar Encoder does not exist.");
        _tokenId = IInterstellarEncoder(interstellarEncoder).encodeTokenId(
            address(this), uint8(IInterstellarEncoder.ObjectClass.LAND), uint128(lastTokenId));

        require(!tokenLocation.hasLocation(_tokenId), "Land already have location.");
        
        tokenLocation.setTokenLocation(_tokenId, _x, _y);
        uint256 locationId = tokenLocation.encodeLocationId(_x, _y);
        require(locationId2TokenId[locationId] == 0, "Land in this position already been mint.");
        locationId2TokenId[locationId] = _tokenId;

        tokenId2LandAttr[_tokenId].fungibleResouceRate[registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN)] = _goldRate;
        tokenId2LandAttr[_tokenId].fungibleResouceRate[registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN)] = _woodRate;
        tokenId2LandAttr[_tokenId].fungibleResouceRate[registry.addressOf(CONTRACT_WATER_ERC20_TOKEN)] = _waterRate;
        tokenId2LandAttr[_tokenId].fungibleResouceRate[registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN)] = _fireRate;
        tokenId2LandAttr[_tokenId].fungibleResouceRate[registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN)] = _soilRate;

        tokenId2LandAttr[_tokenId].mask = _mask;

        tokenOwership.mint(_beneficiary, _tokenId);
    }

    function assignMultipleLands(
        int[] _xs, int[] _ys, address _beneficiary, uint16[] _goldRates, uint16[] _woodRates, uint16[] _waterRates, uint16[] _fireRates, uint16[] _soilRates, uint256[] _masks
        ) public onlyAdmin returns (uint[]){
        require(_xs.length == _ys.length, "Length of xs didn't match length of ys");
        require(
            _xs.length == _goldRates.length && _xs.length == _woodRates.length 
            && _xs.length == _waterRates.length && _xs.length == _fireRates.length && _xs.length == _soilRates.length, 
            "Length of postions didn't match length of land attributes");

        require(_xs.length == _masks.length, "Length of masks didn't match length of ys");

        uint[] memory _tokenIds = new uint[](_xs.length);

        for (uint i = 0; i < _xs.length; i++) {
            _tokenIds[i] = assignNewLand(
                _xs[i], _ys[i], _beneficiary, _goldRates[i], _woodRates[i], _waterRates[i], _fireRates[i], _soilRates[i], _masks[i]
                );
        }

        return _tokenIds;
    }

        // encode (x,y) to get tokenId
    function getTokenIdByLocation(int _x, int _y) public view returns (uint256) {
        uint locationId = tokenLocation.encodeLocationId(_x, _y);
        return locationId2TokenId[locationId];
    }

    function exists(int _x, int _y) public view returns (bool) {
        uint locationId = tokenLocation.encodeLocationId(_x, _y);
        uint tokenId = locationId2TokenId[locationId];
        return tokenOwership.exists(tokenId);
    }

    function ownerOfLand(int _x, int _y) public view returns (address) {
        uint locationId = tokenLocation.encodeLocationId(_x, _y);
        uint tokenId = locationId2TokenId[locationId];
        return tokenOwership.ownerOf(tokenId);
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
        uint256 length = tokenOwership.balanceOf(_landholder);
        int[] memory x = new int[](length);
        int[] memory y = new int[](length);

        for(uint i = 0; i < length; i++) {
            uint tokenId = tokenOwership.tokenOfOwnerByIndex(_landholder, i);
            (x[i], y[i]) = tokenLocation.getTokenLocation(tokenId);
        }

        return (x, y);
    }

    function modifyResourceRate(uint _landTokenID, address _resourceToken, uint16 _newResouceRate) public onlyAdmin {
        tokenId2LandAttr[_landTokenID].fungibleResouceRate[_resourceToken] = _newResouceRate;

        // TODO: emit event
    }

    function setHasBox(uint _landTokenID, bool isHasBox) public onlyAdmin {
        if (isHasBox) {
            tokenId2LandAttr[_landTokenID].mask |= HASBOX;
        } else {
            tokenId2LandAttr[_landTokenID].mask &= ~HASBOX;
        }
        
        // TODO: emit event
    }

    function hasBox(uint256 _landTokenID) public view returns (bool) {
        return (tokenId2LandAttr[_landTokenID].mask & HASBOX) != 0;
    }

    function isReserved(uint256 _landTokenID) public view returns (bool) {
        return (tokenId2LandAttr[_landTokenID].mask & RESERVED) != 0;
    }

    function isSpecial(uint256 _landTokenID) public view returns (bool) {
        return (tokenId2LandAttr[_landTokenID].mask & SPECIAL) != 0;
    }

    function getResourceRate(uint _landTokenId, address _resourceToken) public view returns (uint16) {
        return tokenId2LandAttr[_landTokenId].fungibleResouceRate[_resourceToken];
    }
}
