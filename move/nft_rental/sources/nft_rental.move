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
    const EInvalidKiosk: u64 = 3;
    const ERentingPeriodNotOver: u64 = 4;

    // structs
    /// Extension Key for Kiosk Rentables extension.
    struct Rentables has drop {}

    /// Promise struct for borrowing by value.
    struct Promise has store {
        item_id: ID,
        duration: u64,
        start_date: Option<u64>,
        price_per_day: u64,
        renter: address,
        borrower_kiosk: ID
    }

    /// A wrapper object that holds an asset that is being rented. 
    /// Contains information relevant to the rental period, cost and renter.
    struct Rentable< T: key + store> has store {
        object: T,
        duration: u64, // timestamp or epochs of total amount of time offered for renting
        start_date: Option<u64>, // initially undefined, is updated once someone rents it
        price_per_day: u64,
        renter: address
    }

    // methods

    /// Enables someone to install the Rentables extension in their Kiosk.
    public fun install(kiosk: &mut Kiosk, cap: &KioskOwnerCap, ctx: &mut TxContext){
        kiosk_extension::add(Rentables {}, kiosk, cap, PERMISSIONS, ctx);
    }

    /// Remove the extension from the Kiosk. Can only be performed by the owner,
    /// The extension storage must be empty for the transaction to succeed.
    public fun remove(kiosk: &mut Kiosk, cap: &KioskOwnerCap) {
        kiosk_extension::remove<Rentables>(kiosk, cap);
    }

    /// Enables someone to list an asset within the Rentables extension's Bag, 
    /// creating a Bag entry with the asset's ID as the key and a Rentable wrapper object as the value.
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

    /// Allows the renter to delist an item, that is not currently being rented.
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

    /// This enables individuals to rent a listed Rentable. 
    /// It permits anyone to borrow an item on behalf of another user, provided they have the Rentables extension installed.
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
        assert!(coin_value >= total_price, ENotEnoughCoins);
        
        transfer::public_transfer(coin, kiosk::owner(renter_kiosk));
        
        option::fill(&mut rentable.start_date, clock::timestamp_ms(clock));
        place_in_bag(borrower_kiosk, item, rentable);      
    }

    /// Enables the borrower to acquire the Rentable by reference from their bag.
    public fun borrow<T: key + store>(kiosk: &mut Kiosk, cap: &KioskOwnerCap, id: ID): &T {
        assert!(kiosk::has_access(kiosk, cap), ENotOwner);
        let ext_storage_mut = kiosk_extension::storage_mut(Rentables {}, kiosk);
        let rentable = bag::borrow<ID, Rentable<T>>(ext_storage_mut, id);

        &rentable.object
    }

    /// Enables the borrower to temporarily acquire the Rentable with an agreement or promise to return it.
    /// All the information about the Rentable is stored within the promise, 
    /// facilitating the reconstruction of the Rentable when the object is returned.
    public fun borrow_val<T: key + store>(kiosk: &mut Kiosk, cap: &KioskOwnerCap, id: ID): (T, Promise) {
        assert!(kiosk::has_access(kiosk, cap), ENotOwner);
        let borrower_kiosk = object::id(kiosk);

        let rentable = take_from_bag<T>(kiosk, id);

        let promise = Promise {
            item_id: id,
            duration: rentable.duration,
            start_date: rentable.start_date,
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
    public fun return_val<T: key + store>(kiosk: &mut Kiosk, object: T, promise: Promise) {
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
            start_date,
            price_per_day,
            renter
        };

        place_in_bag(kiosk, item_id, rentable);
    }

    /// Enables the owner to reclaim their asset once the rental period has concluded.
    public fun reclaim_rentable<T: key + store>(
        renter_kiosk: &mut Kiosk, 
        borrower_kiosk: &mut Kiosk, 
        policy: &TransferPolicy<T>, 
        clock: &Clock,
        item: ID) {
        assert!(kiosk_extension::is_installed<Rentables>(renter_kiosk), EExtensionNotInstalled);

        let rentable = take_from_bag<T>(borrower_kiosk, item);

        let Rentable {            
            object,
            duration,
            start_date,
            price_per_day: _,
            renter: renter } = rentable;

        let renter_kiosk_owner = kiosk::owner(renter_kiosk);
        assert!(renter_kiosk_owner == renter, EInvalidKiosk);

        let start_date_u64 = *option::borrow(&start_date);
        let current_timestamp = clock::timestamp_ms(clock);
        let final_timestamp = start_date_u64 + duration*86400;

        assert!(current_timestamp > final_timestamp, ERentingPeriodNotOver);

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