// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";

contract DeployGoerli is DeployBase {
    // Arbitrum Goerli addresses
    // 1. Endpoint
    // 2. External account

    constructor()
        DeployBase(
            0x5956D6f55011678b2CAB217cD21626F7668ba6c5,
            0x28CcdB531854d09D48733261688dc1679fb9A242
        )
    {}

    function run() external {
        setup();
    }
}
