pragma solidity ^0.4.24;

interface IItemBar {
	//0x33372e46
	function enhanceStrengthRateOf(
		address _resourceToken,
		uint256 _tokenId
	) external view returns (uint256);

	function maxAmount() external view returns (uint256);

	//0x993ac21a
	function enhanceStrengthRateByIndex(
		address _resourceToken,
		uint256 _landTokenId,
		uint256 _index
	) external view returns (uint256);

	//0x09d367f1
	function getBarItem(uint256 _landTokenId, uint256 _index)
		external
		view
		returns (address, uint256, address);

	//0xc46f18f7
	function getStatusByItem(address _item, uint256 _itemId)
		external	
		view
		returns (address, uint256, address, uint256);
}
