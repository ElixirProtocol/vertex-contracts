// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

contract MockClearinghouse {
    address public quoteToken;

    constructor(address _quoteToken) {
        quoteToken = _quoteToken;
    }

    function getQuote() external view returns (address) {
        return quoteToken;
    }

    function getOraclePriceX18(uint32 productId) external pure returns (uint256) {
        if (productId == 1) {
            return 27_000 * 10 ** 18;
        } else {
            return 0;
        }
    }

    // Exclude from coverage report
    function test() public {}
}
