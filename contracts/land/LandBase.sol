pragma solidity ^0.4.24;

import "@evolutionland/common/contracts/RBACWithAdmin.sol";
import "@evolutionland/common/contracts/interfaces/ILandData.sol";
import "@evolutionland/common/contracts/interfaces/ITokenLocation.sol";
import "@evolutionland/common/contracts/interfaces/IInterstellarEncoder.sol";
import "@evolutionland/common/contracts/interfaces/ISettingsRegistry.sol";
import "@evolutionland/common/contracts/TokenOwnership.sol";
import "@evolutionland/common/contracts/SettingIds.sol";

contract LandBase is RBACWithAdmin, ILandData, SettingIds {

    // event land attributions modification
    event Modified(uint indexed tokenId, uint rightAt, uint leftAt, uint newValue);

    // event batch modify resources
    event BatchModified(uint indexed tokenId, uint goldRate, uint woodRate, uint waterRate, uint fireRate, uint soilRate);

    ISettingsRegistry public registry;

    ITokenLocation public tokenLocation;

    TokenOwnership public tokenOwership;

    /**
     * @dev mapping from token id to land resource atrribute.
     * LandResourceAttr contains attibutes of Land asset, and is encoded in type of uint256
     * consider LandResourceAttr a binary array with the index starting at 0.
     * the rightmost one is the 0th element and the leftmost one is 255th element.
     * from the right to the left:
     * LandResourceAttr[0,15] : goldrate
     * LandResourceAttr[16,31] : woodrate
     * LandResourceAttr[32,47] : waterrate
     * LandResourceAttr[48,63] : firerate
     * LandResourceAttr[64,79] : soilrate
     * LandResourceAttr[80,95] : flag // 1:reserved, 2:special 3:hasBox
     * LandResourceAttr[96,255] : not open yet
    */
    mapping (uint256 => uint256) public tokenId2Attributes;

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
    function assignNewLand(int _x, int _y, address beneficiary, uint256 _landAttribute) public onlyAdmin 
        xAtlantisRangeLimit(_x) yAtlantisRangeLimit(_y) returns (uint _tokenId) {
        // auto increase token id, start from 1

        lastTokenId += 1;
        require(lastTokenId <= 340282366920938463463374607431768211455, "Can not be stored with 128 bits.");

        address interstellarEncoder = registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER);
        require(interstellarEncoder != address(0), "Contract Interstellar Encoder does not exist.");
        _tokenId = IInterstellarEncoder(interstellarEncoder).encodeTokenId(
            address(this), uint8(IInterstellarEncoder.ObjectClass.LAND), uint128(lastTokenId));

        require(_landAttribute != 0, "Land Attribute can not be zero");
        require(!tokenLocation.hasLocation(_tokenId), "Land already have location.");
        
        tokenLocation.setTokenLocation(_tokenId, _x, _y);
        uint256 locationId = tokenLocation.encodeLocationId(_x, _y);
        require(locationId2TokenId[locationId] == 0, "Land in this position already been mint.");
        locationId2TokenId[locationId] = _tokenId;

        tokenId2Attributes[_tokenId] = _landAttribute;

        tokenOwership.mint(beneficiary, _tokenId);
    }

    function assignMultipleLands(int[] _xs, int[] _ys, address _beneficiary, uint256[] _landAttributes) public onlyAdmin returns (uint[]){
        require(_xs.length == _ys.length, "Length of xs didn't match length of ys");
        require(_xs.length == _landAttributes.length, "Length of postions didn't match length of land attributes");

        uint[] memory _tokenIds = new uint[](_xs.length);

        for (uint i = 0; i < _xs.length; i++) {
            _tokenIds[i] = assignNewLand(_xs[i], _ys[i], _beneficiary, _landAttributes[i]);
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

    function batchModifyResources(
        uint _tokenId, uint _goldRate, uint _woodRate, uint _waterRate, uint _fireRate, uint _soilRate) public onlyAdmin {
        uint landInfo = tokenId2Attributes[_tokenId];
        uint afterGoldModified = _getModifyInfoFromAttributes(landInfo, 0, 15, _goldRate);
        uint afterWoodModified = _getModifyInfoFromAttributes(afterGoldModified, 16, 31, _woodRate);
        uint afterWaterModified = _getModifyInfoFromAttributes(afterWoodModified, 32, 47, _waterRate);
        uint afterFireModified = _getModifyInfoFromAttributes(afterWaterModified, 48, 63, _fireRate);
        uint afterSoilModified = _getModifyInfoFromAttributes(afterFireModified, 64, 79, _soilRate);

        tokenId2Attributes[_tokenId] = afterSoilModified;

        emit BatchModified(_tokenId, _goldRate, _woodRate, _waterRate, _fireRate, _soilRate);
    }

    function modifyAttributes(uint _tokenId, uint _right, uint _left, uint _newValue) public onlyAdmin {
        uint landInfo = tokenId2Attributes[_tokenId];
        uint newValue = _getModifyInfoFromAttributes(landInfo, _right, _left, _newValue);
        tokenId2Attributes[_tokenId] = newValue;
        emit Modified(_tokenId, _right, _left, _newValue);
    }

    function hasBox(uint256 _tokenId) public view returns (bool) {
        uint landInfo = tokenId2Attributes[_tokenId];
        uint flag = getInfoFromAttributes(landInfo, 80, 95);
        return (flag == 3);
    }

    function isReserved(uint256 _tokenId) public view returns (bool) {
        uint landInfo = tokenId2Attributes[_tokenId];
        uint flag = getInfoFromAttributes(landInfo, 80, 95);
        return (flag == 1);
    }

    function isSpecial(uint256 _tokenId) public view returns (bool) {
        uint landInfo = tokenId2Attributes[_tokenId];
        uint flag = getInfoFromAttributes(landInfo, 80, 95);
        return (flag == 2);
    }

    // get every attribute from landInfo of certain tokenId(land pixel)
    function getDetailsFromLandInfo(uint _tokenId)
    public
    view
    returns (
        uint goldRate,
        uint woodRate,
        uint waterRate,
        uint fireRate,
        uint soilRate,
        uint flag) {
        uint landInfo = tokenId2Attributes[_tokenId];
        goldRate = getInfoFromAttributes(landInfo, 0, 15);
        woodRate = getInfoFromAttributes(landInfo, 16, 31);
        waterRate = getInfoFromAttributes(landInfo, 32, 47);
        fireRate = getInfoFromAttributes(landInfo, 48, 63);
        soilRate = getInfoFromAttributes(landInfo, 64, 79);
        flag = getInfoFromAttributes(landInfo, 80, 95);
    }


    function _getModifyInfoFromAttributes(uint256 _attributes, uint _rightAt, uint _leftAt, uint _value) internal pure returns (uint) {
        uint rightReserve = (_attributes << (256 - _rightAt)) >> (256 - _rightAt);
        uint emptyTarget = (_attributes >> _leftAt) << _leftAt;
        uint newValue = _value << _rightAt;
        return (emptyTarget + newValue + rightReserve);
    }


    /**
    * @dev get specific snippet of info from _flag
    * @param _attributes - LandPixel.flag
    * @param _rightAt - where the snippet start from the right
    * @param _leftAt - where the snippet end to the left
    * for example, uint(000...010100), because of the index starting at 0.
    * the '101' part's _rightAt is 2, and _leftAt is 4.
    */
    function getInfoFromAttributes(uint256 _attributes, uint _rightAt, uint _leftAt) public pure returns (uint) {
        uint leftShift = _attributes << (255 - _leftAt);
        uint rightShift = leftShift >> (_rightAt + 255 - _leftAt);
        return rightShift;
    }

}
