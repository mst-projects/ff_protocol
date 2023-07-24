use starknet::testing;

#[test]
fn test_constructor() {
    let mut contract = testing::deploy("contracts/contract.cairo").unwrap();
    let (tx, _) = contract.constructor(()).unwrap();
    contract.submit_tx(tx).unwrap();
}