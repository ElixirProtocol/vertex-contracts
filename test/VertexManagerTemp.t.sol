// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {ProcessQueue} from "test/utils/ProcessQueue.sol";

import {VertexManager, IVertexManager} from "src/VertexManager.sol";
import {VertexProcessor} from "src/VertexProcessor.sol";
import {VertexRouter} from "src/VertexRouter.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract TestVertexManagerTemp is Test, ProcessQueue {
    VertexManager internal manager;

    IERC20 BTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20 USDC = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    IERC20 WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

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

        // Deploy new Manager implementation.
        VertexManager newManager = new VertexManager();

        // Upgrade proxy to new implementation.
        manager.upgradeTo(address(newManager));

        // Check upgrade by ensuring storage is not changed.
        require(address(manager.endpoint()) == endpoint, "Invalid upgrade");

        address[] memory routers = new address[](1);
        routers[0] = address(0xEe7DFBe0CE3ad8044eB36C38bDb59f56e0f86088);

        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 100;

        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);

        manager.tempUnqueue(routers, amounts, tokens);
    }

    // Exclude from coverage report
    function test() public {}
}
