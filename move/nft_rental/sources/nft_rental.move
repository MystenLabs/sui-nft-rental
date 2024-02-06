// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// This module facilitates the rental of NFTs using kiosks. 
/// It allows users to list their NFTs for renting, rent NFTs for a specified duration, and return them after the rental period.
module nft_rental::rentables_ext {
    // std imports
    use std::option::{Self, Option};

    // sui imports
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::tx_context::{Self, TxContext};
    use sui::kiosk_extension::{Self};
    use sui::bag;
    use sui::object::{Self, UID, ID};
    use sui::transfer_policy::{Self, TransferPolicy, TransferPolicyCap, has_rule};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::package::{Publisher};

    // other imports
    use kiosk::kiosk_lock_rule::{Rule};

    // consts
    const PERMISSIONS: u128 = 11;

    const EExtensionNotInstalled: u64 = 0;
    const ENotOwner: u64 = 1;
    const ENotEnoughCoins: u64 = 2;
    const EInvalidKiosk: u64 = 3;
    const ERentingPeriodNotOver: u64 = 4;
    const EObjectNotExists: u64 = 5;

    const secondsInADay = 86400;

    // ==================== Structs ====================
    
    /// Extension Key for Kiosk Rentables extension.
    struct Rentables has drop {}

    /// Promise struct for borrowing by value.
    struct Promise has store {
        item_id: ID,
        duration: u64,
        start_date: u64,
        price_per_day: u64,
        renter: address,
        borrower_kiosk: ID
    }

    /// A wrapper object that holds an asset that is being rented. 
    /// Contains information relevant to the rental period, cost and renter.
    struct Rentable<T: key + store> has store {
        object: T,
        duration: u64, // total amount of time offered for renting in days
        start_date: Option<u64>, // initially undefined, is updated once someone rents it
        price_per_day: u64,
        renter: address
    }

    /// A shared object that should be minted by every creator. 
    /// Provides authorized access to an empty TransferPolicy. 
    struct ProtectedTP<phantom T> has key, store {
        id: UID,
        transfer_policy: TransferPolicy<T>,
        policy_cap: TransferPolicyCap<T>
    }

    // ==================== Methods ====================

    /// Mints and shares a ProtectedTP for type T.
    public fun create_protected_tp<T>(publisher: &Publisher, ctx: &mut TxContext) {        
        // Creates an empty TP and shares a ProtectedTP<T> object.
        // This can be used to bypass the lock rule under specific conditions.
        // Storing inside the cap the ProtectedTP with no way to access it
        // as we do not want to modify this policy
        let (transfer_policy, policy_cap) = transfer_policy::new<T>(publisher, ctx);
        
        let protected_tp = ProtectedTP {
            id: object::new(ctx),
            transfer_policy,
            policy_cap
        };
        transfer::share_object(protected_tp);
    }

    /// Enables someone to install the Rentables extension in their Kiosk.
    public fun install(kiosk: &mut Kiosk, cap: &KioskOwnerCap, ctx: &mut TxContext) {
        kiosk_extension::add(Rentables {}, kiosk, cap, PERMISSIONS, ctx);
    }

    /// Remove the extension from the Kiosk. Can only be performed by the owner,
    /// The extension storage must be empty for the transaction to succeed.
    public fun remove(kiosk: &mut Kiosk, cap: &KioskOwnerCap, _ctx: &mut TxContext) {
        kiosk_extension::remove<Rentables>(kiosk, cap);
    }

    /// Enables someone to list an asset within the Rentables extension's Bag, 
    /// creating a Bag entry with the asset's ID as the key and a Rentable wrapper object as the value.
    /// Does not require the item to be already placed in the Kiosk.
    public fun list<T: key + store>(
        kiosk: &mut Kiosk, 
        cap: &KioskOwnerCap, 
        item: T,
		duration: u64, 
        price_per_day: u64,
        ctx: &mut TxContext) {
        
        assert!(kiosk::has_access(kiosk, cap), ENotOwner);
        assert!(kiosk_extension::is_installed<Rentables>(kiosk), EExtensionNotInstalled);

        let item_id = object::id<T>(&item);
        let rentable = Rentable {
            object: item,
            duration,
            start_date: option::none<u64>(),
            price_per_day,
            renter: tx_context::sender(ctx)
        };         
        place_in_bag(kiosk, item_id, rentable);               
    }

    /// Enables someone to list an asset within the Rentables extension's Bag, 
    /// creating a Bag entry with the asset's ID as the key and a Rentable wrapper object as the value.
    /// Requires the existance of a ProtectedTP which can only be created by the creator of type T.
    /// The difference between this method and list is that this one works on kiosk locked assets.
    public fun list_locked<T: key + store>(
        kiosk: &mut Kiosk, 
        cap: &KioskOwnerCap,
        protected_tp: &ProtectedTP<T>, 
        item: ID, 
        duration: u64, 
        price_per_day: u64,
        ctx: &mut TxContext) {
        
        assert!(kiosk::has_access(kiosk, cap), ENotOwner);
        assert!(kiosk_extension::is_installed<Rentables>(kiosk), EExtensionNotInstalled);

        // kiosk::list<T>(kiosk, cap, item, 0);
        let coin = coin::zero<SUI>(ctx);
        let (object, request) = kiosk::purchase<T>(kiosk, item, coin);

        let (_item, _paid, _from) = transfer_policy::confirm_request(&protected_tp.transfer_policy, request);

        let rentable = Rentable {
            object,
            duration,
            start_date: option::none<u64>(),
            price_per_day,
            renter: tx_context::sender(ctx)
        };
        place_in_bag(kiosk, item, rentable);            
    }

    /// Allows the renter to delist an item, that is not currently being rented.
    /// Delists the item from the Rentables extension's Bag while respecting lock Rules if present.
    public fun delist<T: key + store>(kiosk: &mut Kiosk, cap: &KioskOwnerCap, transfer_policy: &TransferPolicy<T>, item: ID, _ctx: &mut TxContext) {
        assert!(kiosk::has_access(kiosk, cap), ENotOwner);

        let rentable = take_from_bag<T>(kiosk, item);
        
        let Rentable {            
            object,
            duration: _,
            start_date: _,
            price_per_day: _,
            renter: _ 
        } = rentable;

        if (has_rule<T, Rule>(transfer_policy)) {
            kiosk::lock(kiosk, cap, transfer_policy, object);
        }
        else {
            kiosk::place(kiosk, cap, object);
        };
    }

    /// This enables individuals to rent a listed Rentable. 
    /// It permits anyone to borrow an item on behalf of another user, provided they have the Rentables extension installed.
    public fun rent<T: key + store>(
        renter_kiosk: &mut Kiosk, 
        borrower_kiosk: &mut Kiosk, 
        item: ID, 
		coin: Coin<SUI>, 
        clock: &Clock,
        _ctx: &mut TxContext) {
        
        assert!(kiosk_extension::is_installed<Rentables>(borrower_kiosk), EExtensionNotInstalled);

        let rentable = take_from_bag<T>(renter_kiosk, item);
        
        let total_price = rentable.price_per_day*rentable.duration;
        let coin_value = coin::value(&coin);
        assert!(coin_value == total_price, ENotEnoughCoins);
        
        transfer::public_transfer(coin, rentable.renter);
        
        option::fill(&mut rentable.start_date, clock::timestamp_ms(clock));
        place_in_bag(borrower_kiosk, item, rentable);      
    }

    /// Enables the borrower to acquire the Rentable by reference from their bag.
    public fun borrow<T: key + store>(kiosk: &mut Kiosk, cap: &KioskOwnerCap, id: ID, _ctx: &mut TxContext): &T {
        assert!(kiosk::has_access(kiosk, cap), ENotOwner);
        let ext_storage_mut = kiosk_extension::storage_mut(Rentables {}, kiosk);
        let rentable = bag::borrow<ID, Rentable<T>>(ext_storage_mut, id);

        &rentable.object
    }

    /// Enables the borrower to temporarily acquire the Rentable with an agreement or promise to return it.
    /// All the information about the Rentable is stored within the promise, 
    /// facilitating the reconstruction of the Rentable when the object is returned.
    public fun borrow_val<T: key + store>(kiosk: &mut Kiosk, cap: &KioskOwnerCap, id: ID, _ctx: &mut TxContext): (T, Promise) {
        assert!(kiosk::has_access(kiosk, cap), ENotOwner);
        let borrower_kiosk = object::id(kiosk);

        let rentable = take_from_bag<T>(kiosk, id);

        let promise = Promise {
            item_id: id,
            duration: rentable.duration,
            start_date: *option::borrow(&rentable.start_date),
            price_per_day: rentable.price_per_day,
            renter: rentable.renter,
            borrower_kiosk
        };
        
        let Rentable {            
            object,
            duration: _,
            start_date: _,
            price_per_day: _,
            renter: _ } = rentable;

        (object, promise)
    }

    /// Enables the borrower to return the borrowed item.
    public fun return_val<T: key + store>(kiosk: &mut Kiosk, object: T, promise: Promise, _ctx: &mut TxContext) {
        assert!(kiosk_extension::is_installed<Rentables>(kiosk), EExtensionNotInstalled);

        let Promise {    
            item_id,        
            duration,
            start_date,
            price_per_day,
            renter,
            borrower_kiosk} = promise;

        let kiosk_id = object::id(kiosk);
        assert!(kiosk_id == borrower_kiosk, EInvalidKiosk);

        let rentable = Rentable {
            object,
            duration,
            start_date: option::some(start_date),
            price_per_day,
            renter
        };

        place_in_bag(kiosk, item_id, rentable);
    }

    /// Enables the owner to reclaim their asset once the rental period has concluded.
    public fun reclaim_rentable<T: key + store>(
        renter_kiosk: &mut Kiosk, 
        borrower_kiosk: &mut Kiosk, 
        transfer_policy: &TransferPolicy<T>, 
        clock: &Clock,
        item: ID,
        _ctx: &mut TxContext) {
        assert!(kiosk_extension::is_installed<Rentables>(renter_kiosk), EExtensionNotInstalled);

        let rentable = take_from_bag<T>(borrower_kiosk, item);

        let Rentable {            
            object,
            duration,
            start_date,
            price_per_day: _,
            renter: renter } = rentable;

        // HERE!
        let renter_kiosk_owner = kiosk::owner(renter_kiosk);
        assert!(renter_kiosk == renter, EInvalidKiosk);

        let start_date_u64 = *option::borrow(&start_date);
        let current_timestamp = clock::timestamp_ms(clock);
        let final_timestamp = start_date_u64 + duration*secondsInADay;

        assert!(current_timestamp > final_timestamp, ERentingPeriodNotOver);

        if (has_rule<T, Rule>(transfer_policy)) {
            kiosk_extension::lock<Rentables, T>(Rentables {}, renter_kiosk, object, transfer_policy);
        }
        else {
            kiosk_extension::place<Rentables, T>(Rentables {}, renter_kiosk, object, transfer_policy);
        };
    }

    // ==================== Helper methods ====================

    fun take_from_bag<T: key + store>(kiosk: &mut Kiosk, item_id: ID) : Rentable<T> {

        let ext_storage_mut = kiosk_extension::storage_mut(Rentables {}, kiosk);

        assert!(bag::contains(ext_storage_mut, item_id), EObjectNotExists);

        let rentable = bag::remove<ID, Rentable<T>>(
            ext_storage_mut,
            item_id
        );

        rentable
    }

    fun place_in_bag<T: key + store>(kiosk: &mut Kiosk, item_id: ID, rentable: Rentable<T>) {
        let ext_storage_mut = kiosk_extension::storage_mut(Rentables {}, kiosk);
        bag::add(ext_storage_mut, item_id, rentable);        
    }
}