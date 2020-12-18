pragma solidity ^0.4.24;

import "./interfaces/IItemBar.sol";
import "./LandResourceV4.sol";

contract LandResourceV5 is LandResourceV4 {
	event StartMining(
		uint256 minerTokenId,
		uint256 landTokenId,
		address resource,
		uint256 minerStrength,
		uint256 enhancedStrengh
	);
	event StopMining(
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

	// rate precision
	uint128 public constant RATE_PRECISION = 10**8;

	mapping(uint256 => mapping(address => mapping(address => uint256)))
		public land2ItemBarMinedBalance;

	mapping(uint256 => mapping(address => uint256))
		public land2ItemBarEnhancedStrength;

	function _updateStrength(
		uint256 _apostleTokenId,
		uint256 _landTokenId,
		address _resource,
		bool _isStop
	) internal returns (uint256, uint256) {
		address miner =
			IInterstellarEncoder(
				registry.addressOf(CONTRACT_INTERSTELLAR_ENCODER)
			)
				.getObjectAddress(_apostleTokenId);
		uint256 strength =
			IMinerObject(miner).strengthOf(
				_apostleTokenId,
				_resource,
				_landTokenId
			);

		// V5 add item bar
		uint256 enhancedStrength =
			strength
				.mul(
				IItemBar(registry.addressOf(CONTRACT_LAND_ITEM_BAR))
					.enhanceStrengthRateOf(_resource, _landTokenId)
			)
				.div(RATE_PRECISION);

		if (_isStop) {
			mine(_landTokenId);
			land2ResourceMineState[_landTokenId].totalMinerStrength[
				_resource
			] = land2ResourceMineState[_landTokenId].totalMinerStrength[
				_resource
			]
				.sub(strength);

			land2ItemBarEnhancedStrength[_landTokenId][
				_resource
			] = land2ItemBarEnhancedStrength[_landTokenId][_resource].sub(
				enhancedStrength
			);
		} else {
			land2ResourceMineState[_landTokenId].totalMinerStrength[
				_resource
			] = land2ResourceMineState[_landTokenId].totalMinerStrength[
				_resource
			]
				.add(strength);

			land2ItemBarEnhancedStrength[_landTokenId][
				_resource
			] = land2ItemBarEnhancedStrength[_landTokenId][_resource].add(
				enhancedStrength
			);
		}
		return (strength, enhancedStrength);
	}

	function startMining(
		uint256 _tokenId,
		uint256 _landTokenId,
		address _resource
	) public {
		ITokenUse(registry.addressOf(CONTRACT_TOKEN_USE)).addActivity(
			_tokenId,
			msg.sender,
			0
		);
		// require the permission from land owner;
		require(
			isLander(_landTokenId, msg.sender),
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

		(uint256 strength, uint256 enhancedStrength) =
			_updateStrength(_tokenId, _landTokenId, _resource, false);

		miner2Index[_tokenId] = MinerStatus({
			landTokenId: _landTokenId,
			resource: _resource,
			indexInResource: uint64(_index)
		});

		emit StartMining(
			_tokenId,
			_landTokenId,
			_resource,
			strength,
			enhancedStrength
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

		(uint256 strength, uint256 enhancedStrength) =
			_updateStrength(_tokenId, landTokenId, resource, true);

		// if (land2ResourceMineState[landTokenId].totalMiners == 0) {
		// 	land2ResourceMineState[landTokenId].totalMinerStrength[
		// 		resource
		// 	] = 0;
		// 	land2ItemBarEnhancedStrength[landTokenId][resource] = 0;
		// }

		delete miner2Index[_tokenId];

		emit StopMining(
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
			_updateMinerStrengths(_apostleTokenId, true);
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
			_updateMinerStrengths(_apostleTokenId, false);
		// _isStop == true - minus strength
		// _isStop == false - add strength
		emit UpdateMiningStrengthWhenStart(
			_apostleTokenId,
			landTokenId,
			strength,
			enhancedStrength
		);
	}

	function _updateMinerStrengths(uint256 _apostleTokenId, bool _isStop)
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
	function updateAllMinerStrengthWhenStop(uint256 _landTokenId) public auth {
		mine(_landTokenId);
	}

	// can only be called by ItemBar
	// _isStop == false - add strength
	function updateAllMinerStrengthWhenStart(uint256 _landTokenId) public auth {
		if (land2ResourceMineState[_landTokenId].totalMiners == 0) {
			return;
		}
		_updateEnhancedStrengthByElement(
			_landTokenId,
			registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN)
		);
		_updateEnhancedStrengthByElement(
			_landTokenId,
			registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN)
		);
		_updateEnhancedStrengthByElement(
			_landTokenId,
			registry.addressOf(CONTRACT_WATER_ERC20_TOKEN)
		);
		_updateEnhancedStrengthByElement(
			_landTokenId,
			registry.addressOf(CONTRACT_FIRE_ERC20_TOKEN)
		);
		_updateEnhancedStrengthByElement(
			_landTokenId,
			registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN)
		);
	}

	function _updateEnhancedStrengthByElement(
		uint256 _landTokenId,
		address _resource
	) internal {
		if (land2ResourceMineState[_landTokenId].miners[_resource].length > 0) {
			uint256 strength =
				land2ResourceMineState[_landTokenId].totalMinerStrength[
					_resource
				];
			address itemBar = registry.addressOf(CONTRACT_LAND_ITEM_BAR);
			uint256 enhancedStrength =
				strength
					.mul(
					IItemBar(registry.addressOf(CONTRACT_LAND_ITEM_BAR))
						.enhanceStrengthRateOf(_resource, _landTokenId)
				)
					.div(RATE_PRECISION);

			land2ItemBarEnhancedStrength[_landTokenId][
				_resource
			] = enhancedStrength;
			emit UpdateEnhancedStrengthByElement(
				_landTokenId,
				_resource,
				enhancedStrength
			);
		}
	}

	function isLander(uint256 _landTokenId, address _to)
		internal
		view
		returns (bool)
	{
		return
			_to ==
			ERC721(registry.addressOf(CONTRACT_OBJECT_OWNERSHIP)).ownerOf(
				_landTokenId
			);
	}

	function _getMaxMineBalance(
		uint256 _tokenId,
		address _resourceToken,
		uint256 _currentTime,
		uint256 _lastUpdateTime
	) internal view returns (uint256) {
		// totalMinerStrength is in wei
		uint256 mineSpeed =
			land2ResourceMineState[_tokenId].totalMinerStrength[_resourceToken]
				.add(land2ItemBarEnhancedStrength[_tokenId][_resourceToken]);

		return mineSpeed.mul(_currentTime - _lastUpdateTime).div(1 days);
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
				land2ItemBarMinedBalance[_landTokenId][barStaker][
					_resourceToken
				] = land2ItemBarMinedBalance[_landTokenId][barStaker][
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

		if (land2ItemBarMinedBalance[_landTokenId][msg.sender][gold] > 0) {
			goldBalance = land2ItemBarMinedBalance[_landTokenId][msg.sender][
				gold
			];
			IMintableERC20(gold).mint(msg.sender, goldBalance);
			land2ItemBarMinedBalance[_landTokenId][msg.sender][gold] = 0;
		}

		if (land2ItemBarMinedBalance[_landTokenId][msg.sender][wood] > 0) {
			woodBalance = land2ItemBarMinedBalance[_landTokenId][msg.sender][
				wood
			];
			IMintableERC20(wood).mint(msg.sender, woodBalance);
			land2ItemBarMinedBalance[_landTokenId][msg.sender][wood] = 0;
		}

		if (land2ItemBarMinedBalance[_landTokenId][msg.sender][water] > 0) {
			waterBalance = land2ItemBarMinedBalance[_landTokenId][msg.sender][
				water
			];
			IMintableERC20(water).mint(msg.sender, waterBalance);
			land2ItemBarMinedBalance[_landTokenId][msg.sender][water] = 0;
		}

		if (land2ItemBarMinedBalance[_landTokenId][msg.sender][fire] > 0) {
			fireBalance = land2ItemBarMinedBalance[_landTokenId][msg.sender][
				fire
			];
			IMintableERC20(fire).mint(msg.sender, fireBalance);
			land2ItemBarMinedBalance[_landTokenId][msg.sender][fire] = 0;
		}

		if (land2ItemBarMinedBalance[_landTokenId][msg.sender][soil] > 0) {
			soilBalance = land2ItemBarMinedBalance[_landTokenId][msg.sender][
				soil
			];
			IMintableERC20(gold).mint(msg.sender, soilBalance);
			land2ItemBarMinedBalance[_landTokenId][msg.sender][soil] = 0;
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
		require(
			isLander(_landTokenId, msg.sender),
			"Must be the owner of the land."
		);

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
			isLander(_landTokenId, msg.sender),
			"Must be the owner of the land."
		);

		mine(_landTokenId);
		claimLandResource(_landTokenId);
		claimBarResource(_landTokenId);
	}

	function _calculateResources(
		address _to,
		uint256 _landTokenId,
		address _resourceToken,
		uint256 _minedBalance
	) internal view returns (uint256 landResource, uint256 barResource) {
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

		if (isLander(_landTokenId, _to)) {
			landResource = landResource.add(landBalance);
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
				if (_to == IItemBar(itemBar).getBarStaker(_landTokenId, i)) {
					barResource = barResource.add(barBalance);
				}
			}
		}
		return;
	}

	function availableResources(
		address _to,
		uint256 _landTokenId,
		address[5] _resourceTokens
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
			uint256 mined =
				_calculateMinedBalance(_landTokenId, _resourceTokens[i], now);

			uint256[2] available;
			(available[0], available[1]) = _calculateResources(
				_to,
				_landTokenId,
				_resourceTokens[i],
				mined
			);
			if (isLander(_landTokenId, _to)) {
				available[0] = available[0].add(
					land2ResourceMineState[_landTokenId].mintedBalance[
						_resourceTokens[i]
					]
				);
			}
			available[1] = available[1].add(
				land2ItemBarMinedBalance[_landTokenId][_to][_resourceTokens[i]]
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

	function getLandMinedBalance(uint256 _landTokenId, address _resourceToken)
		public
		view
		returns (uint256)
	{
		return
			land2ResourceMineState[_landTokenId].mintedBalance[_resourceToken];
	}

	function getBarMinedBalance(
		uint256 _landTokenId,
		address _to,
		address _resourceToken
	) public view returns (uint256) {
		return land2ItemBarMinedBalance[_landTokenId][_to][_resourceToken];
	}

	function getLandMiningStrength(uint256 _landTokenId, address _resourceToken)
		public
		view
		returns (uint256)
	{
		return
			land2ResourceMineState[_landTokenId].totalMinerStrength[
				_resourceToken
			];
	}

	function getBarMiningStrength(uint256 _landTokenId, address _resourceToken)
		public
		view
		returns (uint256)
	{
		return land2ItemBarEnhancedStrength[_landTokenId][_resourceToken];
	}

	function getMinerOnLand(uint256 _landTokenId, address _resourceToken)
		public
		view
		returns (uint256[])
	{
		return land2ResourceMineState[_landTokenId].miners[_resourceToken];
	}

	// function availableResources(
	// 	uint256 _landTokenId,
	// 	address[5] _resourceTokens
	// )
	// 	public
	// 	view
	// 	returns (
	// 		uint256,
	// 		uint256,
	// 		uint256,
	// 		uint256,
	// 		uint256
	// 	)
	// {
	// 	revert();
	// }

	// function getMinerOnLand(uint _landTokenId, address _resourceToken, uint _index) public view returns (uint256) {
	// revert();
	// }
}
