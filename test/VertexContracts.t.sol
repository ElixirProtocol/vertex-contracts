// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {Utils} from "./utils/Utils.t.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

import {IClearinghouse} from "../src/interfaces/IClearinghouse.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";
import {VertexFactory} from "../src/VertexFactory.sol";

contract VertexContracts is Test {
    Utils internal utils;

    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // Arbitrum mainnet addresses
    IEndpoint internal endpoint = IEndpoint(0xbbEE07B3e8121227AfCFe1E2B82772246226128e);
    ERC20 internal paymentToken;
    IClearinghouse internal clearingHouse;

    // Elixir contracts
    VertexFactory internal vertexFactoryImplementation;
    ERC1967Proxy internal proxy;
    VertexFactory internal vertexFactory;

    // Assuming base token is WBTC and quote token is USDC.
    ERC20 internal baseToken = ERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    ERC20 internal quoteToken = ERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    /*//////////////////////////////////////////////////////////////
                                  USERS
    //////////////////////////////////////////////////////////////*/

    // Neutral users
    address internal ALICE;
    address internal BOB;

    // Elixir users
    address internal FACTORY_OWNER;

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    uint256 internal networkFork;
    string internal NETWORK_RPC_URL = vm.envString("ARBITRUM_RPC_URL");

    // Off-chain validator account that makes request on behalf of the vaults.
    address internal EXTERNAL_ACCOUNT;

    /*//////////////////////////////////////////////////////////////
                                PREPARE
    //////////////////////////////////////////////////////////////*/

    function prepare() public {
        networkFork = vm.createFork(NETWORK_RPC_URL);
        vm.selectFork(networkFork);
        clearingHouse = IClearinghouse(endpoint.clearinghouse());
        paymentToken = ERC20(clearingHouse.getQuote());
    }

    function testSetUp() public {
        utils = new Utils();
        address payable[] memory users = utils.createUsers(4);

        ALICE = users[0];
        vm.label(ALICE, "Alice");

        BOB = users[1];
        vm.label(BOB, "Bob");

        FACTORY_OWNER = users[2];
        vm.label(FACTORY_OWNER, "Factory Owner");

        EXTERNAL_ACCOUNT = users[3];
        vm.label(EXTERNAL_ACCOUNT, "External Account");

        // Fork network and fetch Vertex contracts.
        prepare();

        // Deploy Factory implementation
        vertexFactoryImplementation = new VertexFactory();

        // Deploy proxy contract and point it to implementation
        proxy = new ERC1967Proxy(address(vertexFactoryImplementation), "");

        // wrap in ABI to support easier calls
        vertexFactory = VertexFactory(address(proxy));

        vertexFactory.initialize(clearingHouse, endpoint, EXTERNAL_ACCOUNT, FACTORY_OWNER);

        // Deal payment token to the factory, which pays for the slow mode transactions of all the vaults.
        deal(address(paymentToken), address(vertexFactory), type(uint128).max);
    }
}
