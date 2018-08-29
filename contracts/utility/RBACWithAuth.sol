pragma solidity ^0.4.24;

import "./interfaces/IAuthority.sol";
import "./RBACWithAdmin.sol";

/**
 * @title RBACWithAuth
 * @dev It's recommended that you define constants in the contract,
 * like ROLE_AUTH_CONTROLLER below, to avoid typos.
 * This introduce the auth features from ds-auth, an advanced feature added to RBACWithAdmin.
 * It's recommended that you follow a strategy
 * of strictly defining the abilities of your roles
 * and the API-surface of your contract.
 */
contract RBACWithAuth is RBACWithAdmin {
    /**
     * A constant role name for indicating auth controllers.
     */
    string public constant ROLE_AUTH_CONTROLLER = "auth_controller";

    IAuthority  public  authority;

    event LogSetAuthority (address indexed authority);

    /**
     * @dev modifier to scope access to auth controllers
     * // reverts
     */
    modifier onlyAuthController()
    {
        checkRole(msg.sender, ROLE_AUTH_CONTROLLER);
        _;
    }

    modifier isAuth {
        require( isAuthorized(msg.sender, msg.sig) );
        _;
    }

    /**
     * @dev constructor. Sets msg.sender as auth controllers by default
     */
    constructor() public
    {
        addRole(msg.sender, ROLE_AUTH_CONTROLLER);
    }

    function setAuthority(IAuthority _authority)
        public
        onlyAuthController
    {
        authority = _authority;
        emit LogSetAuthority(authority);
    }

    function isAuthorized(address src, bytes4 sig) internal view returns (bool) {
        if ( hasRole(msg.sender, ROLE_AUTH_CONTROLLER) ) {
            return true;
        } else if (authority == IAuthority(0)) {
            return false;
        } else {
            return authority.canCall(src, this, sig);
        }
    }

}