pragma solidity ^0.4.24;

import "./interfaces/IItemBar.sol";
import "./LandResourceV4.sol";

contract LandResourceV5 is LandResourceV4 {
	event ClearAllMiningStrengthWhenStop(uint256 indexed landTokenId);
	// 0x434f4e54524143545f4c414e445f4954454d5f42415200000000000000000000
	bytes32 public constant CONTRACT_LAND_ITEM_BAR = "CONTRACT_LAND_ITEM_BAR";

	// rate precision
	uint128 public constant RATE_PRECISION = 10**8;

	mapping(uint256 => mapping(address => mapping(address => uint256))) land2ItemBarMinedStrength;

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
				land2ResourceMineState[_landTokenId].maxMiners,
			"Land: EXCEED_MINER_LIMIT"
		);

		address miner =
			IInterstellarEncoder(
				registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)
			)
				.getObjectAddress(_tokenId);
		uint256 strength =
			IMinerObject(miner).strengthOf(_tokenId, _resource, _landTokenId);

		// V5 add item bar
		address itemBar = registry.addressOf(CONTRACT_LAND_ITEM_BAR);
		uint256 enhanceRate =
			IItemBar(itemBar).enhanceStrengthRateOf(_resource, _landTokenId);
		uint256 enhanceStrength = strength.mul(enhanceRate).div(RATE_PRECISION);
		uint256 totalStrength = strength.add(enhanceStrength);

		land2ResourceMineState[_landTokenId].miners[_resource].push(_tokenId);
		land2ResourceMineState[_landTokenId].totalMinerStrength[
			_resource
		] = land2ResourceMineState[_landTokenId].totalMinerStrength[_resource]
			.add(totalStrength);

		miner2Index[_tokenId] = MinerStatus({
			landTokenId: _landTokenId,
			resource: _resource,
			indexInResource: uint64(_index)
		});

		emit StartMining(_tokenId, _landTokenId, _resource, totalStrength);
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

		// V5 add item bar
		address itemBar = registry.addressOf(CONTRACT_LAND_ITEM_BAR);
		uint256 enhanceRate =
			IItemBar(itemBar).enhanceStrengthRateOf(resource, landTokenId);
		uint256 enhanceStrength = strength.mul(enhanceRate).div(RATE_PRECISION);
		uint256 totalStrength = strength.add(enhanceStrength);

		// for backward compatibility
		// if strength can fluctuate some time in the future
		if (
			land2ResourceMineState[landTokenId].totalMinerStrength[resource] !=
			0
		) {
			if (
				land2ResourceMineState[landTokenId].totalMinerStrength[
					resource
				] > totalStrength
			) {
				land2ResourceMineState[landTokenId].totalMinerStrength[
					resource
				] = land2ResourceMineState[landTokenId].totalMinerStrength[
					resource
				]
					.sub(totalStrength);
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

		emit StopMining(_tokenId, landTokenId, resource, totalStrength);
	}

	function updateMinerStrengthWhenStop(uint256 _apostleTokenId) public auth {
		if (miner2Index[_apostleTokenId].landTokenId == 0) {
			return;
		}
		(uint256 landTokenId, uint256 strength) =
			_updateMinerStrength(_apostleTokenId, true);
		// _isStop == true - minus strength
		// _isStop == false - add strength
		emit UpdateMiningStrengthWhenStop(
			_apostleTokenId,
			landTokenId,
			strength
		);
	}

	function updateMinerStrengthWhenStart(uint256 _apostleTokenId) public auth {
		if (miner2Index[_apostleTokenId].landTokenId == 0) {
			return;
		}
		(uint256 landTokenId, uint256 strength) =
			_updateMinerStrength(_apostleTokenId, false);
		// _isStop == true - minus strength
		// _isStop == false - add strength
		emit UpdateMiningStrengthWhenStart(
			_apostleTokenId,
			landTokenId,
			strength
		);
	}

	// can only be called by ItemBar
	// _isStop == true - minus strength
	function updateAllMinerStrengthWhenStop(uint256 _landTokenId) public auth {
		if (land2ResourceMineState[_landTokenId].totalMiners == 0) {
			return;
		}
		mine(_landTokenId);
		address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
		address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
		address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
		address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
		address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);
		land2ResourceMineState[_landTokenId].totalMinerStrength[gold] = 0;
		land2ResourceMineState[_landTokenId].totalMinerStrength[wood] = 0;
		land2ResourceMineState[_landTokenId].totalMinerStrength[water] = 0;
		land2ResourceMineState[_landTokenId].totalMinerStrength[fire] = 0;
		land2ResourceMineState[_landTokenId].totalMinerStrength[soil] = 0;
		emit ClearAllMiningStrengthWhenStop(_landTokenId);
	}

	// can only be called by ItemBar
	// _isStop == false - add strength
	function updateAllMinerStrengthWhenStart(uint256 _landTokenId) public auth {
		if (land2ResourceMineState[_landTokenId].totalMiners == 0) {
			return;
		}
		_updateMinerStrengthByElement(
			_landTokenId,
			registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN)
		);
		_updateMinerStrengthByElement(
			_landTokenId,
			registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN)
		);
		_updateMinerStrengthByElement(
			_landTokenId,
			registry.addressOf(CONTRACT_WATER_ERC20_TOKEN)
		);
		_updateMinerStrengthByElement(
			_landTokenId,
			registry.addressOf(CONTRACT_WATER_ERC20_TOKEN)
		);
		_updateMinerStrengthByElement(
			_landTokenId,
			registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN)
		);
	}

	function _updateMinerStrengthByElement(
		uint256 _landTokenId,
		address _resourceToken
	) internal {
		uint256[] memory miners =
			land2ResourceMineState[_landTokenId].miners[_resourceToken];
		for (uint256 i = 0; i < miners.length; i++) {
			(uint256 landTokenId, uint256 strength) =
				_updateMinerStrength(miners[i], false);
			emit UpdateMiningStrengthWhenStop(miners[i], landTokenId, strength);
		}
	}

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

		// V5 add item bar
		address itemBar = registry.addressOf(CONTRACT_LAND_ITEM_BAR);
		uint256 enhanceRate =
			IItemBar(itemBar).enhanceStrengthRateOf(resource, landTokenId);
		uint256 enhanceStrength = strength.mul(enhanceRate).div(RATE_PRECISION);
		uint256 totalStrength = strength.add(enhanceStrength);

		if (_isStop) {
			mine(landTokenId);
			land2ResourceMineState[landTokenId].totalMinerStrength[
				resource
			] = land2ResourceMineState[landTokenId].totalMinerStrength[resource]
				.sub(totalStrength);
		} else {
			land2ResourceMineState[landTokenId].totalMinerStrength[
				resource
			] = land2ResourceMineState[landTokenId].totalMinerStrength[resource]
				.add(totalStrength);
		}

		return (landTokenId, totalStrength);
	}

	function isLander(uint256 _landTokenId) internal view returns (bool) {
		return
			msg.sender ==
			ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(
				_landTokenId
			);
	}

	function isBarStaker(uint256 _landTokenId) internal view returns (bool) {
		address itemBar = registry.addressOf(CONTRACT_LAND_ITEM_BAR);
		for (uint256 i = 0; i < IItemBar(itemBar).maxAmount(); i++) {
			address barStaker = IItemBar(itemBar).getBarStaker(_landTokenId, i);
			if (msg.sender == barStaker) {
				return true;
			}
		}
		return false;
	}

	function _mineResource(uint256 _landTokenId, address _resourceToken)
		internal
	{
		// the longest seconds to zero speed.
		uint256 minedBalance =
			_calculateMinedBalance(_landTokenId, _resourceToken, now);

		// V5 yeild distribution
		address itemBar = registry.addressOf(CONTRACT_LAND_ITEM_BAR);
		uint256 enhanceRate =
			IItemBar(itemBar).enhanceStrengthRateOf(
				_resourceToken,
				_landTokenId
			);
		uint256 landBalance =
			minedBalance.mul(RATE_PRECISION).div(
				enhanceRate.add(RATE_PRECISION)
			);
		if (enhanceRate > 0) {
			uint256 itemBalance = minedBalance.sub(landBalance);
			for (uint256 i = 0; i < IItemBar(itemBar).maxAmount(); i++) {
				uint256 barRate =
					IItemBar(itemBar).enhanceStrengthRateByIndex(
						_resourceToken,
						_landTokenId,
						i
					);
				uint256 barBalance = itemBalance.mul(barRate).div(enhanceRate);
				address barStaker =
					IItemBar(itemBar).getBarStaker(_landTokenId, i);
				//TODO:: give fee to lander
				land2ItemBarMinedStrength[_landTokenId][barStaker][
					_resourceToken
				] = land2ItemBarMinedStrength[_landTokenId][barStaker][
					_resourceToken
				]
					.add(barBalance);
			}
		}

		land2ResourceMineState[_landTokenId].mintedBalance[
			_resourceToken
		] = land2ResourceMineState[_landTokenId].mintedBalance[_resourceToken]
			.add(landBalance);
	}

	function claimBarResource(uint256 _landTokenId) public {
		require(isBarStaker(_landTokenId), "Only Bar starker.");

		address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
		address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
		address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
		address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
		address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);

		uint256 goldBalance;
		uint256 woodBalance;
		uint256 waterBalance;
		uint256 fireBalance;
		uint256 soilBalance;

		if (land2ItemBarMinedStrength[_landTokenId][msg.sender][gold] > 0) {
			goldBalance = land2ItemBarMinedStrength[_landTokenId][msg.sender][
				gold
			];
			IMintableERC20(gold).mint(msg.sender, goldBalance);
			land2ItemBarMinedStrength[_landTokenId][msg.sender][gold] = 0;
		}

		if (land2ItemBarMinedStrength[_landTokenId][msg.sender][wood] > 0) {
			woodBalance = land2ItemBarMinedStrength[_landTokenId][msg.sender][
				wood
			];
			IMintableERC20(wood).mint(msg.sender, woodBalance);
			land2ItemBarMinedStrength[_landTokenId][msg.sender][wood] = 0;
		}

		if (land2ItemBarMinedStrength[_landTokenId][msg.sender][water] > 0) {
			waterBalance = land2ItemBarMinedStrength[_landTokenId][msg.sender][
				water
			];
			IMintableERC20(water).mint(msg.sender, waterBalance);
			land2ItemBarMinedStrength[_landTokenId][msg.sender][water] = 0;
		}

		if (land2ItemBarMinedStrength[_landTokenId][msg.sender][fire] > 0) {
			fireBalance = land2ItemBarMinedStrength[_landTokenId][msg.sender][
				fire
			];
			IMintableERC20(fire).mint(msg.sender, fireBalance);
			land2ItemBarMinedStrength[_landTokenId][msg.sender][fire] = 0;
		}

		if (land2ItemBarMinedStrength[_landTokenId][msg.sender][soil] > 0) {
			soilBalance = land2ItemBarMinedStrength[_landTokenId][msg.sender][
				soil
			];
			IMintableERC20(gold).mint(msg.sender, soilBalance);
			land2ItemBarMinedStrength[_landTokenId][msg.sender][soil] = 0;
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

	function claimLandResource(uint256 _landTokenId) public {
		require(isLander(_landTokenId), "Must be the owner of the land.");

		address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
		address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
		address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
		address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
		address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);

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

	function claimAllResource(uint256 _landTokenId) public {
		require(
			isLander(_landTokenId) || isBarStaker(_landTokenId),
			"Must be the owner of the land or Bar starker."
		);

		address gold = registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN);
		address wood = registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN);
		address water = registry.addressOf(CONTRACT_WATER_ERC20_TOKEN);
		address fire = registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN);
		address soil = registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN);

		_mineAllResource(_landTokenId, gold, wood, water, fire, soil);

		if (isLander(_landTokenId)) {
			claimLandResource(_landTokenId);
		}

		if (isBarStaker(_landTokenId)) {
			claimBarResource(_landTokenId);
		}
	}

	function _calculateBarResources(
		uint256 _landTokenId,
		address _resourceToken,
		uint256 _minedBalance
	) public view returns (uint256) {
		address itemBar = registry.addressOf(CONTRACT_LAND_ITEM_BAR);
		uint256 enhanceRate =
			IItemBar(itemBar).enhanceStrengthRateOf(
				_resourceToken,
				_landTokenId
			);
		// V5 yeild distribution
		uint256 landBalance =
			_minedBalance.mul(RATE_PRECISION).div(
				enhanceRate.add(RATE_PRECISION)
			);

		uint256 callerResource;
		if (isLander(_landTokenId)) {
			callerResource = callerResource.add(landBalance);
		}
		if (enhanceRate > 0) {
			uint256 itemBalance = _minedBalance.sub(landBalance);
			for (uint256 i = 0; i < IItemBar(itemBar).maxAmount(); i++) {
				uint256 barRate =
					IItemBar(itemBar).enhanceStrengthRateByIndex(
						_resourceToken,
						_landTokenId,
						i
					);
				uint256 barBalance = itemBalance.mul(barRate).div(enhanceRate);
				//TODO:: give fee to lander
				if (
					msg.sender ==
					IItemBar(itemBar).getBarStaker(_landTokenId, i)
				) {
					callerResource = callerResource.add(barBalance);
				}
			}
		}
		return callerResource;
	}

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
		uint256[5] memory availables;
		for (uint256 i = 0; i < 5; i++) {
			uint256 mined =
				_calculateMinedBalance(_landTokenId, _resourceTokens[i], now);

			uint256 available =
				_calculateBarResources(_landTokenId, _resourceTokens[i], mined);
			available = available.add(
				land2ItemBarMinedStrength[_landTokenId][msg.sender][
					_resourceTokens[i]
				]
			);
			if (isLander(_landTokenId)) {
				available = available.add(
					land2ResourceMineState[_landTokenId].mintedBalance[
						_resourceTokens[i]
					]
				);
			}
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
