use core::zeroable::Zeroable;
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing::{set_caller_address, set_contract_address};

use array::{ArrayTrait, SpanTrait, SpanCopy, SpanSerde};
use option::OptionTrait;
use debug::PrintTrait;
use integer::u256_sqrt;
use integer::{U256Add, U256Sub, U256Mul, U256Div};
use result::ResultTrait;
use serde::Serde;
use traits::{Into, TryInto, PartialEq};

use soraswap::tests::utils;
use soraswap::erc20::ERC20;
use soraswap::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use soraswap::factory::{IFactoryDispatcher, IFactoryDispatcherTrait};
use soraswap::factory::Factory;
use soraswap::pool::{IPoolDispatcher, IPoolDispatcherTrait};
use soraswap::pool::Pool;
use soraswap::pool::Pool::PoolImpl;
use soraswap::router::Router;
use soraswap::router::Router::RouterImpl;
use soraswap::router::Router::InternalImpl;
use soraswap::router::{IRouterDispatcher, IRouterDispatcherTrait};

const DECIMALS: u8 = 18;
const MINIMUM_LIQUIDITY: u256 = 1000;
const INITIAL_LIQUIDITY: u256 = 1_000_000_000;
const NAME: felt252 = 'Soraswap';
const SYMBOL: felt252 = 'SRS';


fn POOL_STATE() -> Pool::ContractState {
    Pool::contract_state_for_testing()
}

fn ERC20_STATE() -> ERC20::ContractState {
    ERC20::contract_state_for_testing()
}

fn ZERO_ADDRESS() -> ContractAddress {
    contract_address_const::<0>()
}

fn OWNER() -> ContractAddress {
    contract_address_const::<1>()
}

fn FACTORY() -> ContractAddress {
    contract_address_const::<2>()
}

fn TOKEN_A() -> ContractAddress {
    contract_address_const::<11>()
}

fn TOKEN_B() -> ContractAddress {
    contract_address_const::<12>()
}

//
// Setup
//

fn setup() -> Pool::ContractState {
    let mut state = POOL_STATE();
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
// deploy setup
//

fn deploy_erc20_token(name: felt252) -> ContractAddress {
    set_caller_address(OWNER());

    let mut calldata = ArrayTrait::new();
    name.serialize(ref output: calldata);
    'ERC'.serialize(ref output: calldata);
    DECIMALS.serialize(ref output: calldata);
    INITIAL_LIQUIDITY.serialize(ref output: calldata);
    OWNER().serialize(ref output: calldata);

    let contract_address = utils::deploy(ERC20::TEST_CLASS_HASH, calldata);
    contract_address
}

fn deploy_factory() -> ContractAddress {
    set_caller_address(OWNER());

    let mut calldata = ArrayTrait::new();
    Pool::TEST_CLASS_HASH.serialize(ref output: calldata);
    OWNER().serialize(ref output: calldata);

    let contract_address = utils::deploy(Factory::TEST_CLASS_HASH, calldata);
    contract_address
}

fn deploy_pool() -> ContractAddress {
    set_caller_address(FACTORY());
    let mut calldata = ArrayTrait::new();

    let contract_address = utils::deploy(Pool::TEST_CLASS_HASH, calldata);
    contract_address
}

fn deploy_router() -> ContractAddress {
    set_caller_address(ZERO_ADDRESS()); // anyone can deploy router contract
    let mut calldata = ArrayTrait::new();
    FACTORY().serialize(ref output: calldata);
    let contract_address = utils::deploy(Router::TEST_CLASS_HASH, calldata);
    contract_address
}

fn initialize_mint() -> (ContractAddress, ContractAddress, ContractAddress) {
    // Assume factory contract is deployed
    let factory = deploy_factory();

    // Assume token_a and token_b are deployed
    let token_a = deploy_erc20_token('token_a');
    let token_b = deploy_erc20_token('token_b');

    // deploy pool contract, then initialize
    let pool = deploy_pool();
    set_contract_address(FACTORY());
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };
    pool_dispatcher.initialize(token_a, token_b);
    (pool, token_a, token_b)
}

fn process_mint(
    pool: ContractAddress,
    token_a: ContractAddress,
    token_b: ContractAddress,
    a_amount: u256,
    b_amount: u256
) -> (u256, u256, u256, u256, u256, u256) {
    // tranfer token a and token b to pool contract
    set_contract_address(OWNER());
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };

    let token_a_dispatcher = IERC20Dispatcher { contract_address: token_a };
    let token_b_dispatcher = IERC20Dispatcher { contract_address: token_b };

    token_a_dispatcher.transfer(pool, a_amount);
    token_b_dispatcher.transfer(pool, b_amount);

    // mint
    set_contract_address(OWNER());
    let liquidity = pool_dispatcher.mint(OWNER());
    let total_supply = pool_dispatcher.total_supply();
    let balance0 = token_a_dispatcher.balance_of(pool);
    let balance1 = token_b_dispatcher.balance_of(pool);
    let (reserve0, reserve1) = pool_dispatcher.get_reserves();

    (liquidity, total_supply, balance0, balance1, reserve0, reserve1)
}

//
// constructor
// 

#[test]
#[available_gas(200_000_000)]
fn test_constructor() {
    set_caller_address(ZERO_ADDRESS()); // anyone can deploy router contract
    let mut calldata = ArrayTrait::new();
    FACTORY().serialize(ref output: calldata);
    let contract_address = utils::deploy(Router::TEST_CLASS_HASH, calldata);
    let factory = IRouterDispatcher { contract_address: contract_address }.get_factory();
    assert(factory == FACTORY(), 'factory address is incorrect');
}
//
// Getters
//

#[test]
#[available_gas(200_000_000)]
fn test_quote() {
    // let (pool, token_a, token_b) = initialize_mint();
    // let a_amount = 30_000_000;
    // let b_amount = 50_000_000;
    // let (liquidity, total_supply, balance0, balance1, reserve0, reserve1) = process_mint(
    //     pool, token_a, token_b, a_amount, b_amount
    // );
    let router = deploy_router();
    let router_dispatcher = IRouterDispatcher { contract_address: router };
    assert(router_dispatcher.quote(100, 500, 100) == 20, 'amount_b is not equivalent');
}

#[test]
#[available_gas(200_000_000)]
fn test_sort_tokens() {
    let router = deploy_router();
    let router_dispatcher = IRouterDispatcher { contract_address: router };
    let (token0, token1) = router_dispatcher.sort_tokens(TOKEN_A(), TOKEN_B());
    assert(token0 == TOKEN_A() && token1 == TOKEN_B(), 'tokens are not sorted');

    let (token0, token1) = router_dispatcher.sort_tokens(TOKEN_B(), TOKEN_A());
    assert(token0 == TOKEN_A() && token1 == TOKEN_B(), 'tokens are not sorted (reverse)');
}

#[test]
#[available_gas(200_000_000)]
fn test_get_amount_out() {}

