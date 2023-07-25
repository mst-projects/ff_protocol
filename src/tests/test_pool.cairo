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
use soraswap::pool::{IPoolDispatcher, IPoolDispatcherTrait};
use soraswap::pool::Pool;
use soraswap::pool::Pool::PoolImpl;
use soraswap::pool::Pool::InternalImpl;
use soraswap::erc20::ERC20;


fn STATE() -> Pool::ContractState {
    Pool::contract_state_for_testing()
}

fn ERC20_STATE() -> ERC20::ContractState {
    ERC20::contract_state_for_testing()
}

fn FACTORY() -> ContractAddress {
    contract_address_const::<1>()
}

fn TOKEN_A() -> ContractAddress {
    contract_address_const::<2>()
}

fn TOKEN_B() -> ContractAddress {
    contract_address_const::<3>()
}

fn READER() -> ContractAddress {
    contract_address_const::<99>()
}

fn ZERO_ADDRESS() -> ContractAddress {
    contract_address_const::<0>()
}

//
// Setup
//

fn setup() -> Pool::ContractState {
    let mut state = STATE();
    set_caller_address(FACTORY());
    Pool::constructor(ref state);
    state
}

fn setup_erc20_tokens() -> (ERC20::ContractState, ERC20::ContractState) {
    let mut token_a_state = ERC20_STATE();
    let mut token_b_state = ERC20_STATE();
    (token_a_state, token_b_state)
}

//
// Getters
//

#[test]
#[available_gas(20_000_000)]
fn test_get_factory_address() {
    let mut state = setup();
    let factory = PoolImpl::get_factory(@state);
    assert(factory == FACTORY(), 'Factory address is incorrect');
}

#[test]
#[available_gas(20_000_000)]
fn test_minimum_liquidity() {
    let mut state = setup();
    let minimum_liquidity = PoolImpl::get_minimum_liquidity(@state);
    assert(minimum_liquidity == 1000, 'Minimum liquidity is incorrect');
}

//todo How to handle constructor of Parent in inheritance
#[test]
#[available_gas(20_000_000)]
fn test_get_name() {
    let mut state = setup();
    let name = PoolImpl::get_name(@state);
    name.print()
}

//
// invoke
//
#[test]
#[available_gas(20_000_000)]
fn test_initialize_get_token_0_and_1() {
    let mut state = setup();
    set_caller_address(FACTORY());
    PoolImpl::initialize(ref state, TOKEN_A(), TOKEN_B());

    let token0 = PoolImpl::get_token0(@state);
    assert(token0 == TOKEN_A(), 'Token0 is incorrect');

    let token1 = PoolImpl::get_token1(@state);
    assert(token1 == TOKEN_B(), 'Token1 is incorrect');
}

#[test]
#[available_gas(20_000_000)]
#[should_panic(expected: ('P Should be called from factory', ))]
fn test_initialize_should_be_called_from_factory() {
    let mut state = setup();
    set_caller_address(READER());
    PoolImpl::initialize(ref state, TOKEN_A(), TOKEN_B());
}

#[test]
#[available_gas(20_000_000)]
fn test_get_reserves() {
    let mut state = setup();
    set_caller_address(FACTORY());
    PoolImpl::initialize(ref state, TOKEN_A(), TOKEN_B());

    set_caller_address(READER());
    let (reserve0, reserve1) = PoolImpl::get_reserves(@state);
    assert(reserve0 == 0, 'P: Reserve0 is incorrect');
    assert(reserve1 == 0, 'P: Reserve1 is incorrect');
}

#[test]
#[available_gas(20_000_000)]
fn test_get_k_last() {
    let mut state = setup();
    set_caller_address(FACTORY());
    PoolImpl::initialize(ref state, TOKEN_A(), TOKEN_B());

    set_caller_address(READER());
    let k_last = PoolImpl::get_k_last(@state);
    assert(k_last == 0, 'P: K last is incorrect');
}

#[test]
#[available_gas(20_000_000)]
fn test_mint() { // todo: IERC20Dispatcherのテストをどのように行うか。
    let mut state = setup();
}

//
// Internal functions
//
#[test]
#[available_gas(20_000_000)]
fn _update() {
    let mut state = setup();
    set_caller_address(ZERO_ADDRESS());
    InternalImpl::_update(ref state, 400, 150, 300, 200);

    let (reserve0, reserve1) = PoolImpl::get_reserves(@state);
    reserve0.print();
    assert(reserve0 == 400, 'Reserve0 is incorrect');
    assert(reserve1 == 150, 'Reserve1 is incorrect');
}
