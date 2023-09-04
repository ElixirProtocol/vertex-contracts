// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

contract MockClearinghouse {
    address public quoteToken;

    constructor(address _quoteToken) {
        quoteToken = _quoteToken;
    }

    function getQuote() external view returns (address) {
        return quoteToken;
    }

    // Exclude from coverage report
    function test() public {}
}
