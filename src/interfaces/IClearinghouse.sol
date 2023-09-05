// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface IClearinghouse {
    /// @notice Retrieve quote ERC20 address.
    function getQuote() external view returns (address);

    /// @notice Retrieve the engine of a product.
    function getEngineByProduct(uint32 productId) external view returns (address);
}
