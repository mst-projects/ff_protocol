use starknet::{ContractAddress, ContractAddressIntoFelt252};
use starknet::{TryInto, Into};

use array::{ArrayTrait, SpanTrait};
use hash::LegacyHash;

use soraswap::soraswap_pool::ISoraswapPoolDispatcher;

#[starknet::interface]
trait ISoraswapCallee<TContractState> {
    fn soraswap_call(
        ref self: TContractState,
        sender: ContractAddress,
        amount0: u256,
        amount1: u256,
        data: Span<felt252>,
    ) -> (u256, u256);
}

trait SoraswapLibrary {
    fn get_reserves() -> (u256, u256);
    fn pair_for(
        factory: ContractAddress, token_a: ContractAddress, token_b: ContractAddress, 
    ) -> ContractAddress;
    fn sort_tokens(
        token_a: ContractAddress, token_b: ContractAddress, 
    ) -> (ContractAddress, ContractAddress);
}

impl SoraswapLibraryImpl of SoraswapLibrary { // fetches and sorts the reserves for a pair
    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    fn sort_tokens(
        token_a: ContractAddress, token_b: ContractAddress, 
    ) -> (ContractAddress, ContractAddress) {
        assert(token_a != token_b, 'IDENTICAL_ADDRESSES');
        let token_a_as_felt: felt252 = token_a.into();
        let token_b_as_felt: felt252 = token_b.into();
        let token_a_as_u256: u256 = token_a_as_felt.into();
        let token_b_as_u256: u256 = token_b_as_felt.into();
        if token_a_as_u256 < token_b_as_u256 {
            return (token_a, token_b);
        } else {
            return (token_b, token_a);
        }
    }

    fn get_reserves() -> (u256, u256) {
        let (token0, _token1) = self.sort_tokens(token_a, token_b);
        let (reserve0, reserve1, ) = ISoraswapPoolDispatcher(pairFor(factory, token_a, token_b))
            .get_reserves();
    }
// calculates the CREATE2 address for a pair without making any external calls
// fn pool_for(
//     factory: ContractAddress,
//     token_a: ContractAddress,
//     token_b: ContractAddress,
// ) -> ContractAddress {
//     let (token0, token1) = sort_tokens(token_a, token_b);  
// }

}

