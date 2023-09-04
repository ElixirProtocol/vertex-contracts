// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import {VertexManager} from "../src/VertexManager.sol";

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
        manager = VertexManager(0x69446a7b3CBcfC0C9403Cf4Eba263EdE21422f11);

        // Deploy new implementation.
        newManager = new VertexManager();

        // Upgrade proxy to new implementation.
        manager.upgradeTo(address(newManager));

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public {}
}
