const StandardERC223 = artifacts.require('StandardERC223');
const InterstellarEncoder = artifacts.require('InterstellarEncoder');
const SettingsRegistry = artifacts.require('SettingsRegistry');
const SettingIds = artifacts.require('SettingIds');
const LandBase = artifacts.require('LandBase');
const TokenOwnership = artifacts.require('TokenOwnership');
const Proxy = artifacts.require('OwnedUpgradeabilityProxy');
const TokenOwnershipAuthority = artifacts.require('TokenOwnershipAuthority');
const TokenLocation = artifacts.require('TokenLocation');

module.exports = {
    initiateLand : initiateLand
}

async function initiateLand(accounts) {
    let settingsRegistry = await SettingsRegistry.new();

    let gold = await StandardERC223.new("GOLD");
    let wood = await StandardERC223.new("WOOD");
    let water = await StandardERC223.new("WATER");
    let fire = await StandardERC223.new("FIRE");
    let soil = await StandardERC223.new("SOIL");

    let settingsId = await SettingIds.new();

    let goldId = await settingsId.CONTRACT_GOLD_ERC20_TOKEN.call();
    let woodId = await settingsId.CONTRACT_WOOD_ERC20_TOKEN.call();
    let waterId = await settingsId.CONTRACT_WATER_ERC20_TOKEN.call();
    let fireId = await settingsId.CONTRACT_FIRE_ERC20_TOKEN.call();
    let soilId = await settingsId.CONTRACT_SOIL_ERC20_TOKEN.call();

    // register resouces to registry
    await settingsRegistry.setAddressProperty(goldId, gold.address);
    await settingsRegistry.setAddressProperty(woodId, wood.address);
    await settingsRegistry.setAddressProperty(waterId, water.address);
    await settingsRegistry.setAddressProperty(fireId, fire.address);
    await settingsRegistry.setAddressProperty(soilId, soil.address);

    // new LandBase
    let tokenLocation = await TokenLocation.new();
    let landBase = await LandBase.new();
    let landBaseProxy = await Proxy.new();
    await landBaseProxy.upgradeTo(landBase);

    // new TokenOwnerShip
    let tokenOwnership = await TokenOwnerShip.new();
    let tokenOwnershipProxy = await Proxy.new();

    // register to settingsRegisty
    let landBaseId = await settingsId.CONTRACT_LAND_BASE.call();
    await settingsRegistry.setAddressProperty(landBaseId, landBaseProxy.address);
    let tokenOwnershipId = await settingsId.CONTRACT_TOKEN_OWNERSHIP.call();
    await settingsRegistry.setAddressProperty(tokenOwnershipId, tokenOwnershipProxy);

    await landBaseProxy.initializeContract(settingsRegistry.address, tokenLocation.address);
    let tokenOwnershipAuthority = await TokenOwnershipProxy.new(landBaseProxy.address);
    await tokenOwnershipProxy.upgradeTo(tokenOwnership);
    await tokenOwnership.initializeContract(settingsRegistry.address);

    await tokenOwnershipProxy.setAuthority(tokenOwnershipAuthority.address);

    return {landBase: landBaseProxy, tokenOwnership: tokenOwnershipProxy, gold: gold, wood: wood, water: water, fire: fire, soil: soil}

}