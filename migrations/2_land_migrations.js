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
const LocationCoder = artifacts.require("./LocationCoder.sol");

let gold_address;
let wood_address;
let water_address;
let fire_address;
let soil_address;

let landBaseProxy_address;
let objectOwnershipProxy_address;
let tokenLocationProxy_address

module.exports = async (deployer, network, accounts) => {
    deployer.deploy(LocationCoder);
    deployer.link(LocationCoder, TokenLocation);
    deployer.link(LocationCoder, LandBase);

    if (network == "development") {
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
        await deployer.deploy(Proxy);
        await deployer.deploy(LandBase)
    }).then(async () => {
        let tokenLocationProxy = await Proxy.deployed();
        tokenLocationProxy_address = tokenLocationProxy.address;
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
        let tokenLocation = await TokenLocation.deployed();

        let objectOwnershipAuthority = await ObjectOwnershipAuthority.deployed();
        let tokenLocationAuthority = await TokenLocationAuthority.deployed();
        await objectOwnershipAuthority.setWhitelist(landBaseProxy_address, true);
        await tokenLocationAuthority.setWhitelist(landBaseProxy_address, true);

        // register in registry
        let objectOwnershipId = await settingIds.CONTRACT_OBJECT_OWNERSHIP.call();
        let landBaseId = await settingIds.CONTRACT_LAND_BASE.call();
        let tokenLocationId = await settingIds.CONTRACT_TOKEN_LOCATION.call();
        await settingsRegistry.setAddressProperty(landBaseId,landBaseProxy_address);
        await settingsRegistry.setAddressProperty(objectOwnershipId, objectOwnershipProxy_address);
        await settingsRegistry.setAddressProperty(tokenLocationId, tokenLocationProxy_address);

        // upgrade
        await Proxy.at(landBaseProxy_address).upgradeTo(landBase.address);
        await Proxy.at(objectOwnershipProxy_address).upgradeTo(objectOwnership.address);
        await Proxy.at(tokenLocationProxy_address).upgradeTo(tokenLocation.address);

        // verify proxies' implementations
        let landBase_impl = await Proxy.at(landBaseProxy_address).implementation();
        console.log("landBase_impl: ", landBase_impl);
        let objectOwnership_impl = await Proxy.at(objectOwnershipProxy_address).implementation()
        console.log("objectOwnership_impl: ", objectOwnership_impl);
        let tokenLocation_impl = await Proxy.at(tokenLocationProxy_address).implementation();
        console.log("tokenLocation_impl: ", tokenLocation_impl);

        let tokenLocationProxy = await TokenLocation.at(tokenLocationProxy_address);
        await tokenLocationProxy.initializeContract();
        let landProxy = await LandBase.at(landBaseProxy_address);
        landProxy.initializeContract(settingsRegistry.address);
        await ObjectOwnership.at(objectOwnershipProxy_address).initializeContract(settingsRegistry.address);

        // set authority
        await tokenLocationProxy.setAuthority(tokenLocationAuthority.address);
        await ObjectOwnership.at(objectOwnershipProxy_address).setAuthority(objectOwnershipAuthority.address);
        console.log('Intialize Successfully!')

    })

}