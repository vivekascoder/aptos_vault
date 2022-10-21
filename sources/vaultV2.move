

module aptos_vault::VaultV2 {
    use std::string;
    use std::signer;
    use std::option;

    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{AptosCoin};

    const ENOT_INIT: u64 = 0;
    const ENOT_ENOUGH_LP: u64 = 1;
    const ENOT_DEPLOYER_ADDRESS: u64 = 2;

    struct LP has key {}

    struct VaultInfo has key {
        mint_cap: coin::MintCapability<LP>,
        burn_cap: coin::BurnCapability<LP>,
        total_staked: u64,
        resource: address,
        resource_cap: account::SignerCapability
    }


    public fun init_module(sender: signer) {
        // Only owner can create admin.
        assert!(signer::address_of(&sender) == @deployer_address, ENOT_DEPLOYER_ADDRESS);

        // Create a resource account to hold the funds.
        let (resource, resource_cap) = account::create_resource_account(&sender, x"01");

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<LP>(
            &resource,
            string::utf8(b"LP Token"),
            string::utf8(b"LP"),
            18,
            false
        );

        // We don't need to freeze the tokens.
        coin::destroy_freeze_cap(freeze_cap);

        // Register the resource account.
        coin::register<LP>(&sender);

        move_to(&sender, VaultInfo {
            mint_cap: mint_cap, 
            burn_cap: burn_cap, 
            total_staked: 0, 
            resource: signer::address_of(&resource), 
            resource_cap: resource_cap
        });
    }

    /// Signet deposits `amount` amount of LP into the vault.
    /// LP tokens to mint = (token_amount / total_staked_amount) * total_lp_supply
    public entry fun deposite(sender: signer, vault_owner: address, amount: u64) acquires VaultInfo {
        let sender_addr = signer::address_of(&sender);
        assert!(exists<VaultInfo>(vault_owner), ENOT_INIT);

        let vault_info = borrow_global_mut<VaultInfo>(vault_owner);
        // Deposite some amount of tokens and mint shares.
        coin::transfer<AptosCoin>(&sender, vault_info.resource, amount);

        vault_info.total_staked = vault_info.total_staked + amount;

        // Mint shares
        let shares_to_mint: u64;
        let supply = coin::supply<LP>();
        let total_lp_supply = if (option::is_some(&supply)) option::extract(&mut supply) else 0;

        if (total_lp_supply == 0) {
            shares_to_mint = amount;
        } else {
            shares_to_mint = (amount * (total_lp_supply as u64)) / vault_info.total_staked;
        };
        coin::deposit<LP>(sender_addr, coin::mint<LP>(shares_to_mint, &vault_info.mint_cap));
    }

    /// Withdraw some amount of AptosCoin based on total_staked of LP token.
    public entry fun withdraw(sender: signer, vault_owner: address, shares: u64) acquires VaultInfo{
        let sender_addr = signer::address_of(&sender);
        assert!(exists<VaultInfo>(vault_owner), ENOT_INIT);

        let vault_info = borrow_global_mut<VaultInfo>(vault_owner);

        // Make sure resource sender's account has enough LP tokens.
        assert!(coin::balance<LP>(sender_addr) >= shares, ENOT_ENOUGH_LP);

        // Burn LP tokens of user
        let supply = coin::supply<LP>();
        let total_lp_supply = if (option::is_some(&supply)) option::extract(&mut supply) else 0;
        let amount_to_give = shares * vault_info.total_staked / (total_lp_supply as u64);

        coin::burn<LP>(coin::withdraw<LP>(&sender, shares), &vault_info.burn_cap);

        // Transfer the locked AptosCoin from the resource account.
        let resource_account_from_cap: signer = account::create_signer_with_capability(&vault_info.resource_cap);
        coin::transfer<AptosCoin>(&resource_account_from_cap, sender_addr, amount_to_give);

        // Update the info in the VaultInfo.
        vault_info.total_staked = vault_info.total_staked - shares;
    }
}
