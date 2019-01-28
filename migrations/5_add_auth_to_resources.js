const StandardERC223 = artifacts.require('StandardERC223')
const MintAndBurnAuthority = artifacts.require('MintAndBurnAuthority');

const conf = {
    gold_address: '0xf2b3aeba2fd26eb9c7af802e728069f1c217e565',
    wood_address: '0x9314fc7e0a2825f5b2a38bed43ddfdf1b30216b1',
    water_address: '0xbffb29084e610ffea58bbd81f044cdb68979babd',
    fire_address: '0x5f405a65b67a2ba03ffd1fdf20e0e92b50e41ae3',
    soil_address: '0x8a768e5dafa2950b0d0a686d45b5226ffeb24aa6',
    landResourceProxy_address: '0x6bcb3c94040ba63e4da086f2a8d0d6f5f72b8490'
}

module.exports = async(deployer, network) => {

    if(network == 'kovan') {
        return;
    }


    deployer.deploy(MintAndBurnAuthority, [conf.landResourceProxy_address]).then(async() => {
        await StandardERC223.at(conf.gold_address).setAuthority(MintAndBurnAuthority.address);
        await StandardERC223.at(conf.wood_address).setAuthority(MintAndBurnAuthority.address);
        await StandardERC223.at(conf.water_address).setAuthority(MintAndBurnAuthority.address);
        await StandardERC223.at(conf.fire_address).setAuthority(MintAndBurnAuthority.address);
        await StandardERC223.at(conf.soil_address).setAuthority(MintAndBurnAuthority.address);
    })
}