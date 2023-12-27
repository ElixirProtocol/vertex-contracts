// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {VertexManager, IVertexManager} from "../src/VertexManager.sol";
import {VertexRouter} from "../src/VertexRouter.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract TestVertexManagerUSDC is Test {
    VertexManager internal manager;

    IERC20Metadata BTC = IERC20Metadata(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20Metadata USDC = IERC20Metadata(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    IERC20Metadata USDCE = IERC20Metadata(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20Metadata WETH = IERC20Metadata(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    uint256 public networkFork;

    // RPC URL for Arbitrum fork.
    string public networkRpcUrl = vm.envString("ARBITRUM_RPC_URL");

    function testUSDC() external {
        networkFork = vm.createFork(networkRpcUrl);

        vm.selectFork(networkFork);

        // Wrap in ABI to support easier calls.
        manager = VertexManager(0x052Ab3fd33cADF9D9f227254252da3f996431f75);

        // Deploy with key.
        vm.startPrank(manager.owner());

        /*//////////////////////////////////////////////////////////////
                                      SET UP
        //////////////////////////////////////////////////////////////*/

        // 1. Add USDC token for pool. Using BTC-PERP as example here.
        address[] memory token = new address[](1);
        token[0] = address(USDC);

        uint256[] memory hardcap = new uint256[](1);
        hardcap[0] = 0;

        manager.addPoolTokens(2, token, hardcap);
        
        // 2. Set the hardcap of USDC.e and USDC to previous USDC.e one.
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDCE);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = 0;
        hardcaps[1] = type(uint256).max;

        manager.updatePoolHardcaps(2, tokens, hardcaps);

        vm.stopPrank();

        /*//////////////////////////////////////////////////////////////
                                      TEST
        //////////////////////////////////////////////////////////////*/

        // Try to deposit USDC to pool.
        uint256 amountUSDC = 100 * 10 ** USDCE.decimals();

        deal(address(USDC), address(this), amountUSDC);

        USDC.approve(address(manager), amountUSDC);

        uint256 fee = manager.getTransactionFee(address(WETH));

        manager.depositPerp{value: fee}(2, address(USDC), amountUSDC, address(this));

        // Get the router address
        (address router,,,) = manager.getPoolToken(2, address(USDC));

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue();
        vm.stopPrank();

        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        assertEq(userActiveAmountUSDC, amountUSDC);

        // Check that you cannot despoit USDC.e (i.e. amount of active remains the same).
        manager.depositPerp{value: fee}(2, address(USDCE), amountUSDC, address(this));

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue();
        vm.stopPrank();

        userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        assertEq(userActiveAmountUSDC, amountUSDC);
    }

    /// @notice Processes any transactions in the Elixir queue.
    function processQueue() public {
        // Loop through the queue and process each transaction using the idTo provided.
        for (uint128 i = manager.queueUpTo() + 1; i < manager.queueCount() + 1; i++) {
            VertexManager.Spot memory spot = manager.nextSpot();

            if (spot.spotType == IVertexManager.SpotType.DepositPerp) {
                IVertexManager.DepositPerp memory spotTxn = abi.decode(spot.transaction, (IVertexManager.DepositPerp));

                manager.unqueue(i, abi.encode(IVertexManager.DepositPerpResponse({shares: spotTxn.amount})));
            } else {}
        }
    }

    // Exclude from coverage report
    function test() public {}
}
