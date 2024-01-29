#[test_only]
module nft_rental::tests {
    // sui imports
    use sui::test_scenario::{Self};
    use sui::object::{Self, UID, ID};
    use sui::transfer_policy::{Self, TransferPolicy, TransferPolicyCap};
    use sui::package::{Self};
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::kiosk_test_utils::{Self};
    use sui::transfer;
    use sui::clock::{Self};
    use sui::tx_context::{TxContext, dummy};

    // other imports 
    use nft_rental::rentables_ext::{Self, Promise, ProtectedTP};
    use kiosk::kiosk_lock_rule::{Self as lock_rule};
    
    const RENTER: address = @0xAAAA;
    const BORROWER: address = @0xBBBB;

    struct T has key, store {id: UID}
    struct TESTS has drop {}

    struct PromiseWrapper has key, store {
        id: UID,
        promise: Promise
    }


    #[test]
    fun test_install_extension() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_remove_extension() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::remove(&mut kiosk, &kiosk_cap);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_created_protected_tp() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let witness = TESTS {};
        let publisher = package::test_claim(witness, &mut dummy());

        test_scenario::next_tx(test, RENTER);
        {
            rentables_ext::create_protected_tp<T>(&publisher, test_scenario::ctx(test)); 

        };
        test_scenario::next_tx(test, RENTER);
        {
            let protected_tp = test_scenario::take_shared<ProtectedTP<T>>(test);
            test_scenario::return_shared<ProtectedTP<T>>(protected_tp);
        };
        package::burn_publisher(publisher);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_list_with_extension() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut kiosk, &kiosk_cap, item, 120000, 10000000, RENTER);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::EExtensionNotInstalled)]
    fun test_list_without_extension() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut kiosk, &kiosk_cap, item, 120000, 10000000, RENTER);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::ENotOwner)]
    fun test_list_with_wrong_cap() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let _borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_address<KioskOwnerCap>(test, BORROWER);

            rentables_ext::list(&mut kiosk, &kiosk_cap, item, 120000, 10000000, RENTER);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_list_locked_with_extension() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let witness = TESTS {};
        let publisher = package::test_claim(witness, &mut dummy());

        let (transfer_policy, policy_cap) = transfer_policy::new<T>(&publisher, test_scenario::ctx(test));
        transfer::public_transfer(transfer_policy, RENTER);
        transfer::public_transfer(policy_cap, RENTER);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            rentables_ext::create_protected_tp<T>(&publisher, test_scenario::ctx(test)); 

        };
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);
            let transfer_policy = test_scenario::take_from_sender<TransferPolicy<T>>(test);

            kiosk::lock<T>(&mut kiosk, &kiosk_cap, &transfer_policy, item);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
            test_scenario::return_to_sender(test, transfer_policy);
        };
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);
            let protected_tp = test_scenario::take_shared<ProtectedTP<T>>(test);

            rentables_ext::list_locked(&mut kiosk, &kiosk_cap, &protected_tp, item_id, 120000, 10000000, RENTER, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
            test_scenario::return_shared<ProtectedTP<T>>(protected_tp);
        };
        transfer::public_transfer(publisher, RENTER);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::EExtensionNotInstalled)]
    fun test_list_locked_without_extension() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let witness = TESTS {};
        let publisher = package::test_claim(witness, &mut dummy());

        let (transfer_policy, policy_cap) = transfer_policy::new<T>(&publisher, test_scenario::ctx(test));
        transfer::public_transfer(transfer_policy, RENTER);
        transfer::public_transfer(policy_cap, RENTER);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            rentables_ext::create_protected_tp<T>(&publisher, test_scenario::ctx(test)); 

        };
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);
            let transfer_policy = test_scenario::take_from_sender<TransferPolicy<T>>(test);

            kiosk::lock<T>(&mut kiosk, &kiosk_cap, &transfer_policy, item);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
            test_scenario::return_to_sender(test, transfer_policy);
        };
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);
            let protected_tp = test_scenario::take_shared<ProtectedTP<T>>(test);

            rentables_ext::list_locked(&mut kiosk, &kiosk_cap, &protected_tp, item_id, 120000, 10000000, RENTER, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
            test_scenario::return_shared<ProtectedTP<T>>(protected_tp);
        };
        transfer::public_transfer(publisher, RENTER);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::ENotOwner)]
    fun test_list_locked_with_wrong_cap() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let witness = TESTS {};
        let publisher = package::test_claim(witness, &mut dummy());

        let (transfer_policy, policy_cap) = transfer_policy::new<T>(&publisher, test_scenario::ctx(test));
        transfer::public_transfer(transfer_policy, RENTER);
        transfer::public_transfer(policy_cap, RENTER);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let _borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            rentables_ext::create_protected_tp<T>(&publisher, test_scenario::ctx(test)); 

        };
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);
            let transfer_policy = test_scenario::take_from_sender<TransferPolicy<T>>(test);

            kiosk::lock<T>(&mut kiosk, &kiosk_cap, &transfer_policy, item);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
            test_scenario::return_to_sender(test, transfer_policy);
        };
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_address<KioskOwnerCap>(test, BORROWER);
            let protected_tp = test_scenario::take_shared<ProtectedTP<T>>(test);

            rentables_ext::list_locked(&mut kiosk, &kiosk_cap, &protected_tp, item_id, 120000, 10000000, RENTER, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
            test_scenario::return_shared<ProtectedTP<T>>(protected_tp);
        };
        transfer::public_transfer(publisher, RENTER);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_delist_locked() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);
        let witness = TESTS {};

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));

        let publisher = package::claim(witness, &mut dummy());
        let (transfer_policy, policy_cap) = transfer_policy::new<T>(&publisher, test_scenario::ctx(test));
        transfer::public_transfer(transfer_policy, RENTER);
        transfer::public_transfer(policy_cap, RENTER);
        transfer::public_transfer(publisher, RENTER);
        
        test_scenario::next_tx(test, RENTER);
        {
            let transfer_policy = test_scenario::take_from_sender<TransferPolicy<T>>(test);
            let policy_cap = test_scenario::take_from_sender<TransferPolicyCap<T>>(test);

            lock_rule::add(&mut transfer_policy, &policy_cap);

            test_scenario::return_to_sender(test, transfer_policy);
            test_scenario::return_to_sender(test, policy_cap);
        };
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut kiosk, &kiosk_cap, item, 120000, 10000000, RENTER);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);
            let transfer_policy = test_scenario::take_from_sender<TransferPolicy<T>>(test);

            rentables_ext::delist<T>(&mut kiosk, &kiosk_cap, &transfer_policy, item_id);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
            test_scenario::return_to_sender(test, transfer_policy);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_delist_placed() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);
        let witness = TESTS {};

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));

        let publisher = package::claim(witness, &mut dummy());
        let (transfer_policy, policy_cap) = transfer_policy::new<T>(&publisher, test_scenario::ctx(test));
        transfer::public_transfer(transfer_policy, RENTER);
        transfer::public_transfer(policy_cap, RENTER);
        transfer::public_transfer(publisher, RENTER);
        
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut kiosk, &kiosk_cap, item, 120000, 10000000, RENTER);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);
            let transfer_policy = test_scenario::take_from_sender<TransferPolicy<T>>(test);

            rentables_ext::delist<T>(&mut kiosk, &kiosk_cap, &transfer_policy, item_id);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
            test_scenario::return_to_sender(test, transfer_policy);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::ENotOwner)]
    fun test_delist_with_wrong_cap() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);
        let witness = TESTS {};

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let _borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        let publisher = package::claim(witness, test_scenario::ctx(test));
        let (transfer_policy, policy_cap) = transfer_policy::new<T>(&publisher, test_scenario::ctx(test));
        transfer::public_transfer(transfer_policy, RENTER);
        transfer::public_transfer(policy_cap, RENTER);
        transfer::public_transfer(publisher, RENTER);

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut kiosk, &kiosk_cap, item, 120000, 10000000, RENTER);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_address<KioskOwnerCap>(test, BORROWER);
            let transfer_policy = test_scenario::take_from_sender<TransferPolicy<T>>(test);

            rentables_ext::delist<T>(&mut kiosk, &kiosk_cap, &transfer_policy, item_id);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
            test_scenario::return_to_sender(test, transfer_policy);

        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_rent_with_extension() {
        let scenario= test_scenario::begin(BORROWER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut renter_kiosk, &renter_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut renter_kiosk, &renter_kiosk_cap, item, 2, 10, RENTER);


            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            let clock = clock::create_for_testing(test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::EExtensionNotInstalled)]
    fun test_rent_without_extension() {
        let scenario= test_scenario::begin(BORROWER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut renter_kiosk, &renter_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut renter_kiosk, &renter_kiosk_cap, item, 2, 10, RENTER);


            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(100, test_scenario::ctx(test));

            let clock = clock::create_for_testing(test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::ENotEnoughCoins)]
    fun test_rent_with_not_enough_coins() {
        let scenario= test_scenario::begin(BORROWER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut renter_kiosk, &renter_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut renter_kiosk, &renter_kiosk_cap, item, 2, 10, RENTER);


            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };


        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(10, test_scenario::ctx(test));

            let clock = clock::create_for_testing(test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_borrow() {
        let scenario= test_scenario::begin(BORROWER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut renter_kiosk, &renter_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut renter_kiosk, &renter_kiosk_cap, item, 2, 10, RENTER);


            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            let clock = clock::create_for_testing(test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            let _object = rentables_ext::borrow<T>(&mut kiosk, &kiosk_cap, item_id);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::ENotOwner)]
    fun test_borrow_with_wrong_cap() {
        let scenario= test_scenario::begin(BORROWER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut renter_kiosk, &renter_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut renter_kiosk, &renter_kiosk_cap, item, 2, 10, RENTER);


            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            let clock = clock::create_for_testing(test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let kiosk_cap = test_scenario::take_from_address<KioskOwnerCap>(test, RENTER);

            let _object = rentables_ext::borrow<T>(&mut kiosk, &kiosk_cap, item_id);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_borrow_val() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            rentables_ext::list(&mut kiosk, &kiosk_cap, item, 2, 10, RENTER);
        
            test_scenario::return_shared<Kiosk>(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            let clock = clock::create_for_testing(test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            let (object, promise) = rentables_ext::borrow_val<T>(&mut kiosk, &kiosk_cap, item_id);
            
            let promise_wrapper = PromiseWrapper {
                id: object::new(test_scenario::ctx(test)),
                promise
            };

            transfer::public_transfer(object, BORROWER);
            transfer::public_transfer(promise_wrapper, BORROWER);
            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::ENotOwner)]
    fun test_borrow_val_with_wrong_cap() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            rentables_ext::list(&mut kiosk, &kiosk_cap, item, 2, 10, RENTER);
        
            test_scenario::return_shared<Kiosk>(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            let clock = clock::create_for_testing(test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let kiosk_cap = test_scenario::take_from_address<KioskOwnerCap>(test, RENTER);

            let (object, promise) = rentables_ext::borrow_val<T>(&mut kiosk, &kiosk_cap, item_id);
            
            let promise_wrapper = PromiseWrapper {
                id: object::new(test_scenario::ctx(test)),
                promise
            };

            transfer::public_transfer(object, BORROWER);
            transfer::public_transfer(promise_wrapper, BORROWER);
            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_return_val() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            rentables_ext::list(&mut kiosk, &kiosk_cap, item, 2, 10, RENTER);
        
            test_scenario::return_shared<Kiosk>(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            let clock = clock::create_for_testing(test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            let (object, promise) = rentables_ext::borrow_val<T>(&mut kiosk, &kiosk_cap, item_id);
            
            let promise_wrapper = PromiseWrapper {
                id: object::new(test_scenario::ctx(test)),
                promise
            };

            transfer::public_transfer(object, BORROWER);
            transfer::public_transfer(promise_wrapper, BORROWER);
            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let object = test_scenario::take_from_sender<T>(test);
            let promise_wrapper = test_scenario::take_from_sender<PromiseWrapper>(test);

            let PromiseWrapper {
                id,        
                promise
            } = promise_wrapper;
            
            object::delete(id);
            rentables_ext::return_val(&mut kiosk, object, promise);
            test_scenario::return_shared(kiosk);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::EExtensionNotInstalled)]
    fun test_return_val_without_extension() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            rentables_ext::list(&mut kiosk, &kiosk_cap, item, 2, 10, RENTER);
        
            test_scenario::return_shared<Kiosk>(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            let clock = clock::create_for_testing(test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            let (object, promise) = rentables_ext::borrow_val<T>(&mut kiosk, &kiosk_cap, item_id);
            
            let promise_wrapper = PromiseWrapper {
                id: object::new(test_scenario::ctx(test)),
                promise
            };

            transfer::public_transfer(object, BORROWER);
            transfer::public_transfer(promise_wrapper, BORROWER);
            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::remove(&mut kiosk, &kiosk_cap);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let object = test_scenario::take_from_sender<T>(test);
            let promise_wrapper = test_scenario::take_from_sender<PromiseWrapper>(test);

            let PromiseWrapper {
                id,        
                promise
            } = promise_wrapper;
            
            object::delete(id);
            rentables_ext::return_val(&mut kiosk, object, promise);
            test_scenario::return_shared(kiosk);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::EInvalidKiosk)]
    fun test_return_val_wrong_kiosk() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            rentables_ext::list(&mut kiosk, &kiosk_cap, item, 2, 10, RENTER);
        
            test_scenario::return_shared<Kiosk>(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            let clock = clock::create_for_testing(test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            let (object, promise) = rentables_ext::borrow_val<T>(&mut kiosk, &kiosk_cap, item_id);
            
            let promise_wrapper = PromiseWrapper {
                id: object::new(test_scenario::ctx(test)),
                promise
            };

            transfer::public_transfer(object, BORROWER);
            transfer::public_transfer(promise_wrapper, BORROWER);
            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let object = test_scenario::take_from_sender<T>(test);
            let promise_wrapper = test_scenario::take_from_sender<PromiseWrapper>(test);

            let PromiseWrapper {
                id,        
                promise
            } = promise_wrapper;
            
            object::delete(id);
            rentables_ext::return_val(&mut kiosk, object, promise);
            test_scenario::return_shared(kiosk);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_reclaim() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        let clock = clock::create_for_testing(test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut renter_kiosk, &renter_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut renter_kiosk, &renter_kiosk_cap, item, 2, 10, RENTER);


            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            clock::increment_for_testing(&mut clock, 180000);
            let otw = TESTS {};

            let publisher = package::test_claim(otw, test_scenario::ctx(test));
            let (policy, cap) = transfer_policy::new<T>(&publisher, test_scenario::ctx(test));

            rentables_ext::reclaim_rentable<T>(&mut renter_kiosk, &mut borrower_kiosk, &policy, &clock, item_id);

            clock::destroy_for_testing(clock);
            transfer::public_share_object(publisher);
            transfer::public_share_object(policy);
            transfer::public_transfer(cap, RENTER);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_reclaim_locked() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);
        let witness = TESTS {};

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        let clock = clock::create_for_testing(test_scenario::ctx(test));

        let publisher = package::claim(witness, &mut dummy());
        let (transfer_policy, policy_cap) = transfer_policy::new<T>(&publisher, test_scenario::ctx(test));
        transfer::public_transfer(transfer_policy, RENTER);
        transfer::public_transfer(policy_cap, RENTER);

        test_scenario::next_tx(test, RENTER);
        {
            let transfer_policy = test_scenario::take_from_sender<TransferPolicy<T>>(test);
            let policy_cap = test_scenario::take_from_sender<TransferPolicyCap<T>>(test);

            lock_rule::add(&mut transfer_policy, &policy_cap);

            test_scenario::return_to_sender(test, transfer_policy);
            test_scenario::return_to_sender(test, policy_cap);
        };
        test_scenario::next_tx(test, RENTER);
        {
            rentables_ext::create_protected_tp<T>(&publisher, test_scenario::ctx(test)); 

        };
        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut renter_kiosk, &renter_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);
            let transfer_policy = test_scenario::take_from_sender<TransferPolicy<T>>(test);

            kiosk::lock<T>(&mut kiosk, &kiosk_cap, &transfer_policy, item);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
            test_scenario::return_to_sender(test, transfer_policy);
        };
        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);
            let protected_tp = test_scenario::take_shared<ProtectedTP<T>>(test);

            rentables_ext::list_locked(&mut kiosk, &kiosk_cap, &protected_tp, item_id, 5, 1, RENTER, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
            test_scenario::return_shared<ProtectedTP<T>>(protected_tp);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };
        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::next_tx(test, RENTER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let transfer_policy = test_scenario::take_from_sender<TransferPolicy<T>>(test);

            clock::increment_for_testing(&mut clock, 432000000);

            rentables_ext::reclaim_rentable<T>(&mut renter_kiosk, &mut borrower_kiosk, &transfer_policy, &clock, item_id);

            clock::destroy_for_testing(clock);
            test_scenario::return_to_sender(test, transfer_policy);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        transfer::public_transfer(publisher, RENTER);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::EInvalidKiosk)]
    fun test_reclaim_wrong_kiosk() {
        let scenario= test_scenario::begin(BORROWER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        let clock = clock::create_for_testing(test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut renter_kiosk, &renter_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut renter_kiosk, &renter_kiosk_cap, item, 2, 10, RENTER);


            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            clock::increment_for_testing(&mut clock, 180000);
            let otw = TESTS {};

            let publisher = package::test_claim(otw, test_scenario::ctx(test));
            let (policy, cap) = transfer_policy::new<T>(&publisher, test_scenario::ctx(test));

            rentables_ext::reclaim_rentable<T>(&mut renter_kiosk, &mut borrower_kiosk, &policy, &clock, item_id);

            clock::destroy_for_testing(clock);
            transfer::public_share_object(publisher);
            transfer::public_share_object(policy);
            transfer::public_transfer(cap, RENTER);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::ERentingPeriodNotOver)]
    fun test_reclaim_renting_period_not_over() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        let clock = clock::create_for_testing(test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut renter_kiosk, &renter_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut renter_kiosk, &renter_kiosk_cap, item, 2, 10, RENTER);


            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            clock::increment_for_testing(&mut clock, 100000);
            let otw = TESTS {};

            let publisher = package::test_claim(otw, test_scenario::ctx(test));
            let (policy, cap) = transfer_policy::new<T>(&publisher, test_scenario::ctx(test));

            rentables_ext::reclaim_rentable<T>(&mut renter_kiosk, &mut borrower_kiosk, &policy, &clock, item_id);

            clock::destroy_for_testing(clock);
            transfer::public_share_object(publisher);
            transfer::public_share_object(policy);
            transfer::public_transfer(cap, RENTER);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code=rentables_ext::EExtensionNotInstalled)]
    fun test_reclaim_without_extension() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;
        let item = T {id: object::new(test_scenario::ctx(test))};
        let item_id = object::id(&item);

        let renter_kiosk_id = create_kiosk(RENTER, test_scenario::ctx(test));
        let borrower_kiosk_id = create_kiosk(BORROWER, test_scenario::ctx(test));

        let clock = clock::create_for_testing(test_scenario::ctx(test));

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut renter_kiosk, &renter_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let renter_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::list(&mut renter_kiosk, &renter_kiosk_cap, item, 2, 10, RENTER);


            test_scenario::return_to_sender(test, renter_kiosk_cap);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let borrower_kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut borrower_kiosk, &borrower_kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_to_sender(test, borrower_kiosk_cap);
            test_scenario::return_shared(borrower_kiosk);
        };

        test_scenario::next_tx(test, BORROWER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            let coin = kiosk_test_utils::get_sui(20, test_scenario::ctx(test));

            rentables_ext::rent<T>(&mut renter_kiosk, &mut borrower_kiosk, item_id, coin, &clock);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::remove(&mut kiosk, &kiosk_cap);

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(test, kiosk_cap);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let borrower_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, borrower_kiosk_id);
            let renter_kiosk = test_scenario::take_shared_by_id<Kiosk>(test, renter_kiosk_id);

            clock::increment_for_testing(&mut clock, 180000);
            let otw = TESTS {};

            let publisher = package::test_claim(otw, test_scenario::ctx(test));
            let (policy, cap) = transfer_policy::new<T>(&publisher, test_scenario::ctx(test));

            rentables_ext::reclaim_rentable<T>(&mut renter_kiosk, &mut borrower_kiosk, &policy, &clock, item_id);

            clock::destroy_for_testing(clock);
            transfer::public_share_object(publisher);
            transfer::public_share_object(policy);
            transfer::public_transfer(cap, RENTER);
            test_scenario::return_shared(borrower_kiosk);
            test_scenario::return_shared(renter_kiosk);
        };
        test_scenario::end(scenario);
    }

    // Helper methods
    fun create_kiosk(sender: address, ctx: &mut TxContext): ID {
        let (kiosk, kiosk_cap) = kiosk_test_utils::get_kiosk(ctx);
        let kiosk_id = object::id(&kiosk);
        transfer::public_share_object(kiosk);
        transfer::public_transfer(kiosk_cap, sender);

        kiosk_id
    }
}