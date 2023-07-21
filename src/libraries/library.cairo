use starknet::ContractAddress;
use starknet::ContractAddressIntoFelt252;
use starknet::TryInto;
use starknet::Into;
use soraswap::soraswap_pool::ISoraswapPoolDispatcher;

trait ISoraswapLibrary {
    fn quote(
        reserve0: u256,
        reserve1: u256,
        amount: u256,
    ) -> u256;

    fn get_reserves(    
    ) -> (u256, u256);

    fn pair_for(
        factory: ContractAddress,
        token_a: ContractAddress,
        token_b: ContractAddress,
    ) -> ContractAddress;

    fn sort_tokens(
        token_a: ContractAddress,
        token_b: ContractAddress,
    ) -> (ContractAddress, ContractAddress);

    fn get_amounts_out(
        factory: ContractAddress,
        amount_in: u256,
        path: Array<ContractAddress>,
    ) -> Array<u256>;
}

        impl ISoraswapLibraryImpl of ISoraswapLibrary {
            fn quote(
                reserve_0: u256,
                reserve_1: u256,
                amount: u256,
            ) -> u256 {
                return amount * reserve_1 / reserve_0;
            }
            
            // fetches and sorts the reserves for a pair
            fn get_reserves(    
            ) -> (u256, u256) {
                let (token_0: ContractAddress, ) = sort_tokens(token_a, token_b);
                let (reserve_0, reserve_1, ) = ISoraswapPoolDispatcher(pairFor(factory, token_a, token_b)).get_reserves();

            }

            
            // returns sorted token addresses, used to handle return values from pairs sorted in this order
            fn sort_tokens(
                token_a: ContractAddress,
                token_b: ContractAddress,
            ) -> (ContractAddress, ContractAddress) {
                assert(token_a != token_b, 'SoraswapLibrary: IDENTICAL_ADDRESSES');
                let token_a_felt: felt252 = token_a.try_into().unwrap();
        
                // addressの大きさを比較する方法は？
                if (token_b.into() < token_b.into()) {
                   let  (token_0, token_1) = (token_a, token_b);
                } else {
                    let  (token_0, token_1) = (token_b, token_a);

                }
                  

                return token_a < token_b ? (token_a, token_b) : (token_b, token_a);
            }
            

            // calculates the CREATE2 address for a pair without making any external calls
            fn pair_for(
                factory: ContractAddress,
                tokenA: ContractAddress,
                tokenB: ContractAddress,
            ) -> ContractAddress {
               let (token_0, token_1) = sort_tokens(token_a, token_b);  
            }

            // performs chained get_amounts_out calculations on any number of pairs
            fn get_amounts_out(

            ) -> 
                

}

