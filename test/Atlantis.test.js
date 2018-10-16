const StandardERC223 = artifacts.require('StandardERC223');
const InterstellarEncoder = artifacts.require('InterstellarEncoder');
const SettingsRegistry = artifacts.require('SettingsRegistry');
const SettingIds = artifacts.require('SettingIds');
const LandBase = artifacts.require('LandBase');
const ObjectOwnership = artifacts.require('ObjectOwnership');
const Proxy = artifacts.require('OwnedUpgradeabilityProxy');
const ObjectOwnershipAuthority = artifacts.require('ObjectOwnershipAuthority');
const TokenLocationAuthority = artifacts.require('TokenLocationAuthority');
const TokenLocation = artifacts.require('TokenLocation');
const initial = require('./initial/LandInitial');
var initiateLand = initial.initiateLand;
const Web3 = require('web3');
var web3 = new Web3(Web3.givenProvider);

var from = '0x4cc4c344eba849dc09ac9af4bff1977e44fc1d7e';

contract('Land series contracts', async (accounts) => {
    let gold;
    let wood;
    let water;
    let fire;
    let soil;
    let landBase;
    let objectOwnership;
    let tokenLocation;
    let interstellarEncoder;
    let landBaseProxy;

    before('intialize', async () => {
      var initlal = await initiateLand(accounts);
        gold = initlal.gold;
        wood = initlal.wood;
        water = initlal.water;
        fire = initlal.fire;
        soil = initlal.soil;
        landBase = initlal.landBase;
        objectOwnership = initlal.objectOwnership;
        tokenLocation = initlal.tokenLocation;
        interstellarEncoder = initlal.interstellarEncoder;
    })

    it('test initialization', async () => {
        let cancall1 = await ObjectOwnershipAuthority.at(await objectOwnership.authority()).canCall(landBase.address, objectOwnership.address,
            web3.eth.abi.encodeFunctionSignature('mintObject(address,uint128)'));
        assert(cancall1, 'cancall1 should be true');
        let cancall2 = await TokenLocationAuthority.at(await tokenLocation.authority()).canCall(landBase.address, tokenLocation.address,
            web3.eth.abi.encodeFunctionSignature('setTokenLocationHM(uint256,int256,int256)'));
        assert(cancall2, 'cancall2 should be true');
    })

    it('assign new land', async () => {
        // let attr = 100 + 99 * 65536 + 98 * 65536 * 65536 + 97 * 65536 * 65536 * 65536 + 96 * 65536 * 65536 * 65536 * 65536;
        // let attr = 1770914734569771171940;
        // console.log(attr);
        let tokenId = await landBase.assignNewLand(-90, 13, from
            , "1770914734569771171940", 4);
        console.log("tokenId: ", tokenId.valueOf());
        let tokenOne = await interstellarEncoder.encodeTokenIdForObjectContract(objectOwnership.address, landBase.address, 1);
        console.log("tokenOne: ", tokenOne.valueOf());
        // console.log("tokenOne: ", tokenOne.toNubmer());
        let owner = await objectOwnership.ownerOf(tokenOne);
        assert.equal(owner, from);

        let xxx = await landBase.getResourceRateAttr.call(tokenOne.valueOf())
        console.log(xxx.valueOf());

        assert.equal((await landBase.getResourceRate.call(tokenOne.valueOf(), gold.address)).toNumber(), 100);
        assert.equal((await landBase.getResourceRate.call(tokenOne.valueOf(), wood.address)).toNumber(), 99);
        assert.equal((await landBase.getResourceRate.call(tokenOne.valueOf(), water.address)).toNumber(), 98);
        assert.equal((await landBase.getResourceRate.call(tokenOne.valueOf(), fire.address)).toNumber(), 97);
        assert.equal((await landBase.getResourceRate.call(tokenOne.valueOf(), soil.address)).toNumber(), 96);
    })

})