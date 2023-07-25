use starknet::{ContractAddress};

#[starknet::interface]
trait IFactory<TContractState> {
    fn create_pool(
        ref self: TContractState, token_a: ContractAddress, token_b: ContractAddress
    ) -> ContractAddress;
    // give inputs unsorted to the getter function
    fn set_fee_to(ref self: TContractState, fee_to: ContractAddress);
    fn set_fee_to_setter(ref self: TContractState, fee_to_setter: ContractAddress);
    fn get_pool_by_tokens(
        self: @TContractState, token_a: ContractAddress, token_b: ContractAddress
    ) -> ContractAddress;
    fn get_fee_to(self: @TContractState) -> ContractAddress;
    fn get_fee_to_setter(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
mod Factory {
    use starknet::{ContractAddress, ContractAddressIntoFelt252};
    use starknet::class_hash::ClassHash;
    use starknet::get_caller_address;
    use starknet::syscalls::deploy_syscall;

    use array::{ArrayTrait, SpanTrait};
    use hash::LegacyHash;
    use traits::{Into, TryInto};

    use zeroable::Zeroable;
    use starknet::contract_address::ContractAddressZeroable;
    use serde::Serde;

    use soraswap::pool::{IPoolDispatcher, IPoolDispatcherTrait};

    // keyをつけるか否かに意味はあるか。
    #[storage]
    struct Storage {
        pool_class_hash: ClassHash,
        fee_to: ContractAddress, // recipient of fees
        fee_to_setter: ContractAddress, // a peson who can change the fee_to address
        //variablesの順番が逆になっても、特定できるか。
        pool_by_tokens: LegacyMap::<(ContractAddress, ContractAddress), ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PairCreated: PairCreated
    }

    // keyはStorageにつけるのか。Eventにつけるのか。
    #[derive(Drop, starknet::Event)]
    struct PairCreated {
        #[key]
        token0: ContractAddress,
        token1: ContractAddress,
        pool: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, pool_contract_class_hash: ClassHash, fee_to_setter: ContractAddress
    ) {
        self.pool_class_hash.write(pool_contract_class_hash);
        self.fee_to.write(ContractAddressZeroable::zero());
        self.fee_to_setter.write(fee_to_setter);
    }

    #[external(v0)]
    impl FactoryImpl of super::IFactory<ContractState> {
        fn create_pool(
            ref self: ContractState, token_a: ContractAddress, token_b: ContractAddress
        ) -> ContractAddress {
            assert(token_a != token_b, 'IDENTICAL_ADDRESSES');
            // ContractAddressを比較する方法（もっと良い方法）
            let token_a_as_felt: felt252 = token_a.into();
            let token_b_as_felt: felt252 = token_b.into();
            let token_a_as_u256: u256 = token_a_as_felt.into();
            let token_b_as_u256: u256 = token_b_as_felt.into();
            let (mut token0, mut token1) = (token_a, token_b);
            if (token_a_as_u256 < token_b_as_u256) {
                token0 = token_a;
                token1 = token_b;
            } else {
                token0 = token_b;
                token1 = token_a;
            }
            assert(token0.is_non_zero(), 'ZERO_ADDRESS');

            let class_hash = self.pool_class_hash.read();
            let mut pool: ContractAddress = self.pool_by_tokens.read((token0, token1));
            assert(pool.is_zero(), 'POOL_EXISTS');

            let contract_address_salt = LegacyHash::hash(token0.into(), token1);

            // constructorにargumentなしの場合を表現できているか。
            let calldata = ArrayTrait::<felt252>::new().span();

            let deploy_from_zero = false;
            // deoloy pool contract
            let (created_pool, returned_data) = deploy_syscall(
                class_hash, contract_address_salt, calldata, deploy_from_zero: false, 
            )
                .unwrap_syscall();
            IPoolDispatcher { contract_address: created_pool }.initialize(token0, token1);
            self.pool_by_tokens.write((token0, token1), created_pool);
            self
                .pool_by_tokens
                .write((token1, token0), created_pool); // populate mapping in the reverse direction
            self
                .emit(
                    Event::PairCreated(
                        PairCreated { token0: token0, token1: token1, pool: created_pool }
                    )
                );
            created_pool
        }

        fn set_fee_to(ref self: ContractState, fee_to: ContractAddress) {
            assert(get_caller_address() == self.fee_to_setter.read(), 'FORBIDDEN');
            self.fee_to.write(fee_to);
        }

        fn set_fee_to_setter(ref self: ContractState, fee_to_setter: ContractAddress) {
            assert(get_caller_address() == self.fee_to_setter.read(), 'FORBIDDEN');
            self.fee_to_setter.write(fee_to_setter);
        }

        fn get_pool_by_tokens(
            self: @ContractState, token_a: ContractAddress, token_b: ContractAddress
        ) -> ContractAddress {
            assert(token_a != token_b, 'IDENTICAL_ADDRESSES');
            self.pool_by_tokens.read((token_a, token_b))
        }

        fn get_fee_to(self: @ContractState) -> ContractAddress {
            self.fee_to.read()
        }

        fn get_fee_to_setter(self: @ContractState) -> ContractAddress {
            self.fee_to_setter.read()
        }
    }
}

