// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {MockToken} from "test/utils/MockToken.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

import {IEndpoint} from "src/interfaces/IEndpoint.sol";

import {VertexManager, IVertexManager} from "src/VertexManager.sol";
import {VertexProcessor} from "src/VertexProcessor.sol";
import {Handler} from "test/invariants/VertexManagerHandler.sol";

contract TestInvariantsVertexManager is Test {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Vertex contracts
    IEndpoint public endpoint = IEndpoint(0xbbEE07B3e8121227AfCFe1E2B82772246226128e);

    // Elixir contracts
    VertexManager public manager;

    // Tokens
    IERC20Metadata public BTC = IERC20Metadata(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20Metadata public USDC = IERC20Metadata(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    IERC20Metadata public WETH = IERC20Metadata(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    uint256 public BTC_TOTAL;
    uint256 public USDC_TOTAL;
    uint256 public WETH_TOTAL;

    // Handler
    Handler public handler;

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    // Pool types.
    enum PoolType {
        Spot,
        Perp
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        uint256 networkFork = vm.createFork(vm.envString("ARBITRUM_RPC_URL"), 176065658);

        vm.selectFork(networkFork);

        // Create perp pool with BTC, USDC, and ETH as tokens.
        address[] memory perpTokens = new address[](3);
        perpTokens[0] = address(BTC);
        perpTokens[1] = address(USDC);
        perpTokens[2] = address(WETH);

        // Create spot pool with BTC (base) and USDC (quote) as tokens.
        address[] memory spotTokens = new address[](2);
        spotTokens[0] = address(BTC);
        spotTokens[1] = address(USDC);

        uint256[] memory spotHardcaps = new uint256[](2);
        spotHardcaps[0] = type(uint256).max;
        spotHardcaps[1] = type(uint256).max;

        uint256[] memory perpHardcaps = new uint256[](3);
        perpHardcaps[0] = type(uint256).max;
        perpHardcaps[1] = type(uint256).max;
        perpHardcaps[2] = type(uint256).max;

        // Deploy Processor implementation
        VertexProcessor processorImplementation = new VertexProcessor();

        // Deploy Manager implementation
        VertexManager managerImplementation = new VertexManager();

        // Deploy and initialize the proxy contract.
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(managerImplementation),
            abi.encodeWithSignature(
                "initialize(address,address,uint256)", address(endpoint), address(processorImplementation), 1000000
            )
        );

        // Wrap in ABI to support easier calls
        manager = VertexManager(address(proxy));

        // Wrap into the handler.
        handler = new Handler(manager, spotTokens, perpTokens, address(this));

        // Approve the manager to move USDC for fee payments.
        USDC.approve(address(manager), type(uint256).max);

        // Deal payment token to the owner, which pays for the slow mode transactions of the pools. No update to the totalSupply.
        deal(address(USDC), address(this), type(uint128).max);

        // Add perp pool.
        manager.addPool(2, perpTokens, perpHardcaps, IVertexManager.PoolType.Perp, address(this));

        // Add spot pool.
        manager.addPool(1, spotTokens, spotHardcaps, IVertexManager.PoolType.Spot, address(this));

        // Add token support.
        manager.updateToken(address(USDC), 0);
        manager.updateToken(address(BTC), 1);
        manager.updateToken(address(WETH), 3);

        // Set the total supplies.
        BTC_TOTAL = BTC.totalSupply();
        USDC_TOTAL = USDC.totalSupply();
        WETH_TOTAL = WETH.totalSupply();

        // Mint tokens.
        deal(address(BTC), address(handler), BTC_TOTAL, true);
        deal(address(USDC), address(handler), USDC_TOTAL, true);
        deal(address(WETH), address(handler), WETH_TOTAL, true);

        // Select the selectors to use for fuzzing.
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = Handler.depositPerp.selector;
        selectors[1] = Handler.depositSpot.selector;
        selectors[2] = Handler.withdrawSpot.selector;
        selectors[3] = Handler.withdrawPerp.selector;
        selectors[4] = Handler.claimPerp.selector;
        selectors[5] = Handler.claimSpot.selector;

        // Set the target selector.
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        // Set the target contract.
        targetContract(address(handler));
    }

    /*//////////////////////////////////////////////////////////////
                  DEPOSIT/WITHDRAWAL INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    // The sum of the Handler's balances, the active amounts, and the pending amounts should always equal the total amount given.
    // Aditionally, the total amounts given must match the total supply of the tokens.
    function invariant_conservationOfTokens() public {
        // Active amounts
        (, uint256 spotActiveAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, uint256 spotActiveAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        (, uint256 perpActiveAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, uint256 perpActiveAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, uint256 perpActiveAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        // Pending amounts
        uint256 pendingAmountBTC = handler.reduceActors(0, this.accumulatePendingBalanceBTC);
        uint256 pendingAmountUSDC = handler.reduceActors(0, this.accumulatePendingBalanceUSDC);
        uint256 pendingAmountWETH = handler.reduceActors(0, this.accumulatePendingBalanceWETH);

        assertEq(
            BTC_TOTAL,
            BTC.balanceOf(address(handler)) + spotActiveAmountBTC + perpActiveAmountBTC + pendingAmountBTC
                + handler.ghost_fees(address(BTC))
        );
        assertEq(
            USDC_TOTAL,
            USDC.balanceOf(address(handler)) + spotActiveAmountUSDC + perpActiveAmountUSDC + pendingAmountUSDC
                + handler.ghost_fees(address(USDC))
        );
        assertEq(
            WETH_TOTAL,
            WETH.balanceOf(address(handler)) + perpActiveAmountWETH + pendingAmountWETH
                + handler.ghost_fees(address(WETH))
        );
    }

    // The active amounts should always be equal to the sum of individual active balances. Obtained by the ghost values.
    function invariant_solvencyDeposits() public {
        (, uint256 spotActiveAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, uint256 spotActiveAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        (, uint256 perpActiveAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, uint256 perpActiveAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, uint256 perpActiveAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        assertEq(
            spotActiveAmountBTC + perpActiveAmountBTC,
            handler.ghost_deposits(address(BTC)) - handler.ghost_withdraws(address(BTC))
        );
        assertEq(
            spotActiveAmountUSDC + perpActiveAmountUSDC,
            handler.ghost_deposits(address(USDC)) - handler.ghost_withdraws(address(USDC))
        );
        assertEq(perpActiveAmountWETH, handler.ghost_deposits(address(WETH)) - handler.ghost_withdraws(address(WETH)));
    }

    // The active amounts should always be equal to the sum of individual active balances. Obtained by the sum of each user.
    function invariant_solvencyBalances() public {
        uint256 sumOfActiveBalancesBTC = handler.reduceActors(0, this.accumulateActiveBalanceBTC);
        uint256 sumOfActiveBalancesUSDC = handler.reduceActors(0, this.accumulateActiveBalanceUSDC);
        uint256 sumOfActiveBalancesWETH = handler.reduceActors(0, this.accumulateActiveBalanceWETH);

        (, uint256 spotActiveAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, uint256 spotActiveAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        (, uint256 perpActiveAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, uint256 perpActiveAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, uint256 perpActiveAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        assertEq(spotActiveAmountBTC + perpActiveAmountBTC, sumOfActiveBalancesBTC);
        assertEq(spotActiveAmountUSDC + perpActiveAmountUSDC, sumOfActiveBalancesUSDC);
        assertEq(perpActiveAmountWETH, sumOfActiveBalancesWETH);
    }

    // No individual account balance can exceed the tokens totalSupply().
    function invariant_depositorBalances() public {
        handler.forEachActor(this.assertAccountBalanceLteTotalSupply);
    }

    // The sum of the deposits must always be greater or equal than the sum of withdraws.
    function invariant_depositsAndWithdraws() public {
        uint256 sumOfDepositsBTC = handler.ghost_deposits(address(BTC));
        uint256 sumOfDepositsUSDC = handler.ghost_deposits(address(USDC));
        uint256 sumOfDepositsWETH = handler.ghost_deposits(address(WETH));

        uint256 sumOfWithdrawsBTC = handler.ghost_withdraws(address(BTC));
        uint256 sumOfWithdrawsUSDC = handler.ghost_withdraws(address(USDC));
        uint256 sumOfWithdrawsWETH = handler.ghost_withdraws(address(WETH));

        assertGe(sumOfDepositsBTC, sumOfWithdrawsBTC);
        assertGe(sumOfDepositsUSDC, sumOfWithdrawsUSDC);
        assertGe(sumOfDepositsWETH, sumOfWithdrawsWETH);
    }

    // The sum of ghost withdrawals must be equal to the sum of pending balances, claims and ghost fees.
    function invariant_withdrawBalances() public {
        uint256 sumOfClaimsBTC = handler.ghost_claims(address(BTC));
        uint256 sumOfClaimsUSDC = handler.ghost_claims(address(USDC));
        uint256 sumOfClaimsWETH = handler.ghost_claims(address(WETH));

        uint256 sumOfPendingBalancesBTC = handler.reduceActors(0, this.accumulatePendingBalanceBTC);
        uint256 sumOfPendingBalancesUSDC = handler.reduceActors(0, this.accumulatePendingBalanceUSDC);
        uint256 sumOfPendingBalancesWETH = handler.reduceActors(0, this.accumulatePendingBalanceWETH);

        assertEq(
            handler.ghost_withdraws(address(BTC)),
            sumOfPendingBalancesBTC + sumOfClaimsBTC + handler.ghost_fees(address(BTC))
        );
        assertEq(
            handler.ghost_withdraws(address(USDC)),
            sumOfPendingBalancesUSDC + sumOfClaimsUSDC + handler.ghost_fees(address(USDC))
        );
        assertEq(
            handler.ghost_withdraws(address(WETH)),
            sumOfPendingBalancesWETH + sumOfClaimsWETH + handler.ghost_fees(address(WETH))
        );
    }

    // Two pools cannot share the same router. Each pool must have a unique and constant router for all tokens supported by it.
    function invariant_router() public {
        (address routerBTC1,,,) = manager.getPoolToken(1, address(BTC));
        (address routerUSDC1,,,) = manager.getPoolToken(1, address(USDC));
        (address routerBTC2,,,) = manager.getPoolToken(2, address(BTC));
        (address routerUSDC2,,,) = manager.getPoolToken(2, address(USDC));
        (address routerWETH2,,,) = manager.getPoolToken(2, address(WETH));

        assertEq(routerBTC1, routerUSDC1);
        assertEq(routerBTC2, routerUSDC2);
        assertEq(routerBTC2, routerWETH2);
        assertTrue(routerBTC1 != routerBTC2);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function assertAccountBalanceLteTotalSupply(address account) external {
        uint256 activeAmountBTC = activeAmountUser(address(BTC), account);
        uint256 activeAmountUSDC = activeAmountUser(address(USDC), account);
        uint256 activeAmountWETH = manager.getUserActiveAmount(2, address(WETH), account);

        assertLe(activeAmountBTC, BTC.totalSupply());
        assertLe(activeAmountUSDC, USDC.totalSupply());
        assertLe(activeAmountWETH, WETH.totalSupply());
    }

    function accumulateActiveBalanceBTC(uint256 balance, address caller) external view returns (uint256) {
        return balance + activeAmountUser(address(BTC), caller);
    }

    function accumulateActiveBalanceUSDC(uint256 balance, address caller) external view returns (uint256) {
        return balance + activeAmountUser(address(USDC), caller);
    }

    function accumulateActiveBalanceWETH(uint256 balance, address caller) external view returns (uint256) {
        return balance + manager.getUserActiveAmount(2, address(WETH), caller);
    }

    function accumulatePendingBalanceBTC(uint256 balance, address caller) external view returns (uint256) {
        return balance + manager.getUserPendingAmount(1, address(BTC), caller)
            + manager.getUserPendingAmount(2, address(BTC), caller);
    }

    function accumulatePendingBalanceUSDC(uint256 balance, address caller) external view returns (uint256) {
        return balance + manager.getUserPendingAmount(1, address(USDC), caller)
            + manager.getUserPendingAmount(2, address(USDC), caller);
    }

    function accumulatePendingBalanceWETH(uint256 balance, address caller) external view returns (uint256) {
        return balance + manager.getUserPendingAmount(2, address(WETH), caller);
    }

    function activeAmountUser(address token, address user) public view returns (uint256) {
        return manager.getUserActiveAmount(1, token, user) + manager.getUserActiveAmount(2, token, user);
    }

    receive() external payable {}

    // Exclude from coverage report
    function test() public {}
}
