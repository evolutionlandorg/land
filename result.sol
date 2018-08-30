pragma solidity ^0.4.24;

// File: openzeppelin-solidity/contracts/access/rbac/Roles.sol

/**
 * @title Roles
 * @author Francisco Giordano (@frangio)
 * @dev Library for managing addresses assigned to a Role.
 * See RBAC.sol for example usage.
 */
library Roles {
  struct Role {
    mapping (address => bool) bearer;
  }

  /**
   * @dev give an address access to this role
   */
  function add(Role storage _role, address _addr)
    internal
  {
    _role.bearer[_addr] = true;
  }

  /**
   * @dev remove an address' access to this role
   */
  function remove(Role storage _role, address _addr)
    internal
  {
    _role.bearer[_addr] = false;
  }

  /**
   * @dev check if an address has this role
   * // reverts
   */
  function check(Role storage _role, address _addr)
    internal
    view
  {
    require(has(_role, _addr));
  }

  /**
   * @dev check if an address has this role
   * @return bool
   */
  function has(Role storage _role, address _addr)
    internal
    view
    returns (bool)
  {
    return _role.bearer[_addr];
  }
}

// File: openzeppelin-solidity/contracts/access/rbac/RBAC.sol

/**
 * @title RBAC (Role-Based Access Control)
 * @author Matt Condon (@Shrugs)
 * @dev Stores and provides setters and getters for roles and addresses.
 * Supports unlimited numbers of roles and addresses.
 * See //contracts/mocks/RBACMock.sol for an example of usage.
 * This RBAC method uses strings to key roles. It may be beneficial
 * for you to write your own implementation of this interface using Enums or similar.
 */
contract RBAC {
  using Roles for Roles.Role;

  mapping (string => Roles.Role) private roles;

  event RoleAdded(address indexed operator, string role);
  event RoleRemoved(address indexed operator, string role);

  /**
   * @dev reverts if addr does not have role
   * @param _operator address
   * @param _role the name of the role
   * // reverts
   */
  function checkRole(address _operator, string _role)
    public
    view
  {
    roles[_role].check(_operator);
  }

  /**
   * @dev determine if addr has role
   * @param _operator address
   * @param _role the name of the role
   * @return bool
   */
  function hasRole(address _operator, string _role)
    public
    view
    returns (bool)
  {
    return roles[_role].has(_operator);
  }

  /**
   * @dev add a role to an address
   * @param _operator address
   * @param _role the name of the role
   */
  function addRole(address _operator, string _role)
    internal
  {
    roles[_role].add(_operator);
    emit RoleAdded(_operator, _role);
  }

  /**
   * @dev remove a role from an address
   * @param _operator address
   * @param _role the name of the role
   */
  function removeRole(address _operator, string _role)
    internal
  {
    roles[_role].remove(_operator);
    emit RoleRemoved(_operator, _role);
  }

  /**
   * @dev modifier to scope access to a single role (uses msg.sender as addr)
   * @param _role the name of the role
   * // reverts
   */
  modifier onlyRole(string _role)
  {
    checkRole(msg.sender, _role);
    _;
  }

  /**
   * @dev modifier to scope access to a set of roles (uses msg.sender as addr)
   * @param _roles the names of the roles to scope access to
   * // reverts
   *
   * @TODO - when solidity supports dynamic arrays as arguments to modifiers, provide this
   *  see: https://github.com/ethereum/solidity/issues/2467
   */
  // modifier onlyRoles(string[] _roles) {
  //     bool hasAnyRole = false;
  //     for (uint8 i = 0; i < _roles.length; i++) {
  //         if (hasRole(msg.sender, _roles[i])) {
  //             hasAnyRole = true;
  //             break;
  //         }
  //     }

  //     require(hasAnyRole);

  //     _;
  // }
}

// File: evolutionlandcommon/contracts/RBACWithAdmin.sol

// https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/examples/RBACWithAdmin.sol

/**
 * @title RBACWithAdmin
 * @author Matt Condon (@Shrugs)
 * @dev It's recommended that you define constants in the contract,
 * like ROLE_ADMIN below, to avoid typos.
 * @notice RBACWithAdmin is probably too expansive and powerful for your
 * application; an admin is actually able to change any address to any role
 * which is a very large API surface. It's recommended that you follow a strategy
 * of strictly defining the abilities of your roles
 * and the API-surface of your contract.
 * This is just an example for example's sake.
 */
contract RBACWithAdmin is RBAC {
  /**
   * A constant role name for indicating admins.
   */
  string public constant ROLE_ADMIN = "admin";

  /**
   * @dev modifier to scope access to admins
   * // reverts
   */
  modifier onlyAdmin()
  {
    checkRole(msg.sender, ROLE_ADMIN);
    _;
  }

  /**
   * @dev constructor. Sets msg.sender as admin by default
   */
  constructor()
    public
  {
    addRole(msg.sender, ROLE_ADMIN);
  }

  /**
   * @dev add a role to an account
   * @param _account the account that will have the role
   * @param _roleName the name of the role
   */
  function adminAddRole(address _account, string _roleName)
    public
    onlyAdmin
  {
    addRole(_account, _roleName);
  }

  /**
   * @dev remove a role from an account
   * @param _account the account that will no longer have the role
   * @param _roleName the name of the role
   */
  function adminRemoveRole(address _account, string _roleName)
    public
    onlyAdmin
  {
    removeRole(_account, _roleName);
  }
}

// File: evolutionlandcommon/contracts/interfaces/ILandData.sol

interface ILandData {

    function batchModifyResources(uint _tokenId, uint _goldRate, uint _woodRate, uint _waterRate, uint _fireRate, uint _soilRate) public;

    function modifyAttributes(uint _tokenId, uint _right, uint _left, uint _newValue) public;

    function isReserved(uint256 _tokenId) public view returns (bool);
    function isSpecial(uint256 _tokenId) public view returns (bool);
    function hasBox(uint256 _tokenId) public view returns (bool);

    function getDetailsFromLandInfo(uint _tokenId)
    public
    view
    returns (
        uint goldRate,
        uint woodRate,
        uint waterRate,
        uint fireRate,
        uint soilRate,
        uint flag);

    function encodeTokenId(int _x, int _y) pure public returns (uint);


}

// File: contracts/land/LandGenesisData.sol

contract LandGenesisData is RBACWithAdmin, ILandData {

    /**
     * @dev mapping from token id to land resource atrribute.
     * LandResourceAttr contains attibutes of Land asset, and is encoded in type of uint256
     * consider LandResourceAttr a binary array with the index starting at 0.
     * the rightmost one is the 0th element and the leftmost one is 255th element.
     * from the right to the left:
     * LandResourceAttr[0,15] : goldrate
     * LandResourceAttr[16,31] : woodrate
     * LandResourceAttr[32,47] : waterrate
     * LandResourceAttr[48,63] : firerate
     * LandResourceAttr[64,79] : soilrate
     * LandResourceAttr[80,95] : flag // 1:reserved, 2:special 3:hasBox
     * LandResourceAttr[96,255] : not open yet
    */
    mapping(uint256 => uint256) public tokenId2Attributes;


    // event land attributions modification
    event Modified(uint indexed tokenId, uint rightAt, uint leftAt, uint newValue);

    // event batch modify resources
    event BatchModified(uint indexed tokenId, uint goldRate, uint woodRate, uint waterRate, uint fireRate, uint soilRate);


    function addLandPixel(uint256 _tokenId, uint256 _landAttribute) public onlyAdmin {
        require(_landAttribute != 0);
        require(tokenId2Attributes[_tokenId] == 0);
        tokenId2Attributes[_tokenId] = _landAttribute;
    }

    function batchAdd(uint256[] _tokenIds, uint256[] _landAttributes) public onlyAdmin {
        require(_tokenIds.length == _landAttributes.length);
        uint length = _tokenIds.length;
        for (uint i = 0; i < length; i++) {
            addLandPixel(_tokenIds[i], _landAttributes[i]);
        }
    }

    function batchModifyResources(uint _tokenId, uint _goldRate, uint _woodRate, uint _waterRate, uint _fireRate, uint _soilRate) public onlyAdmin {
        uint landInfo = tokenId2Attributes[_tokenId];
        uint afterGoldModified = _getModifyInfoFromAttributes(landInfo, 0, 15, _goldRate);
        uint afterWoodModified = _getModifyInfoFromAttributes(afterGoldModified, 16, 31, _woodRate);
        uint afterWaterModified = _getModifyInfoFromAttributes(afterWoodModified, 32, 47, _waterRate);
        uint afterFireModified = _getModifyInfoFromAttributes(afterWaterModified, 48, 63, _fireRate);
        uint afterSoilModified = _getModifyInfoFromAttributes(afterFireModified, 64, 79, _soilRate);

        tokenId2Attributes[_tokenId] = afterSoilModified;

        emit BatchModified(_tokenId, _goldRate, _woodRate, _waterRate, _fireRate, _soilRate);
    }

    function modifyAttributes(uint _tokenId, uint _right, uint _left, uint _newValue) public onlyAdmin {
        uint landInfo = tokenId2Attributes[_tokenId];
        uint newValue = _getModifyInfoFromAttributes(landInfo, _right, _left, _newValue);
        tokenId2Attributes[_tokenId] = newValue;
        emit Modified(_tokenId, _right, _left, _newValue);
    }

    function hasBox(uint256 _tokenId) public view returns (bool) {
        uint landInfo = tokenId2Attributes[_tokenId];
        uint flag = getInfoFromAttributes(landInfo, 80, 95);
        return (flag == 3);
    }

    function isReserved(uint256 _tokenId) public view returns (bool) {
        uint landInfo = tokenId2Attributes[_tokenId];
        uint flag = getInfoFromAttributes(landInfo, 80, 95);
        return (flag == 1);
    }

    function isSpecial(uint256 _tokenId) public view returns (bool) {
        uint landInfo = tokenId2Attributes[_tokenId];
        uint flag = getInfoFromAttributes(landInfo, 80, 95);
        return (flag == 2);
    }

    // get every attribute from landInfo of certain tokenId(land pixel)
    function getDetailsFromLandInfo(uint _tokenId)
    public
    view
    returns (
        uint goldRate,
        uint woodRate,
        uint waterRate,
        uint fireRate,
        uint soilRate,
        uint flag) {
        uint landInfo = tokenId2Attributes[_tokenId];
        goldRate = getInfoFromAttributes(landInfo, 0, 15);
        woodRate = getInfoFromAttributes(landInfo, 16, 31);
        waterRate = getInfoFromAttributes(landInfo, 32, 47);
        fireRate = getInfoFromAttributes(landInfo, 48, 63);
        soilRate = getInfoFromAttributes(landInfo, 64, 79);
        flag = getInfoFromAttributes(landInfo, 80, 95);
    }


    function _getModifyInfoFromAttributes(uint256 _attributes, uint _rightAt, uint _leftAt, uint _value) internal pure returns (uint) {
        uint emptyTarget = (_attributes >> _leftAt) << _leftAt;
        uint newValue = _value << _rightAt;
        return (emptyTarget + newValue);
    }


    /**
    * @dev get specific snippet of info from _flag
    * @param _attributes - LandPixel.flag
    * @param _rightAt - where the snippet start from the right
    * @param _leftAt - where the snippet end to the left
    * for example, uint(000...010100), because of the index starting at 0.
    * the '101' part's _rightAt is 2, and _leftAt is 4.
    */
    function getInfoFromAttributes(uint256 _attributes, uint _rightAt, uint _leftAt) public pure returns (uint) {
        uint leftShift = _attributes << (255 - _leftAt);
        uint rightShift = leftShift >> (_rightAt + 255 - _leftAt);
        return rightShift;
    }

}
