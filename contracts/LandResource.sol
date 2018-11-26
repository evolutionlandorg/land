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
import "./interfaces/IMiner.sol";

/**
 * @title LandResource
 * @dev LandResource is registry that manage the element resources generated on Land, and related resource releasing speed.
 */
contract LandResource is DSAuth, IActivity, LandSettingIds {
    using SafeMath for *;

    // For every seconds, the speed will decrease by current speed multiplying (DENOMINATOR_in_seconds - seconds) / DENOMINATOR_in_seconds
    // resource will decrease 1/10000 every day.
    uint256 public constant DENOMINATOR = 10000;

    uint256 public constant TOTAL_SECONDS = DENOMINATOR * (1 days);

    bool private singletonLock = false;

    ISettingsRegistry public registry;

    uint256 resourceReleaseStartTime;
    
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
        mapping(address=>uint256) mintedBalance;
        mapping(address=>uint256[]) miners;
        mapping(address=>uint256) totalMinerStrength;
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

    mapping (uint256 => ResourceMineState) public land2ResourceMineState;

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

    // get amount of speed uint at this moment
    function _getReleaseSpeedInSeconds(uint256 _tokenId, uint256 _time) internal view returns (uint256 currentSpeed) {
        require(_time > resourceReleaseStartTime, "Should after release time");
        require(_time > land2ResourceMineState[_tokenId].lastUpdateTime, "Should after release last update time");

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
    function _getMinableBalance(uint256 _tokenId, address _resourceToken) public view returns (uint256 minableBalance) {
        // the longest seconds to zero speed.
        uint256 currentTime = now;
        if (land2ResourceMineState[_tokenId].lastUpdateTime >= (resourceReleaseStartTime + TOTAL_SECONDS)) {
            return 0;
        } else if (now > (resourceReleaseStartTime + TOTAL_SECONDS))
        {
            currentTime = (resourceReleaseStartTime + TOTAL_SECONDS);
        }

        require(currentTime >= land2ResourceMineState[_tokenId].lastUpdateTime);

        uint256 speed_in_current_period = getReleaseSpeed(
            _tokenId, _resourceToken, (currentTime + land2ResourceMineState[_tokenId].lastUpdateTime) / 2);

        // calculate the area of trapezoid
        minableBalance = speed_in_current_period.mul(currentTime - land2ResourceMineState[_tokenId].lastUpdateTime).mul(1 ether).div(1 days);
    }

    function _getMaxMineBalance(uint256 _tokenId, address _resourceToken) internal view returns (uint256) {
        // TODO: Every miner add one speed for now for every day
        uint256 mineSpeed = land2ResourceMineState[_tokenId].totalMinerStrength[_resourceToken];

        // the longest seconds to zero speed.
        uint256 currentTime = now;
        if (land2ResourceMineState[_tokenId].lastUpdateTime >= (resourceReleaseStartTime + TOTAL_SECONDS)) {
            return 0;
        } else if (now > (resourceReleaseStartTime + TOTAL_SECONDS))
        {
            currentTime = (resourceReleaseStartTime + TOTAL_SECONDS);
        }

        return mineSpeed.mul(currentTime - land2ResourceMineState[_tokenId].lastUpdateTime).mul(1 ether).div(1 days);
    }

    function mine(uint256 _tokenId) public {
        _mineAllResource(
            _tokenId,
            registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN),
            registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN),
            registry.addressOf(CONTRACT_WATER_ERC20_TOKEN),
            registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN),
            registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN)
        );
    }

    function _mineAllResource(uint256 _tokenId, address _gold, address _wood, address _water, address _fire, address _soil) internal {
        require(IInterstellarEncoder(registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)).getObjectClass(_tokenId) == 1, "Token must be land.");

        if (land2ResourceMineState[_tokenId].lastUpdateTime == 0) {
            land2ResourceMineState[_tokenId].lastUpdateTime = resourceReleaseStartTime;
            land2ResourceMineState[_tokenId].lastUpdateSpeedInSeconds = TOTAL_SECONDS;
        }

        _mineResource(_tokenId, _gold);
        _mineResource(_tokenId, _wood);
        _mineResource(_tokenId, _water);
        _mineResource(_tokenId, _fire);
        _mineResource(_tokenId, _soil);

        land2ResourceMineState[_tokenId].lastUpdateTime = now;
        land2ResourceMineState[_tokenId].lastUpdateSpeedInSeconds = _getReleaseSpeedInSeconds(_tokenId, now);
    }

    function _mineResource(uint256 _tokenId, address _resourceToken) internal {
        uint256 _minedBalance = _getMaxMineBalance(_tokenId, _resourceToken);
        uint256 _minableBalance = _getMinableBalance(_tokenId, _resourceToken);

        if (_minedBalance > _minableBalance) {
            _minedBalance = _minableBalance;
        }

        land2ResourceMineState[_tokenId].mintedBalance[_resourceToken] = _minedBalance;
    }

    function claimAllResource(uint256 _tokenId) public {
        require(msg.sender == ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(_tokenId), "Must be the owner of the land");

        address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
        address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
        address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
        address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
        address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);

        _mineAllResource(_tokenId, gold, wood, water, fire, soil);

        if (land2ResourceMineState[_tokenId].mintedBalance[gold] > 0) {
            IMintableERC20(gold).mint(msg.sender, land2ResourceMineState[_tokenId].mintedBalance[gold]);
            land2ResourceMineState[_tokenId].mintedBalance[gold] = 0;
        }

        if (land2ResourceMineState[_tokenId].mintedBalance[wood] > 0) {
            IMintableERC20(gold).mint(msg.sender, land2ResourceMineState[_tokenId].mintedBalance[wood]);
            land2ResourceMineState[_tokenId].mintedBalance[wood] = 0;
        }

        if (land2ResourceMineState[_tokenId].mintedBalance[water] > 0) {
            IMintableERC20(gold).mint(msg.sender, land2ResourceMineState[_tokenId].mintedBalance[water]);
            land2ResourceMineState[_tokenId].mintedBalance[water] = 0;
        }

        if (land2ResourceMineState[_tokenId].mintedBalance[fire] > 0) {
            IMintableERC20(gold).mint(msg.sender, land2ResourceMineState[_tokenId].mintedBalance[fire]);
            land2ResourceMineState[_tokenId].mintedBalance[fire] = 0;
        }

        if (land2ResourceMineState[_tokenId].mintedBalance[soil] > 0) {
            IMintableERC20(gold).mint(msg.sender, land2ResourceMineState[_tokenId].mintedBalance[soil]);
            land2ResourceMineState[_tokenId].mintedBalance[soil] = 0;
        }
    }

    // both for own _tokenId or hired one
    function startMining(uint256 _tokenId, uint256 _landTokenId, address _resource) public {
        ITokenUse tokenUse = ITokenUse(registry.addressOf(CONTRACT_TOKEN_USE));
        ERC721 nft = ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP));
        require(nft.ownerOf(_tokenId) == msg.sender || tokenUse.getTokenUser(_tokenId) == msg.sender);
        if(nft.ownerOf(_tokenId) == msg.sender ) {
            tokenUse.startTokenUseFromActivity(_tokenId, msg.sender, msg.sender, now, MAX_UINT48_TIME, 0);
        }


        // TODO require the permission from land owner;

        // make sure that _tokenId won't be used repeatedly
        if(miner2Index[_tokenId].landTokenId == 0) {
            uint256 _index = land2ResourceMineState[_landTokenId].miners[_resource].length;

            land2ResourceMineState[_landTokenId].miners[_resource].push(_tokenId);

            uint256 strength = IMiner(registry.addressOf(CONTRACT_MINER)).getStrength(_tokenId);
            land2ResourceMineState[_landTokenId].totalMinerStrength[_resource] += strength;

            miner2Index[_tokenId] = MinerStatus({
                landTokenId: _landTokenId,
                resource: _resource,
                indexInResource: uint64(_index)
                });

            // update status!
            mine(_landTokenId);
        }
    }

    function batchStartMining(uint256[] _tokenIds, uint256[] _landTokenIds, address[] _resources) public {
        require(_tokenIds.length == _landTokenIds.length && _landTokenIds.length == _resources.length, "input error");
        uint length = _tokenIds.length;
        
        for(uint i = 0; i < length; i++) {
            startMining(_tokenIds[i], _landTokenIds[i], _resources[i]);
        }

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
        // remove the miner from land2ResourceMineState;
        uint64 minerIndex = miner2Index[_tokenId].indexInResource;
        address resource = miner2Index[_tokenId].resource;
        uint64 lastMinerIndex = uint64(land2ResourceMineState[miner2Index[_tokenId].landTokenId].miners[resource].length - 1);
        uint256 lastMiner = land2ResourceMineState[miner2Index[_tokenId].landTokenId].miners[resource][lastMinerIndex];

        land2ResourceMineState[miner2Index[_tokenId].landTokenId].miners[resource][minerIndex] = lastMiner;
        land2ResourceMineState[miner2Index[_tokenId].landTokenId].miners[resource][lastMinerIndex] = 0;

        land2ResourceMineState[miner2Index[_tokenId].landTokenId].miners[resource].length--;
        miner2Index[lastMiner].indexInResource = minerIndex;

        uint256 strength = IMiner(registry.addressOf(CONTRACT_MINER)).getStrength(_tokenId);
        land2ResourceMineState[miner2Index[_tokenId].landTokenId].totalMinerStrength[resource] -= strength;

        delete miner2Index[_tokenId];
    }
}