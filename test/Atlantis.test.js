const StandardERC223 = artifacts.require('StandardERC223');
const InterstellarEncoder = artifacts.require('InterstellarEncoder');
const SettingsRegistry = artifacts.require('SettingsRegistry');
const SettingIds = artifacts.require('SettingIds');
const LandBase = artifacts.require('LandBase');
const ObjectOwnership = artifacts.require('ObjectOwnership');
const Proxy = artifacts.require('OwnedUpgradeabilityProxy');
const Authority = artifacts.require('Authority');
const TokenLocation = artifacts.require('TokenLocation');
const initial = require('./initial/LandInitial');
var initiateLand = initial.initiateLand;
const Web3 = require('web3');
var web3 = new Web3(Web3.givenProvider);


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

        let objectInLand = await landBase.objectOwnership();
        console.log("objectInLand: ", objectInLand);
        let cancall1 = await Authority.at(await objectOwnership.authority()).canCall(landBase.address, objectOwnership.address,
            web3.eth.abi.encodeFunctionSignature('mintObject(address,uint128)'));
        assert(cancall1, 'cancall1 should be true');
        let cancall2 = await Authority.at(await tokenLocation.authority()).canCall(landBase.address, tokenLocation.address,
            web3.eth.abi.encodeFunctionSignature('setTokenLocation(uint256,int256,int256)'));
        assert(cancall2, 'cancall2 should be true');
    })

    it('assign new land', async () => {
        let tokenId = await landBase.assignNewLand(-90, 12, accounts[0], 100, 99, 98, 97, 96, 4);
        console.log("tokenId: ", tokenId.valueOf());
        let tokenOne = await interstellarEncoder.encodeTokenIdForObjectContract(objectOwnership.address, landBase.address, 1);
        console.log("tokenOne: ", tokenOne.valueOf());
        let owner = await objectOwnership.ownerOf(tokenOne);
        assert.equal(owner, accounts[0]);
    })

})