// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {ProcessQueue} from "test/utils/ProcessQueue.sol";

import {VertexManager, IVertexManager} from "src/VertexManager.sol";
import {VertexProcessor} from "src/VertexProcessor.sol";
import {VertexRouter} from "src/VertexRouter.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract TestVertexManagerUpgrade is Test, ProcessQueue {
    VertexManager internal manager;

    IERC20 BTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20 USDC = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    IERC20 WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    uint256 public networkFork;

    // RPC URL for Arbitrum fork.
    string public networkRpcUrl = vm.envString("ARBITRUM_RPC_URL");

    function testUpgradeFork() external {
        networkFork = vm.createFork(networkRpcUrl);

        vm.selectFork(networkFork);

        // Wrap in ABI to support easier calls.
        manager = VertexManager(0x052Ab3fd33cADF9D9f227254252da3f996431f75);

        // Deploy with key.
        vm.startPrank(manager.owner());

        // Get the endpoint address before upgrading.
        address endpoint = address(manager.endpoint());

        // Deploy new Processor implementation.
        VertexProcessor newProcessor = new VertexProcessor();

        // Deploy new Manager implementation.
        VertexManager newManager = new VertexManager();

        // Upgrade proxy to new implementation.
        manager.upgradeToAndCall(
            address(newManager), abi.encodeWithSelector(VertexManager.updateProcessor.selector, address(newProcessor))
        );

        // Check upgrade by ensuring storage is not changed.
        require(address(manager.endpoint()) == endpoint, "Invalid upgrade");

        // Increase hardcap
        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        address[] memory spotTokens = new address[](2);
        spotTokens[0] = address(BTC);
        spotTokens[1] = address(USDC);

        manager.updatePoolHardcaps(1, spotTokens, hardcaps);

        uint256[] memory ids = new uint256[](1);
        address[] memory signers = new address[](1);

        ids[0] = 1;
        signers[0] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;

        manager.updateLinkedSigners(ids, signers);
        vm.stopPrank();

        uint256 amountBTC = 10 * 10 ** 8;
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC + manager.getTransactionFee(address(BTC)));
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC + manager.getTransactionFee(address(BTC)));
        USDC.approve(address(manager), amountUSDC);

        uint256 fee = manager.getTransactionFee(address(WETH));

        manager.depositSpot{value: fee}(
            1, address(BTC), address(USDC), amountBTC, amountUSDC, amountUSDC, address(this)
        );

        // Get the router address
        (address router,,,) = manager.getPoolToken(1, address(BTC));

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, amountBTC);
        assertEq(userActiveAmountUSDC, amountUSDC);
    }

    // Exclude from coverage report
    function test() public {}
}
