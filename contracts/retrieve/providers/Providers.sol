// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./../settings/Settings.sol";
import "./../deals/Deals.sol";
import "./../appeals/Appeals.sol";
import "./../vault/Vault.sol";

contract Providers is Ownable, ReentrancyGuard {
    // Defining provider struct
    // TODO: Replace with new entry
    struct Provider {
        bool active;
        string endpoint;
        bool _exists;
        uint64 actor_id;
    }
    Settings settings;
    Deals dealsStore;
    Appeals appealsStore;
    Vault vaultStore;
    // Mapping referees providers
    mapping(address => Provider) public providers;
    // Array of active providers
    address[] public active_providers;
    // Event emitted when a deal is redeemed
    event DealRedeemed(uint256 index);

    mapping(uint64 => address) public provider_actor_id_to_eth_address;

    constructor(address _settings_address, address _vault_address, address _appeals_address) {
        settings = Settings(_settings_address);
        appealsStore = Appeals(_appeals_address);
        vaultStore = Vault(_vault_address);
    }

    function setDealsAddress(address _deals_address) external onlyOwner {
        dealsStore = Deals(_deals_address);
    }

    function getAddress(uint64 _actor_id) public view returns (address) {
        return provider_actor_id_to_eth_address[_actor_id];
    }

    /**
     * This method checks if address is provider
     * @param _address address of provider
     */
    function isProvider(address _address) public pure returns (bool) {
        return _address != address(0);
    }

    /*
        This method will say if address is a provider or not
    */
    function providerExists(address check) public view returns (bool) {
        return providers[check]._exists;
    }

    /*
        This method will allow owner to remove a provider
    */
    function removeProvider(address _provider) external onlyOwner {
        delete providers[_provider];
    }

    /*
        This method will allow provider to withdraw funds for deal
    */
    function redeemDeal(uint256 deal_index) external nonReentrant {
        require(dealsStore.getOwner(deal_index) == msg.sender, "Only provider can redeem");
        require(dealsStore.isActive(deal_index), "Deal is not active");
        require(dealsStore.dealNotEnded(deal_index), "Deal didn't ended, can't redeem");
        require(
            appealsStore.hasNoPendingAppeals(deal_index),
            "Found a pending appeal, can't redeem"
        );
        require(
            appealsStore.hasNoActiveAppeals(deal_index),
            // getRound(active_appeals[deals[deal_index].data_uri]) >= 99,
            "Found an active appeal, can't redeem"
        );
        // KS-PLW-04: Dealer can claim bounty when deal is cancelled
        require(!dealsStore.isCancelled(deal_index), "Deal already cancelled");

        // Move value from contract to address
        vaultStore.subFromVault(dealsStore.getValue(deal_index));
        vaultStore.add(msg.sender, dealsStore.getValue(deal_index));

        // Giving back collateral to provider
        vaultStore.subFromVault(dealsStore.getCollateral(deal_index));
        vaultStore.add(msg.sender, dealsStore.getCollateral(deal_index));
        // Close the deal
        dealsStore.retireDeal(deal_index);
        emit DealRedeemed(deal_index);
    }

    // ACCEPTANCE OF DEALS BY PROVIDER

    function acceptRetrievalDealProposal(uint256 deal_index) external nonReentrant {
        require(
            block.timestamp <
                (dealsStore.getTimestampRequest(deal_index) + settings.proposal_timeout()) &&
                !dealsStore.isCancelled(deal_index) &&
                dealsStore.isProvider(deal_index, msg.sender),
            "Deal expired, canceled or not allowed to accept"
        );
        require(
            vaultStore.getBalance(msg.sender) >= dealsStore.getCollateral(deal_index),
            "Can't accept because you don't have enough balance in contract"
        );
        // Mint the nft to the provider
        dealsStore.mint(msg.sender, deal_index);
        // _mint(msg.sender, deal_index);
        // Activate contract
        dealsStore.startDeal(deal_index);
        // Deposit collateral to contract
        vaultStore.sub(msg.sender, dealsStore.getCollateral(deal_index));
        vaultStore.addToVault(dealsStore.getCollateral(deal_index));
    }

    /*
        This method will return provider status in deal
    */
    function isProviderInDeal(uint256 deal_index, address provider) external view returns (bool) {
        return dealsStore.isProvider(deal_index, provider);
    }

    /*
        This method will allow owner to enable or disable a provider
    */
    function setProviderStatus(
        address _provider,
        bool _state,
        string memory _endpoint,
        uint64 _actor_id
    ) external {
        // KS-PLW-02: Duplicate provider address is allowed
        require(_provider != address(0x0), "Invalid address");
        require(providers[_provider]._exists == false, "Provider already exists");
        providers[_provider]._exists = true;
        if (settings.permissioned_providers()) {
            require(msg.sender == owner(), "Only owner can manage providers");
        } else {
            require(
                _provider == msg.sender || msg.sender == owner(),
                "You can't manage another provider's state"
            );
        }
        providers[_provider].active = _state;
        providers[_provider].endpoint = _endpoint;
        providers[_provider].actor_id = _actor_id;
        if (_state) {
            active_providers.push(_provider);
        } else {
            for (uint256 i = 0; i < active_providers.length; i++) {
                if (active_providers[i] == _provider) {
                    // KS-PLW-07: Vault Deposit Not Returned to Outgoing Provider
                    require(vaultStore.getBalance(_provider) == 0, "Provider Vault is not empty");
                    delete active_providers[i];
                }
            }
        }
    }
}
