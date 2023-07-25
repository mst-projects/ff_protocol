use core::zeroable::Zeroable;
use starknet::class_hash::ClassHash;
use starknet::class_hash_const;
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing::set_caller_address;

use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use result::ResultTrait;
use serde::Serde;
use traits::{Into, TryInto};

use soraswap::tests::utils;
use soraswap::factory::{IFactoryDispatcher, IFactoryDispatcherTrait};
use soraswap::factory::Factory;
use soraswap::factory::Factory::FactoryImpl;

fn STATE() -> Factory::ContractState {
    Factory::contract_state_for_testing()
}
fn OWNER() -> ContractAddress {
    contract_address_const::<1>()
}

fn NEW_OWNER() -> ContractAddress {
    contract_address_const::<2>()
}

fn FEE_RECEIVER() -> ContractAddress {
    contract_address_const::<3>()
}

fn POOL_CLASS_HASH() -> ClassHash {
    class_hash_const::<0x020a3f9f75016417a0a86a8a13e7ce75bb8a0021db689108268db28eb5c2b818>()
}

//
// Setup
//

fn setup() -> Factory::ContractState {
    let mut state = STATE();
    let owner = OWNER();
    let class_hash = POOL_CLASS_HASH();
    Factory::constructor(ref state, class_hash, owner);
    state
}

//
// Getters
//

#[test]
#[available_gas(20_000_000)]
fn test_get_fee_to_setter() {
    let mut state = setup();
    let fee_to_setter = FactoryImpl::get_fee_to_setter(@state);
    assert(fee_to_setter == OWNER(), 'fee_to_setter should be zero');
}

#[test]
#[available_gas(20_000_000)]
fn test_get_fee_to() {
    let mut state = setup();
    let fee_to = FactoryImpl::get_fee_to(@state);
    assert(fee_to.is_zero(), 'fee_to should be zero');
}

//
// set fee-related states
//

#[test]
#[available_gas(20_000_000)]
fn test_set_fee_to() {
    let mut state = setup();
    set_caller_address(OWNER());
    FactoryImpl::set_fee_to(ref state, FEE_RECEIVER());

    let fee_to = FactoryImpl::get_fee_to(@state);
    assert(fee_to == FEE_RECEIVER(), 'fee_to should be FEE_RECEIVER');
}

#[test]
#[available_gas(20_000_000)]
#[should_panic(expected: ('FORBIDDEN', ))]
fn test_set_fee_to_from_zero() {
    let mut state = setup();
    FactoryImpl::set_fee_to(ref state, FEE_RECEIVER());
}

#[test]
#[available_gas(20_000_000)]
fn test_set_fee_to_setter() {
    let mut state = setup();
    set_caller_address(OWNER());
    FactoryImpl::set_fee_to_setter(ref state, NEW_OWNER());

    let fee_to_setter = FactoryImpl::get_fee_to_setter(@state);
    assert(fee_to_setter == NEW_OWNER(), 'fee_to_setter should NEW_OWNER');

    set_caller_address(NEW_OWNER());
    FactoryImpl::set_fee_to(ref state, FEE_RECEIVER());
    let fee_to = FactoryImpl::get_fee_to(@state);
    assert(fee_to == FEE_RECEIVER(), 'fee_to should be FEE_RECEIVER');
}

#[test]
#[available_gas(20_000_000)]
#[should_panic(expected: ('FORBIDDEN', ))]
fn test_set_fee_to_setter_from_zero() {
    let mut state = setup();
    FactoryImpl::set_fee_to(ref state, NEW_OWNER());
}
// #[test]
// #[available_gas(20_000_000)]
// fn test_utils() {
//     let factory_class_hash =
//         class_hash_const::<0x060ecc284bb8848f5999f385b4508932b1100054d797bf10c833f5e9e8bf3b4d>();

//     let pool_class_hash =
//         class_hash_const::<0x020a3f9f75016417a0a86a8a13e7ce75bb8a0021db689108268db28eb5c2b818>();

//     let mut calldata = ArrayTrait::<felt252>::new();
//     pool_class_hash.serialize(ref output: calldata);

//     let mut factory = utils::deploy(factory_class_hash, calldata);
//     factory.print();
// }


