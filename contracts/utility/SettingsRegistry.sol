pragma solidity ^0.4.24;

import './interfaces/ISettingsRegistry.sol';
import './RBACWithAuth.sol';

/**
 * @title SettingsRegistry
 * @dev This contract holds all the settings for updating and querying.
 */
contract SettingsRegistry is ISettingsRegistry, RBACWithAuth {
    mapping(bytes32 => uint256) public uintProperties;
    mapping(bytes32 => string) public stringProperties;
    mapping(bytes32 => address) public addressProperties;
    mapping(bytes32 => bytes) public bytesProperties;
    mapping(bytes32 => bool) public boolProperties;
    mapping(bytes32 => int256) public intProperties;


    // TODO: add events.

    function uintOf(bytes32 _propertyName) public view returns (uint256) {
        return uintProperties[_propertyName];
    }

    function stringOf(bytes32 _propertyName) public view returns (string) {
        return stringProperties[_propertyName];
    }

    function addressOf(bytes32 _propertyName) public view returns (address) {
        return addressProperties[_propertyName];
    }

    function bytesOf(bytes32 _propertyName) public view returns (bytes) {
        return bytesProperties[_propertyName];
    }

    function boolOf(bytes32 _propertyName) public view returns (bool) {
        return boolProperties[_propertyName];
    }

    function intOf(bytes32 _propertyName) public view returns (int) {
        return intProperties[_propertyName];
    }


    function setUintProperty(bytes32 _propertyName, uint _value) public isAuth {
        uintProperties[_propertyName] = _value;
    }

    function setStringProperty(bytes32 _propertyName, string _value) public isAuth {
        stringProperties[_propertyName] = _value;
    }

    function setAddressProperty(bytes32 _propertyName, address _value) public isAuth {
        addressProperties[_propertyName] = _value;
    }

    function setBytesProperty(bytes32 _propertyName, bytes _value) public isAuth {
        bytesProperties[_propertyName] = _value;
    }

    function setBoolProperty(bytes32 _propertyName, bool _value) public isAuth {
        boolProperties[_propertyName] = _value;
    }

    function setIntProperty(bytes32 _propertyName, int _value) public isAuth {
        intProperties[_propertyName] = _value;
    }

}