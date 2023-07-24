use array::ArrayTrait;
use result::ResultTrait;
use option::OptionTrait;
use traits::TryInto;
use starknet::ContractAddress;
use starknet::Felt252TryIntoContractAddress;
use cheatcodes::PreparedContract;
use forge_print::PrintTrait;

use soraswap::soraswap_factory::{ISoraswapFactoryDispatcher, ISoraswapFactorySafeDispatcher};
use soraswap::soraswap_pool::{ISoraswapPoolDispatcher, ISoraswapPoolSafeDispatcher};
use soraswap::soraswap_router::{ISoraswapRouterDispatcher, ISoraswapRouterSafeDispatcher};
use soraswap::soraswap_erc20::{ISoraswapERC20Dispatcher, ISoraswapERC20SafeDispatcher};

#[test]
fn test_contract() -> ContractAddress {
    let class_hash = declare('SoraswapFactory').unwrap();
    // let prepared = PreparedContract {
    //     class_hash: class_hash, constructor_calldata: @ArrayTrait::new()
    // };
    // let contract_address = deploy(prepared).unwrap();
    class_hash.print();
// let contract_address: ContractAddress = contract_address.try_into().unwrap();
}
// #[test]
// fn test_increase_balance() { // let contract_address = deploy_hello_starknet();
// let safe_dispatcher = IHelloStarknetSafeDispatcher { contract_address };

// let balance_before = safe_dispatcher.get_balance().unwrap();
// assert(balance_before == 0, 'Invalid balance');

// safe_dispatcher.increase_balance(42).unwrap();

// let balance_after = safe_dispatcher.get_balance().unwrap();
// assert(balance_after == 42, 'Invalid balance');
// }

// #[test]
// fn test_cannot_increase_balance_with_zero_value() { // let contract_address = deploy_hello_starknet();
// let safe_dispatcher = IHelloStarknetSafeDispatcher { contract_address };

// let balance_before = safe_dispatcher.get_balance().unwrap();
// assert(balance_before == 0, 'Invalid balance');

// match safe_dispatcher.increase_balance(0) {
//     Result::Ok(_) => panic_with_felt252('Should have panicked'),
//     Result::Err(panic_data) => {
//         assert(*panic_data.at(0) == 'Amount cannot be 0', *panic_data.at(0));
//     }
// };
// }


