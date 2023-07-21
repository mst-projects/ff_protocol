

#[starknet::interface]
trait ISoraswapFactory <TContractState>{
    fn get_pair(self: @TContractState, token_a: u256, token_b: u256) -> u256;
    fn create_pair(ref self: TContractState, token_a: u256, token_b: u256) -> u256;
}

#[starknet::contract]
mod SoraswapFactory {
    use starknet::ContractAddress;

    #[storage]
    struct Storage {
        fee_to: ContractAddress,//何のために定義されているものか。
        fee_to_setter: ContractAddress,//何のために定義されているものか。
        get_pair: LegacyMap
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PairCreated: PairCreated
    }

    #[derive(Drop, starknet::Event)]
    struct PairCreated {
        token0: ContractAddress,
        token1: ContractAddress,
        pair: ContractAddress,
        pair_address: ContractAddress,
        number: u256, //このナンバーとは何か。
    }

    #[constructor]
    fn constructor(ref self: ContractState, fee_to_setter: ContractAddress) {
        self.fee_to_setter.write(fee_to_setter);
    }


}

