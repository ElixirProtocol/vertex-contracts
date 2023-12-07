// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {VertexManager} from "../../src/VertexManager.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract DeploySepolia is DeployBase {
    // Vertex Sepolia Endpoint
    constructor()
        DeployBase(
            0xaDeFDE1A14B6ba4DA3e82414209408a49930E8DC,
            0x28CcdB531854d09D48733261688dc1679fb9A242,
            0xA7Fcb606611358afa388b6bd23b3B2F2c6abEd82,
            0xbC47901f4d2C5fc871ae0037Ea05c3F614690781,
            0x94B3173E0a23C28b2BA9a52464AC24c2B032791c,
            0x0881FAabdDdECf1B4c3D5331DF33C13A1b6589ea,
            0xA1c062ddEf8f7B0a97e3Bb219108Ce73410772cE,
            0x00aBCa5597d51e6C06eCfA655E73CE70A1e2cdCf
        )
    {}

    function run() external {
        setup();
    }

    // Exclude from coverage report
    function test() public override {}
}
