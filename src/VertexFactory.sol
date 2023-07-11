// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

import {IClearinghouse} from "./interfaces/clearinghouse/IClearinghouse.sol";
import {IEndpoint} from "./interfaces/IEndpoint.sol";
import {VertexStable} from "./VertexStable.sol";

/// @title Elixir Vault Factory for Vertex
/// @author The Elixir Team
/// @notice Factory for Elixir-based Vertex vaults based on a pair of ERC20 tokens.
contract VertexFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using Bytes32AddressLib for address;
    using Bytes32AddressLib for bytes32;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the vault address for a given product id
    /// @dev Returns address instead of Stable or Perp vault type to avoid casting
    mapping(uint32 => address) public getVaultByProduct;

    /// @notice Vertex's clearing house contract
    IClearinghouse public clearingHouse;

    IEndpoint public endpoint;

    address public externalAccount;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new Vault is deployed.
    /// @param token0 The first token of the vault by address sort order
    /// @param token1 The second token of the vault by address sort order
    /// @param vault The address of the created vault
    event VaultDeployed(address token0, address token1, address vault);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SameTokens();
    error TokenIsZero();
    error InvalidProduct();

    /*//////////////////////////////////////////////////////////////
                               INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice No constructor in upgradable contracts, so initialized with this function.
    function initialize(IClearinghouse _clearingHouse, IEndpoint _endpoint, address _externalAccount, address owner)
        public
        initializer
    {
        __UUPSUpgradeable_init();
        __Ownable_init();

        clearingHouse = _clearingHouse;
        endpoint = _endpoint;
        externalAccount = _externalAccount;

        // Initialize OwnableUpgradeable explicitly with given multisig address.
        transferOwnership(owner);
    }

    /*//////////////////////////////////////////////////////////////
                          VAULT DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new Vault which supports a specific underlying token.
    /// @dev This will revert if a Vault that accepts the same underlying token has already been deployed.
    /// @param id The ID of the product on Vertex
    /// @param token0 Token 0 of the vault to be created
    /// @param token1 Token 1 of the vault to be created
    function deployVault(uint32 id, ERC20 token0, ERC20 token1) external onlyOwner returns (address vault) {
        if (token0 == token1) revert SameTokens();
        if (address(token0) == address(0) || address(token1) == address(0)) revert TokenIsZero();
        if (clearingHouse.getEngineByProduct(id) == address(0)) revert InvalidProduct();

        // Use the CREATE2 opcode to deploy a new Vault contract.
        // The salt includes the block number to allow to deploy multiple vaults per combination of tokens.
        vault = address(
            new VertexStable{salt: keccak256(abi.encode(id, token0, token1, block.number))}(
                id,
                string(abi.encodePacked("Elixir LP ", token0.name(), "-", token1.name(), " for Vertex")),
                string(abi.encodePacked("elxr-", token0.symbol(), "-", token1.symbol())),
                token0,
                token1
            )
        );

        emit VaultDeployed(address(token0), address(token1), vault);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Upgrades the implementation of the proxy to new address.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
