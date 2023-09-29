// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./../functions/render/IRENDER.sol";

/**
 * @title Settings for retrieval protocol adapted from retriev
 */
contract Settings is Ownable {
    // admins
    mapping(uint8 => mapping(address => bool)) public admins;
    // Multipliers
    uint256 public slashing_multiplier = 1000;
    uint8 public committee_divider = 4;
    // Deal parameters
    uint32 public proposal_timeout = 86_400;
    uint8 public max_appeals = 5;
    uint256 public min_deal_value = 0;
    // Round parameters
    uint32 public round_duration = 300;
    uint32 public min_duration = 86_400;
    uint32 public max_duration = 31_536_000;
    uint8 public slashes_threshold = 12;
    uint8 public rounds_limit = 12;
    // Render contract
    IRENDER public token_render;
    // Contract state variables
    bool public contract_protected = true;
    bool public permissioned_providers = false;
    // Protocol address
    address public protocol_address;

    constructor(address _protocol_address) {
        require(_protocol_address != address(0), "Can't init protocol with black-hole");
        protocol_address = _protocol_address;
    }

    /*
        Admin function to setup roles
    */

    function setRole(uint8 kind, bool status, address admin) external {
        // Set specified role, using:
        // 1 - Protocol managers
        // 2 - Referees managers
        // 3 - Providers managers
        admins[kind][admin] = status;
    }

    /*
        Admin functions to fine tune protocol
    */
    function tuneRefereesVariables(uint8 kind, uint8 value8, uint32 value32) external {
        require(msg.sender == owner() || admins[2][msg.sender], "Can't manage referees variables");
        if (kind == 0) {
            committee_divider = value8;
        } else if (kind == 1) {
            max_appeals = value8;
        } else if (kind == 2) {
            round_duration = value32;
        } else if (kind == 3) {
            rounds_limit = value8;
        } else if (kind == 4) {
            slashes_threshold = value8;
        }
    }

    function tuneProvidersVariables(uint8 kind, uint256 value256, uint32 value32) external {
        require(msg.sender == owner() || admins[3][msg.sender], "Can't manage providers variables");
        if (kind == 0) {
            proposal_timeout = value32;
        } else if (kind == 1) {
            min_deal_value = value256;
        } else if (kind == 2) {
            slashing_multiplier = value256;
        } else if (kind == 3) {
            min_duration = value32;
        } else if (kind == 4) {
            max_duration = value32;
        }
    }

    function tuneProtocolVariables(uint8 kind, address addy, bool state) external {
        require(msg.sender == owner() || admins[1][msg.sender], "Can't manage protocol variables");
        if (kind == 0) {
            token_render = IRENDER(addy);
        } else if (kind == 1) {
            protocol_address = addy;
        } else if (kind == 2) {
            contract_protected = state;
        } else if (kind == 3) {
            permissioned_providers = state;
        }
    }
}
