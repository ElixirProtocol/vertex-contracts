// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";

contract DeployGoerli is DeployBase {
    // Arbitrum Goerli addresses
    // 1. ClearingHouse
    // 2. Endpoint
    // 3. External account

    constructor()
        DeployBase(
            0x61B10E98049B00d4D863e3637D9E14Acd23ad8a3,
            0x5956D6f55011678b2CAB217cD21626F7668ba6c5,
            0x28CcdB531854d09D48733261688dc1679fb9A242
        )
    {}

    function run() external {
        setup();
    }
}
