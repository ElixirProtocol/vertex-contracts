// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {VertexManager} from "../../src/VertexManager.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract DeployGoerli is DeployBase {
    // Vertex Goerli Endpoint
    constructor()
        DeployBase(
            0x5956D6f55011678b2CAB217cD21626F7668ba6c5,
            0x28CcdB531854d09D48733261688dc1679fb9A242,
            0x5Cc7c91690b2cbAEE19A513473D73403e13fb431,
            0x179522635726710Dd7D2035a81d856de4Aa7836c,
            0xCC59686e3a32Fb104C8ff84DD895676265eFb8a6,
            0x34e9827219aA7B7962eF591714657817e79eBBbb,
            0x067763aA51E4c7C30eA26DfE08cE2FeA5683cc85
        )
    {}

    function run() external {
        setup();
    }

    // Exclude from coverage report
    function test() public override {}
}
