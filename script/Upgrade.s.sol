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

        // Check upgrade by ensuring storage is not changed. 
        require(address(manager.endpoint()) == 0x5956D6f55011678b2CAB217cD21626F7668ba6c5, "Invalid upgrade");
    }

    // Exclude from coverage report
    function test() public {}
}
