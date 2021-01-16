pragma solidity ^0.4.24;

interface IMetaDataTeller {
	function addTokenMeta(
		address _token,
		uint16 _grade,
		uint112 _strengthRate
	) external;

	//0xf666196d
	function getMetaData(address _token, uint256 _id)
		external
		view
		returns (
			uint16,
			uint16,
			uint16
		);

	//0x7999a5cf
	function getPrefer(address _token) external view returns (uint256);

	//0x33281815
	function getRate(
		address _token,
		uint256 _id,
		uint256 _index
	) external view returns (uint256);
}
