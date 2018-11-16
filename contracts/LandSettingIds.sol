pragma solidity ^0.4.24;

import "@evolutionland/common/contracts/SettingIds.sol";
import "@evolutionland/common/contracts/interfaces/ISettingsRegistry.sol";

contract LandSettingIds is SettingIds {

    uint256 public constant GOLD_MAGNITUDE = 1;
    uint256 public constant WOOD_MAGNITUDE = 1;
    uint256 public constant WATER_MAGNITUDE = 1;
    uint256 public constant FIRE_MAGNITUDE = 1;
    uint256 public constant SOIL_MAGNITUDE = 1;

    // depositing X RING for 12 months, interest is about (1 * _unitInterest * X / 10**7) KTON
    // default: 1000
    // bytes32 public constant UINT_BANK_UNIT_INTEREST = "UINT_BANK_UNIT_INTEREST";

    // penalty multiplier
    // default: 3
    // bytes32 public constant UINT_BANK_PENALTY_MULTIPLIER = "UINT_BANK_PENALTY_MULTIPLIER";
}