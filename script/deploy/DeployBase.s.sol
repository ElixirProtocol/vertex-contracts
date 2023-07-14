// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import {IEndpoint, IClearinghouse, VertexFactory} from "../../src/VertexFactory.sol";
import {UUPSProxy} from "../../test/VertexContracts.t.sol";

abstract contract DeployBase is Script {
    // Environment specific variables.
    IClearinghouse internal clearingHouse;
    IEndpoint internal endpoint;
    address internal externalAccount;

    // Deploy addresses.
    VertexFactory internal factoryImplementation;
    UUPSProxy internal proxy;
    VertexFactory internal factory;

    // Deployer key.
    uint256 internal deployerKey;

    constructor(address _clearingHouse, address _endpoint, address _externalAccount) {
        clearingHouse = IClearinghouse(_clearingHouse);
        endpoint = IEndpoint(_endpoint);
        externalAccount = _externalAccount;
    }

    function setup() internal {
        deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Deploy with key.
        vm.startBroadcast(deployerKey);

        // Deploy Factory implementation.
        factoryImplementation = new VertexFactory();

        // TODO: Check correct proxy contract.
        // Deploy proxy contract and point it to implementation.
        proxy = new UUPSProxy(address(factoryImplementation), "");

        // Wrap in ABI to support easier calls.
        factory = VertexFactory(address(proxy));

        factory.initialize(clearingHouse, endpoint, externalAccount, vm.addr(deployerKey));

        vm.stopBroadcast();
    }
}
