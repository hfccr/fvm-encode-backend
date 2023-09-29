// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract Vault is ReentrancyGuard, AccessControl {
    // Referee, Providers and Clients vault
    mapping(address => uint256) public vault;
    bytes32 public constant APPEALS_ROLE = keccak256("APPEALS_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    constructor() {
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function setAppealsRole(address _address) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _grantRole(APPEALS_ROLE, _address);
    }

    /*
        This method will allow provider deposit ETH in order to accept deals
    */
    function depositToVault() external payable nonReentrant {
        // require(isProvider(msg.sender), "Only providers can deposit into contract");
        require(msg.value > 0, "Must send some value");
        vault[msg.sender] += msg.value;
    }

    /*
        This method will allow to withdraw ethers from contract
    */
    function withdrawFromVault(uint256 amount) external nonReentrant {
        uint256 balance = vault[msg.sender];
        require(balance >= amount, "Not enough balance to withdraw");
        vault[msg.sender] -= amount;
        bool success;
        (success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdraw to user failed");
    }

    function getProtocolBalance(address _protocol_address, uint256 amount) external nonReentrant {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not authorized");
        uint256 balance = vault[_protocol_address];
        require(balance >= amount, "Not enough balance to withdraw");
        vault[_protocol_address] -= amount;
        bool success;
        (success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdraw to user failed");
    }

    function setValue(address _address, uint256 _value) public {
        require(hasRole(APPEALS_ROLE, msg.sender), "Caller is not authorized");
        vault[_address] = _value;
    }

    function sub(address _address, uint256 _value) public {
        require(hasRole(APPEALS_ROLE, msg.sender), "Caller is not authorized");
        vault[_address] -= _value;
    }

    function add(address _address, uint256 _value) public {
        require(hasRole(APPEALS_ROLE, msg.sender), "Caller is not authorized");
        vault[_address] += _value;
    }

    function getBalance(address _address) public view returns (uint256) {
        return vault[_address];
    }
}
