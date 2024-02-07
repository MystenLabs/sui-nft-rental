// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// This module facilitates the rental of NFTs using kiosks. 
/// It allows users to list their NFTs for renting, rent NFTs for a specified duration, and return them after the rental period.
module nft_rental::rentables_ext {
    // std imports
    use std::option::{Self, Option};

    // sui imports
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::tx_context::{TxContext};
    use sui::kiosk_extension;
    use sui::bag;
    use sui::object::{Self, UID, ID};
    use sui::transfer_policy::{Self, TransferPolicy, TransferPolicyCap, has_rule};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
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
    const EExceedsMaxValue: u64 = 6;

    const SECONDS_IN_A_DAY: u64 = 86400;
    const BASIS_POINT_RECIPROCAL: u64 = 10000;
    const MAX_VALUE_U64: u64 = 18446744073709551605;

    // ==================== Structs ====================
    
    /// Extension Key for Kiosk Rentables extension.
    struct Rentables has drop {}

    /// Promise struct for borrowing by value.
    struct Promise has store {
        item_id: ID,
        duration: u64,
        start_date: u64,
        price_per_day: u64,
        renter_kiosk: ID,
        borrower_kiosk: ID
    }

    /// A wrapper object that holds an asset that is being rented. 
    /// Contains information relevant to the rental period, cost and renter.
    struct Rentable<T: key + store> has store {
        object: T,
        duration: u64, // total amount of time offered for renting in days
        start_date: Option<u64>, // initially undefined, is updated once someone rents it
        price_per_day: u64,
        kiosk_id: ID // the kiosk id that the object was taken from
    }

    /// A shared object that should be minted by every creator. 
    /// Defines the royalties the creator will receive from each rent invocation. 
    struct RentalPolicy<phantom T> has key, store {
        id: UID,
        balance: Balance<SUI>,
        amount_bp: u64
    }

    /// A shared object that should be minted by every creator. 
    /// Even for creators that do not wish to enforce royalties.
    /// Provides authorized access to an empty TransferPolicy. 
    struct ProtectedTP<phantom T> has key, store {
        id: UID,
        transfer_policy: TransferPolicy<T>,
        policy_cap: TransferPolicyCap<T>
    }

    // ==================== Methods ====================

    /// Mints and shares a ProtectedTP & a RentalPolicy object for type T. 
    /// Can only be performed by the publisher of type T.
    public fun setup_renting<T: drop>(publisher: &Publisher, amount_bp: u64, ctx: &mut TxContext) {        
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

        let rental_policy = RentalPolicy<T> {
            id: object::new(ctx),
            balance: balance::zero<SUI>(),
            amount_bp
        };

        transfer::share_object(protected_tp);
        transfer::share_object(rental_policy);
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
    /// Requires the existance of a ProtectedTP which can only be created by the creator of type T.
    /// Assumes item is already placed (& optionally locked) in a Kiosk.
    public fun list<T: key + store>(
        kiosk: &mut Kiosk, 
        cap: &KioskOwnerCap,
        protected_tp: &ProtectedTP<T>, 
        item: ID, 
        duration: u64, 
        price_per_day: u64,
        ctx: &mut TxContext) {
        
        kiosk::set_owner(kiosk, cap, ctx);
        assert!(kiosk_extension::is_installed<Rentables>(kiosk), EExtensionNotInstalled);

        kiosk::list<T>(kiosk, cap, item, 0);
        let coin = coin::zero<SUI>(ctx);
        let (object, request) = kiosk::purchase<T>(kiosk, item, coin);

        let (_item, _paid, _from) = transfer_policy::confirm_request(&protected_tp.transfer_policy, request);

        let rentable = Rentable {
            object,
            duration,
            start_date: option::none<u64>(),
            price_per_day,
            kiosk_id: object::id(kiosk)
        };
        place_in_bag(kiosk, item, rentable);            
    }

    /// Allows the renter to delist an item, that is not currently being rented.
    /// Places (or locks, if a lock rule is present) the object back to owner's Kiosk. 
    /// Creators should mint an empty TransferPolicy even if they don't want to apply any royalties.
    public fun delist<T: key + store>(kiosk: &mut Kiosk, cap: &KioskOwnerCap, transfer_policy: &TransferPolicy<T>, item: ID, _ctx: &mut TxContext) {
        assert!(kiosk::has_access(kiosk, cap), ENotOwner);

        let rentable = take_from_bag<T>(kiosk, item);
        
        let Rentable {            
            object,
            duration: _,
            start_date: _,
            price_per_day: _,
            kiosk_id: _
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
    /// The Rental Policy defines the portion of the coin that will be retained as fees and added to the Rental Policy's balance.
    public fun rent<T: key + store>(
        renter_kiosk: &mut Kiosk, 
        borrower_kiosk: &mut Kiosk, 
        rental_policy: &mut RentalPolicy<T>,
        item: ID, 
		coin: Coin<SUI>, 
        clock: &Clock,
        ctx: &mut TxContext) {
        
        assert!(kiosk_extension::is_installed<Rentables>(borrower_kiosk), EExtensionNotInstalled);

        let rentable = take_from_bag<T>(renter_kiosk, item);
        
        let total_price = rentable.price_per_day*rentable.duration;
        assert!(total_price <= MAX_VALUE_U64, EExceedsMaxValue);

        let coin_value = coin::value(&coin);
        assert!(coin_value == total_price, ENotEnoughCoins);
        
        let fees_amount = (coin_value*rental_policy.amount_bp)/BASIS_POINT_RECIPROCAL;
        let fees = coin::split<SUI>(&mut coin, fees_amount, ctx);

        coin::put(&mut rental_policy.balance, fees);
        transfer::public_transfer(coin, kiosk::owner(renter_kiosk));
        
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
            renter_kiosk: rentable.kiosk_id,
            borrower_kiosk
        };
        
        let Rentable {            
            object,
            duration: _,
            start_date: _,
            price_per_day: _,
            kiosk_id: _} = rentable;

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
            renter_kiosk,
            borrower_kiosk} = promise;

        let kiosk_id = object::id(kiosk);
        assert!(kiosk_id == borrower_kiosk, EInvalidKiosk);

        let rentable = Rentable {
            object,
            duration,
            start_date: option::some(start_date),
            price_per_day,
            kiosk_id: renter_kiosk
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
            kiosk_id } = rentable;

        assert!(object::id(renter_kiosk) == kiosk_id, EInvalidKiosk);

        let start_date_u64 = *option::borrow(&start_date);
        let current_timestamp = clock::timestamp_ms(clock);
        let final_timestamp = start_date_u64 + duration*SECONDS_IN_A_DAY;

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