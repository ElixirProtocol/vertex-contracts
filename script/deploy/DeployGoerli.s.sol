// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";

contract DeployGoerli is DeployBase {
    constructor() DeployBase() {}

    function run() external {
        setup();
    }
}
