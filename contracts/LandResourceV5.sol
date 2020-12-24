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

	mapping(uint256 => ResourceMineState) public land2ResourceMineState;

	struct MinerStatus {
		uint256 landId;
		address resource;
		uint64 indexInResource;
	}
	mapping(uint256 => MinerStatus) public miner2Index;

	/*
	 *  Event
	 */

	event LandResourceClaimed(
		address owner,
		uint256 landId,
		uint256 goldBalance,
		uint256 woodBalance,
		uint256 waterBalance,
		uint256 fireBalance,
		uint256 soilBalance
	);

	event ItemResourceClaimed(
		address owner,
		uint256 itemTokenId,
		uint256 goldBalance,
		uint256 woodBalance,
		uint256 waterBalance,
		uint256 fireBalance,
		uint256 soilBalance
	);

	// V5 change
	// event StartMining(uint256 minerTokenId, uint256 landId, address _resource, uint256 strength);
	// event StopMining(uint256 minerTokenId, uint256 landId, address _resource, uint256 strength);

	// event UpdateMiningStrengthWhenStop(uint256 apostleTokenId, uint256 landId, uint256 strength);
	// event UpdateMiningStrengthWhenStart(uint256 apostleTokenId, uint256 landId, uint256 strength);

	// v5 add
	event StartMining(
		uint256 minerTokenId,
		uint256 landId,
		address resource,
		uint256 minerStrength,
		uint256 enhancedStrengh
	);
	event StopMining(
		uint256 minerTokenId,
		uint256 landId,
		address _resource,
		uint256 strength,
		uint256 enhancedStrength
	);
	event UpdateMiningStrengthWhenStop(
		uint256 apostleTokenId,
		uint256 landId,
		uint256 strength,
		uint256 enhancedStrength
	);
	event UpdateMiningStrengthWhenStart(
		uint256 apostleTokenId,
		uint256 landId,
		uint256 strength,
		uint256 enhancedStrength
	);
	event UpdateEnhancedStrengthByElement(
		uint256 landId,
		address resourceToken,
		uint256 enhancedStrength
	);

	// 0x434f4e54524143545f4c414e445f4954454d5f42415200000000000000000000
	bytes32 public constant CONTRACT_LAND_ITEM_BAR = "CONTRACT_LAND_ITEM_BAR";

	//0x4655524e4143455f4954454d5f4d494e455f4645450000000000000000000000
	bytes32 public constant FURNACE_ITEM_MINE_FEE = "FURNACE_ITEM_MINE_FEE";

	// rate precision
	uint128 public constant RATE_PRECISION = 10**8;

	uint256 maxMiners;

	// owner may be more simple
	mapping(address => mapping(uint256 => mapping(address => uint256)))
		public land2ItemMinedBalance;
	mapping(uint256 => mapping(address => uint256))
		public land2BarEnhancedStrength;

	ERC721 public ownership;
	IInterstellarEncoder public interstellarEncoder;
	ITokenUse public tokenuse;
	IItemBar public itembar;
	ILandBase public landbase;
	address public gold;
	address public wood;
	address public water;
	address public fire;
	address public soil;

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

		refresh();
	}

	function refresh() public auth {
		ownership = ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP));
		interstellarEncoder = IInterstellarEncoder(
			registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)
		);
		tokenuse = ITokenUse(registry.addressOf(CONTRACT_TOKEN_USE));
		itembar = IItemBar(registry.addressOf(CONTRACT_LAND_ITEM_BAR));
		landbase = ILandBase(registry.addressOf(CONTRACT_LAND_BASE));

		gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
		wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
		water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
		fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
		soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);
	}

	function getLandMinedBalance(uint256 _landId, address _resource)
		public
		view
		returns (uint256)
	{
		return land2ResourceMineState[_landId].mintedBalance[_resource];
	}

	function getItemMinedBalance(
		address _itemToken,
		uint256 _itemId,
		address _resource
	) public view returns (uint256) {
		return land2ItemMinedBalance[_itemToken][_itemId][_resource];
	}

	function getLandMiningStrength(uint256 _landId, address _resource)
		public
		view
		returns (uint256)
	{
		return land2ResourceMineState[_landId].totalMinerStrength[_resource];
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

	function getMinerOnLand(
		uint256 _landId,
		address _resource,
		uint256 _index
	) public view returns (uint256) {
		return land2ResourceMineState[_landId].miners[_resource][_index];
	}

	function landWorkingOn(uint256 _apostleTokenId)
		public
		view
		returns (uint256 landId)
	{
		landId = miner2Index[_apostleTokenId].landId;
	}

	// get amount of speed uint at this moment
	function _getReleaseSpeedInSeconds(uint256 _tokenId, uint256 _time)
		internal
		view
		returns (uint256 currentSpeed)
	{
		require(_time >= resourceReleaseStartTime, "Landrs: TOO_EARLY");
		require(
			_time >= land2ResourceMineState[_tokenId].lastUpdateTime,
			"Landrs: TIME_ERROR"
		);

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
			landbase
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
			landbase
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

	function setMaxMiners(uint256 _maxMiners) public auth {
		require(_maxMiners > maxMiners, "Land: INVALID_MAXMINERS");
		maxMiners = _maxMiners;
	}

	function mine(uint256 _landId) public {
		_mineAllResource(_landId);
	}

	function _mineAllResource(uint256 _landId) internal {
		require(
			interstellarEncoder.getObjectClass(_landId) == 1,
			"Land: INVAID_TOKENID"
		);

		// if (land2ResourceMineState[_landId].lastUpdateTime == 0) {
		//     land2ResourceMineState[_landId].lastUpdateTime = uint128(resourceReleaseStartTime);
		//     land2ResourceMineState[_landId].lastUpdateSpeedInSeconds = TOTAL_SECONDS;
		// }

		_mineResource(_landId, gold);
		_mineResource(_landId, wood);
		_mineResource(_landId, water);
		_mineResource(_landId, fire);
		_mineResource(_landId, soil);

		// land2ResourceMineState[_landId].lastUpdateSpeedInSeconds = _getReleaseSpeedInSeconds(_landId, now);
		land2ResourceMineState[_landId].lastUpdateTime = uint128(now);
	}

	function _mineResource(uint256 _landId, address _resource) internal {
		if (getLandMiningStrength(_landId, _resource) == 0) {
			return;
		}
		// the longest seconds to zero speed.
		uint256 minedBalance = _calculateMinedBalance(_landId, _resource, now);
		if (minedBalance == 0) {
			return;
		}

		if (getBarMiningStrength(_landId, _resource) > 0) {
			// V5 yeild distribution
			uint256 enhanceRate =
				itembar.enhanceStrengthRateOf(_resource, _landId);
			uint256 landBalance =
				minedBalance.mul(RATE_PRECISION).div(
					enhanceRate.add(RATE_PRECISION)
				);
			if (enhanceRate > 0) {
				uint256 itemBalance = minedBalance.sub(landBalance);
				for (uint256 i = 0; i < itembar.maxAmount(); i++) {
					(address itemToken, uint256 itemId) =
						itembar.getBarItem(_landId, i);
					if (itemToken != address(0)) {
						uint256 barRate =
							itembar.enhanceStrengthRateByIndex(
								_resource,
								_landId,
								i
							);

						uint256 barBalance =
							itemBalance.mul(barRate).div(enhanceRate);
						uint256 fee =
							barBalance
								.mul(registry.uintOf(FURNACE_ITEM_MINE_FEE))
								.div(RATE_PRECISION);
						barBalance = barBalance.sub(fee);
						landBalance = landBalance.add(fee);
						land2ItemMinedBalance[itemToken][itemId][
							_resource
						] = getItemMinedBalance(itemToken, itemId, _resource)
							.add(barBalance);
					}
				}
			}
		}

		land2ResourceMineState[_landId].mintedBalance[
			_resource
		] = getLandMinedBalance(_landId, _resource).add(landBalance);
	}

	function _calculateMinedBalance(
		uint256 _landId,
		address _resource,
		uint256 _currentTime
	) internal returns (uint256) {
		uint256 currentTime =
			_currentTime.min256((resourceReleaseStartTime + TOTAL_SECONDS));
		uint256 lastUpdateTime = land2ResourceMineState[_landId].lastUpdateTime;
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
		address miner = interstellarEncoder.getObjectAddress(_tokenId);
		return IMinerObject(miner).strengthOf(_tokenId, _resource, _landId);
	}

	function _enhancedStrengthOf(
		uint256 _strength,
		uint256 _landId,
		address _resource
	) internal returns (uint256) {
		return
			_strength
				.mul(itembar.enhanceStrengthRateOf(_resource, _landId))
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
			land2ResourceMineState[_landId].totalMinerStrength[
				_resource
			] = getLandMiningStrength(_landId, _resource).sub(strength);

			land2BarEnhancedStrength[_landId][
				_resource
			] = land2BarEnhancedStrength[_landId][_resource].sub(
				enhancedStrength
			);
		} else {
			land2ResourceMineState[_landId].totalMinerStrength[
				_resource
			] = getLandMiningStrength(_landId, _resource).add(strength);

			land2BarEnhancedStrength[_landId][
				_resource
			] = land2BarEnhancedStrength[_landId][_resource].add(
				enhancedStrength
			);
		}
		return (strength, enhancedStrength);
	}

	function startMining(
		uint256 _tokenId,
		uint256 _landId,
		address _resource
	) public {
		tokenuse.addActivity(_tokenId, msg.sender, 0);
		// require the permission from land owner;
		require(isOwner(_landId, msg.sender), "Land: ONLY_LANDER");
		uint256 _index =
			land2ResourceMineState[_landId].miners[_resource].length;
		land2ResourceMineState[_landId].totalMiners += 1;
		require(land2ResourceMineState[_landId].totalMiners <= maxMiners);

		// make sure that _tokenId won't be used repeatedly
		require(miner2Index[_tokenId].landId == 0, "Land: REPEATED_MINING");

		// update status!
		mine(_landId);

		(uint256 strength, uint256 enhancedStrength) =
			_updateStrength(_tokenId, _landId, _resource, false);

		land2ResourceMineState[_landId].miners[_resource].push(_tokenId);

		miner2Index[_tokenId] = MinerStatus({
			landId: _landId,
			resource: _resource,
			indexInResource: uint64(_index)
		});

		emit StartMining(
			_tokenId,
			_landId,
			_resource,
			strength,
			enhancedStrength
		);
	}

	function batchStartMining(
		uint256[] _tokenIds,
		uint256[] _landIds,
		address[] _resources
	) public {
		require(
			_tokenIds.length == _landIds.length &&
				_landIds.length == _resources.length,
			"Land: INVALID_INPUT"
		);
		uint256 length = _tokenIds.length;

		for (uint256 i = 0; i < length; i++) {
			startMining(_tokenIds[i], _landIds[i], _resources[i]);
		}
	}

	function batchClaimLandResource(uint256[] _landIds) public {
		uint256 length = _landIds.length;

		for (uint256 i = 0; i < length; i++) {
			claimLandResource(_landIds[i]);
		}
	}

	// Only trigger from Token Activity.
	function activityStopped(uint256 _tokenId) public auth {
		_stopMining(_tokenId);
	}

	function stopMining(uint256 _tokenId) public {
		tokenuse.removeActivity(_tokenId, msg.sender);
	}

	function _stopMining(uint256 _tokenId) internal {
		uint64 minerIndex = miner2Index[_tokenId].indexInResource;
		address resource = miner2Index[_tokenId].resource;
		uint256 landId = miner2Index[_tokenId].landId;

		require(landId != 0, "Land: NO_MINER");

		mine(landId);

		uint64 lastMinerIndex =
			uint64(
				land2ResourceMineState[landId].miners[resource].length.sub(1)
			);
		uint256 lastMiner =
			land2ResourceMineState[landId].miners[resource][lastMinerIndex];
		land2ResourceMineState[landId].miners[resource][minerIndex] = lastMiner;
		land2ResourceMineState[landId].miners[resource][lastMinerIndex] = 0;
		land2ResourceMineState[landId].miners[resource].length -= 1;
		miner2Index[lastMiner].indexInResource = minerIndex;
		land2ResourceMineState[landId].totalMiners -= 1;

		(uint256 strength, uint256 enhancedStrength) =
			_updateStrength(_tokenId, landId, resource, true);

		if (land2ResourceMineState[landId].totalMiners == 0) {
			land2ResourceMineState[landId].totalMinerStrength[resource] = 0;
			land2BarEnhancedStrength[landId][resource] = 0;
		}

		delete miner2Index[_tokenId];

		emit StopMining(_tokenId, landId, resource, strength, enhancedStrength);
	}

	function updateMinerStrengthWhenStop(uint256 _apostleTokenId) public auth {
		(uint256 landId, uint256 strength, uint256 enhancedStrength) =
			_updateMinerStrength(_apostleTokenId, true);
		// _isStop == true - minus strength
		// _isStop == false - add strength
		emit UpdateMiningStrengthWhenStop(
			_apostleTokenId,
			landId,
			strength,
			enhancedStrength
		);
	}

	function updateMinerStrengthWhenStart(uint256 _apostleTokenId) public auth {
		(uint256 landId, uint256 strength, uint256 enhancedStrength) =
			_updateMinerStrength(_apostleTokenId, false);
		// _isStop == true - minus strength
		// _isStop == false - add strength
		emit UpdateMiningStrengthWhenStart(
			_apostleTokenId,
			landId,
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
		uint256 landId = landWorkingOn(_apostleTokenId);
		require(landId != 0, "this apostle is not mining.");
		address resource = miner2Index[_apostleTokenId].resource;
		if (_isStop) {
			mine(landId);
		}
		(uint256 strength, uint256 enhancedStrength) =
			_updateStrength(_apostleTokenId, landId, resource, _isStop);
		return (landId, strength, enhancedStrength);
	}

	// function beforeUpdateMinerStrength(uint256 _apostleId) public auth {
	// 	mine(_landId);
	// }

	// function afterUpdateMinerStrength(uint256 _apostleId) public auth {
	// }

	// can only be called by ItemBar
	// _isStop == true - minus strength
	function updateAllMinerStrengthWhenStop(uint256 _landId) public auth {
		mine(_landId);
	}

	// can only be called by ItemBar
	// _isStop == false - add strength
	function updateAllMinerStrengthWhenStart(uint256 _landId) public auth {
		_updateEnhancedStrengthByElement(_landId, gold);
		_updateEnhancedStrengthByElement(_landId, wood);
		_updateEnhancedStrengthByElement(_landId, water);
		_updateEnhancedStrengthByElement(_landId, fire);
		_updateEnhancedStrengthByElement(_landId, soil);
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

	function isOwner(uint256 _tokenId, address _to)
		internal
		view
		returns (bool)
	{
		return _to == ownership.ownerOf(_tokenId);
	}

	function _claimItemResource(
		address _itemToken,
		uint256 _itemId,
		address _resource
	) internal returns (uint256) {
		uint256 balance = getItemMinedBalance(_itemToken, _itemId, _resource);
		if (balance > 0) {
			IMintableERC20(_resource).mint(msg.sender, balance);
			land2ItemMinedBalance[_itemToken][_itemId][_resource] = 0;
			return balance;
		} else {
			return 0;
		}
	}

	function claimItemResource(address _itemToken, uint256 _itemId) public {
		(address staker, uint256 landId) =
			itembar.getTokenIdByItem(_itemToken, _itemId);
		if (staker == address(0) && landId == 0) {
			require(
				ERC721(_itemToken).ownerOf(_itemId) == msg.sender,
				"Land: ONLY_ITEM_ONWER"
			);
		} else {
			require(staker == msg.sender, "Land: ONLY_ITEM_STAKER");
			mine(landId);
		}

		uint256 goldBalance = _claimItemResource(_itemToken, _itemId, gold);
		uint256 woodBalance = _claimItemResource(_itemToken, _itemId, wood);
		uint256 waterBalance = _claimItemResource(_itemToken, _itemId, water);
		uint256 fireBalance = _claimItemResource(_itemToken, _itemId, fire);
		uint256 soilBalance = _claimItemResource(_itemToken, _itemId, soil);

		emit ItemResourceClaimed(
			msg.sender,
			_itemId,
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
		uint256 balance = getLandMinedBalance(_landId, _resource);
		if (balance > 0) {
			IMintableERC20(_resource).mint(msg.sender, balance);
			land2ResourceMineState[_landId].mintedBalance[_resource] = 0;
			return balance;
		} else {
			return 0;
		}
	}

	function claimLandResource(uint256 _landId) public {
		require(isOwner(_landId, msg.sender), "Land: ONLY_LANDER");

		mine(_landId);
		uint256 goldBalance = _claimLandResource(_landId, gold);
		uint256 woodBalance = _claimLandResource(_landId, wood);
		uint256 waterBalance = _claimLandResource(_landId, water);
		uint256 fireBalance = _claimLandResource(_landId, fire);
		uint256 soilBalance = _claimLandResource(_landId, soil);

		emit LandResourceClaimed(
			msg.sender,
			_landId,
			goldBalance,
			woodBalance,
			waterBalance,
			fireBalance,
			soilBalance
		);
	}

	function _calculateResources(
		address _itemToken,
		uint256 _itemId,
		uint256 _landId,
		address _resource,
		uint256 _minedBalance
	) internal view returns (uint256 landBalance, uint256 barResource) {
		uint256 enhanceRate = itembar.enhanceStrengthRateOf(_resource, _landId);
		// V5 yeild distribution
		landBalance = _minedBalance.mul(RATE_PRECISION).div(
			enhanceRate.add(RATE_PRECISION)
		);

		if (enhanceRate > 0) {
			uint256 itemBalance = _minedBalance.sub(landBalance);
			for (uint256 i = 0; i < itembar.maxAmount(); i++) {
				uint256 barRate =
					itembar.enhanceStrengthRateByIndex(_resource, _landId, i);

				uint256 barBalance = itemBalance.mul(barRate).div(enhanceRate);
				uint256 fee =
					barBalance.mul(registry.uintOf(FURNACE_ITEM_MINE_FEE)).div(
						RATE_PRECISION
					);
				barBalance = barBalance.sub(fee);
				landBalance = landBalance.add(fee);
				(address itemToken, uint256 itemId) =
					itembar.getBarItem(_landId, i);
				if (_itemId == itemId && _itemToken == itemToken) {
					barResource = barResource.add(barBalance);
				}
			}
		}
		return;
	}

	function availableLandResources(
		uint256 _landId,
		address[] memory _resources
	) public view returns (uint256[] memory) {
		uint256[] memory availables = new uint256[](_resources.length);
		for (uint256 i = 0; i < _resources.length; i++) {
			uint256 mined = _calculateMinedBalance(_landId, _resources[i], now);

			(uint256 available, ) =
				_calculateResources(
					address(0),
					0,
					_landId,
					_resources[i],
					mined
				);
			available = available.add(
				getLandMinedBalance(_landId, _resources[i])
			);
			availables[i] = available;
		}
		return availables;
	}

	function availableItemResources(
		address _itemToken,
		uint256 _itemId,
		address[] memory _resources
	) public view returns (uint256[] memory) {
		uint256[] memory availables = new uint256[](_resources.length);
		for (uint256 i = 0; i < _resources.length; i++) {
			(address staker, uint256 landId) =
				itembar.getTokenIdByItem(_itemToken, _itemId);
			uint256 available = 0;
			if (staker != address(0) && landId != 0) {
				uint256 mined =
					_calculateMinedBalance(landId, _resources[i], now);
				(, uint256 availableItem) =
					_calculateResources(
						_itemToken,
						_itemId,
						landId,
						_resources[i],
						mined
					);
				available = available.add(availableItem);
			}
			available = available.add(
				getItemMinedBalance(_itemToken, _itemId, _resources[i])
			);
			availables[i] = available;
		}
		return availables;
	}
}
