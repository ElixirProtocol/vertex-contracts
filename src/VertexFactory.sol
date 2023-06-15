// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {VertexPool} from "./VertexPool.sol";

/// @title Elixir Pool Factory for Vertex
/// @author The Elixir Team
/// @notice Factory for Elixir-based Vertex pools based on a pair of ERC20 tokens.
contract VaultFactory {
    using Bytes32AddressLib for address;
    using Bytes32AddressLib for bytes32;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new Pool is deployed.
    /// @param token0 The first token of the pool by address sort order
    /// @param token1 The second token of the pool by address sort order
    /// @param pool The address of the created pool
    event PoolDeployed(address token0, address token1, address pool);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SameTokens();
    error TokenIsZero();

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new Vault which supports a specific underlying token.
    /// @dev This will revert if a Vault that accepts the same underlying token has already been deployed.
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    function deployVault(address tokenA, address tokenB) external returns (Vault vault) {
        if (tokenA == tokenB) revert SameTokens();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert TokenIsZero();

        // Use the CREATE2 opcode to deploy a new Vault contract.
        // This will revert if a Vault which accepts this underlying token has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        pool = address(new VertexPool{salt: keccak256(abi.encode(token0, token1))}(token0, token1));

        emit PoolDeployed(token0, token1, pool);
    }
}
