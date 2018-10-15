pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "@evolutionland/common/contracts/ObjectOwnership.sol";
import "./LandBase.sol";

/**
 * @title LandResource
 * @dev LandResource is registry that manage the element resources generated on Land, and related resource releasing speed.
 */
contract LandResource is Ownable{
    using SafeMath for *;

    LandBase public landBase;
    ObjectOwnership public objectOwnership;

    // ERC20 resource tokens
    address public gold;
    address public wood;
    address public hho;
    address public fire;
    address public sioo;

    uint256 resourceReleaseStartTime;
    
    uint256 public aattenPerDay = 1; // TODO: move to global settings contract.
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
        mapping(address=>uint256) updatedMintableBalances;
        uint256 lastUpdateSpeedInSecondsDenominator;
        uint256 lastDestoryAttenInSecondsDenominator;
        uint256 industryIndex;
        uint256 lastUpdateTime;
    }

    mapping (uint256 => UpdatedElementResource) public resourceBalance;

    constructor(address _landBase, address _objectOwnership, uint256
         _resourceReleaseStartTime, address _gold, address _wood, address _hho, address _fire, address _sioo) public {
        landBase = LandBase(_landBase);
        objectOwnership = ObjectOwnership(_objectOwnership);
        resourceReleaseStartTime = _resourceReleaseStartTime;

        gold = _gold;
        wood = _wood;
        hho = _hho;
        fire = _fire;
        sioo = _sioo;
    }

    /**
     * @dev Ping by outside to notify the element resources should be updated
     * @param _tokenId the token id of the land
     * @param _data the data sent by outside to update the balance and speed of element resources (TODO: To be implemented)
     */
    function ping(uint256 _tokenId, bytes _data) public {
        require(msg.sender == address(landBase));

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

        return landBase.getResourceRate(_tokenId, _resourceToken).mul(_getSpeedInSecondsDenominatorForLand(_tokenId, now)).div(denominator_in_seconds);
    }

    /**
     * @dev Get and Query the amount of resources available for use on specific land.
     * @param _tokenId The token id of specific land.
    */
    function getCurrentBalanceOnLandForResource(uint256 _tokenId, address _resourceToken) public view 
    returns (uint256 currentBalance) {
        // first, add the updated balance
        currentBalance = resourceBalance[_tokenId].updatedMintableBalances[_resourceToken];

        if (_resourceToken != gold && _resourceToken != wood && _resourceToken != hho && _resourceToken != fire && _resourceToken != sioo)
        {
            return currentBalance;
        }
        // second, add the balance which have not been updated;

        uint256 v_init = landBase.getResourceRate(_tokenId, _resourceToken);

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

    function changelandBase(address _newLandGenesisData) public onlyOwner {
        landBase = LandBase(_newLandGenesisData);
    }

    function _updateElementResource(uint256 _tokenId) internal {
        resourceBalance[_tokenId].updatedMintableBalances[gold] = getCurrentBalanceOnLandForResource(_tokenId, gold);
        resourceBalance[_tokenId].updatedMintableBalances[wood] = getCurrentBalanceOnLandForResource(_tokenId, wood);
        resourceBalance[_tokenId].updatedMintableBalances[hho] = getCurrentBalanceOnLandForResource(_tokenId, hho);
        resourceBalance[_tokenId].updatedMintableBalances[fire] = getCurrentBalanceOnLandForResource(_tokenId, fire);
        resourceBalance[_tokenId].updatedMintableBalances[sioo] = getCurrentBalanceOnLandForResource(_tokenId, sioo);
        resourceBalance[_tokenId].lastUpdateTime = now;
        resourceBalance[_tokenId].lastUpdateSpeedInSecondsDenominator = _getSpeedInSecondsDenominatorForLand(_tokenId, now);
    }

}