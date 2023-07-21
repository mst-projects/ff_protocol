#[starknet::interface]
trait ISoraswapFactory <TContractState>{
    fn get_pair(self: @TContractState, token_a: u256, token_b: u256) -> u256;
    fn create_pair(ref self: TContractState, token_a: u256, token_b: u256) -> u256;
}

