const Proxy = artifacts.require('OwnedUpgradeabilityProxy');
const LandResource = artifacts.require('LandResource');
const LandResourceAuthority = artifacts.require('LandResourceAuthority');

const conf = {
    registry_address: '0xd8b7a3f6076872c2c37fb4d5cbfeb5bf45826ed7',
    tokenUseProxy_address: '0xd2bcd143db59ddd43df2002fbf650e46b2b7ea19'
}

module.exports = async(deployer, network) => {
    if(network == 'kovan') {
        return;
    }

    deployer.deploy(Proxy);
    deployer.deploy(LandResource).then(async() => {
        await deployer.deploy(LandResourceAuthority, [conf.tokenUseProxy_address])
    }).then(async() => {
        await Proxy.at(Proxy.address).upgradeTo(LandResource.address);
        console.log("UPGRADE DONE!");

        let landResourceProxy = await LandResource.at(Proxy.address);
        await landResourceProxy.initializeContract(conf.registry_address, 1544083267);
        console.log("INITIALIZE DONE!");

        await landResourceProxy.setAuthority(LandResourceAuthority.address);

        console.log('MIGRATION SUCCESS!');


    })
}