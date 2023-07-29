use core::math::Oneable;
use starknet::ContractAddress;

#[starknet::interface]
trait IPool<TContractState> {
    // Getters for IERC20-related states
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;

    // Getters for Pool-related states
    fn get_factory(self: @TContractState) -> ContractAddress;
    fn get_minimum_liquidity(self: @TContractState) -> u256;
    fn get_tokens(self: @TContractState) -> (ContractAddress, ContractAddress);
    fn get_reserves(self: @TContractState) -> (u256, u256);
    fn get_k_last(self: @TContractState) -> u256;

    // IERC20-related functions
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    );
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256);
    fn increase_allowance(ref self: TContractState, spender: ContractAddress, added_value: u256);
    fn decrease_allowance(
        ref self: TContractState, spender: ContractAddress, subtracted_value: u256
    );

    // Pool-related functions
    fn initialize(ref self: TContractState, token0: ContractAddress, token1: ContractAddress);
    fn skim(ref self: TContractState, to: ContractAddress);
    fn mint(ref self: TContractState, to: ContractAddress) -> u256;
    fn burn(ref self: TContractState, to: ContractAddress) -> (u256, u256);
    fn swap(
        ref self: TContractState,
        amount0_out: u256,
        amount1_out: u256,
        data: Span<felt252>,
        to: ContractAddress
    );
    fn sync(ref self: TContractState);
}

#[starknet::contract]
mod Pool {
    use array::{ArrayTCloneImpl, SpanSerde, ArrayTrait, SpanTrait};
    use debug::PrintTrait;
    use integer::{U256Add, U256Sub, U256Mul, U256Div};
    use serde::Serde;
    use starknet::ContractAddress;
    use starknet::{get_contract_address, get_caller_address};
    use starknet::contract_address_const;
    use traits::{TryInto, Into};
    use zeroable::Zeroable;

    use soraswap::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use soraswap::factory::{IFactoryDispatcher, IFactoryDispatcherTrait};
    use soraswap::libraries::library::{ICalleeContractDispatcher, ICalleeContractDispatcherTrait};

    const DECIMALS: u8 = 18;
    const MINIMUM_LIQUIDITY: u256 = 1000;
    const NAME: felt252 = 'Soraswap';
    const SYMBOL: felt252 = 'SRS';

    #[storage] //structは明示しない限り、外からアクセスできないという理解で良いか。
    struct Storage {
        minimum_liquidity: u256,
        name: felt252,
        symbol: felt252,
        decimals: u8,
        total_supply: u256,
        balances: LegacyMap::<ContractAddress, u256>,
        allowances: LegacyMap::<(ContractAddress, ContractAddress), u256>,
        factory: ContractAddress,
        token0: ContractAddress,
        token1: ContractAddress,
        reserve0: u256,
        reserve1: u256,
        k_last: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Swap: Swap,
        Mint: Mint,
        Burn: Burn,
        Sync: Sync,
        Transfer: Transfer,
        Approval: Approval,
    }

    #[derive(Drop, starknet::Event)]
    struct Mint {
        #[key]
        sender: ContractAddress,
        amount0: u256,
        amount1: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Burn {
        #[key]
        sender: ContractAddress,
        amount0: u256,
        amount1: u256,
        #[key]
        to: ContractAddress
    }

    #[derive(Drop, Serde, starknet::Event)]
    struct Swap {
        #[key]
        sender: ContractAddress,
        amount0_in: u256,
        amount1_in: u256,
        amount0_out: u256,
        amount1_out: u256,
        #[key]
        to: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct Sync {
        reserve0: u256,
        reserve1: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        value: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        value: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.factory.write(get_caller_address());
        self.name.write(NAME);
        self.symbol.write(SYMBOL);
        self.decimals.write(DECIMALS);
        self.minimum_liquidity.write(MINIMUM_LIQUIDITY);
    }

    #[external(v0)]
    impl PoolImpl of super::IPool<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self.name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            self.decimals.read()
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.total_supply.read()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.allowances.read((owner, spender))
        }

        // getters
        fn get_factory(self: @ContractState) -> ContractAddress {
            self.factory.read()
        }

        fn get_minimum_liquidity(self: @ContractState) -> u256 {
            self.minimum_liquidity.read()
        }

        fn get_tokens(self: @ContractState) -> (ContractAddress, ContractAddress) {
            (self.token0.read(), self.token1.read())
        }

        fn get_reserves(self: @ContractState) -> (u256, u256) {
            (self.reserve0.read(), self.reserve1.read())
        }

        fn get_k_last(self: @ContractState) -> u256 {
            self.k_last.read()
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            let sender = get_caller_address();
            // これが安全であるか。
            self.transfer_helper(sender, recipient, amount);
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            let caller = get_caller_address();
            self.spend_allowance(sender, caller, amount);
            self.transfer_helper(sender, recipient, amount);
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            self.approve_helper(caller, spender, amount);
        }

        fn increase_allowance(
            ref self: ContractState, spender: ContractAddress, added_value: u256
        ) {
            let caller = get_caller_address();
            self
                .approve_helper(
                    caller, spender, self.allowances.read((caller, spender)) + added_value
                );
        }

        fn decrease_allowance(
            ref self: ContractState, spender: ContractAddress, subtracted_value: u256
        ) {
            let caller = get_caller_address();
            self
                .approve_helper(
                    caller, spender, self.allowances.read((caller, spender)) - subtracted_value
                );
        }
        // todo: if token0 == token1, then what happens?
        fn initialize(ref self: ContractState, token0: ContractAddress, token1: ContractAddress) {
            assert(get_caller_address() == self.factory.read(), 'Should be called from factory');
            assert(token0 != token1, 'identical addresses');
            self.token0.write(token0);
            self.token1.write(token1);
        }

        // この関数は、現実にdepositされている残高が増えた後に呼ぶことが想定される（そうしないと、callerは何もmintすることができない。
        // 現実にdepositされている残高はbalanceと観念され、スマコンに記録されている残高は、reserveと観念される。 add liquidity
        fn mint(ref self: ContractState, to: ContractAddress) -> u256 {
            assert(to.is_non_zero(), 'Should not mint to zero');
            let reserve0 = self.reserve0.read();
            let reserve1 = self.reserve1.read();
            let contract = get_contract_address();
            let balance0 = IERC20Dispatcher {
                contract_address: self.token0.read()
            }.balance_of(contract);
            let balance1 = IERC20Dispatcher {
                contract_address: self.token1.read()
            }.balance_of(contract);

            // if overflow happens, then panic
            let amount0 = U256Sub::sub(balance0, reserve0);
            let amount1 = U256Sub::sub(balance1, reserve1);
            // // if protocol fee is on
            // let fee_on = self._mint_fee(reserve0, reserve1);
            let fee_on = false;
            // // total supplyは、Liquidity Tokenの発行前の数量を示す。
            let total_supply = self.total_supply.read();
            let minimum_liquidity: u256 = self.minimum_liquidity.read();

            let mut liquidity = 0_u256;

            if total_supply == 0 {
                liquidity = u256_sqrt(U256Mul::mul(amount0, amount1)).into() - minimum_liquidity;
                assert(liquidity > 0, 'liquidity less than minmum');
                // mint minimum liquidity to zero address
                self
                    ._mint(
                        Zeroable::zero(), minimum_liquidity
                    ); // liquidity tokenが0の場合、minumum liquidityとして強制的に幾らかが割り当てられる。minimum liquidityは永久にロックされる。
            //poolを作った時に、これは発行されるはず。これは、poolを作った人が支払う負担金のようなもので、poolを作った人も取り出すことができないように、liquidity tokenは0アドレスに対して発行される。
            } else {
                let liquidity0 = U256Div::div(U256Mul::mul(amount0, total_supply), reserve0);
                let liquidity1 = U256Div::div(U256Mul::mul(amount1, total_supply), reserve1);

                liquidity = if liquidity0 <= liquidity1 {
                    liquidity0
                } else {
                    liquidity1
                };
            }
            assert(liquidity > 0, 'liquidity should be posivite');
            self._mint(to, liquidity);
            self._update(balance0, balance1, reserve0, reserve1);
            if (fee_on) {
                self.k_last.write(U256Mul::mul(reserve0, reserve1));
            }
            self.emit(Event::Mint(Mint { sender: get_caller_address(), amount0, amount1 }));
            liquidity
        }

        // This function is expected to be called atomically after the caller sends liquidity tokens to the pool contract 
        fn burn(ref self: ContractState, to: ContractAddress) -> (u256, u256) {
            let contract = get_contract_address();
            let reserve0 = self.reserve0.read();
            let reserve1 = self.reserve1.read();
            let token0 = self.token0.read();
            let token1 = self.token1.read();

            let balance0 = IERC20Dispatcher { contract_address: token0 }.balance_of(contract);
            let balance1 = IERC20Dispatcher { contract_address: token1 }.balance_of(contract);

            let liquidity = self
                .balances
                .read(contract); // balance of liquidity token sent to the pool contract itself
            // let fee_on = self._mint_fee(reserve0, reserve1);
            //todo: to review and rewrite mint_fee
            let fee_on = false;
            let total_supply = self.total_supply.read();

            let amount0 = U256Div::div(U256Mul::mul(liquidity, balance0), total_supply);
            let amount1 = U256Div::div(U256Mul::mul(liquidity, balance1), total_supply);

            assert(amount0 > 0 && amount1 > 0, 'burn amounts should positive');
            self._burn(contract, liquidity);

            let token0_dispatcher = IERC20Dispatcher { contract_address: token0 };
            token0_dispatcher.approve(contract, amount0);
            token0_dispatcher.transfer_from(contract, to, amount0);
            let token1_dispatcher = IERC20Dispatcher { contract_address: token1 };
            token1_dispatcher.approve(contract, amount1);
            token1_dispatcher.transfer_from(contract, to, amount1);

            let updated_balance0 = token0_dispatcher.balance_of(contract);
            let updated_balance1 = token1_dispatcher.balance_of(contract);
            self._update(updated_balance0, updated_balance1, reserve0, reserve1);

            if fee_on {
                self.k_last.write(U256Mul::mul(reserve0, reserve1));
            }
            self.emit(Event::Burn(Burn { sender: get_caller_address(), amount0, amount1, to }));
            (amount0, amount1)
        }

        // lockのmodifierを追加する必要がある。
        fn swap(
            ref self: ContractState,
            amount0_out: u256,
            amount1_out: u256,
            data: Span<felt252>,
            to: ContractAddress
        ) {
            assert(amount0_out > 0 || amount1_out > 0, 'one amount_out should positive');
            let reserve0 = self.reserve0.read();
            let reserve1 = self.reserve1.read();
            assert(amount0_out < reserve0, 'reserve0 is insufficient');
            assert(amount1_out < reserve1, 'reserve1 is insufficient');

            let contract = get_contract_address();
            let caller = get_caller_address();
            let token0 = self.token0.read();
            let token1 = self.token1.read();

            assert(to != token0 && to != token1, 'to should different from tokens');

            if amount0_out > 0 {
                let token0_dispatcher = IERC20Dispatcher { contract_address: token0 };
                token0_dispatcher.transfer(to, amount0_out);
            }
            IERC20Dispatcher { contract_address: token1 }.balance_of(contract).print();
            if amount1_out > 0 {
                amount1_out.print();
                let token1_dispatcher = IERC20Dispatcher { contract_address: token1 };
                token1_dispatcher.transfer(to, amount1_out);
            }
            // defalut case: data = 0 / if someone wants to send the tokens to another smart contract
            // and invoke some functions with the specified data, data lengsh should be 1 or more.
            if data.len() > 0 {
                ICalleeContractDispatcher {
                    contract_address: to
                }.call_from_swap(get_caller_address(), amount0_out, amount1_out, data);
            }
            // このバランスの量は、スワップによるcallerに対するトークンの送信を実行したあとのトークン残高
            let balance0 = IERC20Dispatcher { contract_address: token0 }.balance_of(contract);
            let balance1 = IERC20Dispatcher { contract_address: token1 }.balance_of(contract);
            let amount0_in = if balance0 > U256Sub::sub(reserve0, amount0_out) {
                U256Sub::sub(balance0, (U256Sub::sub(reserve0, amount0_out)))
            } else {
                0_u256
            };

            let amount1_in = if balance1 > U256Sub::sub(reserve1, amount1_out) {
                U256Sub::sub(balance1, (U256Sub::sub(reserve1, amount1_out)))
            } else {
                0_u256
            };
            assert(amount0_in > 0 || amount1_in > 0, 'one amount_in should positive');
            let balance0_adjusted = U256Sub::sub(U256Mul::mul(balance0, 1000), amount0_in * 3);
            let balance1_adjusted = U256Sub::sub(U256Mul::mul(balance1, 1000), amount1_in * 3);
            // // feeを含めた、更新後のkが、更新前のk以上であることを確認する。
            assert(
                U256Mul::mul(
                    balance0_adjusted, balance1_adjusted
                ) >= U256Mul::mul(U256Mul::mul(reserve0, reserve1), 1000 * 1000),
                'K should not decrease'
            );
            self._update(balance0, balance1, reserve0, reserve1);
            self
                .emit(
                    Event::Swap(
                        Swap {
                            sender: get_caller_address(),
                            amount0_in,
                            amount1_in,
                            amount0_out,
                            amount1_out,
                            to
                        }
                    )
                );
        }

        fn skim(ref self: ContractState, to: ContractAddress) {
            let contract = get_contract_address();
            let token0 = self.token0.read();
            let token1 = self.token1.read();
            let balance0 = IERC20Dispatcher { contract_address: token0 }.balance_of(contract);
            let balance1 = IERC20Dispatcher { contract_address: token1 }.balance_of(contract);
            IERC20Dispatcher {
                contract_address: token0
            }.transfer_from(contract, to, U256Sub::sub(balance0, self.reserve0.read()));
            IERC20Dispatcher {
                contract_address: token1
            }.transfer_from(contract, to, U256Sub::sub(balance1, self.reserve1.read()));
        }

        fn sync(ref self: ContractState) {
            let contract = get_contract_address();
            let token0 = self.token0.read();
            let token1 = self.token1.read();
            let balance0 = IERC20Dispatcher { contract_address: token0 }.balance_of(contract);
            let balance1 = IERC20Dispatcher { contract_address: token1 }.balance_of(contract);
            self._update(balance0, balance1, self.reserve0.read(), self.reserve1.read());
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn transfer_helper(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            assert(!sender.is_zero(), 'ERC20: transfer from 0');
            assert(!recipient.is_zero(), 'ERC20: transfer to 0');
            self.balances.write(sender, self.balances.read(sender) - amount);
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            self.emit(Transfer { from: sender, to: recipient, value: amount });
        }

        fn spend_allowance(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
        ) {
            let current_allowance = self.allowances.read((owner, spender));
            let ONES_MASK = 0xffffffffffffffffffffffffffffffff_u128;
            let is_unlimited_allowance = current_allowance.low == ONES_MASK
                && current_allowance.high == ONES_MASK;
            if !is_unlimited_allowance {
                self.approve_helper(owner, spender, current_allowance - amount);
            }
        }

        fn approve_helper(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
        ) {
            assert(!spender.is_zero(), 'ERC20: approve from 0');
            self.allowances.write((owner, spender), amount);
            self.emit(Event::Approval(Approval { owner, spender, value: amount }));
        }

        // liquidy tokenをtoに対して発行
        fn _mint(ref self: ContractState, to: ContractAddress, value: u256) {
            self.total_supply.write(U256Add::add(self.total_supply.read(), value));
            self.balances.write(to, U256Add::add(self.balances.read(to), value));
        }

        // todo: 難易度が高いのでもっとよく考える。
        fn _mint_fee(ref self: ContractState, reserve0: u256, reserve1: u256) -> bool {
            let fee_to = IFactoryDispatcher { contract_address: self.factory.read() }.get_fee_to();
            let fee_on = fee_to.is_non_zero();

            let k_last = self.k_last.read();
            if fee_on {
                if k_last.is_non_zero() {
                    let root_k = u256_sqrt(U256Mul::mul(reserve0, reserve1));
                    let root_k_last = u256_sqrt(k_last);
                    if (root_k > root_k_last) {
                        let numerator = U256Mul::mul(
                            self.total_supply.read(), (root_k.into() - root_k_last.into())
                        );
                        let denominator = U256Mul::mul(root_k.into(), 5) + root_k_last.into();
                        let liquidity = U256Div::div(numerator, denominator);
                        if (liquidity > 0) {
                            self._mint(fee_to, liquidity);
                        }
                    }
                }
            } else if k_last.is_non_zero() {
                self.k_last.write(0);
            }
            fee_on
        }

        fn _burn(ref self: ContractState, from: ContractAddress, value: u256) {
            self.total_supply.write(U256Sub::sub(self.total_supply.read(), value));
            self.balances.write(from, U256Sub::sub(self.balances.read(from), value));
        }

        // update reserves according to balances
        // todo review whether reverves should be u128 or smaller -> just for gas saving in Ethereum
        fn _update(
            ref self: ContractState, balance0: u256, balance1: u256, reserve0: u256, reserve1: u256
        ) {
            self.reserve0.write(balance0);
            self.reserve1.write(balance1);
            self.emit(Event::Sync(Sync { reserve0, reserve1 }));
        }
    }
}

