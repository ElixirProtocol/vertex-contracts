// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {VertexPool, ERC20} from "./VertexPool.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";
import {Initializable} from  "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

/// @title Elixir Pool Factory for Vertex
/// @author The Elixir Team
/// @notice Factory for Elixir-based Vertex pools based on a pair of ERC20 tokens.
contract VertexFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using Bytes32AddressLib for address;
    using Bytes32AddressLib for bytes32;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist
    /// @dev tokenA and tokenB may be passed in either token0/token1 or token1/token0 order
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    struct Product {
        uint8 id;
        address token0;
        address token1;
    }

    /// @notice Vertex's clearing house contract
    address immutable clearingHouse;

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
                               INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice No constructor in upgradable contracts, so initialized with this function.
    function initialize(uint256 _clearingHouse, address owner) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();

        clearingHouse = _clearingHouse;

        // Initialize OwnableUpgradeable explicitly with given multisig address.
        transferOwnership(owner);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new Vault which supports a specific underlying token.
    /// @dev This will revert if a Vault that accepts the same underlying token has already been deployed.
    /// @param id The ID of the pool on Vertex
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    function deployVault(uint8 id, address token0, address token1) external onlyOwner returns (address pool) {
        if (tokenA == tokenB) revert SameTokens();
        if (address(token0) == address(0) || address(token1) == address(0)) revert TokenIsZero();
        if 

        // Use the CREATE2 opcode to deploy a new Vault contract.
        // This will revert if a Vault which accepts this underlying token has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        pool = address(
            new VertexPool{salt: keccak256(abi.encode(token0, token1))}(
                string(abi.encodePacked("Elixir LP ", token0.name(), "-", token1.name(), " for Vertex")),
                string(abi.encodePacked("elxr-", token0.symbol(), "-", token1.symbol())),
                token0,
                token1
            )
        );

        emit PoolDeployed(address(token0), address(token1), pool);
    }
}
