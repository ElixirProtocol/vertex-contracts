// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MOCK", 18) {}

    function mint(address a, uint256 b) public {
        _mint(a, b);
    }
}
