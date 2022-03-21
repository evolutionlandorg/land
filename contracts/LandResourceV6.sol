pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-solidity/contracts/introspection/SupportsInterfaceWithLookup.sol";
import "@evolutionland/common/contracts/interfaces/IMintableERC20.sol";
import "@evolutionland/common/contracts/interfaces/ISettingsRegistry.sol";
import "@evolutionland/common/contracts/DSAuth.sol";
import "@evolutionland/common/contracts/interfaces/IInterstellarEncoder.sol";
import "@evolutionland/common/contracts/interfaces/ITokenUse.sol";
import "@evolutionland/common/contracts/interfaces/IActivity.sol";
import "@evolutionland/common/contracts/interfaces/IMinerObject.sol";
import "./interfaces/ILandBase.sol";
import "./interfaces/ILandBaseExt.sol";
import "./interfaces/IMetaDataTeller.sol";

// DSAuth see https://github.com/evolutionlandorg/common-contracts/blob/2873a4f8f970bd442ffcf9c6ae63b3dc79e743db/contracts/DSAuth.sol#L40
contract LandResourceV6 is SupportsInterfaceWithLookup, DSAuth, IActivity {
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
		uint256 rate
	);
	event StopBarMining(uint256 barIndex, uint256 landId, address rate);
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
		address itemToken,
		uint256 itemTokenId,
		uint256 goldBalance,
		uint256 woodBalance,
		uint256 waterBalance,
		uint256 fireBalance,
		uint256 soilBalance
	);

	// land item bar
	event Equip(
		uint256 indexed tokenId,
		address resource,
		uint256 index,
		address staker,
		address token,
		uint256 id
	);
	event Divest(
		uint256 indexed tokenId,
		address resource,
		uint256 index,
		address staker,
		address token,
		uint256 id
	);

    	event SetMaxLandBar(uint256 maxAmount);
    	event SetMaxMiner(uint256 maxMiners);

	// 0x434f4e54524143545f4c414e445f424153450000000000000000000000000000
	bytes32 public constant CONTRACT_LAND_BASE = "CONTRACT_LAND_BASE";

	// 0x434f4e54524143545f474f4c445f45524332305f544f4b454e00000000000000
	bytes32 public constant CONTRACT_GOLD_ERC20_TOKEN =
		"CONTRACT_GOLD_ERC20_TOKEN";

	// 0x434f4e54524143545f574f4f445f45524332305f544f4b454e00000000000000
	bytes32 public constant CONTRACT_WOOD_ERC20_TOKEN =
		"CONTRACT_WOOD_ERC20_TOKEN";

	// 0x434f4e54524143545f57415445525f45524332305f544f4b454e000000000000
	bytes32 public constant CONTRACT_WATER_ERC20_TOKEN =
		"CONTRACT_WATER_ERC20_TOKEN";

	// 0x434f4e54524143545f464952455f45524332305f544f4b454e00000000000000
	bytes32 public constant CONTRACT_FIRE_ERC20_TOKEN =
		"CONTRACT_FIRE_ERC20_TOKEN";

	// 0x434f4e54524143545f534f494c5f45524332305f544f4b454e00000000000000
	bytes32 public constant CONTRACT_SOIL_ERC20_TOKEN =
		"CONTRACT_SOIL_ERC20_TOKEN";

	// 0x434f4e54524143545f494e5445525354454c4c41525f454e434f444552000000
	bytes32 public constant CONTRACT_INTERSTELLAR_ENCODER =
		"CONTRACT_INTERSTELLAR_ENCODER";

	// 0x434f4e54524143545f4f424a4543545f4f574e45525348495000000000000000
	bytes32 public constant CONTRACT_OBJECT_OWNERSHIP =
		"CONTRACT_OBJECT_OWNERSHIP";

	// 0x434f4e54524143545f544f4b454e5f5553450000000000000000000000000000
	bytes32 public constant CONTRACT_TOKEN_USE = "CONTRACT_TOKEN_USE";

	//0x4655524e4143455f4954454d5f4d494e455f4645450000000000000000000000
	bytes32 public constant FURNACE_ITEM_MINE_FEE = "FURNACE_ITEM_MINE_FEE";

	// 0x434f4e54524143545f4d455441444154415f54454c4c45520000000000000000
	bytes32 public constant CONTRACT_METADATA_TELLER =
		"CONTRACT_METADATA_TELLER";

	// 0x55494e545f4954454d4241525f50524f544543545f504552494f440000000000
	bytes32 public constant UINT_ITEMBAR_PROTECT_PERIOD =
		"UINT_ITEMBAR_PROTECT_PERIOD";

	// rate precision
	uint128 public constant RATE_PRECISION = 10**8;

	// max land miner amounts
	uint256 public maxMiners;

	// (itemTokenAddress => (itemTokenId => (resourceAddress => mined balance)))
	mapping(address => mapping(uint256 => mapping(address => uint256)))
		public itemMinedBalance;

	// (landTokenId => (resourceAddress => (landBarIndex => itemEnhancedRate)))
	mapping(uint256 => mapping(address => mapping(uint256 => uint256)))
		public land2BarRate;

	// land item bar
	struct Bar {
		address staker;    // staker who equip item to the land item bar
		address token;     // item token address of the item which equpped in the land item bar
		uint256 id;        // item token id
		address resource;  // which resource staker want to stake
	}

	// land item bar status
	struct Status {
		address staker;    // staker who equip item to the land item bar
		uint256 landTokenId; // land token id which the item equipped
		uint256 index;     // land item bar slot which the item equipped
	}

	// max land bar amount
	uint256 public maxAmount;
	// (landTokenId => (landBarIndex => BAR))
	mapping(uint256 => mapping(uint256 => Bar)) public landId2Bars;
	// (itemTokenAddress => (itemTokenId => STATUS))
	mapping(address => mapping(uint256 => Status)) public itemId2Status;
	// (itemTokenAddress => (itemTokenId => itemProtectPeriod))
	mapping(address => mapping(uint256 => uint256)) public protectPeriod;
	// v5 add end

	/*
	 *  Modifiers
	 */
	modifier singletonLockCall() {
		require(!singletonLock, "Only can call once");
		_;
		singletonLock = true;
	}

	// initializeContract be called by proxy contract
	// see https://blog.openzeppelin.com/the-transparent-proxy-pattern/
	function initializeContract(
		address _registry,
		uint256 _resourceReleaseStartTime
	) public singletonLockCall {
        require(_registry!= address(0), "_registry is a zero value");
		// Ownable constructor
		owner = msg.sender;
		emit LogSetOwner(msg.sender);

		registry = ISettingsRegistry(_registry);

		resourceReleaseStartTime = _resourceReleaseStartTime;

	//see https://github.com/evolutionlandorg/common-contracts/blob/2873a4f8f970bd442ffcf9c6ae63b3dc79e743db/contracts/interfaces/IActivity.sol#L6
		_registerInterface(InterfaceId_IActivity);

        maxMiners = 5;
        maxAmount = 5;
	}

	// get amount of speed uint at this moment
	function _getReleaseSpeedInSeconds(uint256 _tokenId, uint256 _time)
		internal
		view
		returns (uint256 currentSpeed)
	{
		require(_time >= resourceReleaseStartTime, "Should after release time");
		require(
			_time >= land2ResourceMineState[_tokenId].lastUpdateTime,
			"Should after release last update time"
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

	// For every seconds, the speed will decrease by current speed multiplying (DENOMINATOR_in_seconds - seconds) / DENOMINATOR_in_seconds.
	// resource will decrease 1/10000 every day.
	// `minableBalance` is an area of a trapezoid.
	// The reason for dividing by `1 days` twice is that the definition of `getResourceRate` is the number of mines that can be mined per day.
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

	function setMaxMiners(uint256 _maxMiners) public auth {
		require(_maxMiners > maxMiners, "Land: INVALID_MAXMINERS");
		maxMiners = _maxMiners;
        emit SetMaxMiner(maxMiners);
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

		_mineResource(_landTokenId, _gold);
		_mineResource(_landTokenId, _wood);
		_mineResource(_landTokenId, _water);
		_mineResource(_landTokenId, _fire);
		_mineResource(_landTokenId, _soil);

		land2ResourceMineState[_landTokenId].lastUpdateTime = uint128(now);
	}

	function _distribution(
		uint256 _landId,
		address _resource,
		uint256 minedBalance,
		uint256 barsRate
	) internal returns (uint256) {
		uint256 landBalance =
			minedBalance.mul(RATE_PRECISION).div(barsRate.add(RATE_PRECISION));
		uint256 barsBalance = minedBalance.sub(landBalance);
		for (uint256 i = 0; i < maxAmount; i++) {
			(address itemToken, uint256 itemId, address resouce) =
				getBarItem(_landId, i);
			if (itemToken != address(0) && resouce == _resource) {
				uint256 barBalance =
					barsBalance.mul(getBarRate(_landId, _resource, i)).div(
						barsRate
					);
				(barBalance, landBalance) = _payFee(barBalance, landBalance);
				itemMinedBalance[itemToken][itemId][
					_resource
				] = getItemMinedBalance(itemToken, itemId, _resource).add(
					barBalance
				);
			}
		}
		return landBalance;
	}

	function _payFee(uint256 barBalance, uint256 landBalance)
		internal
		view
		returns (uint256, uint256)
	{
		uint256 fee =
			barBalance.mul(registry.uintOf(FURNACE_ITEM_MINE_FEE)).div(
				RATE_PRECISION
			);
		barBalance = barBalance.sub(fee);
		landBalance = landBalance.add(fee);
		return (barBalance, landBalance);
	}

	function _mineResource(uint256 _landId, address _resource) internal {
		// the longest seconds to zero speed.
		if (getLandMiningStrength(_landId, _resource) == 0) {
			return;
		}
		uint256 minedBalance = _calculateMinedBalance(_landId, _resource, now);
		if (minedBalance == 0) {
			return;
		}

		uint256 barsRate = getBarsRate(_landId, _resource);
		uint256 landBalance = minedBalance;
		if (barsRate > 0) {
			// V5 yeild distribution
			landBalance = _distribution(
				_landId,
				_resource,
				minedBalance,
				barsRate
			);
		}
		land2ResourceMineState[_landId].mintedBalance[
			_resource
		] = getLandMinedBalance(_landId, _resource).add(landBalance);
	}

	function _calculateMinedBalance(
		uint256 _landTokenId,
		address _resourceToken,
		uint256 _currentTime
	) internal view returns (uint256) {
		uint256 currentTime = _currentTime;

		uint256 minedBalance;
		uint256 minableBalance;
		if (currentTime > (resourceReleaseStartTime + TOTAL_SECONDS)) {
			currentTime = (resourceReleaseStartTime + TOTAL_SECONDS);
		}

		uint256 lastUpdateTime =
			land2ResourceMineState[_landTokenId].lastUpdateTime;
		require(currentTime >= lastUpdateTime, "Land: INVALID_TIMESTAMP");

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

	// both for own _tokenId or hired one
	function startMining(
		uint256 _tokenId,
		uint256 _landTokenId,
		address _resource
	) public {
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

		ITokenUse(registry.addressOf(CONTRACT_TOKEN_USE)).addActivity(
			_tokenId,
			msg.sender,
			0
		);

		// update status!
		mine(_landTokenId);

		uint256 _index =
			land2ResourceMineState[_landTokenId].miners[_resource].length;

		land2ResourceMineState[_landTokenId].totalMiners += 1;

		require(
			land2ResourceMineState[_landTokenId].totalMiners <= maxMiners,
			"Land: EXCEED_MAXAMOUNT"
		);

		address miner =
			IInterstellarEncoder(
				registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)
			)
				.getObjectAddress(_tokenId);
		uint256 strength =
			IMinerObject(miner).strengthOf(_tokenId, _resource, _landTokenId);

		land2ResourceMineState[_landTokenId].miners[_resource].push(_tokenId);
		land2ResourceMineState[_landTokenId].totalMinerStrength[_resource] = land2ResourceMineState[_landTokenId].totalMinerStrength[_resource].add(strength);

		miner2Index[_tokenId] = MinerStatus({
			landTokenId: _landTokenId,
			resource: _resource,
			indexInResource: uint64(_index)
		});

		emit StartMining(_tokenId, _landTokenId, _resource, strength);
	}

	function batchStartMining(
		uint256[] _tokenIds,
		uint256[] _landTokenIds,
		address[] _resources
	) external {
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

	function batchClaimLandResource(uint256[] _landTokenIds) external {
		uint256 length = _landTokenIds.length;

		for (uint256 i = 0; i < length; i++) {
			claimLandResource(_landTokenIds[i]);
		}
	}

        function batchClaimItemResource(address[] _itemTokens, uint256[] _itemIds) external {
            require(_itemTokens.length == _itemIds.length, "Land: INVALID_LENGTH");
            uint256 length = _itemTokens.length;
            for (uint256 i = 0; i < length; i++) {
                claimItemResource(_itemTokens[i], _itemIds[i]);
            }
        }

	// Only trigger from Token Activity.
	function activityStopped(uint256 _tokenId) public auth {
		_stopMining(_tokenId);
	}

	function stopMining(uint256 _tokenId) public {
            address ownership = registry.addressOf(CONTRACT_OBJECT_OWNERSHIP);
            address tokenuse = registry.addressOf(CONTRACT_TOKEN_USE);
            address user = ITokenUse(tokenuse).getTokenUser(_tokenId);
            if (ERC721(ownership).ownerOf(_tokenId) == msg.sender || user == msg.sender) {
                ITokenUse(tokenuse).removeActivity(_tokenId, msg.sender);
            } else {
                // Land owner has right to stop mining
                uint256 landTokenId = miner2Index[_tokenId].landTokenId;
                require(msg.sender == ERC721(ownership).ownerOf(landTokenId), "Land: ONLY_LANDER");
                ITokenUse(tokenuse).removeActivity(_tokenId, user);
            }
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

		land2ResourceMineState[landTokenId].miners[resource].length = land2ResourceMineState[landTokenId].miners[resource].length.sub(1);
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

		emit StopMining(_tokenId, landTokenId, resource, strength);
	}

	// function _updateMinerStrength(uint256 _apostleTokenId, bool _isStop)
	// 	internal
	// 	returns (uint256, uint256)
	// {
	// 	// require that this apostle
	// 	uint256 landTokenId = landWorkingOn(_apostleTokenId);
	// 	require(landTokenId != 0, "this apostle is not mining.");

	// 	address resource = miner2Index[_apostleTokenId].resource;

	// 	address miner =
	// 		IInterstellarEncoder(
	// 			registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)
	// 		)
	// 			.getObjectAddress(_apostleTokenId);
	// 	uint256 strength =
	// 		IMinerObject(miner).strengthOf(
	// 			_apostleTokenId,
	// 			resource,
	// 			landTokenId
	// 		);

	// 	mine(landTokenId);

	// 	if (_isStop) {
	// 		land2ResourceMineState[landTokenId].totalMinerStrength[
	// 			resource
	// 		] = land2ResourceMineState[landTokenId].totalMinerStrength[resource]
	// 			.sub(strength);
	// 	} else {
	// 		land2ResourceMineState[landTokenId].totalMinerStrength[resource] = land2ResourceMineState[landTokenId].totalMinerStrength[resource].add(strength);
	// 	}

	// 	return (landTokenId, strength);
	// }

	// // when a mirrorToken or a pet has tied to apostle
	// // we need to update status and remove this apostle from mining list first
	// // open authority to PetBase
	// // can only be called by PetBase
	// function updateMinerStrengthWhenStop(uint256 _apostleTokenId) public auth {
	// 	uint256 landTokenId;
	// 	uint256 strength;
	// 	(landTokenId, strength) = _updateMinerStrength(_apostleTokenId, true);
	// 	// _isStop == true - minus strength
	// 	// _isStop == false - add strength
	// 	emit UpdateMiningStrengthWhenStop(
	// 		_apostleTokenId,
	// 		landTokenId,
	// 		strength
	// 	);
	// }

	// function updateMinerStrengthWhenStart(uint256 _apostleTokenId) public auth {
	// 	uint256 landTokenId;
	// 	uint256 strength;
	// 	(landTokenId, strength) = _updateMinerStrength(_apostleTokenId, false);
	// 	// _isStop == true - minus strength
	// 	// _isStop == false - add strength
	// 	emit UpdateMiningStrengthWhenStart(
	// 		_apostleTokenId,
	// 		landTokenId,
	// 		strength
	// 	);
	// }

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
		return
			getLandMiningStrength(_landId, _resource)
				.mul(getBarRate(_landId, _resource, _index))
				.div(RATE_PRECISION);
	}

	function getBarRate(
		uint256 _landId,
		address _resource,
		uint256 _index
	) public view returns (uint256) {
		return land2BarRate[_landId][_resource][_index];
	}

	function getBarsRate(uint256 _landId, address _resource)
		public
		view
		returns (uint256 barsRate)
	{
		for (uint256 i = 0; i < maxAmount; i++) {
			barsRate = barsRate.add(getBarRate(_landId, _resource, i));
		}
	}

	function getBarsMiningStrength(uint256 _landId, address _resource)
		public
		view
		returns (uint256 barsMiningStrength)
	{
		return
			getLandMiningStrength(_landId, _resource)
				.mul(getBarsRate(_landId, _resource))
				.div(RATE_PRECISION);
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

	function _getBarRateByIndex(
		uint256 _landId,
		address _resource,
		uint256 _index
	) internal view returns (uint256) {
		return enhanceStrengthRateByIndex(_resource, _landId, _index);
	}

	function _startBarMining(
		uint256 _index,
		uint256 _landId,
		address _resource
	) internal {
		uint256 rate = _getBarRateByIndex(_landId, _resource, _index);
		land2BarRate[_landId][_resource][_index] = rate;
		emit StartBarMining(_index, _landId, _resource, rate);
	}

	function _stopBarMinig(
		uint256 _index,
		uint256 _landId,
		address _resource
	) internal {
		delete land2BarRate[_landId][_resource][_index];
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

	function claimItemResource(address _itemToken, uint256 _itemId) public {
		(address staker, uint256 landId) = getLandIdByItem(_itemToken, _itemId);
		if (staker == address(0) && landId == 0) {
			require(
				ERC721(_itemToken).ownerOf(_itemId) == msg.sender,
				"Land: ONLY_ITEM_OWNER"
			);
		} else {
			require(staker == msg.sender, "Land: ONLY_ITEM_STAKER");
			mine(landId);
		}

		address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
		address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
		address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
		address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
		address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);
		uint256 goldBalance = _claimItemResource(_itemToken, _itemId, gold);
		uint256 woodBalance = _claimItemResource(_itemToken, _itemId, wood);
		uint256 waterBalance = _claimItemResource(_itemToken, _itemId, water);
		uint256 fireBalance = _claimItemResource(_itemToken, _itemId, fire);
		uint256 soilBalance = _claimItemResource(_itemToken, _itemId, soil);

		emit ItemResourceClaimed(
			msg.sender,
			_itemToken,
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
		require(
			msg.sender ==
				ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(
					_landId
				),
			"Land: ONLY_LANDER"
		);

		address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
		address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
		address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
		address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
		address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);
		_mineAllResource(_landId, gold, wood, water, fire, soil);

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
		uint256 barsRate = getBarsRate(_landId, _resource);
		// V5 yeild distribution
		landBalance = _minedBalance.mul(RATE_PRECISION).div(
			barsRate.add(RATE_PRECISION)
		);
		if (barsRate > 0) {
			uint256 barsBalance = _minedBalance.sub(landBalance);
			for (uint256 i = 0; i < maxAmount; i++) {
				(address itemToken, uint256 itemId, address resource) = getBarItem(_landId, i);
				if (_itemId == itemId && _itemToken == itemToken && _resource == resource) {
					uint256 barBalance =
						barsBalance.mul(getBarRate(_landId, _resource, i)).div(
							barsRate
						);
					(barBalance, landBalance) = _payFee(barBalance, landBalance);
					barResource = barResource.add(barBalance);
				}
			}
		}
	}

	function availableLandResources(
		uint256 _landId,
		address[] _resources
	) external view returns (uint256[] memory) {
		uint256[] memory availables = new uint256[](_resources.length);
		for (uint256 i = 0; i < _resources.length; i++) {
			if (getLandMiningStrength(_landId, _resources[i]) > 0) {
				uint256 mined = _calculateMinedBalance(_landId, _resources[i], now);
				(uint256 available, ) =
					_calculateResources(
						address(0),
						0,
						_landId,
						_resources[i],
						mined
					);
				availables[i] = available.add(
					getLandMinedBalance(_landId, _resources[i])
				);
			}
		}
		return availables;
	}

	function availableItemResources(
		address _itemToken,
		uint256 _itemId,
		address[] _resources
	) external view returns (uint256[] memory) {
		uint256[] memory availables = new uint256[](_resources.length);
		for (uint256 i = 0; i < _resources.length; i++) {
			(address staker, uint256 landId) =
				getLandIdByItem(_itemToken, _itemId);
			if (getLandMiningStrength(landId, _resources[i]) > 0) {
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
		}
		return availables;
	}

	function isNotProtect(address _token, uint256 _id)
		public
		view
		returns (bool)
	{
		return protectPeriod[_token][_id] < now;
	}

	function getBarItem(uint256 _tokenId, uint256 _index)
		public
		view
		returns (
			address,
			uint256,
			address
		)
	{
		require(_index < maxAmount, "Furnace: INDEX_FORBIDDEN.");
		return (
			landId2Bars[_tokenId][_index].token,
			landId2Bars[_tokenId][_index].id,
			landId2Bars[_tokenId][_index].resource
		);
	}

	function getLandIdByItem(address _item, uint256 _itemId)
		public
		view
		returns (address, uint256)
	{
		return (
			itemId2Status[_item][_itemId].staker,
			itemId2Status[_item][_itemId].landTokenId
		);
	}

	/**
        @dev Equip function, A NFT can equip to EVO Bar (LandBar or ApostleBar).
        @param _tokenId  Token Id which to be quiped.
        @param _resource Which resouce appply to.
        @param _index    Index of the Bar.
        @param _token    Token address which to quip.
        @param _id       Token Id which to quip.
    	*/
	function equip(
		uint256 _tokenId,
		address _resource,
		uint256 _index,
		address _token,
		uint256 _id
	) public {
		_equip(_tokenId, _resource, _index, _token, _id);
	}

	/// equip rules:
	/// 1. land owner could replace item which is not in protected period.
	/// 2. all user could replace low-class items with high-class item. 
	///    if the classes is the same, high-grade can replace low-grade items.
	function _equip(
		uint256 _tokenId,
		address _resource,
		uint256 _index,
		address _token,
		uint256 _id
	) internal {
		beforeEquip(_tokenId, _resource);
		IMetaDataTeller teller =
			IMetaDataTeller(registry.addressOf(CONTRACT_METADATA_TELLER));
		uint256 resourceId =
			ILandBaseExt(registry.addressOf(CONTRACT_LAND_BASE))
				.resourceToken2RateAttrId(_resource);
		require(resourceId > 0 && resourceId < 6, "Furnace: INVALID_RESOURCE");
		require(
			IInterstellarEncoder(
				registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)
			)
				.getObjectClass(_tokenId) == 1,
			"Furnace: ONLY_LAND"
		);
        require(ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).exists(_tokenId), "Furnace: NOT_EXIST");
		(uint16 objClassExt, uint16 class, uint16 grade) =
			teller.getMetaData(_token, _id);
		require(objClassExt > 0, "Furnace: PERMISSION");
		require(_index < maxAmount, "Furnace: INDEX_FORBIDDEN");
		Bar storage bar = landId2Bars[_tokenId][_index];
		if (bar.token != address(0)) {
			require(isNotProtect(bar.token, bar.id), "Furnace: PROTECT_PERIOD");
			(, uint16 originClass, uint16 originGrade) =
				teller.getMetaData(bar.token, bar.id);
			require(
				class > originClass ||
					(class == originClass && grade > originGrade) ||
					ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP))
						.ownerOf(_tokenId) ==
					msg.sender,
				"Furnace: FORBIDDEN"
			);
			//TODO:: safe transfer
			ERC721(bar.token).transferFrom(address(this), bar.staker, bar.id);
            delete itemId2Status[bar.staker][bar.id];
            // emit Divest(
            //     _tokenId,
            //     bar.resource,
            //     _index,
            //     bar.staker,
            //     bar.token,
            //     bar.id
            // );
		}
		ERC721(_token).transferFrom(msg.sender, address(this), _id);
		bar.staker = msg.sender;
		bar.token = _token;
		bar.id = _id;
		bar.resource = _resource;
		itemId2Status[bar.token][bar.id] = Status({
			staker: bar.staker,
			landTokenId: _tokenId,
			index: _index
		});
		if (isNotProtect(bar.token, bar.id)) {
			protectPeriod[bar.token][bar.id] = _calculateProtectPeriod(class).add(now);
		}
		afterEquiped(_index, _tokenId, _resource);
		emit Equip(_tokenId, _resource, _index, bar.staker, bar.token, bar.id);
	}

	function _calculateProtectPeriod(
		uint16 _class
	) internal view returns (uint256) {
		uint256 baseProtectPeriod =
			registry.uintOf(UINT_ITEMBAR_PROTECT_PERIOD);
		return uint256(_class).mul(baseProtectPeriod);
	}

	function beforeEquip(uint256 _landTokenId, address _resource) internal {
		if (getLandMiningStrength(_landTokenId, _resource) > 0) {
			mine(_landTokenId);
		}
	}

	function afterEquiped(
		uint256 _index,
		uint256 _landTokenId,
		address _resource
	) internal {
		_startBarMining(_index, _landTokenId, _resource);
	}

	function afterDivested(
		uint256 _index,
		uint256 _landTokenId,
		address _resource
	) internal {
		if (getLandMiningStrength(_landTokenId, _resource) > 0) {
			mine(_landTokenId);
		}
		_stopBarMinig(_index, _landTokenId, _resource);
	}

    	function devestAndClaim(address _itemToken, uint256 _tokenId, uint256 _index) public {
		divest(_tokenId, _index);
		claimItemResource(_itemToken, _tokenId);
    	}

	/**
        @dev Divest function, A NFT can Divest from EVO Bar (LandBar or ApostleBar).
        @param _tokenId Token Id which to be unquiped.
        @param _index   Index of the Bar.
    	*/
	function divest(uint256 _tokenId, uint256 _index) public {
		_divest(_tokenId, _index);
	}

	function _divest(uint256 _tokenId, uint256 _index) internal {
		Bar memory bar = landId2Bars[_tokenId][_index];
		require(bar.token != address(0), "Furnace: EMPTY");
		require(bar.staker == msg.sender, "Furnace: FORBIDDEN");
		ERC721(bar.token).transferFrom(address(this), bar.staker, bar.id);
		afterDivested(_index, _tokenId, bar.resource);
		//clean
		delete itemId2Status[bar.token][bar.id];
		delete landId2Bars[_tokenId][_index];
		emit Divest(
			_tokenId,
			bar.resource,
			_index,
			bar.staker,
			bar.token,
			bar.id
		);
	}

	function setMaxAmount(uint256 _maxAmount) public auth {
        require(_maxAmount > maxAmount, "Furnace: INVALID_MAXAMOUNT");
        maxAmount = _maxAmount;
        emit SetMaxLandBar(maxAmount);
	}

	function enhanceStrengthRateByIndex(
		address _resource,
		uint256 _tokenId,
		uint256 _index
	) public view returns (uint256) {
		Bar storage bar = landId2Bars[_tokenId][_index];
		if (bar.token == address(0)) {
			return 0;
		}
		IMetaDataTeller teller =
			IMetaDataTeller(registry.addressOf(CONTRACT_METADATA_TELLER));
		uint256 resourceId =
			ILandBaseExt(registry.addressOf(CONTRACT_LAND_BASE))
				.resourceToken2RateAttrId(_resource);
		return teller.getRate(bar.token, bar.id, resourceId);
	}

	function enhanceStrengthRateOf(address _resource, uint256 _tokenId)
		external
		view
		returns (uint256)
	{
		uint256 rate;
		for (uint256 i = 0; i < maxAmount; i++) {
			rate = rate.add(enhanceStrengthRateByIndex(_resource, _tokenId, i));
		}
		return rate;
	}
}
