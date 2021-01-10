pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/introspection/ERC165.sol";

contract IMinerObject is ERC165  {
    bytes4 internal constant InterfaceId_IMinerObject = 0x64272b75;
    
    /*
     * 0x64272b752 ===
     *   bytes4(keccak256('strengthOf(uint256,address)'))
     */

    function strengthOf(uint256 _tokenId, address _resourceToken, uint256 _landTokenId) public view returns (uint256);

    function cachedStrengthOf(uint256 _tokenId, address _resourceToken, uint256 _landTokenId) public returns (uint256); 

}
