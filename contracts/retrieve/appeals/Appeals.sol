// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./../settings/Settings.sol";
import "./../deals/Deals.sol";
import "./../vault/Vault.sol";

/**
 * @title Appeals
 */
contract Appeals is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    // Defining provider struct
    // TODO: Repace with new entry
    struct Referee {
        bool active;
        string endpoint;
    }

    // Defining appeal struct
    // TODO: Replace with new deal
    struct Appeal {
        // Index object of the deal
        uint256 deal_index;
        // Describe if appeal is active or not
        bool active;
        // Mapping that stores what rounds were processed
        mapping(uint256 => bool) processed;
        // Counter for slashes
        uint128 slashes;
        // Block timestamp of deal creation
        uint256 request_timestamp;
        // Adding block timestamp to calculate timeout
        uint256 origin_timestamp;
    }
    Settings settings;
    Deals dealsStore;
    Vault vaultStore;

    mapping(address => Referee) public referees;
    // Array of active referees
    address[] public active_referees;
    // Mapping appeals
    mapping(uint256 => Appeal) public appeals;
    // Mapping all appeals using deal_index as index
    mapping(uint256 => uint8) public tot_appeals;
    // Mapping pending appeals using data_uri as index
    mapping(uint256 => uint256) public pending_appeals;
    // Mapping active appeals using deal_index as index
    mapping(uint256 => uint256) public active_appeals;

    // Event emitted when new appeal is created
    event AppealCreated(uint256 index, address provider, uint256 deal_index);
    // Event emitted when new appeal started
    event AppealStarted(uint256 index);
    // Event emitted when a slash message is recorded
    event RoundSlashed(uint256 index);
    // Event emitted when a deal is invalidated by an appeal
    event DealInvalidated(uint256 index);

    Counters.Counter private appealCounter;

    constructor(address _settings_address, address _vault_address) {
        settings = Settings(_settings_address);
        vaultStore = Vault(_vault_address);
    }

    function setDealsAddress(address _deals_address) external onlyOwner {
        dealsStore = Deals(_deals_address);
    }

    /*
        This method will allow client to create an appeal
    */
    function createAppeal(uint256 deal_index) external nonReentrant {
        require(
            tot_appeals[deal_index] < settings.max_appeals(),
            "Can't create more appeals on deal"
        );
        require(dealsStore.isActive(deal_index), "Deal is not active");
        require(dealsStore.dealNotEnded(deal_index), "Deal ended, can't create appeals");
        // Check if appeal address was listed
        require(
            dealsStore.isOwner(deal_index, msg.sender),
            "Only authorized addresses can create appeal"
        );
        // Check if there's a pending appeal request
        require(pending_appeals[deal_index] == 0, "There's a pending appeal request");
        // Check if appeal exists or is expired
        require(
            active_appeals[deal_index] == 0 ||
                // Check if appeal is expired
                getRound(active_appeals[deal_index]) >= 99,
            "Appeal exists yet for provided hash"
        );
        // Be sure sent amount is exactly the appeal fee
        require(
            vaultStore.getBalance(msg.sender) >= returnAppealFee(deal_index),
            // msg.value == returnAppealFee(deal_index),
            "Must have enough balance in vault to create an appeal"
        );

        vaultStore.sub(msg.sender, returnAppealFee(deal_index));

        // Split fee to referees
        uint256 payment = returnAppealFee(deal_index);
        tot_appeals[deal_index]++;
        if (payment > 0) {
            uint256 fee = payment / active_referees.length;
            for (uint256 i = 0; i < active_referees.length; i++) {
                vaultStore.add(active_referees[i], fee);
            }
        }
        // Creating next id
        appealCounter.increment();
        uint256 index = appealCounter.current();
        // Storing appeal status
        pending_appeals[deal_index] = index;
        // Creating appeal
        appeals[index].deal_index = deal_index;
        appeals[index].active = true;
        appeals[index].request_timestamp = block.timestamp;
        // Emit appeal created event
        emit AppealCreated(index, dealsStore.getOwner(deal_index), deal_index);
    }

    /*
        This method will allow referees to start an appeal
    */
    function startAppeal(uint256 appeal_index) external {
        require(appeals[appeal_index].origin_timestamp == 0, "Appeal started yet");
        require(referees[msg.sender].active, "Only referees can start appeals");
        appeals[appeal_index].origin_timestamp = block.timestamp;
        // Reset pending appeal state
        pending_appeals[appeals[appeal_index].deal_index] = 0;
        // Set active appeal state
        active_appeals[appeals[appeal_index].deal_index] = appeal_index;
        // Emit appeal created event
        emit AppealStarted(appeal_index);
    }

    /*
        This method checks for duplicate signatures
    */
    function checkDuplicate(bytes[] memory _arr) internal pure returns (bool) {
        if (_arr.length == 0) {
            return false;
        }
        for (uint256 i = 0; i < _arr.length - 1; i++) {
            for (uint256 j = i + 1; j < _arr.length; j++) {
                if (sha256(_arr[i]) == sha256(_arr[j])) {
                    return true;
                }
            }
        }
        return false;
    }

    /*
        This method will allow referees to process an appeal
    */
    function processAppeal(
        uint256 deal_index,
        address[] memory _referees,
        bytes[] memory _signatures
    ) external {
        uint256 appeal_index = active_appeals[deal_index];
        uint256 round = getRound(appeal_index);
        // KS-PLW-01: Duplicate Signatures are not checked while processing an appeal
        require(!checkDuplicate(_signatures), "processAppeal: Duplicate signatures");
        require(dealsStore.isActive(deal_index), "Deal is not active");
        require(appeals[appeal_index].active, "Appeal is not active");
        require(referees[msg.sender].active, "Only referees can process appeals");
        require(round <= settings.rounds_limit(), "This appeal can't be processed anymore");
        require(!appeals[appeal_index].processed[round], "This round was processed yet");
        appeals[appeal_index].processed[round] = true;
        bool slashed = false;
        if (getElectedLeader(appeal_index) == msg.sender) {
            appeals[appeal_index].slashes++;
            slashed = true;
        } else {
            for (uint256 i = 0; i < _referees.length; i++) {
                address referee = _referees[i];
                bytes memory signature = _signatures[i];
                // Be sure leader is not hacking the system
                require(
                    verifyRefereeSignature(signature, deal_index, referee),
                    "Signature doesn't matches"
                );
            }
            if ((_signatures.length * 100) > refereeConsensusThreshold()) {
                appeals[appeal_index].slashes++;
                slashed = true;
            }
        }
        require(slashed, "Appeal wasn't slashed, not the leader or no consensus");
        emit RoundSlashed(appeal_index);
        if (appeals[appeal_index].slashes >= settings.slashes_threshold()) {
            dealsStore.retireDeal(deal_index);
            appeals[appeal_index].active = false;
            // Return value of deal back to owner
            vaultStore.subFromVault(dealsStore.getValue(deal_index));
            vaultStore.add(dealsStore.getOwner(deal_index), dealsStore.getValue(deal_index));
            // Remove funds from provider and charge provider
            uint256 collateral = dealsStore.getCollateral(deal_index);
            vaultStore.subFromVault(collateral);
            // All collateral to protocol's address:
            vaultStore.addToProtocol(collateral);
            // Split collateral between client and protocol:
            // -> vault[settings.protocol_address()] += collateral / 2;
            // -> vault[deals[deal_index].owner] += collateral / 2;
            emit DealInvalidated(deal_index);
        }
    }

    /*
        This method will return the amount in ETH needed to create an appeal
    */
    function returnAppealFee(uint256 deal_index) public view returns (uint256) {
        uint256 fee = dealsStore.getValue(deal_index) / settings.committee_divider();
        return fee;
    }

    /*
        This method verifies a signature
    */
    function verifyRefereeSignature(
        bytes memory _signature,
        uint256 deal_index,
        address referee
    ) public view returns (bool) {
        require(referees[referee].active, "Provided address is not a referee");
        bytes memory message = getPrefix(deal_index);
        bytes32 hashed = ECDSA.toEthSignedMessageHash(message);
        address recovered = ECDSA.recover(hashed, _signature);
        return recovered == referee;
    }

    /*
        This method returns the prefix for
    */
    function getPrefix(uint256 appeal_index) public view returns (bytes memory) {
        uint256 deal_index = appeals[appeal_index].deal_index;
        uint256 round = getRound(appeal_index);
        return
            abi.encodePacked(
                Strings.toString(deal_index),
                Strings.toString(appeal_index),
                Strings.toString(round)
            );
    }

    /*
        This method will say if address is a referee or not
    */
    function isReferee(address check) public view returns (bool) {
        return referees[check].active;
    }

    /*
        This method safely removes an active referee from it's corresponding array,
        part of KS-PLW-06: Removal of referee adds null address to array index
    */
    function removeActiveReferee(uint _index) private {
        require(_index < active_referees.length, "index out of bound");

        for (uint i = _index; i < active_referees.length - 1; i++) {
            active_referees[i] = active_referees[i + 1];
        }
        active_referees.pop();
    }

    /*
        This method will allow owner to enable or disable a referee
    */
    function setRefereeStatus(
        address _referee,
        bool _state,
        string memory _endpoint
    ) external onlyOwner {
        if (_state) {
            // KS-PLW-05: Duplicate referee address is allowed
            require(!isReferee(_referee), "Duplicate referees are not permitted");
            referees[_referee].active = _state;
            referees[_referee].endpoint = _endpoint;
            active_referees.push(_referee);
        } else {
            for (uint256 i = 0; i < active_referees.length; i++) {
                if (active_referees[i] == _referee) {
                    // KS-PLW-06: Removal of referee adds null address to array index
                    removeActiveReferee(i);
                }
            }
        }
    }

    /*
        This method will return the amount of signatures needed to close a rount
    */
    function refereeConsensusThreshold() public view returns (uint256) {
        uint256 half = (active_referees.length * 100) / 2;
        return half;
    }

    /*
        This method will return the leader for a provided appeal
    */
    function getElectedLeader(uint256 appeal_index) public view returns (address) {
        uint256 round = getRound(appeal_index);
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(appeals[appeal_index].origin_timestamp + appeal_index + round)
            )
        );
        uint256 leader = (seed - ((seed / active_referees.length) * active_referees.length));
        return active_referees[leader];
    }

    /*
        This method will return the round for provided appeal
    */
    function getRound(uint256 appeal_index) public view returns (uint256) {
        uint256 appeal_duration = settings.round_duration() * settings.rounds_limit();
        uint256 appeal_end = appeals[appeal_index].origin_timestamp + appeal_duration;
        if (appeal_end >= block.timestamp) {
            uint256 remaining_time = appeal_end - block.timestamp;
            uint256 remaining_rounds = remaining_time / settings.round_duration();
            uint256 round = settings.rounds_limit() - remaining_rounds;
            return round;
        } else {
            // Means appeal is ended
            return 99;
        }
    }

    /*
        This method will return appeal address status in deal
    */
    function canAddressAppeal(
        uint256 deal_index,
        address appeal_address
    ) external view returns (bool) {
        return dealsStore.isReferee(deal_index, appeal_address);
    }

    function totalAppeals() external view returns (uint256) {
        return appealCounter.current();
    }

    function hasNoActiveAppeals(uint256 deal_index) external view returns (bool) {
        return active_appeals[deal_index] >= 99;
    }

    function hasNoPendingAppeals(uint256 deal_index) external view returns (bool) {
        return pending_appeals[deal_index] == 0;
    }
}
