// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface IVertexManager {
    /// @notice The types of spots supported by this contract.
    enum SpotType {
        Empty,
        DepositSpot,
        WithdrawPerp,
        WithdrawSpot,
        DepositPerp
    }

    /// @notice The types of queue-related events.
    enum QueueEvent {
        Deposit,
        Withdraw,
        Unqueue
    }

    /// @notice The structure for perp deposits to be processed by Elixir.
    struct DepositPerp {
        // The ID of the pool.
        uint256 id;
        // The token address.
        address token;
        // The amount of token to deposit.
        uint256 amount;
        // The receiver address.
        address receiver;
    }

    /// @notice The structure for spot deposits to be processed by Elixir.
    struct DepositSpot {
        // The ID of the pool.
        uint256 id;
        // The token0 address.
        address token0;
        // The token1 address.
        address token1;
        // The amount of token0 to deposit.
        uint256 amount0;
        // The low limit of token1 to deposit.
        uint256 amount1Low;
        // The high limit of token1 to deposit.
        uint256 amount1High;
        // The receiver of the virtual LP balance.
        address receiver;
    }

    /// @notice The structure of perp withdrawals to be processed by Elixir.
    struct WithdrawPerp {
        // The ID of the pool.
        uint256 id;
        // The token address.
        address token;
        // The amount of token shares to withdraw.
        uint256 amount;
    }

    /// @notice The structure of spot withdrawals to be processed by Elixir.
    struct WithdrawSpot {
        // The ID of the pool.
        uint256 id;
        // The token0 address.
        address token0;
        // The token1 address.
        address token1;
        // The amount of token0 shares to withdraw.
        uint256 amount0;
    }

    /// @notice The response structure for DepositSpot.
    struct DepositSpotResponse {
        // The amount of token1 to take from user.
        uint256 amount1;
        // The amount of token0 shares to add.
        uint256 token0Shares;
        // The amount of token1 shares to add.
        uint256 token1Shares;
    }

    /// @notice The response structure for DepositPerp.
    struct DepositPerpResponse {
        // The amount of shares to receive.
        uint256 shares;
    }

    /// @notice The response structure for WithdrawPerp.
    struct WithdrawPerpResponse {
        // The amount of of tokens the user should receive.
        uint256 amountToReceive;
    }

    /// @notice The response structure for WithdrawSpot.
    struct WithdrawSpotResponse {
        // The amount of token1 to use.
        uint256 amount1;
        // The amount of token0 the user should receive.
        uint256 amount0ToReceive;
        // The amount of token1 the user should receive.
        uint256 amount1ToReceive;
    }

    /// @notice The types of pools supported by this contract.
    enum PoolType {
        Inactive,
        Spot,
        Perp
    }

    /// @notice The data structure of pools.
    struct Pool {
        // The router address of the pool.
        address router;
        // The pool type. True for spot, false for perp.
        PoolType poolType;
        // The data of the supported tokens in the pool.
        mapping(address token => Token data) tokens;
    }

    /// @notice The data structure of tokens.
    struct Token {
        // The active market making balance of users for a token within a pool.
        mapping(address user => uint256 balance) userActiveAmount;
        // The pending amounts of users for a token within a pool.
        mapping(address user => uint256 amount) userPendingAmount;
        // The pending fees of a token within a pool.
        mapping(address user => uint256 amount) fees;
        // The total active amounts of a token within a pool.
        uint256 activeAmount;
        // The hardcap of the token within a pool.
        uint256 hardcap;
        // The status of the token within a pool. True if token is supported.
        bool isActive;
    }

    /// @notice The data structure of queue spots.
    struct Spot {
        // The sender of the request.
        address sender;
        // The router address of the pool.
        address router;
        // The type of request.
        SpotType spotType;
        // The transaction to process.
        bytes transaction;
    }
}
