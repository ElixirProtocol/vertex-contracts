// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {AddPool} from "../AddBase.s.sol";

contract AddVertex is AddPool {
    constructor()
        AddPool(
            0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8,
            0x052Ab3fd33cADF9D9f227254252da3f996431f75,
            0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5,
            41,
            0x95146881b86B3ee99e63705eC87AfE29Fcc044D9,
            true
        )
    {}

    function run() external {
        setup();
    }

    // Exclude from coverage report
    function test() public override {}
}
