pragma solidity ^0.4.24;

import "@evolutionland/common/contracts/SettingIds.sol";
import "@evolutionland/common/contracts/interfaces/ISettingsRegistry.sol";

contract LandSettingIds is SettingIds {

    uint256 public constant GOLD_MAGNITUDE = 1;
    uint256 public constant WOOD_MAGNITUDE = 1;
    uint256 public constant WATER_MAGNITUDE = 1;
    uint256 public constant FIRE_MAGNITUDE = 1;
    uint256 public constant SOIL_MAGNITUDE = 1;

    bytes32 public constant CONTRACT_MINER = "CONTRACT_MINER";

}