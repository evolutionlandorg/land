pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract UserRegistry is Ownable {
    mapping (address => uint) public latestPing;

        function ping() external {
          latestPing[msg.sender] = block.timestamp;
          // TODO: get the industry activies index of related land, and update LandResourceManager.
    }

    function setLatestToNow(address user) external {
//        // TODO: review and double check the meanings of isApprovedForAll in ERC721
//        require(msg.sender == owner || isApprovedForAll(user, msg.sender), "Unauthorized user");
        latestPing[user] = block.timestamp;
    }
    
}