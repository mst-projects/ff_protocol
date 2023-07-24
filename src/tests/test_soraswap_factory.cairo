use starknet::class_hash::ClassHash;
use starknet::class_hash_const;
use starknet::contract_address_const;
use starknet::testing;

use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use result::ResultTrait;
use serde::Serde;
use traits::{Into, TryInto};

use soraswap::tests::utils;
use soraswap::soraswap_factory::{
    ISoraswapFactory, ISoraswapFactoryDispatcher, ISoraswapFactoryDispatcherTrait
};

use soraswap::soraswap_factory::SoraswapFactory;

fn CALLER() -> ContractAddress {
    constract_address_const::<0>()
}
fn STATE() -> SoraswapFactory::ContractState {
    SoraswapFactory::contract_state_for_testing()
}

//
// Setup
//

fn setup() -> SoraswapFactory::ContractState {
    let mut state = STATE();
    SoraswapFactory::constructor(ref state, class_hash, fee_to_setter);
    state
}

#[test]
#[available_gas(20_000_000)]
fn test_constructor() {
    let factory_class_hash =
        class_hash_const::<0x060ecc284bb8848f5999f385b4508932b1100054d797bf10c833f5e9e8bf3b4d>();

    let pool_class_hash =
        class_hash_const::<0x020a3f9f75016417a0a86a8a13e7ce75bb8a0021db689108268db28eb5c2b818>();

    let mut calldata = ArrayTrait::<felt252>::new();
    pool_class_hash.serialize(ref output: calldata);

    let mut factory = utils::deploy(factory_class_hash, calldata);
    factory.print();
}
