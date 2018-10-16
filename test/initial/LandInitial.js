const StandardERC223 = artifacts.require('StandardERC223');
const InterstellarEncoder = artifacts.require('InterstellarEncoder');
const SettingsRegistry = artifacts.require('SettingsRegistry');
const SettingIds = artifacts.require('SettingIds');
const LandBase = artifacts.require('LandBase');
const ObjectOwnership = artifacts.require('ObjectOwnership');
const Proxy = artifacts.require('OwnedUpgradeabilityProxy');
const LandBaseAuthority = artifacts.require('LandBaseAuthority');
const ObjectOwnershipAuthority = artifacts.require('ObjectOwnershipAuthority');
const TokenLocationAuthority = artifacts.require('TokenLocationAuthority')
const TokenLocation = artifacts.require('TokenLocation');

module.exports = {
    initiateLand : initiateLand
}

async function initiateLand(accounts) {
    let settingsRegistry = await SettingsRegistry.new();
    console.log('SettingsRegistry address : ', settingsRegistry.address);
    let gold = await StandardERC223.new("GOLD");
    console.log('gold address : ', gold.address);
    let wood = await StandardERC223.new("WOOD");
    console.log('wood address : ', wood.address);
    let water = await StandardERC223.new("WATER");
    console.log('water address : ', water.address);
    let fire = await StandardERC223.new("FIRE");
    console.log('fire address : ', fire.address);
    let soil = await StandardERC223.new("SOIL");
    console.log('soil address : ', soil.address);

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
    console.log('tokenLocation address : ', tokenLocation.address);
    let landBase = await LandBase.new({gas: 6000000});
    console.log('landBase address : ', landBase.address);

    
    let landBaseProxy = await Proxy.new();
    console.log('landBaseProxy address : ', landBaseProxy.address);

    let tokenLocationId = await settingsId.CONTRACT_TOKEN_LOCATION.call();
    await settingsRegistry.setAddressProperty(tokenLocationId, tokenLocation.address);

    // new TokenOwnerShip
    let objectOwnership = await ObjectOwnership.new();
    console.log('objectOwnership implementation: ', await objectOwnership.address);
    let objectOwnershipProxy = await Proxy.new();
    console.log('objectOwnershipProxy implementation: ', await objectOwnershipProxy.address);

    let interstellarEncoder = await InterstellarEncoder.new();
    console.log("interstellarEncoder address: ", interstellarEncoder.address);

    // register to settingsRegisty
    let landBaseId = await settingsId.CONTRACT_LAND_BASE.call();
    await settingsRegistry.setAddressProperty(landBaseId, landBaseProxy.address);

    let objectOwnershipId = await settingsId.CONTRACT_OBJECT_OWNERSHIP.call();
    await settingsRegistry.setAddressProperty(objectOwnershipId, objectOwnershipProxy.address);

    let interstellarEncoderId = await settingsId.CONTRACT_INTERSTELLAR_ENCODER.call();
    await settingsRegistry.setAddressProperty(interstellarEncoderId, interstellarEncoder.address);

    await interstellarEncoder.registerNewTokenContract(objectOwnershipProxy.address);
    await interstellarEncoder.registerNewObjectClass(landBaseProxy.address, 1);


    // let authority = await Authority.new(landBaseProxy.address);
    let landBaseAuthority = await LandBaseAuthority.new();
    let objectOwnershipAuthority = await ObjectOwnershipAuthority.new();
    let tokenLocationAuthority = await TokenLocationAuthority.new();

    await objectOwnershipAuthority.setWhitelist(landBaseProxy.address, true);
    await tokenLocationAuthority.setWhitelist(landBaseProxy.address, true);

    // upgrade
    await landBaseProxy.upgradeTo(landBase.address);
    await objectOwnershipProxy.upgradeTo(objectOwnership.address);

    await ObjectOwnership.at(objectOwnershipProxy.address).initializeContract(settingsRegistry.address);
    await LandBase.at(landBaseProxy.address).initializeContract(settingsRegistry.address);

    // set authority
    await tokenLocation.setAuthority(tokenLocationAuthority.address);
    await ObjectOwnership.at(objectOwnershipProxy.address).setAuthority(objectOwnershipAuthority.address);
    console.log('Intialize Successfully!')

    return {landBase: LandBase.at(landBaseProxy.address), objectOwnership:
        ObjectOwnership.at(objectOwnershipProxy.address),
        tokenLocation: tokenLocation,
        interstellarEncoder: interstellarEncoder,
        gold: gold, wood: wood, water: water, fire: fire, soil: soil}

}