// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {Utils} from "../utils/Utils.sol";
import {MockToken} from "../utils/MockToken.sol";
import {MockEndpoint} from "../utils/MockEndpoint.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

import {VertexManager} from "../../src/VertexManager.sol";
import {Handler, BTC_SUPPLY, USDC_SUPPLY} from "./VertexManagerHandler.sol";

contract TestVertexManagerInvariants is Test {
    using Math for uint256;

    Utils internal utils;

    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // Vertex contracts
    MockEndpoint internal endpoint;

    // Elixir contracts
    VertexManager internal vertexManagerImplementation;
    ERC1967Proxy internal proxy;
    VertexManager internal manager;

    // Tokens
    MockToken internal BTC;
    MockToken internal USDC;
    MockToken internal WETH;

    // Handler
    Handler internal handler;

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Deploy mock tokens.
        BTC = new MockToken();
        USDC = new MockToken();
        WETH = new MockToken();

        // Deploy Manager implementation
        vertexManagerImplementation = new VertexManager();

        // Deploy proxy contract and point it to implementation
        proxy = new ERC1967Proxy(address(vertexManagerImplementation), "");

        // Wrap in ABI to support easier calls
        manager = VertexManager(address(proxy));

        // Wrap into the handler.
        handler = new Handler(manager, BTC, USDC, WETH);

        // Select the selectors to use for fuzzing.
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Handler.deposit.selector;

        // Set the target selector.
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        // Set the target contract.
        targetContract(address(handler));

        // Deploy Vertex contracts.
        endpoint = new MockEndpoint(address(USDC), BTC, USDC, WETH);

        // Set the endpoint and external account of the contract.
        manager.initialize(address(endpoint), 0);

        // Add token support.
        manager.updateToken(address(USDC), 0);
        manager.updateToken(address(BTC), 1);
        manager.updateToken(address(WETH), 3);

        // Create BTC spot pool with BTC and USDC as tokens.
        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        manager.addPool(1, address(0), tokens, hardcaps);

        // Create BTC perp pool with BTC, USDC and WETH as tokens.
        tokens = new address[](3);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);
        tokens[2] = address(WETH);

        hardcaps = new uint256[](3);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;
        hardcaps[2] = type(uint256).max;

        manager.addPool(2, address(0), tokens, hardcaps);
    }

    /*//////////////////////////////////////////////////////////////
                  DEPOSIT/WITHDRAWAL INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    // The sum of the Handler's BTC balance plus the BTC active amount should always equal the total BTC_SUPPLY.
    function invariant_conservationOfTokens() public {
        (,,, uint256[] memory activeAmounts) = manager.getPool(1);
        assertEq(BTC_SUPPLY, BTC.balanceOf(address(handler)) + activeAmounts[0]);
    }

    // The BTC active amount should always be equal to the sum of individual active balances.
    function invariant_solvencyDeposits() public {
        (,,, uint256[] memory activeAmounts) = manager.getPool(1);
        assertEq(activeAmounts[0], handler.ghost_depositSum() - handler.ghost_withdrawSum());
    }

    // The BTC active amount should always be equal to the sum of individual active balances.
    function invariant_solvencyBalances() public {
        uint256 sumOfBalances = handler.reduceActors(0, this.accumulateBalance);

        (,,, uint256[] memory activeAmounts) = manager.getPool(1);

        assertEq(activeAmounts[0], sumOfBalances);
    }

    function accumulateBalance(uint256 balance, address caller) external view returns (uint256) {
        return balance + (manager.getUserActiveAmounts(1, caller))[0];
    }

    // Exclude from coverage report
    function test() public {}
}
