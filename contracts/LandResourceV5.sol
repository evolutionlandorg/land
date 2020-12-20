pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/math/Math.sol";
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
import "./interfaces/IItemBar.sol";
import "./LandSettingIds.sol";

contract LandResourceV5 is
	SupportsInterfaceWithLookup,
	DSAuth,
	IActivity,
	LandSettingIds
{
	using SafeMath for *;
	using Math for *;

	// For every seconds, the speed will decrease by current speed multiplying (DENOMINATOR_in_seconds - seconds) / DENOMINATOR_in_seconds
	// resource will decrease 1/10000 every day.
	uint256 public constant DENOMINATOR = 10000;

	uint256 public constant TOTAL_SECONDS = DENOMINATOR * (1 days);

	bool private singletonLock = false;

	ISettingsRegistry public registry;

	uint256 public resourceReleaseStartTime;

	// TODO: remove.
	uint256 public attenPerDay = 1;
	uint256 public recoverAttenPerDay = 20;

	// Struct for recording resouces on land which have already been pinged.
	// 金, Evolution Land Gold
	// 木, Evolution Land Wood
	// 水, Evolution Land Water
	// 火, Evolution Land fire
	// 土, Evolution Land Silicon
	// struct ResourceMineState {
	// 	mapping(address => uint256) mintedBalance;
	// 	mapping(address => uint256[]) miners;
	// 	mapping(address => uint256) totalMinerStrength;
	// 	uint256 lastUpdateSpeedInSeconds;
	// 	uint256 lastDestoryAttenInSeconds;
	// 	uint256 industryIndex;
	// 	uint128 lastUpdateTime;
	// 	uint64 totalMiners;
	// 	uint64 maxMiners;
	// }
	// TODO: remove.
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

	// TODO: remove.
	mapping(uint256 => ResourceMineState) public land2ResourceMineState;

	struct MinerStatus {
		uint256 landTokenId;
		address resource;
		uint64 indexInResource;
	}
	mapping(uint256 => MinerStatus) public miner2Index;

	/*
	 *  Event
	 */

	event ResourceClaimed(
		address owner,
		uint256 landTokenId,
		uint256 goldBalance,
		uint256 woodBalance,
		uint256 waterBalance,
		uint256 fireBalance,
		uint256 soilBalance
	);

	// V5 change
	// event StartMining(uint256 minerTokenId, uint256 landTokenId, address _resource, uint256 strength);
	// event StopMining(uint256 minerTokenId, uint256 landTokenId, address _resource, uint256 strength);

	// event UpdateMiningStrengthWhenStop(uint256 apostleTokenId, uint256 landTokenId, uint256 strength);
	// event UpdateMiningStrengthWhenStart(uint256 apostleTokenId, uint256 landTokenId, uint256 strength);

	// v5 add
	event StartMining(
		uint256 index,
		uint256 minerTokenId,
		uint256 landTokenId,
		address resource,
		uint256 minerStrength,
		uint256 enhancedStrengh
	);
	event StopMining(
		uint256 index,
		uint256 minerTokenId,
		uint256 landTokenId,
		address _resource,
		uint256 strength,
		uint256 enhancedStrength
	);
	event UpdateMiningStrengthWhenStop(
		uint256 apostleTokenId,
		uint256 landTokenId,
		uint256 strength,
		uint256 enhancedStrength
	);
	event UpdateMiningStrengthWhenStart(
		uint256 apostleTokenId,
		uint256 landTokenId,
		uint256 strength,
		uint256 enhancedStrength
	);
	event UpdateEnhancedStrengthByElement(
		uint256 landTokenId,
		address resourceToken,
		uint256 enhancedStrength
	);

	// 0x434f4e54524143545f4c414e445f4954454d5f42415200000000000000000000
	bytes32 public constant CONTRACT_LAND_ITEM_BAR = "CONTRACT_LAND_ITEM_BAR";

	struct RSState {
		uint256 start;
		uint256 strength;
		uint256 minedBalance;
	}

	// rate precision
	uint128 public constant RATE_PRECISION = 10**8;

	uint256 maxMiners;
	mapping(uint256 => mapping(uint256 => uint256)) public land2Miner;
	mapping(uint256 => mapping(address => RSState)) public land2RSState;
	mapping(uint256 => mapping(address => mapping(address => uint256)))
		public land2BarMinedBalance;
	mapping(uint256 => mapping(address => uint256))
		public land2BarEnhancedStrength;

	/*
	 *  Modifiers
	 */
	modifier singletonLockCall() {
		require(!singletonLock, "Only can call once");
		_;
		singletonLock = true;
	}

	function initializeContract(
		address _registry,
		uint256 _resourceReleaseStartTime,
		uint256 _maxMiners
	) public singletonLockCall {
		// Ownable constructor
		owner = msg.sender;
		emit LogSetOwner(msg.sender);

		registry = ISettingsRegistry(_registry);

		resourceReleaseStartTime = _resourceReleaseStartTime;

		maxMiners = _maxMiners;

		_registerInterface(InterfaceId_IActivity);
	}

	function getLandMinedBalance(uint256 _landId, address _resource)
		public
		view
		returns (uint256)
	{
		return land2RSState[_landId][_resource].minedBalance;
	}

	function getBarMinedBalance(
		uint256 _landId,
		address _to,
		address _resource
	) public view returns (uint256) {
		return land2BarMinedBalance[_landId][_to][_resource];
	}

	function getLandMiningStrength(uint256 _landId, address _resource)
		public
		view
		returns (uint256)
	{
		return land2RSState[_landId][_resource].strength;
	}

	function getBarMiningStrength(uint256 _landId, address _resource)
		public
		view
		returns (uint256)
	{
		return land2BarEnhancedStrength[_landId][_resource];
	}

	function getTotalMiningStrength(uint256 _landId, address _resource)
		public
		view
		returns (uint256)
	{
		return
			getLandMiningStrength(_landId, _resource).add(
				getBarMiningStrength(_landId, _resource)
			);
	}

	function getMinerOnLand(uint256 _landId, uint256 _index)
		public
		view
		returns (uint256)
	{
		return land2Miner[_landId][_index];
	}

	function landWorkingOn(uint256 _apostleTokenId)
		public
		view
		returns (uint256 landTokenId)
	{
		landTokenId = miner2Index[_apostleTokenId].landTokenId;
	}

	// get amount of speed uint at this moment
	function _getReleaseSpeedInSeconds(uint256 _tokenId, uint256 _time)
		internal
		view
		returns (uint256 currentSpeed)
	{
		require(_time >= resourceReleaseStartTime, "Landrs: TOO_EARLY");

		// after 10000 days from start
		// the resource release speed decreases to 0
		if (TOTAL_SECONDS < _time - resourceReleaseStartTime) {
			return 0;
		}

		// max amount of speed unit of _tokenId for now
		// suppose that speed_uint = 1 in this function
		uint256 availableSpeedInSeconds =
			TOTAL_SECONDS.sub(_time - resourceReleaseStartTime);
		// time from last update
		// uint256 timeBetween = _time - minerStartTime;

		// the recover speed is 20/10000, 20 times.
		// recoveryRate overall from lasUpdateTime til now + amount of speed uint at lastUpdateTime
		// uint256 nextSpeedInSeconds = land2ResourceMineState[_tokenId].lastUpdateSpeedInSeconds + timeBetween * recoverAttenPerDay;
		// destroyRate overall from lasUpdateTime til now amount of speed uint at lastUpdateTime
		// uint256 destroyedSpeedInSeconds = timeBetween * land2ResourceMineState[_tokenId].lastDestoryAttenInSeconds;

		// if (nextSpeedInSeconds < destroyedSpeedInSeconds)
		// {
		//     nextSpeedInSeconds = 0;
		// } else {
		//     nextSpeedInSeconds = nextSpeedInSeconds - destroyedSpeedInSeconds;
		// }

		// if (nextSpeedInSeconds > availableSpeedInSeconds) {
		//     nextSpeedInSeconds = availableSpeedInSeconds;
		// }

		return availableSpeedInSeconds;
	}

	function getReleaseSpeed(
		uint256 _tokenId,
		address _resource,
		uint256 _time
	) public view returns (uint256 currentSpeed) {
		return
			ILandBase(registry.addressOf(CONTRACT_LAND_BASE))
				.getResourceRate(_tokenId, _resource)
				.mul(_getReleaseSpeedInSeconds(_tokenId, _time))
				.mul(1 ether)
				.div(TOTAL_SECONDS);
	}

	function _getMinableBalance(
		uint256 _tokenId,
		address _resource,
		uint256 _currentTime,
		uint256 _lastUpdateTime
	) public view returns (uint256 minableBalance) {
		uint256 speed_in_current_period =
			ILandBase(registry.addressOf(CONTRACT_LAND_BASE))
				.getResourceRate(_tokenId, _resource)
				.mul(
				_getReleaseSpeedInSeconds(
					_tokenId,
					((_currentTime + _lastUpdateTime) / 2)
				)
			)
				.mul(1 ether)
				.div(1 days)
				.div(TOTAL_SECONDS);

		// calculate the area of trapezoid
		minableBalance = speed_in_current_period.mul(
			_currentTime - _lastUpdateTime
		);
	}

	function setMaxMiners(uint256 _maxMiners) public auth {
		require(_maxMiners > maxMiners, "Land: INVALID_MAXMINERS");
		maxMiners = _maxMiners;
	}

	function settle(uint256 _landId) public {
		address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
		address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
		address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
		address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
		address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);
		settleResource(_landId, gold);
		settleResource(_landId, wood);
		settleResource(_landId, water);
		settleResource(_landId, fire);
		settleResource(_landId, soil);
	}

	function settleResource(uint256 _landId, address _resource) public {
		require(
			IInterstellarEncoder(
				registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)
			)
				.getObjectClass(_landId) == 1,
			"Land: INVAID_TOKENID"
		);
		if (getLandMiningStrength(_landId, _resource) > 0) {
			_mineResource(_landId, _resource);
		}
		land2RSState[_landId][_resource].start = now;
	}

	function _calculateMinedBalance(
		uint256 _landId,
		address _resource,
		uint256 _currentTime
	) internal returns (uint256) {
		uint256 currentTime =
			_currentTime.min256((resourceReleaseStartTime + TOTAL_SECONDS));
		uint256 lastUpdateTime = land2RSState[_landId][_resource].start;
		if (lastUpdateTime == 0) {
			return 0;
		}
		require(currentTime >= lastUpdateTime, "Land: INVALID_TIME");
		uint256 minedBalance;
		uint256 minableBalance;
		if (lastUpdateTime >= (resourceReleaseStartTime + TOTAL_SECONDS)) {
			minedBalance = 0;
			minableBalance = 0;
		} else {
			minedBalance = _getMaxMineBalance(
				_landId,
				_resource,
				currentTime,
				lastUpdateTime
			);
			minableBalance = _getMinableBalance(
				_landId,
				_resource,
				currentTime,
				lastUpdateTime
			);
		}
		return minedBalance.min256(minableBalance);
	}

	function _strengthOf(
		uint256 _tokenId,
		uint256 _landId,
		address _resource
	) internal returns (uint256) {
		address miner =
			IInterstellarEncoder(
				registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)
			)
				.getObjectAddress(_tokenId);
		return IMinerObject(miner).strengthOf(_tokenId, _resource, _landId);
	}

	function _enhancedStrengthOf(
		uint256 _strength,
		uint256 _landId,
		address _resource
	) internal returns (uint256) {
		return
			_strength
				.mul(
				IItemBar(registry.addressOf(CONTRACT_LAND_ITEM_BAR))
					.enhanceStrengthRateOf(_resource, _landId)
			)
				.div(RATE_PRECISION);
	}

	function _updateStrength(
		uint256 _minerTokenId,
		uint256 _landId,
		address _resource,
		bool _isStop
	) internal returns (uint256, uint256) {
		// V5 add item bar
		uint256 strength = _strengthOf(_minerTokenId, _landId, _resource);
		uint256 enhancedStrength =
			_enhancedStrengthOf(strength, _landId, _resource);

		if (_isStop) {
			land2RSState[_landId][_resource].strength = getLandMiningStrength(
				_landId,
				_resource
			)
				.sub(strength);

			land2BarEnhancedStrength[_landId][
				_resource
			] = land2BarEnhancedStrength[_landId][_resource].sub(
				enhancedStrength
			);
		} else {
			land2RSState[_landId][_resource].strength = getLandMiningStrength(
				_landId,
				_resource
			)
				.add(strength);

			land2BarEnhancedStrength[_landId][
				_resource
			] = land2BarEnhancedStrength[_landId][_resource].add(
				enhancedStrength
			);
		}
		return (strength, enhancedStrength);
	}

	function startMining(
		uint256 _index,
		uint256 _tokenId,
		uint256 _landId,
		address _resource
	) public {
		ITokenUse(registry.addressOf(CONTRACT_TOKEN_USE)).addActivity(
			_tokenId,
			msg.sender,
			0
		);
		// require the permission from land owner;
		require(isLander(_landId, msg.sender), "Land: ONLY_LANDER");
		require(_index < maxMiners, "Land: EXCEED_MINER_LIMIT");
		require(land2Miner[_landId][_index] == 0, "Land: MINER_EXISTED");

		// make sure that _tokenId won't be used repeatedly
		require(
			miner2Index[_tokenId].landTokenId == 0,
			"Land: REPEATED_MINING"
		);

		// update status!
		settleResource(_landId, _resource);

		(uint256 strength, uint256 enhancedStrength) =
			_updateStrength(_tokenId, _landId, _resource, false);
		land2Miner[_landId][_index] = _tokenId;

		miner2Index[_tokenId] = MinerStatus({
			landTokenId: _landId,
			resource: _resource,
			indexInResource: uint64(_index)
		});

		emit StartMining(
			_index,
			_tokenId,
			_landId,
			_resource,
			strength,
			enhancedStrength
		);
	}

	function batchStartMining(
		uint256[] indexes,
		uint256[] _tokenIds,
		uint256[] _landIds,
		address[] _resources
	) public {
		require(
			indexes.length == _tokenIds.length &&
				_tokenIds.length == _landIds.length &&
				_landIds.length == _resources.length,
			"Land: INVALID_INPUT"
		);
		uint256 length = _tokenIds.length;

		for (uint256 i = 0; i < length; i++) {
			startMining(indexes[i], _tokenIds[i], _landIds[i], _resources[i]);
		}
	}

	function batchClaimAllResource(uint256[] _landIds) public {
		uint256 length = _landIds.length;

		for (uint256 i = 0; i < length; i++) {
			claimAllResource(_landIds[i]);
		}
	}

	// Only trigger from Token Activity.
	function activityStopped(uint256 _tokenId) public auth {
		_stopMining(_tokenId);
	}

	function stopMining(uint256 _tokenId) public {
		ITokenUse(registry.addressOf(CONTRACT_TOKEN_USE)).removeActivity(
			_tokenId,
			msg.sender
		);
	}

	function _stopMining(uint256 _tokenId) internal {
		uint64 index = miner2Index[_tokenId].indexInResource;
		address resource = miner2Index[_tokenId].resource;
		uint256 landTokenId = miner2Index[_tokenId].landTokenId;

		require(landTokenId != 0, "Land: NO_MINER");

		settleResource(landTokenId, resource);

		(uint256 strength, uint256 enhancedStrength) =
			_updateStrength(_tokenId, landTokenId, resource, true);

		delete land2Miner[landTokenId][index];
		delete miner2Index[_tokenId];

		emit StopMining(
			uint256(index),
			_tokenId,
			landTokenId,
			resource,
			strength,
			enhancedStrength
		);
	}

	function updateMinerStrengthWhenStop(uint256 _apostleTokenId) public auth {
		if (miner2Index[_apostleTokenId].landTokenId == 0) {
			return;
		}
		(uint256 landTokenId, uint256 strength, uint256 enhancedStrength) =
			_updateMinerStrength(_apostleTokenId, true);
		// _isStop == true - minus strength
		// _isStop == false - add strength
		emit UpdateMiningStrengthWhenStop(
			_apostleTokenId,
			landTokenId,
			strength,
			enhancedStrength
		);
	}

	function updateMinerStrengthWhenStart(uint256 _apostleTokenId) public auth {
		if (miner2Index[_apostleTokenId].landTokenId == 0) {
			return;
		}
		(uint256 landTokenId, uint256 strength, uint256 enhancedStrength) =
			_updateMinerStrength(_apostleTokenId, false);
		// _isStop == true - minus strength
		// _isStop == false - add strength
		emit UpdateMiningStrengthWhenStart(
			_apostleTokenId,
			landTokenId,
			strength,
			enhancedStrength
		);
	}

	function _updateMinerStrength(uint256 _apostleTokenId, bool _isStop)
		internal
		returns (
			uint256,
			uint256,
			uint256
		)
	{
		// require that this apostle
		uint256 landTokenId = landWorkingOn(_apostleTokenId);
		require(landTokenId != 0, "this apostle is not mining.");
		address resource = miner2Index[_apostleTokenId].resource;
		(uint256 strength, uint256 enhancedStrength) =
			_updateStrength(_apostleTokenId, landTokenId, resource, _isStop);
		return (landTokenId, strength, enhancedStrength);
	}

	// can only be called by ItemBar
	// _isStop == true - minus strength
	function updateAllMinerStrengthWhenStop(uint256 _landId) public auth {
		settle(_landId);
	}

	// can only be called by ItemBar
	// _isStop == false - add strength
	function updateAllMinerStrengthWhenStart(uint256 _landId) public auth {
		_updateEnhancedStrengthByElement(
			_landId,
			registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN)
		);
		_updateEnhancedStrengthByElement(
			_landId,
			registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN)
		);
		_updateEnhancedStrengthByElement(
			_landId,
			registry.addressOf(CONTRACT_WATER_ERC20_TOKEN)
		);
		_updateEnhancedStrengthByElement(
			_landId,
			registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN)
		);
		_updateEnhancedStrengthByElement(
			_landId,
			registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN)
		);
	}

	function _updateEnhancedStrengthByElement(
		uint256 _landId,
		address _resource
	) internal {
		uint256 strength = getLandMiningStrength(_landId, _resource);
		if (strength > 0) {
			uint256 enhancedStrength =
				_enhancedStrengthOf(strength, _landId, _resource);
			land2BarEnhancedStrength[_landId][_resource] = enhancedStrength;
			emit UpdateEnhancedStrengthByElement(
				_landId,
				_resource,
				enhancedStrength
			);
		}
	}

	function isLander(uint256 _landId, address _to)
		internal
		view
		returns (bool)
	{
		return
			_to ==
			ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(
				_landId
			);
	}

	function _getMaxMineBalance(
		uint256 _tokenId,
		address _resource,
		uint256 _currentTime,
		uint256 _lastUpdateTime
	) internal view returns (uint256) {
		// totalMinerStrength is in wei
		return
			getTotalMiningStrength(_tokenId, _resource)
				.mul(_currentTime - _lastUpdateTime)
				.div(1 days);
	}

	function _mineResource(uint256 _landId, address _resource) internal {
		// the longest seconds to zero speed.
		uint256 minedBalance = _calculateMinedBalance(_landId, _resource, now);
		if (minedBalance == 0) {
			return;
		}

		// V5 yeild distribution
		address itemBar = registry.addressOf(CONTRACT_LAND_ITEM_BAR);
		uint256 enhanceRate =
			IItemBar(itemBar).enhanceStrengthRateOf(_resource, _landId);
		uint256 landBalance =
			minedBalance.mul(RATE_PRECISION).div(
				enhanceRate.add(RATE_PRECISION)
			);
		if (enhanceRate > 0) {
			uint256 itemBalance = minedBalance.sub(landBalance);
			for (uint256 i = 0; i < IItemBar(itemBar).maxAmount(); i++) {
				uint256 barRate =
					IItemBar(itemBar).enhanceStrengthRateByIndex(
						_resource,
						_landId,
						i
					);
				uint256 barBalance = itemBalance.mul(barRate).div(enhanceRate);
				address barStaker = IItemBar(itemBar).getBarStaker(_landId, i);
				if (barStaker == address(0)) {
					continue;
				}
				//TODO:: give fee to lander
				land2BarMinedBalance[_landId][barStaker][
					_resource
				] = land2BarMinedBalance[_landId][barStaker][_resource].add(
					barBalance
				);
			}
		}

		land2RSState[_landId][_resource].minedBalance = getLandMinedBalance(
			_landId,
			_resource
		)
			.add(landBalance);
	}

	function _claimBarResource(uint256 _landId, address _resource)
		internal
		returns (uint256)
	{
		if (getBarMinedBalance(_landId, msg.sender, _resource) > 0) {
			uint256 balance =
				getBarMinedBalance(_landId, msg.sender, _resource);
			IMintableERC20(_resource).mint(msg.sender, balance);
			land2BarMinedBalance[_landId][msg.sender][_resource] = 0;
			return balance;
		} else {
			return 0;
		}
	}

	function claimBarResource(uint256 _landId) public {
		address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
		address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
		address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
		address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
		address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);

		uint256 goldBalance = _claimBarResource(_landId, gold);
		uint256 woodBalance = _claimBarResource(_landId, wood);
		uint256 waterBalance = _claimBarResource(_landId, water);
		uint256 fireBalance = _claimBarResource(_landId, fire);
		uint256 soilBalance = _claimBarResource(_landId, soil);

		emit ResourceClaimed(
			msg.sender,
			_landId,
			goldBalance,
			woodBalance,
			waterBalance,
			fireBalance,
			soilBalance
		);
	}

	function _claimLandResource(uint256 _landId, address _resource)
		internal
		returns (uint256)
	{
		if (getLandMinedBalance(_landId, _resource) > 0) {
			uint256 balance = getLandMinedBalance(_landId, _resource);
			IMintableERC20(_resource).mint(msg.sender, balance);
			land2RSState[_landId][_resource].minedBalance = 0;
			return balance;
		} else {
			return 0;
		}
	}

	function claimLandResource(uint256 _landId) public {
		require(isLander(_landId, msg.sender), "Land: ONLY_LANDER");

		address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
		address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
		address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
		address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
		address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);

		uint256 goldBalance = _claimLandResource(_landId, gold);
		uint256 woodBalance = _claimLandResource(_landId, wood);
		uint256 waterBalance = _claimLandResource(_landId, water);
		uint256 fireBalance = _claimLandResource(_landId, fire);
		uint256 soilBalance = _claimLandResource(_landId, soil);

		emit ResourceClaimed(
			msg.sender,
			_landId,
			goldBalance,
			woodBalance,
			waterBalance,
			fireBalance,
			soilBalance
		);
	}

	function claimAllResource(uint256 _landId) public {
		require(
			isLander(_landId, msg.sender),
			"Must be the owner of the land."
		);

		settle(_landId);
		claimLandResource(_landId);
		claimBarResource(_landId);
	}

	function _calculateResources(
		address _to,
		uint256 _landId,
		address _resource,
		uint256 _minedBalance
	) internal view returns (uint256 landResource, uint256 barResource) {
		address itemBar = registry.addressOf(CONTRACT_LAND_ITEM_BAR);
		uint256 enhanceRate =
			IItemBar(itemBar).enhanceStrengthRateOf(_resource, _landId);
		// V5 yeild distribution
		uint256 landBalance =
			_minedBalance.mul(RATE_PRECISION).div(
				enhanceRate.add(RATE_PRECISION)
			);

		if (isLander(_landId, _to)) {
			landResource = landResource.add(landBalance);
		}
		if (enhanceRate > 0) {
			uint256 itemBalance = _minedBalance.sub(landBalance);
			for (uint256 i = 0; i < IItemBar(itemBar).maxAmount(); i++) {
				uint256 barRate =
					IItemBar(itemBar).enhanceStrengthRateByIndex(
						_resource,
						_landId,
						i
					);
				uint256 barBalance = itemBalance.mul(barRate).div(enhanceRate);
				//TODO:: give fee to lander
				if (_to == IItemBar(itemBar).getBarStaker(_landId, i)) {
					barResource = barResource.add(barBalance);
				}
			}
		}
		return;
	}

	function availableResources(
		address _to,
		uint256 _landId,
		address[5] _resources
	)
		public
		view
		returns (
			uint256[2],
			uint256[2],
			uint256[2],
			uint256[2],
			uint256[2]
		)
	{
		uint256[2][5] memory availables;
		for (uint256 i = 0; i < 5; i++) {
			uint256 mined = _calculateMinedBalance(_landId, _resources[i], now);

			uint256[2] available;
			(available[0], available[1]) = _calculateResources(
				_to,
				_landId,
				_resources[i],
				mined
			);
			if (isLander(_landId, _to)) {
				available[0] = available[0].add(
					getLandMinedBalance(_landId, _resources[i])
				);
			}
			available[1] = available[1].add(
				land2BarMinedBalance[_landId][_to][_resources[i]]
			);
			availables[i] = available;
		}
		return (
			availables[0],
			availables[1],
			availables[2],
			availables[3],
			availables[4]
		);
	}
}
