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

let gold_address;
let wood_address;
let water_address;
let fire_address;
let soil_address;

let landBaseProxy_address;
let objectOwnershipProxy_address;

module.exports = async (deployer, network, accounts) => {
    if (network != "development") {
        return;
    }
    // deployer.deploy(LandBaseAuthority);
    deployer.deploy(ObjectOwnershipAuthority);
    deployer.deploy(TokenLocationAuthority);
    deployer.deploy(StandardERC223, "GOLD"
    ).then(async() => {
        let gold = await StandardERC223.deployed();
        gold_address = gold.address;
        return deployer.deploy(StandardERC223, "WOOD")
    }).then(async() => {
        let wood = await StandardERC223.deployed();
        wood_address = wood.address;
        return deployer.deploy(StandardERC223, "WATER")
    }).then(async() => {
        let water = await StandardERC223.deployed();
        water_address = water.address;
        return deployer.deploy(StandardERC223, "FIRE")
    }).then(async () => {
        let fire = await StandardERC223.deployed();
        fire_address = fire.address;
        return deployer.deploy(StandardERC223, "SOIL")
    }).then(async() => {
        let soil = await StandardERC223.deployed();
        soil_address = soil.address;
        await deployer.deploy(SettingIds);
        await deployer.deploy(SettingsRegistry);
        await deployer.deploy(TokenLocation);
        await deployer.deploy(LandBase)
    }).then(async () => {
        return deployer.deploy(Proxy);
    }).then(async() => {
        let landBaseProxy = await Proxy.deployed();
        landBaseProxy_address = landBaseProxy.address;
        console.log("landBase proxy: ", landBaseProxy_address);
        await deployer.deploy(Proxy);
        return Proxy.deployed();
    }).then(async() => {
        await deployer.deploy(ObjectOwnership);
        let objectOwnershipProxy = await Proxy.deployed();
        objectOwnershipProxy_address = objectOwnershipProxy.address;
        console.log("objectOwnership proxy: ", objectOwnershipProxy_address);
        await deployer.deploy(InterstellarEncoder);
    }).then(async () => {

        let settingIds = await SettingIds.deployed();
        let settingsRegistry = await SettingsRegistry.deployed();

        let goldId = await settingIds.CONTRACT_GOLD_ERC20_TOKEN.call();
        let woodId = await settingIds.CONTRACT_WOOD_ERC20_TOKEN.call();
        let waterId = await settingIds.CONTRACT_WATER_ERC20_TOKEN.call();
        let fireId = await settingIds.CONTRACT_FIRE_ERC20_TOKEN.call();
        let soilId = await settingIds.CONTRACT_SOIL_ERC20_TOKEN.call();

        // register resouces to registry
        await settingsRegistry.setAddressProperty(goldId, gold_address);
        await settingsRegistry.setAddressProperty(woodId, wood_address);
        await settingsRegistry.setAddressProperty(waterId, water_address);
        await settingsRegistry.setAddressProperty(fireId, fire_address);
        await settingsRegistry.setAddressProperty(soilId, soil_address);

        let interstellarEncoder = await InterstellarEncoder.deployed();
        let interstellarEncoderId = await settingIds.CONTRACT_INTERSTELLAR_ENCODER.call();
        await settingsRegistry.setAddressProperty(interstellarEncoderId, interstellarEncoder.address);

        await interstellarEncoder.registerNewTokenContract(objectOwnershipProxy_address);
        await interstellarEncoder.registerNewObjectClass(landBaseProxy_address, 1);


        let landBase = await LandBase.deployed();
        let objectOwnership = await ObjectOwnership.deployed();

        let objectOwnershipAuthority = await ObjectOwnershipAuthority.deployed();
        let tokenLocationAuthority = await TokenLocationAuthority.deployed();
        await objectOwnershipAuthority.setWhitelist(landBaseProxy_address, true);
        await tokenLocationAuthority.setWhitelist(landBaseProxy_address, true);

        // register in registry
        let objectOwnershipId = await settingIds.CONTRACT_OBJECT_OWNERSHIP.call();
        let landBaseId = await settingIds.CONTRACT_LAND_BASE.call();
        await settingsRegistry.setAddressProperty(landBaseId,landBaseProxy_address);
        await settingsRegistry.setAddressProperty(objectOwnershipId, objectOwnershipProxy_address);

        // upgrade
        await Proxy.at(landBaseProxy_address).upgradeTo(landBase.address);
        await Proxy.at(objectOwnershipProxy_address).upgradeTo(objectOwnership.address);

        let impl1 = await Proxy.at(landBaseProxy_address).implementation();
        console.log("impl1: ", impl1);
        let impl2 = await Proxy.at(objectOwnershipProxy_address).implementation()
        console.log("impl2: ", impl2);

        let tokenLocation = await TokenLocation.deployed();
        let landProxy = await LandBase.at(landBaseProxy_address);
        landProxy.initializeContract(settingsRegistry.address, tokenLocation.address);
        await ObjectOwnership.at(objectOwnershipProxy_address).initializeContract(settingsRegistry.address);

        // set authority
        await tokenLocation.setAuthority(tokenLocationAuthority.address);
        await ObjectOwnership.at(objectOwnershipProxy_address).setAuthority(objectOwnershipAuthority.address);
        console.log('Intialize Successfully!')


    })

}