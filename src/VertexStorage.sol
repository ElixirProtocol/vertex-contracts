// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {IEndpoint} from "src/interfaces/IEndpoint.sol";
import {IVertexManager} from "src/interfaces/IVertexManager.sol";

/// @title Elixir storage for Vertex
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Back-end contract with storage variables.
abstract contract VertexStorage is IVertexManager {
    /// @notice The pools managed given an ID.
    mapping(uint256 id => Pool pool) public pools;

    /// @notice The Vertex product IDs of token addresses.
    mapping(address token => uint32 id) public tokenToProduct;

    /// @notice The token addresses of Vertex product IDs.
    mapping(uint32 id => address token) public productToToken;

    /// @notice The queue for Elixir to process.
    mapping(uint128 => Spot) public queue;

    /// @notice The queue count.
    uint128 public queueCount;

    /// @notice The queue up to.
    uint128 public queueUpTo;

    /// @notice The Vertex slow mode fee.
    uint256 public slowModeFee = 1000000;

    /// @notice Vertex's Endpoint contract.
    IEndpoint public endpoint;

    /// @notice Fee payment token for slow mode transactions through Vertex.
    IERC20Metadata public quoteToken;

    /// @notice The pause status of deposits. True if deposits are paused.
    bool public depositPaused;

    /// @notice The pause status of withdrawals. True if withdrawals are paused.
    bool public withdrawPaused;

    /// @notice The pause status of claims. True if claims are paused.
    bool public claimPaused;

    /// @notice Old quote token of Vertex.
    address internal oldQuoteToken;

    /// @notice The smart contract to off-load processing logic.
    address internal processor;
}
