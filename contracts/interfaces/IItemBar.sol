pragma solidity ^0.4.24;

interface IItemBar {
	function enhanceStrengthRateOf(
		address _resourceToken,
		uint256 _landTokenId
	) public view returns (uint256);
}
