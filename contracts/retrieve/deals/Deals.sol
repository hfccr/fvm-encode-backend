// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import {MarketAPI} from "@zondax/filecoin-solidity/contracts/v0.8/MarketAPI.sol";
import {MarketTypes} from "@zondax/filecoin-solidity/contracts/v0.8/types/MarketTypes.sol";
import {CommonTypes} from "@zondax/filecoin-solidity/contracts/v0.8/types/CommonTypes.sol";
import "./../libs/ERC721.sol";
import "./../settings/Settings.sol";
import "./../appeals/Appeals.sol";
import "./../vault/Vault.sol";
import "./../providers/Providers.sol";

contract Deals is ERC721, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    // Defining deal struct
    enum Status {
        None,
        RequestSubmitted,
        DealPublished,
        DealActivated,
        DealTerminated
    }

    // TODO: Replace with deal request struct
    struct Deal {
        // subject of the deal
        string data_uri;
        // Timestamp request
        uint256 timestamp_request;
        // Starting timestamp
        uint256 timestamp_start;
        // Duration of deal expressed in seconds
        uint256 duration;
        // Amount in wei paid for the deal
        uint256 value;
        // Amount in wei needed to accept the deal
        uint256 collateral;
        // Address of provider
        mapping(address => bool) providers;
        // Address of owner
        address owner;
        // Describe if deal is canceled or not
        bool canceled;
        // Addresses authorized to create appeals
        mapping(address => bool) appeal_addresses;
    }

    struct RetrievalDeal {
        address owner;
        uint64 deal_id;
        uint256 retrieval_provider_collateral;
        uint256 retrieval_value;
        bool canceled;
        Status status;
        uint256 timestamp_request;
        uint256 timestamp_start;
        mapping(address => bool) appeal_addresses;
        MarketTypes.GetDealTermReturn term;
        MarketTypes.GetDealDataCommitmentReturn dealCommitment;
        uint64 provider_actor_id;
        uint64 client_actor_id;
    }
    // Mapping deals
    mapping(uint256 => Deal) public deals;

    mapping(uint256 => RetrievalDeal) public retrieval_deals;

    RetrievalDeal[] public retrieval_deal_list;

    Counters.Counter private dealCounter;

    Settings public settings;

    Appeals public appeals;

    Vault public vaultStore;

    Providers public providersStore;

    event DealProposalCreated(
        uint256 index,
        address[] providers,
        string data_uri,
        address[] appeal_addresses
    );

    event RetrievalDealProposalCreate(
        uint256 index,
        address owner,
        uint64 deal_id,
        uint256 retrieval_provider_collateral,
        uint256 retrieval_value,
        address[] appeal_addresses
    );

    constructor(
        address _settings_address,
        address _vault_address
    ) ERC721("Retrieve Deals", "RTRV") {
        settings = Settings(_settings_address);
        vaultStore = Vault(_vault_address);
    }

    function setAppeals(address _appeals_address) external onlyOwner {
        appeals = Appeals(_appeals_address);
    }

    function setProviders(address _providers_address) external onlyOwner {
        providersStore = Providers(_providers_address);
    }

    function isActive(uint256 _deal_index) public view returns (bool) {
        return retrieval_deals[_deal_index].timestamp_start > 0;
    }

    function retireDeal(uint256 _deal_index) public {
        // TODO: Only appeals address can make this change and provider contract address
        retrieval_deals[_deal_index].timestamp_start = 0;
    }

    function startDeal(uint256 _deal_index) public {
        // TODO: Only providers contract should be able to use this
        retrieval_deals[_deal_index].timestamp_start = block.timestamp;
    }

    function dealNotEnded(uint256 _deal_index) public view returns (bool) {
        uint256 end = uint256(
            uint64(CommonTypes.ChainEpoch.unwrap(retrieval_deals[_deal_index].term.end))
        );
        return block.timestamp < end;
    }

    function isReferee(uint256 _deal_index, address _address) public view returns (bool) {
        return retrieval_deals[_deal_index].appeal_addresses[_address];
    }

    function getDataUri(uint256 _deal_index) public view returns (string memory) {
        return string(retrieval_deals[_deal_index].dealCommitment.data);
    }

    function getValue(uint256 _deal_index) public view returns (uint256) {
        return retrieval_deals[_deal_index].retrieval_value;
    }

    function getCollateral(uint256 _deal_index) public view returns (uint256) {
        return retrieval_deals[_deal_index].retrieval_provider_collateral;
    }

    function isCancelled(uint256 _deal_index) public view returns (bool) {
        return retrieval_deals[_deal_index].canceled;
    }

    function isProvider(uint256 _deal_index, address _provider) public view returns (bool) {
        return
            providersStore.getAddress(retrieval_deals[_deal_index].provider_actor_id) == _provider;
    }

    function getTimestampRequest(uint256 _deal_index) public view returns (uint256) {
        return retrieval_deals[_deal_index].timestamp_request;
    }

    // TODO: only provider contract should be able to call this function
    function mint(address _address, uint256 _deal_index) public {
        _mint(_address, _deal_index);
    }

    function totalSupply() public view returns (uint256) {
        return dealCounter.current();
    }

    function totalDeals() external view returns (uint256) {
        return dealCounter.current();
    }

    function balanceOf(address _to_check) public view virtual override returns (uint256) {
        uint256 totalTkns = totalSupply();
        uint256 resultIndex = 0;
        uint256 tnkId;

        for (tnkId = 1; tnkId <= totalTkns; tnkId++) {
            if (ownerOf(tnkId) == _to_check) {
                resultIndex++;
            }
        }

        return resultIndex;
    }

    function getOwner(uint256 _deal_index) public view returns (address) {
        if (retrieval_deals[_deal_index].owner != address(0)) {
            return deals[_deal_index].owner;
        } else {
            return ownerOf(_deal_index);
        }
    }

    function getStartTimestamp(uint256 _deal_index) public view returns (uint256) {
        return retrieval_deals[_deal_index].timestamp_start;
    }

    function getDuration(uint256 _deal_index) public view returns (uint256) {
        MarketTypes.GetDealTermReturn memory term;
        term = retrieval_deals[_deal_index].term;
        return
            uint256(
                uint64(
                    CommonTypes.ChainEpoch.unwrap(term.end) -
                        CommonTypes.ChainEpoch.unwrap(term.start)
                )
            );
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        RetrievalDeal storage retrieval_deal = retrieval_deals[tokenId];
        string memory output = settings.token_render().render(
            tokenId,
            getDataUri(tokenId),
            getValue(tokenId),
            getStartTimestamp(tokenId),
            getDuration(tokenId),
            !appeals.hasNoActiveAppeals(tokenId),
            retrieval_deal.owner
        );
        return output;
    }

    // For creating a proposal for existing deals
    function createRetrievalProposalForExistingDeal(
        uint64 _deal_id,
        uint256 retrieval_provider_collateral,
        uint256 retrieval_value,
        address[] memory _appeal_addresses
    ) external nonReentrant {
        // get the miner id from the deal id
        // create a proposal with deal id, collateral and value
        if (settings.contract_protected()) {
            require(retrieval_value == 0, "Contract is protected, can't accept value");
        }
        require(
            vaultStore.getBalance(msg.sender) >= retrieval_value,
            "Not enough balance to create deal proposal"
        );
        // uint256 maximum_collateral = settings.slashing_multiplier() * value;
        require(retrieval_value >= settings.min_deal_value(), "Collateral or value out of range");
        require(_appeal_addresses.length > 0, "You must define one or more appeal addresses");
        // Creating next id
        dealCounter.increment();
        uint256 index = dealCounter.current();
        // Creating the deal mapping
        retrieval_deals[index].owner = msg.sender;
        retrieval_deals[index].deal_id = _deal_id;
        retrieval_deals[index].retrieval_provider_collateral = retrieval_provider_collateral;
        retrieval_deals[index].retrieval_value = retrieval_value;
        retrieval_deals[index].canceled = false;
        retrieval_deals[index].status = Status.RequestSubmitted;
        retrieval_deals[index].timestamp_request = block.timestamp;
        MarketTypes.GetDealTermReturn memory term;
        term = MarketAPI.getDealTerm(_deal_id);
        retrieval_deals[index].term = term;
        MarketTypes.GetDealDataCommitmentReturn memory dealCommitment;
        dealCommitment = MarketAPI.getDealDataCommitment(_deal_id);
        retrieval_deals[index].dealCommitment = dealCommitment;
        retrieval_deals[index].provider_actor_id = MarketAPI.getDealProvider(_deal_id);
        retrieval_deals[index].client_actor_id = MarketAPI.getDealClient(_deal_id);
        for (uint256 i = 0; i < _appeal_addresses.length; i++) {
            retrieval_deals[index].appeal_addresses[_appeal_addresses[i]] = true;
        }
        vaultStore.sub(msg.sender, retrieval_value);
        vaultStore.add(address(this), retrieval_value);
        emit RetrievalDealProposalCreate(
            index,
            msg.sender,
            _deal_id,
            retrieval_provider_collateral,
            retrieval_value,
            _appeal_addresses
        );
    }

    /*
        This method will allow client to create a deal
    */
    function createDealProposal(
        string memory _data_uri,
        uint256 duration,
        uint256 collateral,
        uint256 value,
        address[] memory _providers,
        address[] memory _appeal_addresses
    ) external nonReentrant {
        if (settings.contract_protected()) {
            require(value == 0, "Contract is protected, can't accept value");
        }
        require(
            vaultStore.getBalance(msg.sender) >= value,
            "Not enough balance to create deal proposal"
        );
        require(
            duration >= settings.min_duration() && duration <= settings.max_duration(),
            "Duration is out allowed range"
        );
        // uint256 maximum_collateral = settings.slashing_multiplier() * msg.value;
        require(
            value >= settings.min_deal_value(),
            // && collateral >= msg.value && collateral <= maximum_collateral
            "Collateral or value out of range"
        );
        require(_appeal_addresses.length > 0, "You must define one or more appeal addresses");
        // Creating next id
        dealCounter.increment();
        uint256 index = dealCounter.current();
        // Creating the deal mapping
        deals[index].timestamp_request = block.timestamp;
        deals[index].owner = msg.sender;
        deals[index].data_uri = _data_uri;
        deals[index].duration = duration;
        deals[index].collateral = collateral;
        deals[index].value = value;
        // Check if provided providers are active and store in struct
        for (uint256 i = 0; i < _providers.length; i++) {
            /*require(
                isProvider(_providers[i]),
                "Requested provider is not active"
            );*/
            deals[index].providers[_providers[i]] = true;
        }
        // Add appeal addresses to deal
        for (uint256 i = 0; i < _appeal_addresses.length; i++) {
            deals[index].appeal_addresses[_appeal_addresses[i]] = true;
        }
        // When created the amount of money is owned by sender
        // vault[address(this)] += msg.value;
        vaultStore.sub(msg.sender, value);
        vaultStore.add(address(this), value);
        // Emit event
        emit DealProposalCreated(index, _providers, _data_uri, _appeal_addresses);
    }
}
