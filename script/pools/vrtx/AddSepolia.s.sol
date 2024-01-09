// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {AddPool} from "script/pools/AddBase.s.sol";

contract AddVertex is AddPool {
    constructor()
        AddPool(
            0xbC47901f4d2C5fc871ae0037Ea05c3F614690781,
            0x052Ab3fd33cADF9D9f227254252da3f996431f75,
            0x28CcdB531854d09D48733261688dc1679fb9A242,
            41,
            0x00aBCa5597d51e6C06eCfA655E73CE70A1e2cdCf,
            true
        )
    {}

    function run() external {
        setup();
    }

    // Exclude from coverage report
    function test() public override {}
}
