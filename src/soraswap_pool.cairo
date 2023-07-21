use array::ArrayTrait;
use result::ResultTrait;
use option::OptionTrait;
use traits::TryInto;
use starknet::ContractAddress;
use starknet::Felt252TryIntoContractAddress;



#[starknet::interface]
trait ISoraswapPool<TContractState> {
    // fn MINIMUM_LIQUIDITY() -> u256; //スマートコントラクトにおいて定数をどのように設定するか。
    fn get_factory(self: @TContractState) -> ContractAddress;
    fn get_token0(self: @TContractState) -> ContractAddress;
    fn get_token1(self: @TContractState) -> ContractAddress;
    fn get_reserves(self: @TContractState) -> (u256, u256);
    fn price0_cumulative_last(self: @TContractState) -> u256;
    fn price1_cumulative_last(self: @TContractState) -> u256;

    fn k_last(self: @TContractState) -> u256;

    fn mint(ref self: TContractState, to: ContractAddress) -> u256;

    fn burn(ref self: TContractState, to: ContractAddress) -> (u256, u256);

    // bytesとは何を指すのか。Spanとはどのような構造のtypeであるか。
    fn swap(ref self: TContractState, amount0_out: u256, amount1_out: u256, bytes: Span<felt252>, to: ContractAddress) -> (u256, u256);

    fn initialize(ref self: TContractState, token0: ContractAddress, token1: ContractAddress);

    fn sum(self: @TContractState, a: u256, b: u256) -> u256;

}

#[starknet::contract]
mod SoraSwapPool {
    use zeroable::Zeroable;
    use starknet::get_caller_address;
    use array::SpanTrait;
    use starknet::contract_address_const;
    use core::traits::TryInto;
    use core::traits::Into;
    use box::BoxTrait;
    use clone::Clone;
    use array::ArrayTCloneImpl;
    use option::OptionTrait;
    use option::OptionTraitImpl;
    use starknet::ContractAddress;
    use starknet::ContractAddressIntoFelt252;
    use array::{SpanSerde, ArrayTrait};
    use starknet::class_hash::ClassHash;
    use core::ec;
    use soraswap::soraswap_erc20::IERC20Dispatcher;
    use soraswap::soraswap_erc20::IERC20;
    use soraswap::soraswap_erc20::IERC20DispatcherTrait;

    #[storage] //structは明示しない限り、外からアクセスできないという理解で良いか。
    struct Storage {
        MINIMUM_LIQUIDITY: u128,
        name: felt252,
        symbol: felt252,
        decimals: u8,
        total_supply: u256,
        balances: LegacyMap::<ContractAddress, u256>,
        allowances: LegacyMap::<(ContractAddress, ContractAddress), u256>,
        // constantをどのように処理するか。
        // feeの情報はどこに保存されるのか。
        factory: ContractAddress,
        token0: ContractAddress,
        token1: ContractAddress,
        reserve0: u256,
        reserve1: u256,
        block_timestamp_last: u256,
        price0_cumulative_last: u256,
        price1_cumulative_last: u256,
        k_last: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Swap: Swap,
        Mint: Mint,
        Burn: Burn,
        Transfer: Transfer,
        Approval: Approval,
    }

    #[derive(Drop, starknet::Event)]
    struct Swap {
        sender: ContractAddress,
        amount0In: u256,
        amount1In: u256,
        amount0Out: u256,
        amount1Out: u256,
        to: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct Mint {
        sender: ContractAddress,
        amount0: u256,
        amount1: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Burn {
        sender: ContractAddress,
        amount0: u256,
        amount1: u256,
        to: ContractAddress
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
        let factory = self.factory.read();
        self.factory.write(get_caller_address());
        let new_factory = self.factory.read();

        self.MINIMUM_LIQUIDITY.write(1000);
    }

    #[external(v0)]
    impl IERC20Impl of soraswap::soraswap_erc20::IERC20<ContractState> {
        fn get_name(self: @ContractState) -> felt252 {
            self.name.read()
        }

        fn get_symbol(self: @ContractState) -> felt252 {
            self.symbol.read()
        }

        fn get_decimals(self: @ContractState) -> u8 {
            self.decimals.read()
        }

        fn get_total_supply(self: @ContractState) -> u256 {
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

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            let sender = get_caller_address();
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
    }


    #[external(v0)]
    impl ISoraswapPoolImpl of super::ISoraswapPool<ContractState>{
    //  // this low-level function should be called from a contract which performs important safety checks
        // この関数は、現実にdepositされている残高が増えた後に呼ぶことが想定される（そうしないと、callerは何もmintすることができない。
        // 現実にdepositされている残高はbalanceと観念され、スマコンに記録されている残高は、reserveと観念される。 add liquidity
        fn mint(ref self: ContractState, to: ContractAddress) -> u256 {
            let contract = starknet::get_contract_address();
            let reserve0 = self.reserve0.read();
            let reserve1 = self.reserve1.read();
            
            let balance0 = IERC20Dispatcher{contract_address: self.token0.read()}.balance_of(contract);
            let balance1 = IERC20Dispatcher{contract_address: self.token1.read()}.balance_of(contract);

            // safe mathを導入する。下記のamountは追加されたトークンの量を表す。
            let amount0 = balance0 - reserve0;
            let amount1 = balance1 - reserve1;

            //　下記の関数は理解していない。
            let feeOn = _mint_fee(_reserve0, reserve1);

            // total supplyは、Liquidity Tokenの発行前の数量を示す。
            let total_supply = self.total_supply.read();

            let minimum_liquidity: u128 = self.MINIMUM_LIQUIDITY.read();
            //sqrtをどのように実装するか。
            if (total_supply == 0) {
                let liquidity: u256 = (u256_sqrt(amount0 * amount1) - minimum_liquidity).into();
                assert(liquidity > 0, 'SoraSwap: INSUFFICIENT_LIQUIDITY_MINTED');
                self._mint(ContractAddress.zero_address(), minimum_liquidity.into()); // liquidity tokenが0の場合、minumum liquidityとして強制的に幾らかが割り当てられる。minimum liquidityは永久にロックされる。
                //poolを作った時に、これは発行されるはず。これは、poolを作った人が支払う負担金のようなもので、poolを作った人も取り出すことができないように、liquidity tokenは0アドレスに対して発行される。
            } else {
                //token0とtoken1のどちらかで見てより小さい方の割合に従って、トークンを発行する。
                let liquidity: u256 = u256_min(amount0 * total_supply / reserve0, amount1 * total_supply / reserve1).into();
                assert(liquidity > 0, 'SoraSwap: INSUFFICIENT_LIQUIDITY_MINTED');
                self._mint(to, minimum_liquidity.into()); 
            }
            _update(balance0, balance1, reserve0, reserve1);
            if (feeOn) {
                self.k_last.write(reserve0 * reserve1);
            }
            self.emit(Mint{sender: get_caller_address(), amount0, amount1});
            


        //     let block_info = starknet::get_block_info().unbox();
        //     _mint(ref self, to, block_info.timestamp);
        }

        fn burn(ref self: ContractState, to: ContractAddress) -> (u256, u256) //amount0, amount1を出力する。
         {
            let contract = starknet::get_contract_address();
            let reserve0 = self.reserve0.read();
            let reserve1 = self.reserve1.read();

            let balance0 = IERC20Dispatcher{contract_address: self.token0.read()}.balance_of(contract);
            let balance1 = IERC20Dispatcher{contract_address: self.token1.read()}.balance_of(contract);

            let liquidity = self.balances.read(contract);



        }

        // lockのmodifierを追加する必要がある。
        fn swap(ref self: ContractState, amount0_out: u256, amount1_out: u256, data: Span<felt252>, to: ContractAddress) -> (u256, u256) {
            assert(amount0_out > 0, 'SoraSwap: INSUFFICIENT_OUTPUT_AMOUNT');
        }

        fn skim(ref self: ContractState, to: ContractAddress) {
        let token0 = self.token0.read();
        let token1 = self.token1.read();
        IERC20Dispatcher{contract_address: token0}.transfer_from(IERC20Dispatcher{contract_address: token0}.balances.read(starknet::get_contract_address()), starknet::get_contract_address()) - self.reserve0.read());
        IERC20Dispatcher{contract_address: token1}.transfer_from(balances(starknet::get_contract_address()) - self.reserve1.read());
        }

    //       getters
        fn get_token0(self: @ContractState) -> ContractAddress {
            return self.token0.read();
        }

        fn get_token1(self: @ContractState) -> ContractAddress {
            return self.token1.read();
        }


        fn get_reserves(self: @ContractState) -> (u256, u256) {
            return (self.reserve0.read(), self.reserve1.read());
        }


    }

    #[generate_trait]
    impl SoraswapERC20PrivateImpl of SoraswapERC20PrivateTrait {
        fn _safe_transfer(ref self: ContractState, token: ContractAddress, to: ContractAddress, value: u256) {
            let success = IERC20Dispatcher{contract_address: token}.transfer(to, value);
            assert(success, 'SoraSwap: TRANSFER_FAILED');
        }
        fn _mint(ref self: ContractState, to: ContractAddress, value: u256){
            self.total_supply.write(self.total_supply.read() + value);
            self.balances.write(to, self.balances.read(to) + value);
        }
        fn _burn(ref self: ContractAddress, from: ContractAddress, value: u256){

        }
        
        fn _update(balance0: u256, balance1: u256, reserve0: u256, reserve1: u256) {
            assert(balance0 <= (-1).into() && balance1 <= (-1).into(), 'SoraSwap: OVERFLOW');
            let block_info = starknet::get_block_info().unbox();
            let block_timestamp = block_info.timestamp % 2**32;
            let price0_cumulative_last = self.price0_cumulative_last.read();
            let price1_cumulative_last = self.price1_cumulative_last.read();
            let k_last = self.k_last.read();

            let block_info = starknet::get_block_info().unbox();
            // block情報から、現在のtimestampを取得する方法。
            let time_elapsed = block_info.timestamp - block_timestamp_last;
            if (time_elapsed > 0 && reserve0 != 0 && reserve1 != 0) {
                self.price0_cumulative_last.write(price0_cumulative_last + u256((reserve1 * 2**112) / reserve0) * time_elapsed);
                self.price1_cumulative_last.write(price1_cumulative_last + u256((reserve0 * 2**112) / reserve1) * time_elapsed);
            }
            self.block_timestamp_last.write(block_info.timestamp);
            self.reserve0.write(balance0);
            self.reserve1.write(balance1);
        }

    }

    #[generate_trait]
    impl StorageImpl of StorageTrait {
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
            self.emit(Approval { owner, spender, value: amount });
        }
    }
}

