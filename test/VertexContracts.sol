// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {Utils} from "./utils/Utils.sol";

import {IClearinghouse} from "../src/interfaces/clearinghouse/IClearinghouse.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";

contract VertexContracts is Test {
    Utils internal utils;

    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    IClearinghouse internal clearingHouse;
    IEndpoint internal endpoint;

    /*//////////////////////////////////////////////////////////////
                                  USERS
    //////////////////////////////////////////////////////////////*/

    // Vertex users
    address internal VERTEX_DEPLOYER;
}
