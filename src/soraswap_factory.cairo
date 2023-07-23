use starknet::{ContractAddress};

#[starknet::interface]
trait ISoraswapFactory<TContractState> {
    fn get_all_pools_length(self: @TContractState) -> usize;
    fn create_pool(
        ref self: TContractState, token_a: ContractAddress, token_b: ContractAddress
    ) -> ContractAddress;
    fn set_fee_to(ref self: TContractState, fee_to: ContractAddress);
    fn get_fee_to(self: @TContractState) -> ContractAddress;
    fn set_fee_to_setter(ref self: TContractState, fee_to_setter: ContractAddress);
}

#[starknet::contract]
mod SoraswapFactory {
    use array::ArrayTrait;
    use starknet::class_hash::ClassHash;
    use starknet::syscalls::deploy_syscall;
    use starknet::{ContractAddress, ContractAddressIntoFelt252};
    use zeroable::Zeroable;
    use starknet::contract_address::ContractAddressZeroable;
    use serde::Serde;
    use soraswap::soraswap_pool::SoraswapPool;

    #[storage]
    struct Storage {
        pool_class_hash: ClassHash,
        fee_to: ContractAddress, // recipient of fees
        fee_to_setter: ContractAddress, // a peson who can change the fee_to address
        //variablesの順番が逆になっても、特定できるか。
        pool_by_tokens: LegacyMap::<(ContractAddress, ContractAddress), ContractAddress>,
        all_pools: Array<ContractAddress>
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
        pool: ContractAddress,
        number: u256, //このナンバーとは何か。
    }

    #[constructor]
    fn constructor(ref self: ContractState, fee_to_setter: ContractAddress) {
        self.fee_to.write(ContractAddress::zero());
        self.fee_to_setter.write(fee_to_setter);
    }

    #[external(v0)]
    impl ISoraswapFactoryImpl of super::ISoraswapFactory<ContractState> {
        fn get_all_pools_length(self: @ContractState) -> usize {
            self.all_pools.len()
        }

        fn create_pool(
            ref self: ContractState, token_a: ContractAddress, token_b: ContractAddress
        ) -> ContractAddress {
            assert(token_a != token_b, 'Soraswap: IDENTICAL_ADDRESSES');
            // ContractAddressを比較する方法
            let token_a_in_felt252 = token_a.serialize();
            let token_b_in_felt252 = token_b.serialize();

            let (mut token0, mut token1) = (token_a, token_b);
            if (token_a_in_felt252 < token_b_in_felt252) {
                token0 = token_a;
                token1 = token_b;
            } else {
                token0 = token_b;
                token1 = token_a;
            }

            let pool: ContractAddress = self.get_pool.read(token0, token1);

            assert(pool.is_zero(), 'POOL_EXISTS');

            fn set_fee_to(ref self: ContractState, fee_to: ContractAddress) {
                assert(starknet::get_caller_address() == self.fee_to_setter.read(), 'Soraswap: FORBIDDEN');
                self.fee_to.write(fee_to);
            }

            fn get_fee_to(self: @ContractState) -> ContractAddress {
                return self.fee_to.read();
            }

            fn set_fee_to_setter(ref self: ContractState, fee_to_setter: ContractAddress) {
                assert(starknet::get_caller_address() == self.fee_to_setter.read(), 'Soraswap: FORBIDDEN');
                self.fee_to_setter.write(fee_to_setter);

            }
        }
    }
}

