pragma solidity ^0.4.24;


// TODO: upgrade common-contacts version then delete this.
contract IApostleBase {
    function createApostle(uint256 _matronId, uint256 _sireId, uint256 _generation, uint256 _genes, uint256 _talents, address _owner) public;

    function isReadyToBreed(uint256 _apostleId) public view returns (bool);
}