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

	event StartMining(
		uint256 minerTokenId,
		uint256 landId,
		address _resource,
		uint256 strength
	);
	event StopMining(
		uint256 minerTokenId,
		uint256 landId,
		address _resource,
		uint256 strength
	);
	event ResourceClaimed(
		address owner,
		uint256 landTokenId,
		uint256 goldBalance,
		uint256 woodBalance,
		uint256 waterBalance,
		uint256 fireBalance,
		uint256 soilBalance
	);
	event UpdateMiningStrengthWhenStop(
		uint256 apostleTokenId,
		uint256 landId,
		uint256 strength
	);
	event UpdateMiningStrengthWhenStart(
		uint256 apostleTokenId,
		uint256 landId,
		uint256 strength
	);

	// v5 add begin
	event StartBarMining(
		uint256 barIndex,
		uint256 landId,
		address resource,
		uint256 enhancedStrengh
	);
	event StopBarMining(uint256 barIndex, uint256 landId, address resource);
	event UpdateBarMiningStrength(
		uint256 index,
		uint256 landId,
		address resource,
		uint256 enhancedStrength
	);
	// event SettleBar(
	// 	uint256 index,
	// 	uint256 landId,
	// 	address resource,
	// 	address itemToken,
	// 	uint256 itemId,
	// 	uint256 barMinedBalance
	// );
	event ItemResourceClaimed(
		address owner,
		address itemToken,
		uint256 itemTokenId,
		uint256 goldBalance,
		uint256 woodBalance,
		uint256 waterBalance,
		uint256 fireBalance,
		uint256 soilBalance
	);

	// 0x434f4e54524143545f4c414e445f4954454d5f42415200000000000000000000
	bytes32 public constant CONTRACT_LAND_ITEM_BAR = "CONTRACT_LAND_ITEM_BAR";

	//0x4655524e4143455f4954454d5f4d494e455f4645450000000000000000000000
	bytes32 public constant FURNACE_ITEM_MINE_FEE = "FURNACE_ITEM_MINE_FEE";

	// rate precision
	uint128 public constant RATE_PRECISION = 10**8;

	uint256 maxMiners;

	mapping(address => mapping(uint256 => mapping(address => uint256)))
		public itemMinedBalance;

	mapping(uint256 => mapping(address => mapping(uint256 => uint256)))
		public land2BarStrength;
	// v5 add end

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

		_registerInterface(InterfaceId_IActivity);
	}

	// get amount of speed uint at this moment
	function _getReleaseSpeedInSeconds(uint256 _tokenId, uint256 _time)
		internal
		view
		returns (uint256 currentSpeed)
	{
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

	function _getBarMaxMineBalance(
		uint256 _tokenId,
		address _resource,
		uint256 _index,
		uint256 _currentTime,
		uint256 _lastUpdateTime
	) internal view returns (uint256) {
		// totalMinerStrength is in wei
		return
			getBarMiningStrength(_tokenId, _resource, _index)
				.mul(_currentTime - _lastUpdateTime)
				.div(1 days);
	}

	function setMaxMiners(uint256 _maxMiners) public auth {
		require(_maxMiners > maxMiners, "Land: INVALID_MAXMINERS");
		maxMiners = _maxMiners;
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

	function _mineAllResource(
		uint256 _landTokenId,
		address _gold,
		address _wood,
		address _water,
		address _fire,
		address _soil
	) internal {
		require(
			IInterstellarEncoder(
				registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)
			)
				.getObjectClass(_landTokenId) == 1,
			"Token must be land."
		);

		if (land2ResourceMineState[_landTokenId].lastUpdateTime == 0) {
			land2ResourceMineState[_landTokenId].lastUpdateTime = uint128(
				resourceReleaseStartTime
			);
			land2ResourceMineState[_landTokenId]
				.lastUpdateSpeedInSeconds = TOTAL_SECONDS;
		}

		_mineResource(_landTokenId, _gold);
		_mineResource(_landTokenId, _wood);
		_mineResource(_landTokenId, _water);
		_mineResource(_landTokenId, _fire);
		_mineResource(_landTokenId, _soil);

		land2ResourceMineState[_landTokenId]
			.lastUpdateSpeedInSeconds = _getReleaseSpeedInSeconds(
			_landTokenId,
			now
		);

		land2ResourceMineState[_landTokenId].lastUpdateTime = uint128(now);
	}

	function _distribution(uint256 _landId, address _resource, uint256 minedBalance, uint256 landStrength, uint256 barsStrength) internal returns (uint256) {
		uint256 landBalance =
			minedBalance.mul(landStrength).div(
				landStrength.add(barsStrength)
			);
		IItemBar itembar = IItemBar(registry.addressOf(CONTRACT_LAND_ITEM_BAR));
		for (uint256 i = 0; i < itembar.maxAmount(); i++) {
			(address itemToken, uint256 itemId,) =
				itembar.getBarItem(_landId, i);
			if (itemToken != address(0)) {
				if (getBarMiningStrength(_landId, _resource, i) > 0) {
					uint256 barBalance =
						minedBalance.sub(landBalance).mul(getBarMiningStrength(_landId, _resource, i)).div(barsStrength);
					(barBalance, landBalance) = _payFee(barBalance, landBalance);
					itemMinedBalance[itemToken][itemId][
						_resource
					] = getItemMinedBalance(itemToken, itemId, _resource)
						.add(barBalance);
				}
			}
		}
		return landBalance;
	}

	function _payFee(uint256 barBalance, uint256 landBalance) internal returns (uint256, uint256) {
		uint256 fee =
			barBalance
				.mul(registry.uintOf(FURNACE_ITEM_MINE_FEE))
				.div(RATE_PRECISION);
		barBalance = barBalance.sub(fee);
		landBalance = landBalance.add(fee);
		return (barBalance, landBalance);
	}

	function _mineResource(uint256 _landId, address _resource) internal {
		uint256 landStrength = getLandMiningStrength(_landId, _resource);
		if (landStrength == 0) {
			return;
		}
		// the longest seconds to zero speed.
		uint256 minedBalance = _calculateMinedBalance(_landId, _resource, now);
		if (minedBalance == 0) {
			return;
		}

		uint256 barsStrength = getBarsMiningStrength(_landId, _resource);
		uint256 landBalance = minedBalance;
		if (barsStrength > 0) {
			// V5 yeild distribution
			landBalance = _distribution(_landId, _resource, minedBalance, landStrength, barsStrength);
		}
		land2ResourceMineState[_landId].mintedBalance[
			_resource
		] = getLandMinedBalance(_landId, _resource).add(landBalance);
	}

	function _calculateMinedBalance(
		uint256 _landTokenId,
		address _resourceToken,
		uint256 _currentTime
	) internal returns (uint256) {
		uint256 currentTime = _currentTime;

		uint256 minedBalance;
		uint256 minableBalance;
		if (currentTime > (resourceReleaseStartTime + TOTAL_SECONDS)) {
			currentTime = (resourceReleaseStartTime + TOTAL_SECONDS);
		}

		uint256 lastUpdateTime =
			land2ResourceMineState[_landTokenId].lastUpdateTime;
		require(currentTime >= lastUpdateTime);

		if (lastUpdateTime >= (resourceReleaseStartTime + TOTAL_SECONDS)) {
			minedBalance = 0;
			minableBalance = 0;
		} else {
			minedBalance = _getMaxMineBalance(
				_landTokenId,
				_resourceToken,
				currentTime,
				lastUpdateTime
			);
			minableBalance = _getMinableBalance(
				_landTokenId,
				_resourceToken,
				currentTime,
				lastUpdateTime
			);
		}

		if (minedBalance > minableBalance) {
			minedBalance = minableBalance;
		}

		return minedBalance;
	}

	function claimAllResource(uint256 _landTokenId) public {
		require(
			msg.sender ==
				ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(
					_landTokenId
				),
			"Must be the owner of the land"
		);

		address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
		address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
		address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
		address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
		address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);

		_mineAllResource(_landTokenId, gold, wood, water, fire, soil);

		uint256 goldBalance;
		uint256 woodBalance;
		uint256 waterBalance;
		uint256 fireBalance;
		uint256 soilBalance;

		if (land2ResourceMineState[_landTokenId].mintedBalance[gold] > 0) {
			goldBalance = land2ResourceMineState[_landTokenId].mintedBalance[
				gold
			];
			IMintableERC20(gold).mint(msg.sender, goldBalance);
			land2ResourceMineState[_landTokenId].mintedBalance[gold] = 0;
		}

		if (land2ResourceMineState[_landTokenId].mintedBalance[wood] > 0) {
			woodBalance = land2ResourceMineState[_landTokenId].mintedBalance[
				wood
			];
			IMintableERC20(wood).mint(msg.sender, woodBalance);
			land2ResourceMineState[_landTokenId].mintedBalance[wood] = 0;
		}

		if (land2ResourceMineState[_landTokenId].mintedBalance[water] > 0) {
			waterBalance = land2ResourceMineState[_landTokenId].mintedBalance[
				water
			];
			IMintableERC20(water).mint(msg.sender, waterBalance);
			land2ResourceMineState[_landTokenId].mintedBalance[water] = 0;
		}

		if (land2ResourceMineState[_landTokenId].mintedBalance[fire] > 0) {
			fireBalance = land2ResourceMineState[_landTokenId].mintedBalance[
				fire
			];
			IMintableERC20(fire).mint(msg.sender, fireBalance);
			land2ResourceMineState[_landTokenId].mintedBalance[fire] = 0;
		}

		if (land2ResourceMineState[_landTokenId].mintedBalance[soil] > 0) {
			soilBalance = land2ResourceMineState[_landTokenId].mintedBalance[
				soil
			];
			IMintableERC20(soil).mint(msg.sender, soilBalance);
			land2ResourceMineState[_landTokenId].mintedBalance[soil] = 0;
		}

		emit ResourceClaimed(
			msg.sender,
			_landTokenId,
			goldBalance,
			woodBalance,
			waterBalance,
			fireBalance,
			soilBalance
		);
	}

	// both for own _tokenId or hired one
	function startMining(
		uint256 _tokenId,
		uint256 _landTokenId,
		address _resource
	) public {
		ITokenUse tokenUse = ITokenUse(registry.addressOf(CONTRACT_TOKEN_USE));

		tokenUse.addActivity(_tokenId, msg.sender, 0);

		// require the permission from land owner;
		require(
			msg.sender ==
				ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(
					_landTokenId
				),
			"Must be the owner of the land"
		);

		// make sure that _tokenId won't be used repeatedly
		require(miner2Index[_tokenId].landTokenId == 0);

		// update status!
		mine(_landTokenId);

		uint256 _index =
			land2ResourceMineState[_landTokenId].miners[_resource].length;

		land2ResourceMineState[_landTokenId].totalMiners += 1;

		if (land2ResourceMineState[_landTokenId].maxMiners == 0) {
			land2ResourceMineState[_landTokenId].maxMiners = 5;
		}

		require(
			land2ResourceMineState[_landTokenId].totalMiners <=
				land2ResourceMineState[_landTokenId].maxMiners
		);

		address miner =
			IInterstellarEncoder(
				registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)
			)
				.getObjectAddress(_tokenId);
		uint256 strength =
			IMinerObject(miner).strengthOf(_tokenId, _resource, _landTokenId);

		land2ResourceMineState[_landTokenId].miners[_resource].push(_tokenId);
		land2ResourceMineState[_landTokenId].totalMinerStrength[
			_resource
		] += strength;

		miner2Index[_tokenId] = MinerStatus({
			landTokenId: _landTokenId,
			resource: _resource,
			indexInResource: uint64(_index)
		});

		//v5 add
		_updateBarsStrength(_landTokenId, _resource);

		emit StartMining(_tokenId, _landTokenId, _resource, strength);
	}

	function batchStartMining(
		uint256[] _tokenIds,
		uint256[] _landTokenIds,
		address[] _resources
	) public {
		require(
			_tokenIds.length == _landTokenIds.length &&
				_landTokenIds.length == _resources.length,
			"input error"
		);
		uint256 length = _tokenIds.length;

		for (uint256 i = 0; i < length; i++) {
			startMining(_tokenIds[i], _landTokenIds[i], _resources[i]);
		}
	}

	function batchClaimAllResource(uint256[] _landTokenIds) public {
		uint256 length = _landTokenIds.length;

		for (uint256 i = 0; i < length; i++) {
			claimAllResource(_landTokenIds[i]);
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
		// remove the miner from land2ResourceMineState;
		uint64 minerIndex = miner2Index[_tokenId].indexInResource;
		address resource = miner2Index[_tokenId].resource;
		uint256 landTokenId = miner2Index[_tokenId].landTokenId;

		// update status!
		mine(landTokenId);

		uint64 lastMinerIndex =
			uint64(
				land2ResourceMineState[landTokenId].miners[resource].length.sub(
					1
				)
			);
		uint256 lastMiner =
			land2ResourceMineState[landTokenId].miners[resource][
				lastMinerIndex
			];

		land2ResourceMineState[landTokenId].miners[resource][
			minerIndex
		] = lastMiner;
		land2ResourceMineState[landTokenId].miners[resource][
			lastMinerIndex
		] = 0;

		land2ResourceMineState[landTokenId].miners[resource].length -= 1;
		miner2Index[lastMiner].indexInResource = minerIndex;

		land2ResourceMineState[landTokenId].totalMiners -= 1;

		address miner =
			IInterstellarEncoder(
				registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)
			)
				.getObjectAddress(_tokenId);
		uint256 strength =
			IMinerObject(miner).strengthOf(_tokenId, resource, landTokenId);

		// for backward compatibility
		// if strength can fluctuate some time in the future
		if (
			land2ResourceMineState[landTokenId].totalMinerStrength[resource] !=
			0
		) {
			if (
				land2ResourceMineState[landTokenId].totalMinerStrength[
					resource
				] > strength
			) {
				land2ResourceMineState[landTokenId].totalMinerStrength[
					resource
				] = land2ResourceMineState[landTokenId].totalMinerStrength[
					resource
				]
					.sub(strength);
			} else {
				land2ResourceMineState[landTokenId].totalMinerStrength[
					resource
				] = 0;
			}
		}

		if (land2ResourceMineState[landTokenId].totalMiners == 0) {
			land2ResourceMineState[landTokenId].totalMinerStrength[
				resource
			] = 0;
		}

		delete miner2Index[_tokenId];

		//v5 add
		_updateBarsStrength(landTokenId, resource);

		emit StopMining(_tokenId, landTokenId, resource, strength);
	}

	// v5 remove
	// function getMinerOnLand(
	// 	uint256 _landTokenId,
	// 	address _resourceToken,
	// 	uint256 _index
	// ) public view returns (uint256) {
	// 	return
	// 		land2ResourceMineState[_landTokenId].miners[_resourceToken][_index];
	// }

	// function getTotalMiningStrength(
	// 	uint256 _landTokenId,
	// 	address _resourceToken
	// ) public view returns (uint256) {
	// 	return
	// 		land2ResourceMineState[_landTokenId].totalMinerStrength[
	// 			_resourceToken
	// 		];
	// }

	function availableResources(
		uint256 _landTokenId,
		address[5] _resourceTokens
	)
		public
		view
		returns (
			uint256,
			uint256,
			uint256,
			uint256,
			uint256
		)
	{
		uint256 availableGold =
			_calculateMinedBalance(_landTokenId, _resourceTokens[0], now) +
				land2ResourceMineState[_landTokenId].mintedBalance[
					_resourceTokens[0]
				];
		uint256 availableWood =
			_calculateMinedBalance(_landTokenId, _resourceTokens[1], now) +
				land2ResourceMineState[_landTokenId].mintedBalance[
					_resourceTokens[1]
				];
		uint256 availableWater =
			_calculateMinedBalance(_landTokenId, _resourceTokens[2], now) +
				land2ResourceMineState[_landTokenId].mintedBalance[
					_resourceTokens[2]
				];
		uint256 availableFire =
			_calculateMinedBalance(_landTokenId, _resourceTokens[3], now) +
				land2ResourceMineState[_landTokenId].mintedBalance[
					_resourceTokens[3]
				];
		uint256 availableSoil =
			_calculateMinedBalance(_landTokenId, _resourceTokens[4], now) +
				land2ResourceMineState[_landTokenId].mintedBalance[
					_resourceTokens[4]
				];

		return (
			availableGold,
			availableWood,
			availableWater,
			availableFire,
			availableSoil
		);
	}

	// V5 remove
	// function mintedBalanceOnLand(uint256 _landTokenId, address _resourceToken) public view returns (uint256) {
	//     return land2ResourceMineState[_landTokenId].mintedBalance[_resourceToken];
	// }

	// function landWorkingOn(uint256 _apostleTokenId) public view returns (uint256 landTokenId) {
	//     landTokenId = miner2Index[_apostleTokenId].landTokenId;
	// }

	function _updateMinerStrength(uint256 _apostleTokenId, bool _isStop)
		internal
		returns (uint256, uint256)
	{
		// require that this apostle
		uint256 landTokenId = landWorkingOn(_apostleTokenId);
		require(landTokenId != 0, "this apostle is not mining.");

		address resource = miner2Index[_apostleTokenId].resource;

		address miner =
			IInterstellarEncoder(
				registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)
			)
				.getObjectAddress(_apostleTokenId);
		uint256 strength =
			IMinerObject(miner).strengthOf(
				_apostleTokenId,
				resource,
				landTokenId
			);

		mine(landTokenId);

		if (_isStop) {
			land2ResourceMineState[landTokenId].totalMinerStrength[
				resource
			] = land2ResourceMineState[landTokenId].totalMinerStrength[resource]
				.sub(strength);
		} else {
			land2ResourceMineState[landTokenId].totalMinerStrength[
				resource
			] += strength;
		}


		//v5 add
		_updateBarsStrength(landTokenId, resource);

		return (landTokenId, strength);
	}

	// when a mirrorToken or a pet has tied to apostle
	// we need to update status and remove this apostle from mining list first
	// open authority to PetBase
	// can only be called by PetBase
	function updateMinerStrengthWhenStop(uint256 _apostleTokenId) public auth {
		uint256 landTokenId;
		uint256 strength;
		(landTokenId, strength) = _updateMinerStrength(_apostleTokenId, true);
		// _isStop == true - minus strength
		// _isStop == false - add strength
		emit UpdateMiningStrengthWhenStop(
			_apostleTokenId,
			landTokenId,
			strength
		);
	}

	function updateMinerStrengthWhenStart(uint256 _apostleTokenId) public auth {
		uint256 landTokenId;
		uint256 strength;
		(landTokenId, strength) = _updateMinerStrength(_apostleTokenId, false);
		// _isStop == true - minus strength
		// _isStop == false - add strength
		emit UpdateMiningStrengthWhenStart(
			_apostleTokenId,
			landTokenId,
			strength
		);
	}

	// V5 add
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
		return itemMinedBalance[_itemToken][_itemId][_resource];
	}

	function getLandMiningStrength(uint256 _landId, address _resource)
		public
		view
		returns (uint256)
	{
		return land2ResourceMineState[_landId].totalMinerStrength[_resource];
	}

	function getBarMiningStrength(
		uint256 _landId,
		address _resource,
		uint256 _index
	) public view returns (uint256) {
		return land2BarStrength[_landId][_resource][_index];
	}

	function getBarsMiningStrength(uint256 _landId, address _resource)
		public
		view
		returns (uint256 barsMiningStrength)
	{
		uint256 maxAmount =
			IItemBar(registry.addressOf(CONTRACT_LAND_ITEM_BAR)).maxAmount();
		for (uint256 i = 0; i < maxAmount; i++) {
			barsMiningStrength = barsMiningStrength.add(
				getBarMiningStrength(_landId, _resource, i)
			);
		}
	}

	function getTotalMiningStrength(uint256 _landId, address _resource)
		public
		view
		returns (uint256)
	{
		return
			getLandMiningStrength(_landId, _resource).add(
				getBarsMiningStrength(_landId, _resource)
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
		landId = miner2Index[_apostleTokenId].landTokenId;
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

	function _enhancedStrengthRateByIndex(
		uint256 _strength,
		uint256 _landId,
		address _resource,
		uint256 _index
	) internal returns (uint256) {
		return
			_strength
				.mul(
				IItemBar(registry.addressOf(CONTRACT_LAND_ITEM_BAR))
					.enhanceStrengthRateByIndex(_resource, _landId, _index)
			)
				.div(RATE_PRECISION);
	}

	// can only be called by LandItemBar
	function afterLandItemBarEquiped(
		uint256 _index,
		uint256 _landId,
		address _resource
	) public auth {
		_startBarMining(_index, _landId, _resource);
	}

	function afterLandItemBarUnequiped(
		uint256 _index,
		uint256 _landId,
		address _resource
	) public auth {
		_stopBarMinig(_index, _landId, _resource);
	}

	function _updateBarsStrength(uint256 _landId, address _resource) internal {
		IItemBar itembar = IItemBar(registry.addressOf(CONTRACT_LAND_ITEM_BAR));
		uint256 maxAmount = itembar.maxAmount();
		for (uint256 i = 0; i < maxAmount; i++) {
			(address itemToken, uint256 itemId, address resource) =
				itembar.getBarItem(_landId, i);
			if (
				itemToken != address(0) && itemId != 0 && resource == _resource
			) {
				_updateBarStrength(i, _landId, _resource);
			}
		}
	}

	function _updateBarStrength(
		uint256 _index,
		uint256 _landId,
		address _resource
	) internal {
		require(
			now > resourceReleaseStartTime &&
				now < (resourceReleaseStartTime + TOTAL_SECONDS),
			"Land: INVALID_TIME"
		);
		uint256 strength = getLandMiningStrength(_landId, _resource);
		uint256 enhancedStrength =
			_enhancedStrengthRateByIndex(
				strength,
				_landId,
				_resource,
				_index
			);
		land2BarStrength[_landId][_resource][_index] = enhancedStrength;
		emit UpdateBarMiningStrength(
			_index,
			_landId,
			_resource,
			enhancedStrength
		);
	}

	function _startBarMining(
		uint256 _index,
		uint256 _landId,
		address _resource
	) internal {
		require(
			now > resourceReleaseStartTime &&
				now < (resourceReleaseStartTime + TOTAL_SECONDS),
			"Land: INVALID_TIME"
		);
		mine(_landId);
		uint256 strength = getLandMiningStrength(_landId, _resource);
		uint256 enhancedStrength =
			_enhancedStrengthRateByIndex(strength, _landId, _resource, _index);
		land2BarStrength[_landId][_resource][_index] = enhancedStrength;
		emit StartBarMining(_index, _landId, _resource, enhancedStrength);
	}

	function _stopBarMinig(
		uint256 _index,
		uint256 _landId,
		address _resource
	) internal {
		require(now > resourceReleaseStartTime, "Land: INVALID_TIME");
		mine(_landId);
		delete land2BarStrength[_landId][_resource][_index];
		emit StopBarMining(_index, _landId, _resource);
	}

	function _claimItemResource(
		address _itemToken,
		uint256 _itemId,
		address _resource
	) internal returns (uint256) {
		uint256 balance = getItemMinedBalance(_itemToken, _itemId, _resource);
		if (balance > 0) {
			IMintableERC20(_resource).mint(msg.sender, balance);
			itemMinedBalance[_itemToken][_itemId][_resource] = 0;
			return balance;
		} else {
			return 0;
		}
	}

	// function claimItemResource(address _itemToken, uint256 _itemId) public {
	// 	IItemBar itembar = IItemBar(registry.addressOf(CONTRACT_LAND_ITEM_BAR));
	// 	(address staker, uint256 landId, address resource, uint256 index) =
	// 		itembar.getStatusByItem(_itemToken, _itemId);
	// 	if (staker == address(0) && landId == 0) {
	// 		require(
	// 			ERC721(_itemToken).ownerOf(_itemId) == msg.sender,
	// 			"Land: ONLY_ITEM_ONWER"
	// 		);
	// 	} else {
	// 		require(staker == msg.sender, "Land: ONLY_ITEM_STAKER");
	// 		settleBar(index, landId, resource);
	// 	}

	// 	uint256 goldBalance =
	// 		_claimItemResource(
	// 			_itemToken,
	// 			_itemId,
	// 			registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN)
	// 		);
	// 	uint256 woodBalance =
	// 		_claimItemResource(
	// 			_itemToken,
	// 			_itemId,
	// 			registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN)
	// 		);
	// 	uint256 waterBalance =
	// 		_claimItemResource(
	// 			_itemToken,
	// 			_itemId,
	// 			registry.addressOf(CONTRACT_WATER_ERC20_TOKEN)
	// 		);
	// 	uint256 fireBalance =
	// 		_claimItemResource(
	// 			_itemToken,
	// 			_itemId,
	// 			registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN)
	// 		);
	// 	uint256 soilBalance =
	// 		_claimItemResource(
	// 			_itemToken,
	// 			_itemId,
	// 			registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN)
	// 		);

	// 	emit ItemResourceClaimed(
	// 		msg.sender,
	// 		_itemToken,
	// 		_itemId,
	// 		goldBalance,
	// 		woodBalance,
	// 		waterBalance,
	// 		fireBalance,
	// 		soilBalance
	// 	);
	// }

	// function availableItemResources(
	// 	address _itemToken,
	// 	uint256 _itemId,
	// 	address[] memory _resources
	// ) public view returns (uint256[] memory) {
	// 	IItemBar itembar = IItemBar(registry.addressOf(CONTRACT_LAND_ITEM_BAR));
	// 	uint256[] memory availables = new uint256[](_resources.length);
	// 	for (uint256 i = 0; i < _resources.length; i++) {
	// 		(address staker, uint256 landId, , uint256 index) =
	// 			itembar.getStatusByItem(_itemToken, _itemId);
	// 		uint256 available = 0;
	// 		if (staker != address(0) && landId != 0) {
	// 			available = _calculateBarMinedBalance(
	// 				index,
	// 				landId,
	// 				_resources[i],
	// 				now
	// 			);
	// 		}
	// 		availables[i] = available.add(
	// 			getItemMinedBalance(_itemToken, _itemId, _resources[i])
	// 		);
	// 	}
	// 	return availables;
	// }
}
