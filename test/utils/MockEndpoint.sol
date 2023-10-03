// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IEndpoint} from "../../src/interfaces/IEndpoint.sol";
import {MockToken} from "./MockToken.sol";
import {MockClearinghouse} from "./MockClearinghouse.sol";

contract MockEndpoint {
    MockClearinghouse public clearingHouse;
    MockToken public BTC;
    MockToken public USDC;
    MockToken public WETH;

    mapping(uint32 => MockToken) public tokens;

    constructor(MockToken _BTC, MockToken _USDC, MockToken _WETH) {
        clearingHouse = new MockClearinghouse(address(BTC), address(USDC), address(WETH));
        BTC = _BTC;
        USDC = _USDC;
        WETH = _WETH;

        tokens[0] = USDC;
        tokens[1] = BTC;
    }

    function clearinghouse() external view returns (address) {
        return address(clearingHouse);
    }

    function submitSlowModeTransaction(bytes calldata transaction) external {
        IEndpoint.TransactionType txType = IEndpoint.TransactionType(uint8(transaction[0]));

        if (txType == IEndpoint.TransactionType.DepositCollateral) {
            IEndpoint.DepositCollateral memory txn = abi.decode(transaction[1:], (IEndpoint.DepositCollateral));
            tokens[txn.productId].transferFrom(address(uint160(bytes20(txn.sender))), address(this), txn.amount);
        } else {}
    }

    function slowModeFees() external pure returns (uint256) {
        return 0;
    }

    // Exclude from coverage report
    function test() public {}
}
