// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface IEngine {
    struct Balance {
        uint128 amount;
        int128 lastCumulativeMultiplierX18;
    }

    /// @notice Returns the balance of a subaccount given a product ID.
    function getBalance(uint32 productId, bytes32 subaccount) external view returns (Balance memory);
}
