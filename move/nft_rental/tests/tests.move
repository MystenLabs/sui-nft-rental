#[test_only]

module nft_rental::tests {
    // Imports 
    use nft_rental::rentables_ext::{Self, Rentable, Promise};

    use std::string::{Self};
    use std::option;
    use std::debug::{Self};

    use sui::test_scenario::{Self, Scenario};
    use sui::transfer_policy::{TransferPolicy};
    use sui::tx_context::{Self, dummy};
    use sui::package::{Self};
    use sui::transfer_policy;
    use sui::coin;
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::kiosk_test_utils::{Self};
    use sui::object::{Self};
    use sui::transfer;


    const RENTER: address = @0xAAAA;
    const BORROWER: address = @0xBBBB;

    #[test]
    fun test_install_extension() {
        let scenario= test_scenario::begin(RENTER);
        let test = &mut scenario;

        test_scenario::next_tx(test, RENTER);
        {
            let (kiosk, kiosk_cap) = kiosk_test_utils::get_kiosk(test_scenario::ctx(test));
            transfer::public_share_object(kiosk);
            transfer::public_transfer(kiosk_cap, RENTER);
        };

        test_scenario::next_tx(test, RENTER);
        {
            let kiosk = test_scenario::take_shared<Kiosk>(test);
            let kiosk_cap = test_scenario::take_from_sender<KioskOwnerCap>(test);

            rentables_ext::install(&mut kiosk, &kiosk_cap, test_scenario::ctx(test));

            test_scenario::return_shared(kiosk);
            test_scenario::return_to_sender(&scenario, kiosk_cap);
        };
        test_scenario::end(scenario);
    }

}