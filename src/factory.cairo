use starknet::{ContractAddress};

#[starknet::interface]
trait IFactory<TContractState> {
    //todo:  only for test. It should be deleted before deployment
    fn _set_pool_by_tokens(
        ref self: TContractState,
        token_a: ContractAddress,
        token_b: ContractAddress,
        pool: ContractAddress
    );
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
    use array::{ArrayTrait, SpanTrait};
    use hash::LegacyHash;
    use serde::Serde;
    use starknet::class_hash::ClassHash;
    use starknet::{ContractAddress, ContractAddressIntoFelt252};
    use starknet::get_caller_address;
    use starknet::syscalls::deploy_syscall;
    use traits::{Into, TryInto};
    use zeroable::Zeroable;

    use field_swap::libraries::library;
    use field_swap::pool::{IPoolDispatcher, IPoolDispatcherTrait};

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
        self.fee_to.write(Zeroable::zero());
        self.fee_to_setter.write(fee_to_setter);
    }

    #[external(v0)]
    impl FactoryImpl of super::IFactory<ContractState> {
        fn _set_pool_by_tokens(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            pool: ContractAddress
        ) {
            let (token0, token1) = library::sort_tokens(token_a, token_b);
            self.pool_by_tokens.write((token_a, token_b), pool);
        }

        fn create_pool(
            ref self: ContractState, token_a: ContractAddress, token_b: ContractAddress
        ) -> ContractAddress {
            assert(token_a != token_b, 'tokens are identical');
            // ContractAddressを比較する方法（もっと良い方法）
            let (token0, token1) = library::sort_tokens(token_a, token_b);
            assert(token0.is_non_zero(), 'token is zero');

            let class_hash = self.pool_class_hash.read();
            let mut pool: ContractAddress = self.pool_by_tokens.read((token0, token1));
            assert(pool.is_zero(), 'pool already exists');

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
            assert(token_a != token_b, 'tokens are identical');
            let (token0, token1) = library::sort_tokens(token_a, token_b);
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

