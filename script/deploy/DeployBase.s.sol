// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import {IEndpoint, VertexManager} from "../../src/VertexManager.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract DeployBase is Script {
    // Environment specific variables.
    address internal feeToken;
    IEndpoint internal endpoint;
    address internal externalAccount;

    // Deploy addresses.
    VertexManager internal managerImplementation;
    ERC1967Proxy internal proxy;
    VertexManager internal manager;

    // Deployer key.
    uint256 internal deployerKey;

    constructor(address _feeToken, address _endpoint, address _externalAccount) {
        feeToken = _feeToken;
        endpoint = IEndpoint(_endpoint);
        externalAccount = _externalAccount;
    }

    function setup() internal {
        deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Deploy with key.
        vm.startBroadcast(deployerKey);

        // Deploy Factory implementation.
        managerImplementation = new VertexManager();

        // Deploy proxy contract and point it to implementation.
        proxy = new ERC1967Proxy(address(managerImplementation), "");

        // Wrap in ABI to support easier calls.
        manager = VertexManager(address(proxy));

        (bool success,) =
            address(feeToken).call(abi.encodeWithSignature("mint(address,uint256)", vm.addr(deployerKey), 20000000000));
        require(success);

        (success,) = address(feeToken).call(
            abi.encodeWithSignature("approve(address,uint256)", address(manager), type(uint256).max)
        );
        require(success);

        manager.initialize(address(endpoint), externalAccount);

        vm.stopBroadcast();
    }
}
