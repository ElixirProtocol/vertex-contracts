// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {VertexManager} from "../../src/VertexManager.sol";

contract DeployMainnet is DeployBase {
    // Vertex Mainnet Endpoint
    constructor()
        DeployBase(
            0xbbEE07B3e8121227AfCFe1E2B82772246226128e,
            0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5,
            0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f,
            0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8,
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            0x912CE59144191C1204E64559FE8253a0e49E6548,
            0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9,
            0x95146881b86B3ee99e63705eC87AfE29Fcc044D9
        )
    {}

    function run() external {
        setup();

        vm.startBroadcast();

        // Transfer ownership to multisig
        manager.transferOwnership(0xdc91701CD5d5a3Adb34d9afD1756f63d3b2201Ac);

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public override {}
}
