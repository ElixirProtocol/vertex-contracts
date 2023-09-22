// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract MockTokenDecimals is ERC20 {
    constructor() ERC20("MockTokenDecimals", "MOCK") {}

    function mint(address a, uint256 b) public {
        _mint(a, b);
    }

    function decimals() public view virtual override returns (uint8) {
        return 20;
    }

    // Exclude from coverage report
    function test() public {}
}
