// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import {VertexManager} from "src/VertexManager.sol";

contract UpgradeContract is Script {
    VertexManager internal manager;
    VertexManager internal newManager;

    function run() external {
        // Start broadcast.
        vm.startBroadcast();

        // Wrap in ABI to support easier calls.
        manager = VertexManager(0x052Ab3fd33cADF9D9f227254252da3f996431f75);

        // Get the endpoint address before upgrading.
        address endpoint = address(manager.endpoint());

        // Deploy new implementation.
        newManager = new VertexManager();

        // Upgrade proxy to new implementation.
        manager.upgradeTo(address(newManager));

        uint256[] memory pools = new uint256[](2);
        address[] memory signers = new address[](2);

        pools[0] = 38; 
        pools[1] = 40;

        signers[0] = 0x28CcdB531854d09D48733261688dc1679fb9A242;
        signers[1] = 0x28CcdB531854d09D48733261688dc1679fb9A242;

        manager.updateLinkedSigners(pools, signers);
        vm.stopBroadcast();

        // Check upgrade by ensuring storage is not changed.
        require(address(manager.endpoint()) == endpoint, "Invalid upgrade");
    }

    // Exclude from coverage report
    function test() public {}
}
