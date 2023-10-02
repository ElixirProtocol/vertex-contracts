// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import {VertexManager} from "src/VertexManager.sol";

contract UpgradeContract is Script {
    VertexManager internal manager;
    VertexManager internal newManager;

    // Deployer key.
    uint256 internal deployerKey;

    function run() external {
        deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Deploy with key.
        vm.startBroadcast(deployerKey);

        // Wrap in ABI to support easier calls.
        manager = VertexManager(0x392dE333fbc1d200beb0E7a317fF50371Ce03A78);

        // Deploy new implementation.
        newManager = new VertexManager();

        // Upgrade proxy to new implementation.
        manager.upgradeTo(address(newManager));

        vm.stopBroadcast();

        // // Check upgrade.
        // (address router, uint256 activeAmount, uint256 hardcap, bool status) = manager.getPoolToken(1, 0x5Cc7c91690b2cbAEE19A513473D73403e13fb431);
        // require(router != address(0) && activeAmount > 0 && hardcap > 0 && status, "Upgrade failed");
    }

    // Exclude from coverage report
    function test() public {}
}
