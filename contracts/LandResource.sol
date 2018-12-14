pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-solidity/contracts/introspection/SupportsInterfaceWithLookup.sol";
import "@evolutionland/common/contracts/interfaces/IMintableERC20.sol";
import "@evolutionland/common/contracts/interfaces/ISettingsRegistry.sol";
import "@evolutionland/common/contracts/DSAuth.sol";
import "@evolutionland/common/contracts/SettingIds.sol";
import "@evolutionland/common/contracts/interfaces/IInterstellarEncoder.sol";
import "@evolutionland/common/contracts/interfaces/ITokenUse.sol";
import "@evolutionland/common/contracts/interfaces/IActivity.sol";
import "@evolutionland/common/contracts/interfaces/IMinerObject.sol";
import "./interfaces/ILandBase.sol";
import "./LandSettingIds.sol";

/**
 * @title LandResource
 * @dev LandResource is registry that manage the element resources generated on Land, and related resource releasing speed.
 */
contract LandResource is SupportsInterfaceWithLookup, DSAuth, IActivity, LandSettingIds {
    using SafeMath for *;

    // For every seconds, the speed will decrease by current speed multiplying (DENOMINATOR_in_seconds - seconds) / DENOMINATOR_in_seconds
    // resource will decrease 1/10000 every day.
    uint256 public constant DENOMINATOR = 10000;

    uint256 public constant TOTAL_SECONDS = DENOMINATOR * (1 days);

    bool private singletonLock = false;

    ISettingsRegistry public registry;

    uint256 public resourceReleaseStartTime;

    // TODO: move to global settings contract.
    uint256 public attenPerDay = 1;
    uint256 public recoverAttenPerDay = 20;

    // Struct for recording resouces on land which have already been pinged.
    // 金, Evolution Land Gold
    // 木, Evolution Land Wood
    // 水, Evolution Land Water
    // 火, Evolution Land fire
    // 土, Evolution Land Silicon
    struct ResourceMineState {
        mapping(address => uint256) mintedBalance;
        mapping(address => uint256[]) miners;
        mapping(address => uint256) totalMinerStrength;
        uint256 lastUpdateSpeedInSeconds;
        uint256 lastDestoryAttenInSeconds;
        uint256 industryIndex;
        uint128 lastUpdateTime;
        uint64 totalMiners;
        uint64 maxMiners;
    }

    struct MinerStatus {
        uint256 landTokenId;
        address resource;
        uint64 indexInResource;
    }

    mapping(uint256 => ResourceMineState) public land2ResourceMineState;

    mapping(uint256 => MinerStatus) public miner2Index;

    /*
     *  Event
     */

    event StartMining(uint256 minerTokenId, uint256 landTokenId, address _resource, uint256 strength);
    event StopMining(uint256 minerTokenId, uint256 landTokenId, address _resource, uint256 strength);
    event ResourceClaimed(address owner, uint256 landTokenId, uint256 goldBalance, uint256 woodBalance, uint256 waterBalance, uint256 fireBalance, uint256 soilBalance);

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

        _registerInterface(InterfaceId_IActivity);
    }

    // get amount of speed uint at this moment
    function _getReleaseSpeedInSeconds(uint256 _tokenId, uint256 _time) internal view returns (uint256 currentSpeed) {
        require(_time >= resourceReleaseStartTime, "Should after release time");
        require(_time >= land2ResourceMineState[_tokenId].lastUpdateTime, "Should after release last update time");

        // after 10000 days from start
        // the resource release speed decreases to 0
        if (TOTAL_SECONDS < _time - resourceReleaseStartTime)
        {
            return 0;
        }

        // max amount of speed unit of _tokenId for now
        // suppose that speed_uint = 1 in this function
        uint256 availableSpeedInSeconds = TOTAL_SECONDS.sub(_time - resourceReleaseStartTime);
        // time from last update
        uint256 timeBetween = _time - land2ResourceMineState[_tokenId].lastUpdateTime;

        // the recover speed is 20/10000, 20 times.
        // recoveryRate overall from lasUpdateTime til now + amount of speed uint at lastUpdateTime
        uint256 nextSpeedInSeconds = land2ResourceMineState[_tokenId].lastUpdateSpeedInSeconds + timeBetween * recoverAttenPerDay;
        // destroyRate overall from lasUpdateTime til now amount of speed uint at lastUpdateTime
        uint256 destroyedSpeedInSeconds = timeBetween * land2ResourceMineState[_tokenId].lastDestoryAttenInSeconds;

        if (nextSpeedInSeconds < destroyedSpeedInSeconds)
        {
            nextSpeedInSeconds = 0;
        } else {
            nextSpeedInSeconds = nextSpeedInSeconds - destroyedSpeedInSeconds;
        }

        if (nextSpeedInSeconds > availableSpeedInSeconds) {
            nextSpeedInSeconds = availableSpeedInSeconds;
        }

        return nextSpeedInSeconds;
    }

    function getReleaseSpeed(uint256 _tokenId, address _resourceToken, uint256 _time) public view returns (uint256 currentSpeed) {
        return ILandBase(registry.addressOf(CONTRACT_LAND_BASE))
        .getResourceRate(_tokenId, _resourceToken).mul(_getReleaseSpeedInSeconds(_tokenId, _time))
        .div(TOTAL_SECONDS);
    }

    /**
     * @dev Get and Query the amount of resources available from lastUpdateTime to now for use on specific land.
     * @param _tokenId The token id of specific land.
    */
    function _getMinableBalance(uint256 _tokenId, address _resourceToken, uint256 _currentTime, uint256 _lastUpdateTime) public view returns (uint256 minableBalance) {

        uint256 speed_in_current_period = getReleaseSpeed(
            _tokenId, _resourceToken, (_currentTime + _lastUpdateTime) / 2);

        // calculate the area of trapezoid
        minableBalance = speed_in_current_period.mul(_currentTime - _lastUpdateTime).mul(1 ether).div(1 days);
    }

    function _getMaxMineBalance(uint256 _tokenId, address _resourceToken, uint256 _currentTime, uint256 _lastUpdateTime) internal view returns (uint256) {
        // totalMinerStrength is in wei
        uint256 mineSpeed = land2ResourceMineState[_tokenId].totalMinerStrength[_resourceToken];

        return mineSpeed.mul(_currentTime - _lastUpdateTime).div(1 days);
    }

    function mine(uint256 _landTokenId) public {
        _mineAllResource(
            _landTokenId,
            registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN),
            registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN),
            registry.addressOf(CONTRACT_WATER_ERC20_TOKEN),
            registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN),
            registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN)
        );
    }

    function _mineAllResource(uint256 _landTokenId, address _gold, address _wood, address _water, address _fire, address _soil) internal {
        require(IInterstellarEncoder(registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)).getObjectClass(_landTokenId) == 1, "Token must be land.");

        if (land2ResourceMineState[_landTokenId].lastUpdateTime == 0) {
            land2ResourceMineState[_landTokenId].lastUpdateTime = uint128(resourceReleaseStartTime);
            land2ResourceMineState[_landTokenId].lastUpdateSpeedInSeconds = TOTAL_SECONDS;
        }

        _mineResource(_landTokenId, _gold);
        _mineResource(_landTokenId, _wood);
        _mineResource(_landTokenId, _water);
        _mineResource(_landTokenId, _fire);
        _mineResource(_landTokenId, _soil);

        land2ResourceMineState[_landTokenId].lastUpdateSpeedInSeconds = _getReleaseSpeedInSeconds(_landTokenId, now);
        land2ResourceMineState[_landTokenId].lastUpdateTime = uint128(now);

    }

    function _mineResource(uint256 _landTokenId, address _resourceToken) internal {
        // the longest seconds to zero speed.
        uint minedBalance = _calculateMinedBalance(_landTokenId, _resourceToken, now);

        land2ResourceMineState[_landTokenId].mintedBalance[_resourceToken] += minedBalance;
    }

    function _calculateMinedBalance(uint256 _landTokenId, address _resourceToken, uint256 _currentTime) internal returns (uint256) {
        uint256 currentTime = _currentTime;

        uint256 minedBalance;
        uint256 minableBalance;
        if (currentTime > (resourceReleaseStartTime + TOTAL_SECONDS))
        {
            currentTime = (resourceReleaseStartTime + TOTAL_SECONDS);
        }

        uint256 lastUpdateTime = land2ResourceMineState[_landTokenId].lastUpdateTime;
        require(currentTime >= lastUpdateTime);

        if (lastUpdateTime >= (resourceReleaseStartTime + TOTAL_SECONDS)) {
            minedBalance = 0;
            minableBalance = 0;
        } else {
            minedBalance = _getMaxMineBalance(_landTokenId, _resourceToken, currentTime, lastUpdateTime);
            minableBalance = _getMinableBalance(_landTokenId, _resourceToken, currentTime, lastUpdateTime);
        }


        if (minedBalance > minableBalance) {
            minedBalance = minableBalance;
        }

        return minedBalance;
    }

    function claimAllResource(uint256 _landTokenId) public {
        require(msg.sender == ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(_landTokenId), "Must be the owner of the land");

        address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
        address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
        address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
        address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
        address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);

        _mineAllResource(_landTokenId, gold, wood, water, fire, soil);

        uint goldBalance;
        uint woodBalance;
        uint waterBalance;
        uint fireBalance;
        uint soilBalance;

        if (land2ResourceMineState[_landTokenId].mintedBalance[gold] > 0) {
            goldBalance = land2ResourceMineState[_landTokenId].mintedBalance[gold];
            IMintableERC20(gold).mint(msg.sender, goldBalance);
            land2ResourceMineState[_landTokenId].mintedBalance[gold] = 0;
        }

        if (land2ResourceMineState[_landTokenId].mintedBalance[wood] > 0) {
            woodBalance = land2ResourceMineState[_landTokenId].mintedBalance[wood];
            IMintableERC20(gold).mint(msg.sender, woodBalance);
            land2ResourceMineState[_landTokenId].mintedBalance[wood] = 0;
        }

        if (land2ResourceMineState[_landTokenId].mintedBalance[water] > 0) {
            waterBalance = land2ResourceMineState[_landTokenId].mintedBalance[water];
            IMintableERC20(gold).mint(msg.sender, waterBalance);
            land2ResourceMineState[_landTokenId].mintedBalance[water] = 0;
        }

        if (land2ResourceMineState[_landTokenId].mintedBalance[fire] > 0) {
            fireBalance = land2ResourceMineState[_landTokenId].mintedBalance[fire];
            IMintableERC20(gold).mint(msg.sender, fireBalance);
            land2ResourceMineState[_landTokenId].mintedBalance[fire] = 0;
        }

        if (land2ResourceMineState[_landTokenId].mintedBalance[soil] > 0) {
            soilBalance = land2ResourceMineState[_landTokenId].mintedBalance[soil];
            IMintableERC20(gold).mint(msg.sender, soilBalance);
            land2ResourceMineState[_landTokenId].mintedBalance[soil] = 0;
        }

        emit ResourceClaimed(msg.sender, _landTokenId, goldBalance, woodBalance, waterBalance, fireBalance, soilBalance);
    }

    // both for own _tokenId or hired one
    function startMining(uint256 _tokenId, uint256 _landTokenId, address _resource) public {
        ITokenUse tokenUse = ITokenUse(registry.addressOf(CONTRACT_TOKEN_USE));

        tokenUse.addActivity(_tokenId, msg.sender, 0);

        // require the permission from land owner;
        require(msg.sender == ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(_landTokenId), "Must be the owner of the land");

        // make sure that _tokenId won't be used repeatedly
        require(miner2Index[_tokenId].landTokenId == 0);

        // update status!
        mine(_landTokenId);

        uint256 _index = land2ResourceMineState[_landTokenId].miners[_resource].length;

        land2ResourceMineState[_landTokenId].totalMiners += 1;

        if (land2ResourceMineState[_landTokenId].maxMiners == 0) {
            land2ResourceMineState[_landTokenId].maxMiners = 5;
        }

        require(land2ResourceMineState[_landTokenId].totalMiners <= land2ResourceMineState[_landTokenId].maxMiners);

        address miner = IInterstellarEncoder(registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)).getObjectAddress(_tokenId);
        uint256 strength = IMinerObject(miner).strengthOf(_tokenId, _resource);

        land2ResourceMineState[_landTokenId].miners[_resource].push(_tokenId);
        land2ResourceMineState[_landTokenId].totalMinerStrength[_resource] += strength;

        miner2Index[_tokenId] = MinerStatus({
            landTokenId : _landTokenId,
            resource : _resource,
            indexInResource : uint64(_index)
            });

        emit StartMining(_tokenId, _landTokenId, _resource, strength);

    }

    function batchStartMining(uint256[] _tokenIds, uint256[] _landTokenIds, address[] _resources) public {
        require(_tokenIds.length == _landTokenIds.length && _landTokenIds.length == _resources.length, "input error");
        uint length = _tokenIds.length;

        for (uint i = 0; i < length; i++) {
            startMining(_tokenIds[i], _landTokenIds[i], _resources[i]);
        }

    }

    // Only trigger from Token Activity.
    function activityStopped(uint256 _tokenId) public auth {

        _stopMining(_tokenId);
    }

    function stopMining(uint256 _tokenId) public {
        ITokenUse(registry.addressOf(CONTRACT_TOKEN_USE)).removeActivity(_tokenId, msg.sender);
    }

    function _stopMining(uint256 _tokenId) public {
        // remove the miner from land2ResourceMineState;
        uint64 minerIndex = miner2Index[_tokenId].indexInResource;
        address resource = miner2Index[_tokenId].resource;
        uint256 landTokenId = miner2Index[_tokenId].landTokenId;

        // update status!
        mine(landTokenId);

        uint64 lastMinerIndex = uint64(land2ResourceMineState[landTokenId].miners[resource].length.sub(1));
        uint256 lastMiner = land2ResourceMineState[landTokenId].miners[resource][lastMinerIndex];

        land2ResourceMineState[landTokenId].miners[resource][minerIndex] = lastMiner;
        land2ResourceMineState[landTokenId].miners[resource][lastMinerIndex] = 0;

        land2ResourceMineState[landTokenId].miners[resource].length -= 1;
        miner2Index[lastMiner].indexInResource = minerIndex;

        land2ResourceMineState[landTokenId].totalMiners -= 1;

        address miner = IInterstellarEncoder(registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)).getObjectAddress(_tokenId);
        uint256 strength = IMinerObject(miner).strengthOf(_tokenId, resource);
        land2ResourceMineState[landTokenId].totalMinerStrength[resource] = land2ResourceMineState[landTokenId].totalMinerStrength[resource].sub(strength);

        delete miner2Index[_tokenId];

        emit StopMining(_tokenId, landTokenId, resource, strength);
    }

    function getMinerOnLand(uint _landTokenId, address _resourceToken, uint _index) public view returns (uint256) {
        return land2ResourceMineState[_landTokenId].miners[_resourceToken][_index];
    }

    function getTotalMiningStrength(uint _landTokenId, address _resourceToken) public view returns (uint256) {
        return land2ResourceMineState[_landTokenId].totalMinerStrength[_resourceToken];
    }

    function availableResources(uint256 _landTokenId, address[5] _resourceTokens) public view returns (uint256,uint256,uint256,uint256,uint256) {

        uint availableGold = _calculateMinedBalance(_landTokenId, _resourceTokens[0], now) + land2ResourceMineState[_landTokenId].mintedBalance[_resourceTokens[0]];
        uint availableWood = _calculateMinedBalance(_landTokenId, _resourceTokens[1], now) + land2ResourceMineState[_landTokenId].mintedBalance[_resourceTokens[1]];
        uint availableWater = _calculateMinedBalance(_landTokenId, _resourceTokens[2], now) + land2ResourceMineState[_landTokenId].mintedBalance[_resourceTokens[2]];
        uint availableFire = _calculateMinedBalance(_landTokenId, _resourceTokens[3], now) + land2ResourceMineState[_landTokenId].mintedBalance[_resourceTokens[3]];
        uint availableSoil = _calculateMinedBalance(_landTokenId, _resourceTokens[4], now) + land2ResourceMineState[_landTokenId].mintedBalance[_resourceTokens[4]];

        return (availableGold, availableWood, availableWater, availableFire, availableSoil);
    }

}