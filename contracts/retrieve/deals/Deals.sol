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
        DealTerminated,
        DealRedeemed
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

    struct RetrievalDealReturn {
        uint256 id;
        address owner;
        uint64 deal_id;
        uint256 retrieval_provider_collateral;
        uint256 retrieval_value;
        bool canceled;
        Status status;
        uint256 timestamp_request;
        uint256 timestamp_start;
        uint64 provider_actor_id;
        uint64 client_actor_id;
        int64 deal_start;
        int64 deal_end;
        bytes data;
        uint64 size;
        bytes appeal_addresses;
    }

    mapping(uint256 => RetrievalDeal) public retrieval_deals;

    mapping(uint256 => address[]) public retrieval_deal_appeal_addresses;

    Counters.Counter private dealCounter;

    Settings public settings;

    Appeals public appeals;

    Vault public vaultStore;

    Providers public providersStore;

    event RetrievalDealProposalCreate(
        uint256 index,
        address owner,
        uint64 deal_id,
        uint256 retrieval_provider_collateral,
        uint256 retrieval_value,
        address[] appeal_addresses
    );

    event DealProposalCanceled(uint256 index);

    constructor(
        address _settings_address,
        address _vault_address,
        address _appeals_address,
        address _providers_address
    ) ERC721("Retrieve Deals", "RTRV") {
        settings = Settings(_settings_address);
        vaultStore = Vault(_vault_address);
        appeals = Appeals(_appeals_address);
        providersStore = Providers(_providers_address);
    }

    function isActive(uint256 _deal_index) public view returns (bool) {
        return retrieval_deals[_deal_index].timestamp_start > 0;
    }

    function retireDeal(uint256 _deal_index) public {
        // TODO: Only appeals address can make this change and provider contract address
        retrieval_deals[_deal_index].timestamp_start = 0;
        retrieval_deals[_deal_index].status = Status.DealRedeemed;
    }

    function startDeal(uint256 _deal_index) public {
        // TODO: Only providers contract should be able to use this
        require(
            retrieval_deals[_deal_index].status == Status.RequestSubmitted,
            "Deal not in published state"
        );
        retrieval_deals[_deal_index].timestamp_start = block.timestamp;
        retrieval_deals[_deal_index].status = Status.DealActivated;
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
            return retrieval_deals[_deal_index].owner;
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
        retrieval_deal_appeal_addresses[index] = _appeal_addresses;
        vaultStore.sub(msg.sender, retrieval_value);
        vaultStore.addToVault(retrieval_value);
        // Creating next id
        dealCounter.increment();
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
        This method will allow client to cancel deal if not accepted
    */
    function cancelDealProposal(uint256 deal_index) external nonReentrant {
        require(retrieval_deals[deal_index].owner == msg.sender, "Only owner can cancel the deal");
        require(!retrieval_deals[deal_index].canceled, "Deal canceled yet");
        // KS-PLW-03: Client can cancel the deal after it is accepted
        require(retrieval_deals[deal_index].timestamp_start == 0, "Deal accepted already");
        retrieval_deals[deal_index].canceled = true;
        retrieval_deals[deal_index].timestamp_start = 0;
        retrieval_deals[deal_index].status = Status.DealTerminated;
        // Remove funds from internal vault giving back to user
        // user will be able to withdraw funds later
        vaultStore.subFromVault(retrieval_deals[deal_index].retrieval_value);
        vaultStore.add(msg.sender, retrieval_deals[deal_index].retrieval_value);
        emit DealProposalCanceled(deal_index);
    }

    function getAllDeals() external view returns (RetrievalDealReturn[] memory) {
        RetrievalDealReturn[] memory deals = new RetrievalDealReturn[](dealCounter.current());
        for (uint256 i = 0; i < dealCounter.current(); i++) {
            deals[i].id = i;
            deals[i].deal_id = retrieval_deals[i].deal_id;
            deals[i].owner = retrieval_deals[i].owner;
            deals[i].deal_id = retrieval_deals[i].deal_id;
            deals[i].retrieval_provider_collateral = retrieval_deals[i]
                .retrieval_provider_collateral;
            deals[i].retrieval_value = retrieval_deals[i].retrieval_value;
            deals[i].canceled = retrieval_deals[i].canceled;
            deals[i].status = retrieval_deals[i].status;
            deals[i].timestamp_request = retrieval_deals[i].timestamp_request;
            deals[i].timestamp_start = retrieval_deals[i].timestamp_start;
            deals[i].provider_actor_id = retrieval_deals[i].provider_actor_id;
            deals[i].client_actor_id = retrieval_deals[i].client_actor_id;
            deals[i].deal_start = CommonTypes.ChainEpoch.unwrap(retrieval_deals[i].term.start);
            deals[i].deal_end = CommonTypes.ChainEpoch.unwrap(retrieval_deals[i].term.end);
            deals[i].data = retrieval_deals[i].dealCommitment.data;
            deals[i].size = retrieval_deals[i].dealCommitment.size;
            address[] memory appeal_addresses = retrieval_deal_appeal_addresses[i];
            bytes memory appeal_addresses_concatenated;
            for (uint256 j = 0; j < appeal_addresses.length; j++) {
                appeal_addresses_concatenated = abi.encodePacked(
                    appeal_addresses_concatenated,
                    abi.encodePacked(appeal_addresses[j])
                );
            }
            deals[i].appeal_addresses = appeal_addresses_concatenated;
        }
        return deals;
    }
}
