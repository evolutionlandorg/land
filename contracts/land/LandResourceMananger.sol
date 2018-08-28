pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./LandGenesisData.sol";
import "./Atlantis.sol";

/**
 * @title LandResourceManager
 * @dev LandResourceManager that records the resources on Land, and resource releasing speed.
 */
contract LandResourceManager is Ownable{
    using SafeMath for *;

    LandGenesisData public landGenesisData;
    Atlantis public atlantis;


    // ERC20 resource tokens
    address public gold;
    address public wood;
    address public hho;
    address public fire;
    address public sioo;


    uint256 resourceReleaseStartTime;


    // TODO: move to global settings contract.
    uint256 public aattenPerDay = 1; // The 
    uint256 public recoveAttenPerDay = 20;
    uint256 public denominator = 10000;

    uint256 denominator_in_seconds = denominator * (1 days);

    // Struct for recording resouces on land which have already been pinged.
    // 金, Evolution Land Gold
    // 木, Evolution Land Wood
    // 水, Evolution Land Water
    // 火, Evolution Land fire
    // 土, Evolution Land Silicon
    struct UpdatedElementResource {
        mapping(address=>uint256) updatedBalances;
        uint256 lastUpdateTime;
        uint256 lastUpdateSpeedInSecondsDenominator;
        uint256 lastDestoryAttenInSecondsDenominator;
    }

    mapping (uint256 => UpdatedElementResource) public resourceBalance;

    constructor(address _landGenesisData, address _atlantis, uint256 _resourceReleaseStartTime, address _gold, address _wood, address _hho, address _fire, address _sioo) public {
        landGenesisData = LandGenesisData(_landGenesisData);
        atlantis = Atlantis(_atlantis);
        resourceReleaseStartTime = _resourceReleaseStartTime;

        gold = _gold;
        wood = _wood;
        hho = _hho;
        fire = _fire;
        sioo = _sioo;
    }


    function ping(uint256 _tokenId, bytes _data) public {
        require(msg.sender == address(atlantis));

        // TODO: 

        // TODO: update lastUpdateSpeedInSecondsDenominator according to activities and detroy rate.
    }

    function _getSpeedInSecondsDenominatorForLand(uint256 _tokenId, uint256 _time) internal view returns (uint256 currentSpeed) {
        require(_time > resourceReleaseStartTime);
        require(_time > resourceBalance[_tokenId].lastUpdateTime);

        if (denominator_in_seconds < _time - resourceReleaseStartTime)
        {
            return 0;
        }

        uint256 v_max_d = denominator_in_seconds.sub( _time - resourceReleaseStartTime);

        uint256 time_between = _time - resourceBalance[_tokenId].lastUpdateTime;

        // the recover speed is 20/10000, 20 times.
        uint256 v_next_d = resourceBalance[_tokenId].lastUpdateSpeedInSecondsDenominator + time_between * recoveAttenPerDay;

        if (v_next_d < time_between * resourceBalance[_tokenId].lastDestoryAttenInSecondsDenominator)
        {
            v_next_d = 0;
        } else {
            v_next_d = v_next_d - time_between * resourceBalance[_tokenId].lastDestoryAttenInSecondsDenominator;
        }

        if (v_next_d > v_max_d){
            v_next_d = v_max_d;
        }

        return v_next_d;
    }

    function getCurrentSpeedForLand(uint256 _tokenId, address _resourceToken) public view returns (uint256 currentSpeed) {

        return _getInitSpeedForLand(_tokenId, _resourceToken).mul(_getSpeedInSecondsDenominatorForLand(_tokenId, now)).div(denominator_in_seconds);
    }

    function _getInitSpeedForLand(uint256 _tokenId, address _resourceToken) internal view returns (uint256 initSpeed) {
        var (v_gold_init, v_wood_init, v_water_init, v_fire_init, v_soil_init, flag) = landGenesisData.getDetailsFromLandInfo(_tokenId);

        if (_resourceToken == gold){
            initSpeed = v_gold_init;
        } else if (_resourceToken == wood){
            initSpeed = v_wood_init;
        } else if (_resourceToken == hho){
            initSpeed = v_water_init;
        } else if (_resourceToken == fire){
            initSpeed = v_fire_init;
        } else if (_resourceToken == sioo){
            initSpeed = v_soil_init;
        } else {
            return 0;
        }
    }


    /**
     * @dev Get and Query the amount of resources available for use on specific land.
     * @param _tokenId The token id of specific land.
    */
    function getCurrentBalanceOnLandForResource(uint256 _tokenId, address _resourceToken) public view 
    returns (uint256 currentBalance) {
        // first, add the updated balance
        currentBalance = resourceBalance[_tokenId].updatedBalances[_resourceToken];

        if (_resourceToken != gold && _resourceToken != wood && _resourceToken != hho && _resourceToken != fire && _resourceToken != sioo)
        {
            return currentBalance;
        }
        // second, add the balance which have not been updated;

        uint256 v_init = _getInitSpeedForLand(_tokenId, _resourceToken);

        // the longest seconds to zero speed.
        uint256 currentTime = now;
        if (resourceBalance[_tokenId].lastUpdateTime >= (resourceReleaseStartTime + denominator_in_seconds)) {
            return currentBalance;
        } else if (now > (resourceReleaseStartTime + denominator_in_seconds))
        {
            currentTime = (resourceReleaseStartTime + denominator_in_seconds);
        }

        require(currentTime >= resourceBalance[_tokenId].lastUpdateTime);

        uint256 mid_now_update_to_start = (currentTime + resourceBalance[_tokenId].lastUpdateTime)/2 - resourceReleaseStartTime;

        uint256 speed_in_current_period = v_init.mul(_getSpeedInSecondsDenominatorForLand(_tokenId, mid_now_update_to_start)).div(denominator_in_seconds);
        

        // FIXME: TODO: is v_init in seconds?
        currentBalance = currentBalance + speed_in_current_period.mul(currentTime - resourceBalance[_tokenId].lastUpdateTime);
    }

    // TODO: the owner of the land can withdraw resources to his own wallet.


    // TODO: add airdrop functin for airdrop tokens to the land.
    // implement by using tokenFallback.


    /**
     * @dev Get and Query the amount of resources available for use on specific land.
     * @param _tokenId The token id of specific land.
    */
    function getCurrentResourceBalanceOnLand(uint256 _tokenId) public view 
    returns (
        uint goldAmount,
        uint woodAmount,
        uint waterAmount,
        uint fireAmount,
        uint soilAmount) {

        goldAmount = getCurrentBalanceOnLandForResource(_tokenId, gold);
        woodAmount = getCurrentBalanceOnLandForResource(_tokenId, wood);
        waterAmount = getCurrentBalanceOnLandForResource(_tokenId, hho);
        fireAmount = getCurrentBalanceOnLandForResource(_tokenId, fire);
        soilAmount = getCurrentBalanceOnLandForResource(_tokenId, sioo);
    }

    function changelandGenesisData(address _newLandGenesisData) public onlyOwner {
        landGenesisData = LandGenesisData(_newLandGenesisData);
    }

    function changeLand(address _newLand) public onlyOwner {
        atlantis = Atlantis(_newLand);
    }

    function _updateElementResource(uint256 _tokenId) internal {
        var (goldAmount, woodAmount, waterAmount, fireAmount, soilAmount) = getCurrentResourceBalanceOnLand(_tokenId);

        resourceBalance[_tokenId].updatedBalances[gold] = goldAmount;
        resourceBalance[_tokenId].updatedBalances[wood] = woodAmount;
        resourceBalance[_tokenId].updatedBalances[hho] = waterAmount;
        resourceBalance[_tokenId].updatedBalances[fire] = fireAmount;
        resourceBalance[_tokenId].updatedBalances[sioo] = soilAmount;
        resourceBalance[_tokenId].lastUpdateTime = now;
        resourceBalance[_tokenId].lastUpdateSpeedInSecondsDenominator = _getSpeedInSecondsDenominatorForLand(_tokenId, now);
    }

}