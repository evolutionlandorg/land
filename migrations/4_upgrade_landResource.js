const Proxy = artifacts.require('OwnedUpgradeabilityProxy');
const LandResource = artifacts.require('LandResource');

const conf = {
    landResourceProxy_address: '0x6bcb3c94040ba63e4da086f2a8d0d6f5f72b8490'
}

module.exports = async (deployer, network) => {

    if (network != 'kovan') {
        return;
    }

    deployer.deploy(LandResource).then(async () => {
        await Proxy.at(conf.landResourceProxy_address).upgradeTo(LandResource.address);
    })


}