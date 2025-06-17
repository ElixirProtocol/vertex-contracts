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
        string memory path = 
          string.concat(root, "/withdraw_batches/WETH_3_batch1.json");
        uint256 poolId = 3;
        address token = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

        string memory json = vm.readFile(path);

        bytes memory rawUsers = vm.parseJson(json, "$[*].user_address");
        bytes memory rawAmounts = vm.parseJson(json, "$[*].amount");
        address[] memory users = abi.decode(rawUsers, (address[]));
        uint256[] memory amounts = abi.decode(rawAmounts, (uint256[]));

        // Start broadcast.
        vm.startBroadcast();

        // Wrap in ABI to support easier calls.
        manager = VertexManager(0x052Ab3fd33cADF9D9f227254252da3f996431f75);
        uint256 queueUpTo = manager.queueUpTo();

        manager.forceWithdraw(poolId, token, users, amounts);

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public {}
}
