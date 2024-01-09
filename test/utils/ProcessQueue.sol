// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {VertexManager, IVertexManager} from "src/VertexManager.sol";

library ProcessQueue {
    /// @notice Processes any transactions in the Elixir queue.
    function processQueue(VertexManager manager) internal {
        // Loop through the queue and process each transaction using the idTo provided.
        for (uint128 i = manager.queueUpTo() + 1; i < manager.queueCount() + 1; i++) {
            VertexManager.Spot memory spot = manager.nextSpot();

            if (spot.spotType == IVertexManager.SpotType.DepositSpot) {
                IVertexManager.DepositSpot memory spotTxn = abi.decode(spot.transaction, (IVertexManager.DepositSpot));

                uint256 amount1 = manager.getBalancedAmount(spotTxn.token0, spotTxn.token1, spotTxn.amount0);

                manager.unqueue(
                    i,
                    abi.encode(
                        IVertexManager.DepositSpotResponse({
                            amount1: amount1,
                            token0Shares: spotTxn.amount0,
                            token1Shares: amount1
                        })
                    )
                );
            } else if (spot.spotType == IVertexManager.SpotType.DepositPerp) {
                IVertexManager.DepositPerp memory spotTxn = abi.decode(spot.transaction, (IVertexManager.DepositPerp));

                manager.unqueue(i, abi.encode(IVertexManager.DepositPerpResponse({shares: spotTxn.amount})));
            } else if (spot.spotType == IVertexManager.SpotType.WithdrawPerp) {
                IVertexManager.WithdrawPerp memory spotTxn = abi.decode(spot.transaction, (IVertexManager.WithdrawPerp));

                manager.unqueue(i, abi.encode(IVertexManager.WithdrawPerpResponse({amountToReceive: spotTxn.amount})));
            } else if (spot.spotType == IVertexManager.SpotType.WithdrawSpot) {
                IVertexManager.WithdrawSpot memory spotTxn = abi.decode(spot.transaction, (IVertexManager.WithdrawSpot));

                uint256 amount1 = manager.getBalancedAmount(spotTxn.token0, spotTxn.token1, spotTxn.amount0);

                manager.unqueue(
                    i,
                    abi.encode(
                        IVertexManager.WithdrawSpotResponse({
                            amount1: amount1,
                            amount0ToReceive: spotTxn.amount0,
                            amount1ToReceive: amount1
                        })
                    )
                );
            } else {}
        }
    }
}
