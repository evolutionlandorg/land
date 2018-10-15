pragma solidity ^0.4.24;

import '@evolutionland/common/contracts/InterstellarEncoder.sol';
import '@evolutionland/common/contracts/SettingsRegistry.sol';
import '@evolutionland/common/contracts/SettingIds.sol';
import '@evolutionland/common/contracts/StandardERC223.sol';
import '@evolutionland/common/contracts/TokenOwnership.sol';
import "@evolutionland/upgraeability-using-unstructured-storage/contracts/OwnedUpgradeabilityProxy.sol";
import "@evolutionland/common/contracts/TokenLocation.sol";

contract Migrations {
  address public owner;
  uint public last_completed_migration;

  constructor() public {
    owner = msg.sender;
  }

  modifier restricted() {
    if (msg.sender == owner) _;
  }

  function setCompleted(uint completed) public restricted {
    last_completed_migration = completed;
  }

  function upgrade(address new_address) public restricted {
    Migrations upgraded = Migrations(new_address);
    upgraded.setCompleted(last_completed_migration);
  }
}
