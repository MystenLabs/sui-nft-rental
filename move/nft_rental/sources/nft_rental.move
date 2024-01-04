module nft_rental::rentables_ext {
    // sui imports
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::tx_context::TxContext;
    use sui::kiosk_extension::{Self};
    use sui::bag;
    use sui::object::{Self, ID};
    use sui::transfer_policy::{TransferPolicy};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::transfer;


    // std imports
    use std::option::{Self, Option};
    // use std::debug::{Self};

    // consts
    const PERMISSIONS: u128 = 1;

    const EExtensionNotInstalled: u64 = 0;
    const ENotOwner: u64 = 1;
    const ENotEnoughCoins: u64 = 2;
    const EInvalidRenterKiosk: u64 = 3;
    const ERentingPeriodNotOver: u64 = 4;

    // structs
    struct Rentables has drop {}

    struct Promise has store {
        item_id: ID,
        duration: u64,
        start_date: Option<u64>,
        price_per_day: u64,
        renter: address
    }

    struct Rentable< T: key + store> has store {
        object: T,
        duration: u64, // timestamp or epochs of total amount of time offered for renting
        start_date: Option<u64>, // initially undefined, is updated once someone rents it
        price_per_day: u64,
        renter: address
    }

    // methods
    public fun install(kiosk: &mut Kiosk, cap: &KioskOwnerCap, ctx: &mut TxContext){
        kiosk_extension::add(Rentables {}, kiosk, cap, PERMISSIONS, ctx);
    }


    public fun list<T: key + store>(
        kiosk: &mut Kiosk, 
        cap: &KioskOwnerCap, 
        item: T,
		duration: u64, 
        price_per_day: u64, 
        renter: address) {
        
        assert!(kiosk::has_access(kiosk, cap), ENotOwner);
        assert!(kiosk_extension::is_installed<Rentables>(kiosk), EExtensionNotInstalled);

        let item_id = object::id<T>(&item);
        let rentable = Rentable {
            object: item,
            duration,
            start_date: option::none<u64>(),
            price_per_day,
            renter
        };         
        place_in_bag(kiosk, item_id, rentable);               
    }

    public fun delist<T: key + store>(kiosk: &mut Kiosk, cap: &KioskOwnerCap, item: ID): T {
        assert!(kiosk::has_access(kiosk, cap), ENotOwner);

        let rentable = take_from_bag<T>(kiosk, item);

        let Rentable {            
            object,
            duration: _,
            start_date: _,
            price_per_day: _,
            renter: _ } = rentable;

        object
    }

    public fun rent<T: key + store>(
        renter_kiosk: &mut Kiosk, 
        borrower_kiosk: &mut Kiosk, 
        item: ID, 
		coin: Coin<SUI>, 
        clock: &Clock){
        
        assert!(kiosk_extension::is_installed<Rentables>(borrower_kiosk), EExtensionNotInstalled);

        let rentable = take_from_bag<T>(renter_kiosk, item);

        let total_price = rentable.price_per_day*rentable.duration;
        let coin_value = coin::value(&coin);
        assert!(coin_value == total_price, ENotEnoughCoins);
        
        transfer::public_transfer(coin, kiosk::owner(renter_kiosk));
        
        option::fill(&mut rentable.start_date, clock::timestamp_ms(clock));
        place_in_bag(borrower_kiosk, item, rentable);      
    }

    public fun borrow<T: key + store>(kiosk: &mut Kiosk, cap: &KioskOwnerCap, id: ID): &T {
        assert!(kiosk::has_access(kiosk, cap), ENotOwner);
        assert!(kiosk_extension::is_installed<Rentables>(kiosk), EExtensionNotInstalled);

        let ext_storage_mut = kiosk_extension::storage_mut(Rentables {}, kiosk);
        let rentable = bag::borrow<ID, Rentable<T>>(ext_storage_mut, id);

        &rentable.object
    }

    public fun borrow_val<T: key + store>(kiosk: &mut Kiosk, cap: &KioskOwnerCap, id: ID): (T, Promise) {
        assert!(kiosk::has_access(kiosk, cap), ENotOwner);
        assert!(kiosk_extension::is_installed<Rentables>(kiosk), EExtensionNotInstalled);

        let rentable = take_from_bag<T>(kiosk, id);

        let promise = Promise {
            item_id: id,
            duration: rentable.duration,
            start_date: rentable.start_date,
            price_per_day: rentable.price_per_day,
            renter: rentable.renter
        };
        
        let Rentable {            
            object,
            duration: _,
            start_date: _,
            price_per_day: _,
            renter: _ } = rentable;

        (object, promise)
    }

    public fun return_val<T: key + store>(kiosk: &mut Kiosk, object: T, promise: Promise) {
        assert!(kiosk_extension::is_installed<Rentables>(kiosk), EExtensionNotInstalled);
        
        let Promise {    
            item_id,        
            duration,
            start_date,
            price_per_day,
            renter} = promise;

        let rentable = Rentable {
            object,
            duration,
            start_date,
            price_per_day,
            renter
        };

        place_in_bag(kiosk, item_id, rentable);
    }

    public fun reclaim_rentable<T: key + store>(
        renter_kiosk: &mut Kiosk, 
        borrower_kiosk: &mut Kiosk, 
        policy: &TransferPolicy<T>, 
        clock: &Clock,
        item: ID) {
        assert!(kiosk_extension::is_installed<Rentables>(renter_kiosk), EExtensionNotInstalled);
        assert!(kiosk_extension::is_installed<Rentables>(borrower_kiosk), EExtensionNotInstalled);

        let rentable = take_from_bag<T>(borrower_kiosk, item);

        let Rentable {            
            object,
            duration,
            start_date,
            price_per_day: _,
            renter: renter } = rentable;
        
        let renter_kiosk_owner = kiosk::owner(renter_kiosk);
        assert!(renter_kiosk_owner == renter, EInvalidRenterKiosk);

        let start_date_u64 = *option::borrow(&start_date);
        let current_timestamp = clock::timestamp_ms(clock);
        assert!(current_timestamp > start_date_u64 + duration, ERentingPeriodNotOver);

        kiosk_extension::place<Rentables, T>(Rentables {}, renter_kiosk, object, policy);
    }

    // Helper methods
    fun take_from_bag<T: key + store>(kiosk: &mut Kiosk, item_id: ID) : Rentable<T> {

        let ext_storage_mut = kiosk_extension::storage_mut(Rentables {}, kiosk);

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