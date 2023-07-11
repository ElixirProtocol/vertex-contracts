// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {Utils} from "./utils/Utils.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IClearinghouse} from "../src/interfaces/clearinghouse/IClearinghouse.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";

contract VertexContracts is Test {
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // Arbitrum mainnet addresses
    IEndpoint internal endpoint = IEndpoint(0xbbEE07B3e8121227AfCFe1E2B82772246226128e);
    ERC20 internal payment;
    IClearinghouse internal clearingHouse;

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    uint256 internal networkFork;
    string NETWORK_RPC_URL = vm.envString("ARBITRUM_RPC_URL");

    /*//////////////////////////////////////////////////////////////
                                PREPARE
    //////////////////////////////////////////////////////////////*/

    function prepare() public {
        networkFork = vm.createFork(NETWORK_RPC_URL);
        vm.selectFork(networkFork);
        clearingHouse = IClearinghouse(endpoint.clearinghouse());
        payment = ERC20(clearingHouse.getQuote());
    }
}
