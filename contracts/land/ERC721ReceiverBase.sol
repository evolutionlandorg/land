pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721Receiver.sol";

contract ERC721ReceiverBase is ERC721Receiver{

    bytes4 internal constant ERC721_RECEIVED = 0x150b7a02;

    function onERC721Received(address _from, uint256 _tokenId, bytes _data) public returns(bytes4) {
        return bytes4(keccak256("onERC721Received(address,uint256,bytes)"));
    }
}
