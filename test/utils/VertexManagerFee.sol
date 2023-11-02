// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {VertexManager} from "../../src/VertexManager.sol";

contract VertexManagerFee is VertexManager {
    function increaseFee() public {
        slowModeFee += slowModeFee;
    }
}
