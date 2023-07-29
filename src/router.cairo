use starknet::ContractAddress;

#[starknet::interface]
trait IRouter<TContractState> {
    // Getters
    fn get_factory(self: @TContractState) -> ContractAddress;
    fn add_liquidity(
        ref self: TContractState,
        token_a: ContractAddress,
        token_b: ContractAddress,
        amount_a_desired: u256,
        amount_b_desired: u256,
        amount_a_min: u256,
        amount_b_min: u256,
        to: ContractAddress,
        deadline: u256,
    ) -> (u256, u256, u256);
    fn remove_liquidity(
        self: @TContractState,
        token_a: ContractAddress,
        token_b: ContractAddress,
        liquidity: u256,
        amount_a_min: u256,
        amount_b_min: u256,
        to: ContractAddress,
        deadline: u256,
    ) -> (u256, u256);
    fn swap_exact_tokens_for_tokens(
        ref self: TContractState,
        amount_in: u256,
        amount_out_min: u256,
        path: Array<ContractAddress>,
        to: ContractAddress,
        deadline: u256,
    ) -> Span<u256>;
    fn swap_tokens_for_exact_tokens(
        ref self: TContractState,
        amount_out: u256,
        amount_in_max: u256,
        path: Array<ContractAddress>,
        to: ContractAddress,
        deadline: u256,
    ) -> Span<u256>;
}

#[starknet::contract]
mod Router {
    use array::{ArrayTrait, SpanTrait};
    use clone::Clone;
    use debug::PrintTrait;
    use integer::{U256Add, U256Sub, U256Mul, U256Div};
    use serde::Serde;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use traits::{Into};
    use zeroable::Zeroable;

    use field_swap::libraries::library;
    use field_swap::erc20::IERC20Dispatcher;
    use field_swap::erc20::IERC20DispatcherTrait;
    use field_swap::pool::{IPoolDispatcher, IPoolDispatcherTrait};
    use field_swap::factory::{IFactoryDispatcher, IFactoryDispatcherTrait};

    #[storage]
    struct Storage {
        factory: ContractAddress, 
    }

    #[constructor]
    fn constructor(ref self: ContractState, factory: ContractAddress) {
        self.factory.write(factory);
    }

    #[external(v0)]
    impl RouterImpl of super::IRouter<ContractState> {
        fn get_factory(self: @ContractState) -> ContractAddress {
            self.factory.read()
        }

        fn add_liquidity(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            amount_a_desired: u256,
            amount_b_desired: u256,
            amount_a_min: u256,
            amount_b_min: u256,
            to: ContractAddress,
            deadline: u256,
        ) -> (u256, u256, u256) {
            let caller = get_caller_address();
            let contract = get_contract_address();
            let pool = IFactoryDispatcher {
                contract_address: self.factory.read()
            }.get_pool_by_tokens(token_a, token_b);
            assert(pool.is_non_zero(), 'pool does not exist');
            let (amount_a, amount_b) = self
                ._add_liquidity(
                    pool,
                    token_a,
                    token_b,
                    amount_a_desired,
                    amount_b_desired,
                    amount_a_min,
                    amount_b_min,
                );
            let token_a_dispatcher = IERC20Dispatcher { contract_address: token_a };
            token_a_dispatcher.transfer_from(caller, pool, amount_a);

            let token_b_dispatcher = IERC20Dispatcher { contract_address: token_b };
            token_b_dispatcher.transfer_from(caller, pool, amount_b);

            // 預け証のトークンを発行する。
            let liquidity = IPoolDispatcher { contract_address: pool,  }.mint(to);
            (amount_a, amount_b, liquidity)
        }
        // "ensure deadlineも実装する必要がある。"
        fn remove_liquidity(
            self: @ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            liquidity: u256,
            amount_a_min: u256,
            amount_b_min: u256,
            to: ContractAddress,
            deadline: u256,
        ) -> (u256, u256) {
            let caller = get_caller_address();
            let pool = IFactoryDispatcher {
                contract_address: self.factory.read()
            }.get_pool_by_tokens(token_a, token_b);
            assert(pool.is_non_zero(), 'pool does not exist');
            IPoolDispatcher { contract_address: pool }.transfer_from(caller, pool, liquidity);
            let (amount0, amount1) = IPoolDispatcher { contract_address: pool }.burn(to);
            let (token0, token1) = library::sort_tokens(token_a, token_b);
            let (amount_a, amount_b) = if token_a == token0 {
                (amount0, amount1)
            } else {
                (amount1, amount0)
            };
            assert(amount_a >= amount_a_min, 'amount_a is insufficient');
            assert(amount_b >= amount_b_min, 'amount_b is insufficient');
            (amount_a, amount_b)
        }

        fn swap_exact_tokens_for_tokens(
            ref self: ContractState,
            amount_in: u256,
            amount_out_min: u256,
            path: Array<ContractAddress>,
            to: ContractAddress,
            deadline: u256,
        ) -> Span<u256> {
            let amounts = library::get_amounts_out(self.factory.read(), amount_in, path.span());
            assert(*amounts.at(amounts.len() - 1) >= amount_out_min, 'output is below min');
            let pool = IFactoryDispatcher {
                contract_address: self.factory.read()
            }.get_pool_by_tokens(*path.at(0), *path.at(1));
            IERC20Dispatcher {
                contract_address: *path.at(0)
            }.transfer_from(get_caller_address(), pool, *amounts.at(0));
            self._swap(amounts, path.span(), to);
            amounts
        }

        fn swap_tokens_for_exact_tokens(
            ref self: ContractState,
            amount_out: u256,
            amount_in_max: u256,
            path: Array<ContractAddress>,
            to: ContractAddress,
            deadline: u256,
        ) -> Span<u256> {
            let amounts = library::get_amounts_in(self.factory.read(), amount_out, path.span());
            'amounts.len'.print();
            amounts.len().print();
            assert(amounts[0].clone() <= amount_in_max, 'input is above max');
            let pool = IFactoryDispatcher {
                contract_address: self.factory.read()
            }.get_pool_by_tokens(*path.at(0), *path.at(1));

            IERC20Dispatcher {
                contract_address: *path.at(0)
            }.transfer_from(get_caller_address(), pool, *amounts.at(0));
            self._swap(amounts, path.span(), to);
            let amounts = ArrayTrait::<u256>::new().span();
            amounts
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // amount,即ち、それぞれのトークンをいくらデポジットするかを算定する関数
        fn _add_liquidity(
            ref self: ContractState,
            pool: ContractAddress,
            token_a: ContractAddress,
            token_b: ContractAddress,
            amount_a_desired: u256,
            amount_b_desired: u256,
            amount_a_min: u256,
            amount_b_min: u256,
        ) -> (u256, u256) {
            let factory: ContractAddress = self.factory.read();
            assert(
                IFactoryDispatcher {
                    contract_address: factory
                }.get_pool_by_tokens(token_a, token_b).is_non_zero(),
                'pool does not exist'
            );

            let (reserve_a, reserve_b) = IPoolDispatcher { contract_address: pool }.get_reserves();
            //reserveが0の場合は、amount_a_desired, amount_b_desiredをそのまま返す
            // token_aとtoken_bのうち、optimalより大きいほうの値をoptimalに切り下げて、逆のトークンはdesiredの値のまま使う。
            let (amount_a, amount_b) = if reserve_a == 0 && reserve_b == 0 {
                (amount_a_desired, amount_b_desired)
            } else {
                let amount_b_optimal = library::quote(amount_a_desired, reserve_a, reserve_b);
                if amount_b_optimal <= amount_b_desired {
                    assert(amount_b_optimal >= amount_b_min, 'amount_b is insufficient');
                    (amount_a_desired, amount_b_optimal)
                } else {
                    let amount_a_optimal = library::quote(amount_b_desired, reserve_b, reserve_a);
                    assert(amount_a_optimal <= amount_a_desired, 'amount_a is insufficient');
                    assert(amount_a_optimal >= amount_a_min, 'amount_a is insufficient');
                    (amount_a_optimal, amount_b_desired)
                }
            };
            'amount_a in _add_liquidity'.print();
            amount_a.print();
            (amount_a, amount_b)
        }

        // requires the initial amount to have already been sent to the first pair
        // 関数のvariablesについても、一度呼び出されたらdropされるのか。
        fn _swap(
            self: @ContractState,
            amounts: Span<u256>,
            path: Span<ContractAddress>,
            to: ContractAddress,
        ) {
            let path_length = path.len();
            let mut i: usize = 0;
            loop {
                if (i >= path_length - 1) {
                    break;
                } else {
                    let (input, output) = (path[i].clone(), path[i + 1].clone());
                    let amount_out = amounts[i + 1];
                    let (token0, _token1) = library::sort_tokens(input, output);
                    // @を使うことにどのような意味があるのか。
                    let (amount0_out, amount1_out) = if input == token0 {
                        (@0.into(), amount_out)
                    } else {
                        (amount_out, @0.into())
                    };
                    let pool = IFactoryDispatcher {
                        contract_address: self.factory.read()
                    }.get_pool_by_tokens(input, output);
                    let data = ArrayTrait::<felt252>::new().span();
                    let to_for_each_swap = if i < path_length - 2 {
                        IFactoryDispatcher {
                            contract_address: self.factory.read()
                        }.get_pool_by_tokens(output, path[i + 2].clone())
                    } else {
                        to
                    };
                    IPoolDispatcher {
                        contract_address: pool
                    }.swap(amount0_out.clone(), amount1_out.clone(), data, to_for_each_swap);
                    i = i + 1;
                };
            };
        }
    }
}
