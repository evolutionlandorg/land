pragma solidity ^0.4.23;

import "./interfaces/IItemBar.sol";
import "./LandResourceV4.sol";

contract LandResourceV5 is LandResourceV4 {
	// 0x434f4e54524143545f4954454d5f424152530000000000000000000000000000
	bytes32 public constant CONTRACT_ITEM_BARS = "CONTRACT_ITEM_BARS";

	// rate precision
	uint112 public constant RATE_DECIMALS = 10**8;

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

		// V5 add item bar
		address itemBar = registry.addressOf(CONTRACT_ITEM_BARS);
		uint256 enhanceRate =
			IItemBar(itemBar).enhanceStrengthRateOf(_resource, _landTokenId);
		uint256 enhanceStrength = strength.mul(enhanceRate).div(RATE_DECIMALS);
		uint256 enhancedStrength = strength.add(enhanceStrength);

		land2ResourceMineState[_landTokenId].miners[_resource].push(_tokenId);
		land2ResourceMineState[_landTokenId].totalMinerStrength[
			_resource
		] = land2ResourceMineState[_landTokenId].totalMinerStrength[_resource]
			.add(enhancedStrength);

		miner2Index[_tokenId] = MinerStatus({
			landTokenId: _landTokenId,
			resource: _resource,
			indexInResource: uint64(_index)
		});

		emit StartMining(_tokenId, _landTokenId, _resource, enhancedStrength);
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
		address itemBar = registry.addressOf(CONTRACT_ITEM_BARS);
		uint256 enhanceRate =
			IItemBar(itemBar).enhanceStrengthRateOf(_resource, _landTokenId);
		uint256 enhanceStrength = strength.mul(enhanceRate).div(RATE_DECIMALS);
		uint256 enhancedStrength = strength.add(enhanceStrength);

		// for backward compatibility
		// if strength can fluctuate some time in the future
		if (
			land2ResourceMineState[landTokenId].totalMinerStrength[resource] !=
			0
		) {
			if (
				land2ResourceMineState[landTokenId].totalMinerStrength[
					resource
				] > enhancedStrength
			) {
				land2ResourceMineState[landTokenId].totalMinerStrength[
					resource
				] = land2ResourceMineState[landTokenId].totalMinerStrength[
					resource
				]
					.sub(enhancedStrength);
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

		emit StopMining(_tokenId, landTokenId, resource, enhancedStrength);
	}

	// _isStop == true - minus strength
	function updateAllMinerStrengthWhenStop(uint256 _landTokenId) public auth {
		if (land2ResourceMineState[_landTokenId].totalMiners == 0) {
			return;
		}
		_updateMinweStrengthByElement(
			registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN),
			true
		);
		_updateMinweStrengthByElement(
			registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN),
			true
		);
		_updateMinweStrengthByElement(
			registry.addressOf(CONTRACT_WATER_ERC20_TOKEN),
			true
		);
		_updateMinweStrengthByElement(
			registry.addressOf(CONTRACT_WATER_ERC20_TOKEN),
			true
		);
		_updateMinweStrengthByElement(
			registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN),
			true
		);
	}

	// _isStop == false - add strength
	function updateAllMinerStrengthWhenStart(uint256 _landTokenId) public auth {
		if (land2ResourceMineState[_landTokenId].totalMiners == 0) {
			return;
		}
		_updateMinweStrengthByElement(
			registry.addressOf(CONTRACT_GOLD_ERC20_TOKEN),
			false
		);
		_updateMinweStrengthByElement(
			registry.addressOf(CONTRACT_WOOD_ERC20_TOKEN),
			false
		);
		_updateMinweStrengthByElement(
			registry.addressOf(CONTRACT_WATER_ERC20_TOKEN),
			false
		);
		_updateMinweStrengthByElement(
			registry.addressOf(CONTRACT_WATER_ERC20_TOKEN),
			false
		);
		_updateMinweStrengthByElement(
			registry.addressOf(CONTRACT_SOIL_ERC20_TOKEN),
			false
		);
	}

	function _updateMinweStrengthByElement(address _resourceToken, bool _isStop)
		internal
	{
		ResourceMineState state = land2ResourceMineState[_landTokenId];
		uint256[] miners = state[_resourceToken].miners;
		for (uint256 i = 0; i < miners.length; i++) {
			(uint256 landTokenId, uint256 strength) =
				_updateMinerStrength(miners[i], _isStop);
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

		mine(landTokenId);
		// V5 add item bar
		address itemBar = registry.addressOf(CONTRACT_ITEM_BARS);
		uint256 enhanceRate =
			IItemBar(itemBar).enhanceStrengthRateOf(_resource, _landTokenId);
		uint256 enhanceStrength = strength.mul(enhanceRate).div(RATE_DECIMALS);
		uint256 enhancedStrength = strength.add(enhanceStrength);

		if (_isStop) {
			land2ResourceMineState[landTokenId].totalMinerStrength[
				resource
			] = land2ResourceMineState[landTokenId].totalMinerStrength[resource]
				.sub(enhancedStrength);
		} else {
			land2ResourceMineState[_landTokenId].totalMinerStrength[
				_resource
			] = land2ResourceMineState[_landTokenId].totalMinerStrength[
				_resource
			]
				.add(enhancedStrength);
		}

		return (landTokenId, enhancedStrength);
	}
}
