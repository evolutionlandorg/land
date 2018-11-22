pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "@evolutionland/common/contracts/interfaces/IMintableERC20.sol";
import "@evolutionland/common/contracts/interfaces/ISettingsRegistry.sol";
import "@evolutionland/common/contracts/DSAuth.sol";
import "@evolutionland/common/contracts/SettingIds.sol";
import "@evolutionland/common/contracts/interfaces/IInterstellarEncoder.sol";
import "@evolutionland/common/contracts/interfaces/ITokenUse.sol";
import "@evolutionland/common/contracts/interfaces/IActivity.sol";
import "./interfaces/ILandBase.sol";
import "./LandSettingIds.sol";

/**
 * @title LandResource
 * @dev LandResource is registry that manage the element resources generated on Land, and related resource releasing speed.
 */
contract LandResource is DSAuth, IActivity, LandSettingIds {
    using SafeMath for *;

    // For every seconds, the speed will decrease by current speed multiplying (DENOMINATOR_in_seconds - seconds) / DENOMINATOR_in_seconds
    // resourc will decrease 1/10000 every day.
    uint256 public constant DENOMINATOR = 10000;

    uint256 public constant TOTAL_SECONDS = DENOMINATOR * (1 days);

    bool private singletonLock = false;

    ISettingsRegistry public registry;

    uint256 resourceReleaseStartTime;
    
    // TODO: move to global settings contract.
    uint256 public aattenPerDay = 1;
    uint256 public recoverAttenPerDay = 20;

    // Struct for recording resouces on land which have already been pinged.
    // 金, Evolution Land Gold
    // 木, Evolution Land Wood
    // 水, Evolution Land Water
    // 火, Evolution Land fire
    // 土, Evolution Land Silicon
    struct ResourceMintState {
        mapping(address=>uint256) mintedBalance;
        mapping(address=>uint256[]) miners;
        uint256 lastUpdateSpeedInSeconds;
        uint256 lastDestoryAttenInSeconds;
        uint256 industryIndex;
        uint256 lastUpdateTime;
    }

    struct MinerStatus {
        uint256 landTokenId;
        address resource;
        uint64  indexInResource;
    }

    mapping (uint256 => ResourceMintState) public land2ResourceMintState;

    mapping (uint256 => MinerStatus) public miner2Index;

    /*
     *  Modifiers
     */
    modifier singletonLockCall() {
        require(!singletonLock, "Only can call once");
        _;
        singletonLock = true;
    }

    function initializeContract(address _registry, uint256 _resourceReleaseStartTime) public singletonLockCall {
        // Ownable constructor
        owner = msg.sender;
        emit LogSetOwner(msg.sender);

        registry = ISettingsRegistry(_registry);

        resourceReleaseStartTime = _resourceReleaseStartTime;
    }

    function _getReleaseSpeedInSeconds(uint256 _tokenId, uint256 _time) internal view returns (uint256 currentSpeed) {
        require(_time > resourceReleaseStartTime, "Should after release time");
        require(_time > land2ResourceMintState[_tokenId].lastUpdateTime, "Should after release last update time");

        if (TOTAL_SECONDS < _time - resourceReleaseStartTime)
        {
            return 0;
        }

        uint256 _availableSpeedInSeconds = TOTAL_SECONDS.sub(_time - resourceReleaseStartTime);

        uint256 _timeBetween = _time - land2ResourceMintState[_tokenId].lastUpdateTime;

        // the recover speed is 20/10000, 20 times.
        uint256 _nextSpeedInSeconds = land2ResourceMintState[_tokenId].lastUpdateSpeedInSeconds + _timeBetween * recoverAttenPerDay;

        uint256 _destroyedSpeedInSeconds = _timeBetween * land2ResourceMintState[_tokenId].lastDestoryAttenInSeconds;

        if (_nextSpeedInSeconds < _destroyedSpeedInSeconds)
        {
            _nextSpeedInSeconds = 0;
        } else {
            _nextSpeedInSeconds = _nextSpeedInSeconds - _destroyedSpeedInSeconds;
        }

        if (_nextSpeedInSeconds > _availableSpeedInSeconds) {
            _nextSpeedInSeconds = _availableSpeedInSeconds;
        }

        return _nextSpeedInSeconds;
    }

    function getReleaseSpeed(uint256 _tokenId, address _resourceToken, uint256 _time) public view returns (uint256 currentSpeed) {
        return ILandBase(registry.addressOf(CONTRACT_LAND_BASE))
            .getResourceRate(_tokenId, _resourceToken).mul(_getReleaseSpeedInSeconds(_tokenId, _time))
            .div(TOTAL_SECONDS);
    }

    /**
     * @dev Get and Query the amount of resources available for use on specific land.
     * @param _tokenId The token id of specific land.
    */
    function _getMintableBalance(uint256 _tokenId, address _resourceToken) public view returns (uint256 _mintableBalance) {
        // the longest seconds to zero speed.
        uint256 currentTime = now;
        if (land2ResourceMintState[_tokenId].lastUpdateTime >= (resourceReleaseStartTime + TOTAL_SECONDS)) {
            return 0;
        } else if (now > (resourceReleaseStartTime + TOTAL_SECONDS))
        {
            currentTime = (resourceReleaseStartTime + TOTAL_SECONDS);
        }

        require(currentTime >= land2ResourceMintState[_tokenId].lastUpdateTime);

        uint256 speed_in_current_period = getReleaseSpeed(
            _tokenId, _resourceToken, (currentTime + land2ResourceMintState[_tokenId].lastUpdateTime) / 2);

        _mintableBalance = speed_in_current_period.mul(currentTime - land2ResourceMintState[_tokenId].lastUpdateTime).mul(1 ether).div(1 days);
    }

    function _getMaxMintBalance(uint256 _tokenId, address _resourceToken) internal view returns (uint256) {
        // TODO: Every miner add one speed for now for every day
        uint256 _mintSpeed = land2ResourceMintState[_tokenId].miners[_resourceToken].length;

        // the longest seconds to zero speed.
        uint256 currentTime = now;
        if (land2ResourceMintState[_tokenId].lastUpdateTime >= (resourceReleaseStartTime + TOTAL_SECONDS)) {
            return 0;
        } else if (now > (resourceReleaseStartTime + TOTAL_SECONDS))
        {
            currentTime = (resourceReleaseStartTime + TOTAL_SECONDS);
        }

        return _mintSpeed.mul(currentTime - land2ResourceMintState[_tokenId].lastUpdateTime).mul(1 ether).div(1 days);
    }

    function mint(uint256 _tokenId) public {
        _mintAllResource(
            _tokenId,
            registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN),
            registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN),
            registry.addressOf(CONTRACT_WATER_ERC20_TOKEN),
            registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN),
            registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN)
        );
    }

    function _mintAllResource(uint256 _tokenId, address _gold, address _wood, address _water, address _fire, address _soil) internal {
        require(IInterstellarEncoder(registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)).getObjectClass(_tokenId) == 1, "Token must be land.");

        if (land2ResourceMintState[_tokenId].lastUpdateTime == 0) {
            land2ResourceMintState[_tokenId].lastUpdateTime = resourceReleaseStartTime;
            land2ResourceMintState[_tokenId].lastUpdateSpeedInSeconds = TOTAL_SECONDS;
        }

        _mintResource(_tokenId, _gold);
        _mintResource(_tokenId, _wood);
        _mintResource(_tokenId, _water);
        _mintResource(_tokenId, _fire);
        _mintResource(_tokenId, _soil);

        land2ResourceMintState[_tokenId].lastUpdateTime = now;
        land2ResourceMintState[_tokenId].lastUpdateSpeedInSeconds = _getReleaseSpeedInSeconds(_tokenId, now);
    }

    function _mintResource(uint256 _tokenId, address _resourceToken) internal {
        uint256 _mintedBalance = _getMaxMintBalance(_tokenId, _resourceToken);
        uint256 _mintableBalance = _getMintableBalance(_tokenId, _resourceToken);

        if (_mintedBalance > _mintableBalance) {
            _mintedBalance = _mintableBalance;
        }

        land2ResourceMintState[_tokenId].mintedBalance[_resourceToken] = _mintedBalance;
    }

    function claimAllResource(uint256 _tokenId) public {
        require(msg.sender == ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(_tokenId), "Must be the owner of the land");

        address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
        address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
        address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
        address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
        address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);

        _mintAllResource(_tokenId, gold, wood, water, fire, soil);

        if (land2ResourceMintState[_tokenId].mintedBalance[gold] > 0) {
            IMintableERC20(gold).mint(msg.sender, land2ResourceMintState[_tokenId].mintedBalance[gold]);
            land2ResourceMintState[_tokenId].mintedBalance[gold] = 0;
        }

        if (land2ResourceMintState[_tokenId].mintedBalance[wood] > 0) {
            IMintableERC20(gold).mint(msg.sender, land2ResourceMintState[_tokenId].mintedBalance[wood]);
            land2ResourceMintState[_tokenId].mintedBalance[wood] = 0;
        }

        if (land2ResourceMintState[_tokenId].mintedBalance[water] > 0) {
            IMintableERC20(gold).mint(msg.sender, land2ResourceMintState[_tokenId].mintedBalance[water]);
            land2ResourceMintState[_tokenId].mintedBalance[water] = 0;
        }

        if (land2ResourceMintState[_tokenId].mintedBalance[fire] > 0) {
            IMintableERC20(gold).mint(msg.sender, land2ResourceMintState[_tokenId].mintedBalance[fire]);
            land2ResourceMintState[_tokenId].mintedBalance[fire] = 0;
        }

        if (land2ResourceMintState[_tokenId].mintedBalance[soil] > 0) {
            IMintableERC20(gold).mint(msg.sender, land2ResourceMintState[_tokenId].mintedBalance[soil]);
            land2ResourceMintState[_tokenId].mintedBalance[soil] = 0;
        }
    }

    function startMining(uint256 _tokenId, uint256 _landTokenId, address _resource) public {
        ITokenUse(registry.addressOf(CONTRACT_TOKEN_USE)).startTokenUseFromActivity(_tokenId, msg.sender, msg.sender, now, MAX_UINT48_TIME, 0);

        ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).transferFrom(msg.sender, registry.addressOf(CONTRACT_TOKEN_USE), _tokenId);

        uint256 _index = land2ResourceMintState[_landTokenId].miners[_resource].length;
        // TODO require the permission from land owner;
        land2ResourceMintState[_landTokenId].miners[_resource].push(_tokenId);

        miner2Index[_tokenId] = MinerStatus({
            landTokenId: _landTokenId,
            resource: _resource,
            indexInResource: uint64(_index)
        });
    }

    function isActivity() public returns (bool) {
        return true;
    }

    // Only trigger from Token Activity.
    function tokenUseStopped(uint256 _tokenId) public auth {
        _stopMining(_tokenId);
    }

    function stopMining(uint256 _tokenId) public {
        // only user can stop mining directly.
        require(
            ITokenUse(registry.addressOf(CONTRACT_TOKEN_USE)).getTokenUser(_tokenId) == msg.sender, "Only token owner can stop the mining.");

        ITokenUse(registry.addressOf(CONTRACT_TOKEN_USE)).stopTokenUseFromActivity(_tokenId);
        _stopMining(_tokenId);
    }

    function _stopMining(uint256 _tokenId) public {
        // remove the miner from land2ResourceMintState;
        uint64 _minerIndex = miner2Index[_tokenId].indexInResource;
        address _resouce = miner2Index[_tokenId].resource;
        uint64 _lastMinerIndex = uint64(land2ResourceMintState[miner2Index[_tokenId].landTokenId].miners[_resouce].length - 1);
        uint256 _lastMiner = land2ResourceMintState[miner2Index[_tokenId].landTokenId].miners[_resouce][_lastMinerIndex];

        land2ResourceMintState[miner2Index[_tokenId].landTokenId].miners[_resouce][_minerIndex] = _lastMiner;
        land2ResourceMintState[miner2Index[_tokenId].landTokenId].miners[_resouce][_lastMinerIndex] = 0;

        land2ResourceMintState[miner2Index[_tokenId].landTokenId].miners[_resouce].length --;
        miner2Index[_lastMiner].indexInResource = _minerIndex;

        delete miner2Index[_tokenId];
    }
}