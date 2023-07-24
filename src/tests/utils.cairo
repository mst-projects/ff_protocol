use core::starknet::SyscallResultTrait;
use starknet::ContractAddress;
use starknet::class_hash::Felt252TryIntoClassHash;
use starknet::class_hash::ClassHash;
use starknet::deploy_syscall;

use array::ArrayTrait;

fn deploy(contract_class_hash: ClassHash, calldata: Array<felt252>) -> ContractAddress {
    let (contract_address, _) = starknet::deploy_syscall(
        contract_class_hash, 0, calldata.span(), false
    )
        .unwrap_syscall();
    contract_address
}
