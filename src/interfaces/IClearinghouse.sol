// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IClearinghouse {
    /// @notice Retrieve quote ERC20 address
    function getQuote() external view returns (address);

    /// @notice Returns the engine associated with a product ID
    function getEngineByProduct(uint32 productId) external view returns (address);
}
