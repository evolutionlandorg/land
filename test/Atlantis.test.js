const Atlantis = artifacts.require("Atlantis.sol");


var atlantis;


contract('atlantis', async(accounts) => {
    it('assign new land to account[1]', async() => {
        atlantis = await Atlantis.new({from:accounts[0]});
        let tokenId = await atlantis.encodeTokenId(-99, 12);
        console.log(tokenId.toString(16));
        await atlantis.assignNewLand(-99, 12, accounts[1]);
        let owner = await atlantis.ownerOf(tokenId);
        assert.equal(owner, accounts[1]);
    });

    it('land position out of range, should return error', async() => {
        try {
            await atlantis.assignNewLand(-99, 32, accounts[1]);
            assert(false, 'did not throw')
        } catch (error) {
            return (error.toString());
        }
    });

})