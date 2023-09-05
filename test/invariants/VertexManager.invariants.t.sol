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
import {Handler} from "./VertexManagerHandler.sol";

contract TestVertexManagerInvariants is Test {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Vertex contracts
    MockEndpoint public endpoint;

    // Elixir contracts
    VertexManager public vertexManagerImplementation;
    ERC1967Proxy public proxy;
    VertexManager public manager;

    // Tokens
    MockToken public BTC;
    MockToken public USDC;
    MockToken public WETH;

    uint256 constant BTC_SUPPLY = 100_000 * 10 ** 18;
    uint256 constant USDC_SUPPLY = 3_000_000_000 * 10 ** 18;

    // Handler
    Handler public handler;

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    // Utils contract.
    Utils public utils;

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

        // Mint tokens.
        BTC.mint(address(handler), BTC_SUPPLY);
        USDC.mint(address(handler), USDC_SUPPLY);

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

    // The sum of the Handler's BTC balance plus the BTC active amount should always equal the total BTC_SUPPLY. Same for USDC.
    function invariant_conservationOfTokens() public {
        (,,, uint256[] memory activeAmounts) = manager.getPool(1);
        assertEq(BTC_SUPPLY, BTC.balanceOf(address(handler)) + activeAmounts[0]);
        assertEq(USDC_SUPPLY, USDC.balanceOf(address(handler)) + activeAmounts[1]);
    }

    // The BTC active amount should always be equal to the sum of individual active balances. Same for USDC.
    function invariant_solvencyDeposits() public {
        (,,, uint256[] memory activeAmounts) = manager.getPool(1);

        assertEq(activeAmounts[0], handler.ghost_deposits(address(BTC)) - handler.ghost_withdraws(address(BTC)));
        assertEq(activeAmounts[1], handler.ghost_deposits(address(USDC)) - handler.ghost_withdraws(address(USDC)));
    }

    // The BTC active amount should always be equal to the sum of individual active balances. Same for USDC.
    function invariant_solvencyBalances() public {
        uint256 sumOfActiveBalancesBTC = handler.reduceActors(0, this.accumulateActiveBalanceBTC);
        uint256 sumOfActiveBalancesUSDC = handler.reduceActors(0, this.accumulateActiveBalanceUSDC);

        (,,, uint256[] memory activeAmounts) = manager.getPool(1);

        assertEq(activeAmounts[0], sumOfActiveBalancesBTC);
        assertEq(activeAmounts[1], sumOfActiveBalancesUSDC);
    }

    // No individual account balance can exceed the tokens totalSupply().
    function invariant_depositorBalances() public {
        handler.forEachActor(this.assertAccountBalanceLteTotalSupply);
    }

    // The sum of the deposits must always be greater or equal than the sum of withdraws.
    function invariant_depositsAndWithdraws() public {
        uint256 sumOfDepositsBTC = handler.ghost_deposits(address(BTC));
        uint256 sumOfWithdrawsBTC = handler.ghost_withdraws(address(BTC));

        uint256 sumOfDepositsUSDC = handler.ghost_deposits(address(USDC));
        uint256 sumOfWithdrawsUSDC = handler.ghost_withdraws(address(USDC));

        assertGe(sumOfDepositsBTC, sumOfWithdrawsBTC);
        assertGe(sumOfDepositsUSDC, sumOfWithdrawsUSDC);
    }

    // The sum of the pending balances must always be less than the sum of ghost withdraws.
    function invariant_pendingBalances() public {
        uint256 sumOfPendingBalancesBTC = handler.reduceActors(0, this.accumulatePendingBalanceBTC);
        uint256 sumOfPendingBalancesUSDC = handler.reduceActors(0, this.accumulatePendingBalanceUSDC);

        assertLe(sumOfPendingBalancesBTC, handler.ghost_withdraws(address(BTC)));
        assertLe(sumOfPendingBalancesUSDC, handler.ghost_withdraws(address(USDC)));
    }

    // The sum of the claims must always be less than the sum of the ghost withdras.
    function invariant_claims() public {
        uint256 sumOfClaimsBTC = handler.ghost_claims(address(BTC));
        uint256 sumOfClaimsUSDC = handler.ghost_claims(address(USDC));

        assertLe(sumOfClaimsBTC, handler.ghost_withdraws(address(BTC)));
        assertLe(sumOfClaimsUSDC, handler.ghost_withdraws(address(USDC)));
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function assertAccountBalanceLteTotalSupply(address account) external {
        uint256[] memory activeAmounts = manager.getUserActiveAmounts(1, account);

        assertLe(activeAmounts[0], BTC.totalSupply());
        assertLe(activeAmounts[1], USDC.totalSupply());
    }

    function accumulateActiveBalanceBTC(uint256 balance, address caller) external view returns (uint256) {
        return balance + (manager.getUserActiveAmounts(1, caller))[0];
    }

    function accumulateActiveBalanceUSDC(uint256 balance, address caller) external view returns (uint256) {
        return balance + (manager.getUserActiveAmounts(1, caller))[1];
    }

    function accumulatePendingBalanceBTC(uint256 balance, address caller) external view returns (uint256) {
        return balance + (manager.pendingBalances(caller, address(BTC)));
    }

    function accumulatePendingBalanceUSDC(uint256 balance, address caller) external view returns (uint256) {
        return balance + (manager.pendingBalances(caller, address(USDC)));
    }

    // Exclude from coverage report
    function test() public {}
}
