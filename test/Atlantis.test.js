const StandardERC223 = artifacts.require('StandardERC223');
const InterstellarEncoder = artifacts.require('InterstellarEncoder');
const SettingsRegistry = artifacts.require('SettingsRegistry');
const SettingIds = artifacts.require('SettingIds');
const LandBase = artifacts.require('LandBase');
const TokenOwnership = artifacts.require('TokenOwnership');
const Proxy = artifacts.require('OwnedUpgradeabilityProxy');
const TokenOwnershipAuthority = artifacts.require('TokenOwnershipAuthority');
const TokenLocation = artifacts.require('TokenLocation');
const initial = require('./initial/LandInitial');
var initiateLand = initial.initiateLand;

contract('Land series contracts', async (accounts) => {
    let gold;
    let wood;
    let water;
    let fire;
    let soil;
    let landBase;
    let tokenOwnership;

    before('intialize', async () => {
      var initlal = await initiateLand(accounts);
        gold = initlal.gold;
        wood = initlal.wood;
        water = initlal.water;
        fire = initlal.fire;
        soil = initlal.soil;
        landBase = initlal.landBase;
        tokenOwnership = initlal.tokenOwnership;
    })

    it('assign new land', async () => {
        let tokendId = await landBase.assignNewLand(-90, 12, accounts[0], 100, 99, 98, 97, 96, 4);
        let owner = await tokenOwnership.ownerOf(tokendId);
        assert.equal(owner, accounts[0]);
    })
})