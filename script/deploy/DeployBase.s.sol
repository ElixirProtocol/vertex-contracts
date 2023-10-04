// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import {IEndpoint, VertexManager} from "../../src/VertexManager.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract DeployBase is Script {
    // Environment specific variables.
    IEndpoint internal endpoint;

    // Deploy addresses.
    VertexManager internal managerImplementation;
    ERC1967Proxy internal proxy;
    VertexManager internal manager;

    // Deployer key.
    uint256 internal deployerKey;

    constructor(address _endpoint) {
        endpoint = IEndpoint(_endpoint);
    }

    function setup() internal {
        deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Deploy with key.
        vm.startBroadcast(deployerKey);

        // Deploy Factory implementation.
        managerImplementation = new VertexManager();

        // Deploy and initialize the proxy contract.
        proxy =
        new ERC1967Proxy(address(managerImplementation), abi.encodeWithSignature("initialize(address,uint256)", address(endpoint), 1000000));

        // Wrap in ABI to support easier calls.
        manager = VertexManager(address(proxy));

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public virtual {}
}
