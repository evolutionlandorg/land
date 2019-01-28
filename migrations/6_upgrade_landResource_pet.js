const Proxy = artifacts.require('OwnedUpgradeabilityProxy');
const LandResourceV3 = artifacts.require('LandResourceV3');
const LandResourceAuthorityV3 = artifacts.require("LandResourceAuthorityV3");

const conf = {
    landResourceProxy_address: '0x6bcb3c94040ba63e4da086f2a8d0d6f5f72b8490',
    tokenUseProxy_address: '0xd2bcd143db59ddd43df2002fbf650e46b2b7ea19',
    ckAdaptorProxy_address: '0x4122003245bd1dd45e32d241c629ce6194768aba'
}

module.exports = async (deployer, network) => {

    if (network != 'kovan') {
        return;
    }

    deployer.deploy(LandResourceV3).then(async () => {
        await Proxy.at(conf.landResourceProxy_address).upgradeTo(LandResourceV3.address);
        await deployer.deploy(LandResourceAuthorityV3, [conf.tokenUseProxy_address, conf.ckAdaptorProxy_address]);
    }).then(async() => {

        // setAuthority
        let landResourceProxy = await LandResourceV3.at(conf.landResourceProxy_address);
        await landResourceProxy.setAuthority(LandResourceAuthorityV3.address);

    })


}