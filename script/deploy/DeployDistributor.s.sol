// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {Distributor} from "src/Distributor.sol";

contract DeployDistributor is Script {
    // Vertex Sepolia Endpoint
    constructor() {}

    function run() external {
        new Distributor{salt: keccak256(abi.encodePacked("Distributor"))}(
            "Distributor", "1", 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5
    }

    // Exclude from coverage report
    function test() public override {}
}
