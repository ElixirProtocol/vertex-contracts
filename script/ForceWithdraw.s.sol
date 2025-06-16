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
        string memory path = string.concat(root, "/users.json");
        string memory json = vm.readFile(path);

        bytes memory rawUsers = vm.parseJson(json, "$[*].user_address");
        bytes memory rawPoolIds = vm.parseJson(json, "$[*].pool_id");
        bytes memory rawTokens = vm.parseJson(json, "$[*].token");
        bytes memory rawShares = vm.parseJson(json, "$[*].active_shares");
        bytes memory rawAmounts = vm.parseJson(json, "$[*].Override_active_amount");
        address[] memory users = abi.decode(rawUsers, (address[]));
        uint256[] memory poolIds = abi.decode(rawPoolIds, (uint256[]));
        address[] memory tokens = abi.decode(rawTokens, (address[]));
        uint256[] memory shares = abi.decode(rawShares, (uint256[]));
        uint256[] memory amounts = abi.decode(rawAmounts, (uint256[]));

        // Start broadcast.
        vm.startBroadcast();

        // Wrap in ABI to support easier calls.
        manager = VertexManager(0x052Ab3fd33cADF9D9f227254252da3f996431f75);
        uint256 queueUpTo = manager.queueUpTo();

        uint256[] memory previousPendingAmounts = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
          previousPendingAmounts[i] = manager.getUserPendingAmount(poolIds[i], tokens[i], users[i]);
        }

        for (uint256 i = 0; i < users.length; i++) {
          uint256 newPendingAmount = manager.getUserPendingAmount(poolIds[i], tokens[i], users[i]);
          require(newPendingAmount - previousPendingAmounts[i] == amounts[i]);
          uint256 newActiveAmount = manager.getUserActiveAmount(poolIds[i], tokens[i], users[i]);
          require(newActiveAmount == 0);
        }

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public {}
}
