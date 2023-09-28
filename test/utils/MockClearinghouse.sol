// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

contract MockClearinghouse {
    address public BTC;
    address public USDC;
    address public WETH;

    constructor(address _BTC, address _USDC, address _WETH) {
        BTC = _BTC;
        USDC = _USDC;
        WETH = _WETH;
    }

    function getQuote() external view returns (address) {
        return USDC;
    }

    function getOraclePriceX18(uint32 productId) external pure returns (uint256) {
        if (productId == 1) {
            return 27_000 * 10 ** 18;
        } else {
            return 0;
        }
    }

    function getEngineByProduct(uint32 productId) external view returns (address) {
        if (productId == 0) {
            return USDC;
        } else if (productId == 1) {
            return BTC;
        } else {
            return WETH;
        }
    }

    // Exclude from coverage report
    function test() public {}
}
