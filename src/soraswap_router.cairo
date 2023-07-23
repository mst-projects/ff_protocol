use starknet::ContractAddress;
use array::{ArrayTrait, SpanTrait};

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
        ref self: TContractState,
        token_a: ContractAddress,
        token_b: ContractAddress,
        liquidity: u256,
        amount_a_min: u256,
        amount_b_min: u256,
        to: ContractAddress,
        deadline: u256,
    ) -> (u256, u256);

    fn swap_tokens_for_exact_tokens(
        ref self: TContractState,
        amount_out: u256,
        amount_in_max: u256,
        path: Array<ContractAddress>,
        to: ContractAddress,
        deadline: u256,
    ) -> Array<u256>;

    fn swap_exact_tokens_for_tokens(
        ref self: TContractState,
        amount_in: u256,
        amount_out_min: u256,
        path: Array<ContractAddress>,
        to: ContractAddress,
        deadline: u256,
    ) -> Array<u256>;

    // getter
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
    ) -> Array<u256>; //amounts_out

    fn get_amounts_in(
        self: @TContractState, amount_out: u256, path: Span<ContractAddress>, 
    ) -> Array<u256>; //amounts_in
}

#[starknet::contract]
mod SoraswapPool {
    use starknet::ContractAddress;
    
    use array::{ArrayTrait, SpanTrait};

    use soraswap::soraswap_factory::ISoraswapFactory;
    use soraswap::soraswap_pool::ISoraswapPool;
    use soraswap::libraries::library::SoraswapLibrary;
    use soraswap::soraswap_erc20::IERC20;
    use soraswap::soraswap_erc20::IERC20Dispatcher;
    use soraswap::soraswap_erc20::IERC20DispatcherTrait;
    use soraswap::soraswap_pool::ISoraswapPoolDispatcher;
    use soraswap::soraswap_pool::ISoraswapPoolDispatcherTrait;

    #[storage]
    struct Storage {
        factory: ContractAddress, 
    }

    // reserveは、各トークンが、poolにデポジットされている量

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
            let (amount_a, amount_b) = self
                ._add_liquidity(
                    token_a,
                    token_b,
                    amount_a_desired,
                    amount_b_desired,
                    amount_a_min,
                    amount_b_min,
                );
            // pairのアドレスを特定した上で、トークンを送信する。
            let pool = SoraswapLibrary.pool_for(self.factory_address.read(), token_a, token_b);

            // dispatcherは定義しなくても使えるのか？自動で作成されるものか？どのような場合に？
            IERC20Dispatcher {
                contract_address: token_a, 
            }.transfer_from(caller, contract, amount_a);

            IERC20Dispatcher {
                contract_address: token_b, 
            }.transfer_from(caller, contract, amount_b);

            //預け証のトークンを発行する。
            let liquidty = ISoraswapPoolDispatcher { contract_address: pool,  }.mint(to);
        }
        // "ensure deadlineも実装する必要がある。"
        fn remove_liquidity(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            liquidity: u256,
            amount_a_min: u256,
            amount_b_min: u256,
            to: ContractAddress,
            deadline: u256,
        ) {
            let pair = SoraswapLibrary.pool_for(factory, token_a, token_b);
        }
        // getter
        // given an out amount of an asset and pair reserves, returns a required amount of the other asset
        fn get_amount_out(
            self: @ContractState, amount_in: u256, reserve_in: u256, reserve_out: u256, 
        ) -> u256 {
            assert(amount_in > 0, 'Soraswap: INSUFFICIENT_INPUT_AMOUNT');
            assert(reserve_in > 0 && reserve_out > 0, 'Soraswap: INSUFFICIENT_LIQUIDITY');
            let amount_in_with_fee = amount_in * 997;
            let numerator = amount_in_with_fee * reserve_out;
            let denominator = reserve_in * 1000 + amount_in_with_fee;
            return numerator / denominator;
        } //amount_out

        // given an output amount of an asset and pair reserves, returns a required amount of the other asset
        fn get_amount_in(
            self: @ContractState, amount_out: u256, reserve_in: u256, reserve_out: u256, 
        ) -> u256 {
            assert(amount_out > 0, 'Soraswap: INSUFFICIENT_OUTPUT_AMOUNT');
            assert(reserve_in > 0 && reserve_out > 0, 'Soraswap: INSUFFICIENT_LIQUIDITY');
            let numerator = reserve_in * amount_out * 1000;
            let denominator = (reserve_out - amount_out) * 997;
            return (numerator / denominator) + 1;
        } //amount_in

        // performs chained get_amount_out calculations on any number of pairs
        fn get_amounts_out(
            self: @ContractState, amount_in: u256, path: Span<ContractAddress>, 
        ) -> Array<u256> {
            let path_length = path.len();
            assert(path_length >= 2, 'Soraswap: INVALID_PATH');
            let amounts = Array<u256>::new(path_length);
            amounts[0] = amount_in;
            for (let i = 0; i < path_length - 1; i++) {
                let (reserve_in, reserve_out) = self.get_reserves(path[i], path[i + 1]);
                amounts[i + 1] = self.get_amount_out(amounts[i], reserve_in, reserve_out);
            }
            return amounts;
        } //amounts_out
    }

    #[generate_trait]
    impl LiquidityImpl of LiquidityTrait {
        // amount,即ち、それぞれのトークンをいくらデポジットするかを算定する関数
        fn _add_liquidity(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            amount_a_desired: u256,
            amount_b_desired: u256,
            amount_a_min: u256,
            amount_b_min: u256,
        ) -> (u256, u256) // amount_a, amount_b
        {
            let factory: ContractAddress = self.factory.read();
            assert(ISoraswapFactory(factory).get_pair(token_a, token_b) != 0, 'PAIR_NOT_EXIST');
            let (reserve_a, reserve_b) = self.get_reserves(factory, token_a, token_b);
            //reserveが0の場合は、amount_a_desired, amount_b_desiredをそのまま返す
            // token_aとtoken_bのうち、optimalより大きいほうの値をoptimalに切り下げて、逆のトークンはdesiredの値のまま使う。
            if (reserve_a == 0 && reserve_b == 0) {
                let (amount_a, amount_b) = (amount_a_desired, amount_b_desired);
            } else {
                let amount_b_optimal = self.quote(amount_a_desired, reserve_a, reserve_b);
                if (amount_b_optimal <= amount_b_desired) {
                    assert(amount_b_optimal >= amount_b_min, 'INSUFFICIENT_B_AMOUNT');
                    return (amount_a_desired, amount_b_optimal);
                } else {
                    let amount_a_optimal = self.quote(amount_b_desired, reserve_b, reserve_a);
                    assert(amount_a_optimal <= amount_a_desired, 'INSUFFICIENT_A_AMOUNT');
                    assert(amount_a_optimal >= amount_a_min, 'INSUFFICIENT_A_AMOUNT');
                    return (amount_a_optimal, amount_b_desired);
                }
            //     // do noth
            }
        }

        fn _remove_liquidity(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            liquidity: u256,
            amount_a_min: u256,
            amount_b_min: u256,
        ) -> (u256, u256) // amount_a, amount_b
        {
            let pair = SoraswapLibrary.pool_for(self.factory, token_a, token_b);
            let balance0 = IERC20Dispatcher { contract_address: token_a, }.balance_of(pair);
            let balance1 = IERC20Dispatcher { contract_address: token_b, }.balance_of(pair);
            let (amount0, amount1) = (liquidity * balance0 / ISoraswapPoolDispatcher { contract_address: pair, }.total_supply(), liquidity * balance1 / ISoraswapPoolDispatcher { contract_address: pair, }.total_supply());
            assert(amount0 >= amount_a_min, 'INSUFFICIENT_A_AMOUNT');
            assert(amount1 >= amount_b_min, 'INSUFFICIENT_B_AMOUNT');
            ISoraswapPoolDispatcher { contract_address: pair, }.transfer_from(caller, pair, liquidity);
            IERC20Dispatcher { contract_address: token_a, }.transfer(caller, amount0);
            IERC20Dispatcher { contract_address: token_b, }.transfer(caller, amount1);
            return (amount0, amount1);
        }
        
    }; 
}

