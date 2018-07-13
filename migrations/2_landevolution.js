var LandAsset = artifacts.require("./contracts/LandEvolutionForbb.sol");

module.exports = function(deployer) {
    deployer.deploy(LandAsset);
};
