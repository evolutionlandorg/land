var LandAsset = artifacts.require("./contracts/LandEvolution.sol");

module.exports = function(deployer) {
    deployer.deploy(LandAsset);
};
