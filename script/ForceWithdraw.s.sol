// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {VertexManager} from "src/VertexManager.sol";

contract UpgradeContract is Script {
    using stdJson for string;

    VertexManager internal manager;

    function run() external {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/pools_summary.json");
        string memory json = vm.readFile(path);

        bytes memory rawPoolIds = vm.parseJson(json, "$[*].pool_id");
        bytes memory rawTokens = vm.parseJson(json, "$[*].token_addr");
        bytes memory rawAmounts = vm.parseJson(json, "$[*].totalToReceive");
        uint256[] memory poolIds = abi.decode(rawPoolIds, (uint256[]));
        address[] memory tokens = abi.decode(rawTokens, (address[]));
        uint128[] memory amounts = abi.decode(rawAmounts, (uint128[]));

        // Start broadcast.
        vm.startBroadcast();

        // Wrap in ABI to support easier calls.
        manager = VertexManager(0x052Ab3fd33cADF9D9f227254252da3f996431f75);
        uint256 queueUpTo = manager.queueUpTo();

        for (uint256 i = 0; i < poolIds.length; i++) {
            manager.withdrawCollateral(poolIds[i], tokens[i], amounts[i]);
        }

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public {}
}
