use starknet::ContractAddress;

#[starknet::interface]
trait ISoraswapRouter<TContractState> {
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

    // fn swap_tokens_for_exact_tokens(
    //     ref self: TContractState,
    //     amount_out: u256,
    //     amount_in_max: u256,
    //     path: Array<ContractAddress>,
    //     to: ContractAddress,
    //     deadline: u256,
    // ) -> Array<u256>;

    fn swap_exact_tokens_for_tokens(
        ref self: TContractState,
        amount_in: u256,
        amount_out_min: u256,
        path: Array<ContractAddress>,
        to: ContractAddress,
        deadline: u256,
    ) -> Span<u256>;

    // view
    fn sort_tokens(
        self: @TContractState, token_a: ContractAddress, token_b: ContractAddress, 
    ) -> (ContractAddress, ContractAddress);

    fn quote(
        self: @TContractState, amount_a: u256, reserve_a: u256, reserve_b: u256, 
    ) -> u256; // amount_b

    fn get_amount_out(
        self: @TContractState, amount_in: u256, reserve_in: u256, reserve_out: u256, 
    ) -> u256; //amount_out

    fn get_amount_in(
        self: @TContractState, amount_out: u256, reserve_in: u256, reserve_out: u256, 
    ) -> u256; //amount_in

    fn get_amounts_out(
        self: @TContractState, amount_in: u256, path: Span<ContractAddress>, 
    ) -> Span<u256>; //amounts_out
// fn get_amounts_in(
//     self: @TContractState, amount_out: u256, path: Span<ContractAddress>, 
// ) -> Span<u256>; //amounts_in
}

#[starknet::contract]
mod SoraswapRouter {
    use starknet::ContractAddress;
    use starknet::get_caller_address;

    use array::{ArrayTrait, SpanTrait};
    use clone::Clone;
    use integer::{U256Add, U256Sub, U256Mul, U256Div};
    use traits::{Into};
    use zeroable::Zeroable;

    use soraswap::libraries::library::SoraswapLibrary;
    use soraswap::soraswap_erc20::IERC20Dispatcher;
    use soraswap::soraswap_erc20::IERC20DispatcherTrait;
    use soraswap::soraswap_pool::{ISoraswapPoolDispatcher, ISoraswapPoolDispatcherTrait};
    use soraswap::soraswap_factory::{ISoraswapFactoryDispatcher, ISoraswapFactoryDispatcherTrait};

    #[storage]
    struct Storage {
        #[key]
        factory: ContractAddress,
    }

    // reserveは、各生トークンが、poolにデポジットされている量

    #[external(v0)]
    impl ISoraswapRouterImpl of super::ISoraswapRouter<ContractState> {
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
            let caller = starknet::get_caller_address();
            let contract = starknet::get_contract_address();
            let pool = ISoraswapFactoryDispatcher {
                contract_address: self.factory.read()
            }.get_pool_by_tokens(token_a, token_b);
            assert(pool.is_non_zero(), 'POOL_NOT_EXIST');
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
            // pairのアドレスを特定した上で、トークンを送信する。

            IERC20Dispatcher {
                contract_address: token_a, 
            }.transfer_from(caller, contract, amount_a);

            IERC20Dispatcher {
                contract_address: token_b, 
            }.transfer_from(caller, contract, amount_b);

            //預け証のトークンを発行する。
            let liquidty = ISoraswapPoolDispatcher { contract_address: pool,  }.mint(to);
            return (amount_a, amount_b, liquidty);
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
            let caller = starknet::get_caller_address();
            let pool = ISoraswapFactoryDispatcher {
                contract_address: self.factory.read()
            }.get_pool_by_tokens(token_a, token_b);
            assert(pool.is_non_zero(), 'POOL_NOT_EXIST');
            ISoraswapPoolDispatcher {
                contract_address: pool
            }.transfer_from(caller, pool, liquidity);
            let (amount0, amount1) = ISoraswapPoolDispatcher { contract_address: pool }.burn(to);
            let (token0, token1) = self._sort_tokens(token_a, token_b);
            let (amount_a, amount_b) = if token_a == token0 {
                (amount0, amount1)
            } else {
                (amount1, amount0)
            };
            assert(amount_a >= amount_a_min, 'INSUFFICIENT_A_AMOUNT');
            assert(amount_b >= amount_b_min, 'INSUFFICIENT_B_AMOUNT');
            return (amount_a, amount_b);
        }

        //todo it does not refer to states in contract, therefore can move it to Library.
        fn sort_tokens(
            self: @ContractState, token_a: ContractAddress, token_b: ContractAddress, 
        ) -> (ContractAddress, ContractAddress) {
            return self._sort_tokens(token_a, token_b);
        }

        // view
        fn quote(self: @ContractState, amount_a: u256, reserve_a: u256, reserve_b: u256, ) -> u256 {
            return self._quote(amount_a, reserve_a, reserve_b);
        }

        // amount_b
        // given an out amount of an asset and pair reserves, returns a required amount of the other asset
        fn get_amount_out(
            self: @ContractState, amount_in: u256, reserve_in: u256, reserve_out: u256, 
        ) -> u256 {
            return self._get_amount_out(amount_in, reserve_in, reserve_out);
        } //amount_out

        // given an output amount of an asset and pair reserves, returns a required amount of the other asset
        fn get_amount_in(
            self: @ContractState, amount_out: u256, reserve_in: u256, reserve_out: u256, 
        ) -> u256 {
            assert(amount_out > 0, 'INSUFFICIENT_OUTPUT_AMOUNT');
            assert(reserve_in > 0 && reserve_out > 0, 'INSUFFICIENT_LIQUIDITY');
            let numerator = reserve_in * amount_out * 1000;
            let denominator = (reserve_out - amount_out) * 997;
            return (numerator / denominator) + 1;
        } //amount_in

        // performs chained get_amount_out calculations on any number of pairs
        fn get_amounts_out(
            self: @ContractState, amount_in: u256, path: Span<ContractAddress>, 
        ) -> Span<u256> {
            return self._get_amounts_out(amount_in, path);
        }

        // fn get_amounts_in(self: @ContractState, amount_out: u256, path: Span<ContractAddress>) -> Span<u256> {
        //     let path_length = path.len();
        //     assert(path_length >= 2, 'INVALID_PATH');
        //     // 固定長のarrayの作成方法
        //     let mut amounts = ArrayTrait::<u256>::new();
        //     amounts.append(amount_out);

        // } 

        //     fn swap_tokens_for_exact_tokens(
        //         ref self: ContractState,
        //         amount_out: u256,
        //         amount_in_max: u256,
        //         path: Array<ContractAddress>,
        //         to: ContractAddress,
        //         deadline: u256,
        // ) -> Span<u256>{
        //     let amounts = self.get_amounts_in(amount_out, path);

        // }

        fn swap_exact_tokens_for_tokens(
            ref self: ContractState,
            amount_in: u256,
            amount_out_min: u256,
            path: Array<ContractAddress>,
            to: ContractAddress,
            deadline: u256,
        ) -> Span<u256> {
            let amounts = self._get_amounts_out(amount_in, path.span());
            assert(
                amounts[amounts.len() - 1].clone() >= amount_out_min, 'INSUFFICIENT_OUTPUT_AMOUNT'
            );
            let pool = ISoraswapFactoryDispatcher {
                contract_address: self.factory.read()
            }.get_pool_by_tokens(path[0].clone(), path[1].clone());
            ISoraswapPoolDispatcher {
                contract_address: pool
            }.transfer_from(starknet::get_caller_address(), pool, amounts[0].clone());
            self._swap(amounts, path.span(), to);
            return amounts;
        }
    }

    #[generate_trait]
    impl LiquidityImpl of LiquidityTrait {
        // returns sorted token addresses, used to handle return values from pairs sorted in this order
        fn _sort_tokens(
            self: @ContractState, token_a: ContractAddress, token_b: ContractAddress, 
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

        fn _quote(
            self: @ContractState, amount_a: u256, reserve_a: u256, reserve_b: u256, 
        ) -> u256 {
            assert(amount_a > 0, 'INSUFFICIENT_AMOUNT');
            assert(reserve_a > 0 && reserve_b > 0, 'INSUFFICIENT_LIQUIDITY');
            return U256Div::div(U256Mul::mul(amount_a, reserve_b), reserve_a);
        }
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
        ) -> (u256, u256) // amount_a, amount_b
        {
            let factory: ContractAddress = self.factory.read();
            assert(
                ISoraswapFactoryDispatcher {
                    contract_address: factory
                }.get_pool_by_tokens(token_a, token_b).is_non_zero(),
                'PAIR_NOT_EXIST'
            );

            let (reserve_a, reserve_b) = ISoraswapPoolDispatcher {
                contract_address: pool
            }.get_reserves();
            //reserveが0の場合は、amount_a_desired, amount_b_desiredをそのまま返す
            // token_aとtoken_bのうち、optimalより大きいほうの値をoptimalに切り下げて、逆のトークンはdesiredの値のまま使う。
            if (reserve_a == 0 && reserve_b == 0) {
                let (amount_a, amount_b) = (amount_a_desired, amount_b_desired);
                return (amount_a, amount_b);
            } else {
                let amount_b_optimal = self._quote(amount_a_desired, reserve_a, reserve_b);
                if (amount_b_optimal <= amount_b_desired) {
                    assert(amount_b_optimal >= amount_b_min, 'INSUFFICIENT_B_AMOUNT');
                    return (amount_a_desired, amount_b_optimal);
                } else {
                    let amount_a_optimal = self._quote(amount_b_desired, reserve_b, reserve_a);
                    assert(amount_a_optimal <= amount_a_desired, 'INSUFFICIENT_A_AMOUNT');
                    assert(amount_a_optimal >= amount_a_min, 'INSUFFICIENT_A_AMOUNT');
                    return (amount_a_optimal, amount_b_desired);
                } // do noth
            }
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
            // for loopの書き方を覚える。
            let mut i: usize = 0;
            loop {
                if (i >= path_length - 1) {
                    break;
                } else {
                    let (input, output) = (path[i].clone(), path[i + 1].clone());
                    let amount_out = amounts[i + 1];
                    let (token0, _token1) = self._sort_tokens(input, output);
                    // @を使うことにどのような意味があるのか。
                    let (amount0_out, amount1_out) = if input == token0 {
                        (@0.into(), amount_out)
                    } else {
                        (amount_out, @0.into())
                    };
                    let pool = ISoraswapFactoryDispatcher {
                        contract_address: self.factory.read()
                    }.get_pool_by_tokens(input, output);
                    let data = ArrayTrait::<felt252>::new().span();
                    let to_for_each_swap = if i < path_length - 2 {
                        ISoraswapFactoryDispatcher {
                            contract_address: self.factory.read()
                        }.get_pool_by_tokens(output, path[i + 2].clone())
                    } else {
                        to
                    };
                    ISoraswapPoolDispatcher {
                        contract_address: pool
                    }.swap(amount0_out.clone(), amount1_out.clone(), data, to_for_each_swap);
                    i = i + 1;
                };
            };
        }

        fn _get_amount_out(
            self: @ContractState, amount_in: u256, reserve_in: u256, reserve_out: u256, 
        ) -> u256 {
            assert(amount_in > 0, 'INSUFFICIENT_INPUT_AMOUNT');
            assert(reserve_in > 0 && reserve_out > 0, 'INSUFFICIENT_LIQUIDITY');
            let amount_in_with_fee = amount_in * 997;
            let numerator = amount_in_with_fee * reserve_out;
            let denominator = reserve_in * 1000 + amount_in_with_fee;
            numerator / denominator
        } //amount_out

        fn _get_amounts_out(
            self: @ContractState, amount_in: u256, path: Span<ContractAddress>, 
        ) -> Span<u256> {
            let path_length = path.len();
            assert(path_length >= 2, 'INVALID_PATH');
            let mut amounts = ArrayTrait::<u256>::new();
            amounts.append(amount_in);

            let mut i: usize = 0;
            loop {
                if (i >= path_length - 1) {
                    break;
                } else {
                    let pool = ISoraswapFactoryDispatcher {
                        contract_address: self.factory.read()
                    }.get_pool_by_tokens(path[i].clone(), path[i + 1].clone());
                    assert(pool.is_zero(), 'POOL_NOT_EXIST');
                    let (reserve_in, reserve_out) = ISoraswapPoolDispatcher {
                        contract_address: pool
                    }.get_reserves();
                    amounts
                        .append(self._get_amount_out(amounts[i].clone(), reserve_in, reserve_out));
                    i = i + 1;
                };
            };
            amounts.span()
        }
    }
}
