pragma solidity ^0.4.25;

interface IItemBar {
	function enhanceStrengthRateOf(
		address _resourceToken,
		uint256 _tokenId
	) external view returns (uint256);

	function maxAmount() external view returns (uint256);

	function enhanceStrengthRateByindex(
		address _resourceToken,
		uint256 _landTokenId,
		uint256 _index
	) external view returns (uint256);

	function getBarStaker(uint256 _landTokenId, uint256 _index)
		external
		view
		returns (address);
}
