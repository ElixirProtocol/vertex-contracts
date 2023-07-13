// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

import {IClearinghouse} from "./interfaces/IClearinghouse.sol";
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
    /// @param baseToken The base token of the vault.
    /// @param quoteToken The quote token of the vault.
    /// @param vault The address of the created vault.
    event VaultDeployed(address indexed baseToken, address indexed quoteToken, address indexed vault);

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
    /// @param baseToken Token 0 of the vault to be created
    /// @param quoteToken Token 1 of the vault to be created
    function deployVault(uint32 id, ERC20 baseToken, ERC20 quoteToken) external onlyOwner returns (address vault) {
        if (baseToken == quoteToken) revert SameTokens();
        if (address(baseToken) == address(0) || address(quoteToken) == address(0)) revert TokenIsZero();
        if (clearingHouse.getEngineByProduct(id) == address(0)) revert InvalidProduct();

        string memory name =
            string(abi.encodePacked("Elixir LP ", baseToken.name(), "-", quoteToken.name(), " for Vertex"));
        string memory symbol = string(abi.encodePacked("elxr-", baseToken.symbol(), "-", quoteToken.symbol()));
        bytes32 salt = keccak256(abi.encode(id, baseToken, quoteToken, block.number));

        vault = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(
                                abi.encodePacked(
                                    type(VertexStable).creationCode, abi.encode(id, name, symbol, baseToken, quoteToken)
                                )
                            )
                        )
                    )
                )
            )
        );

        // Approve vault for it to fetch payment tokens for slow transaction fees.
        ERC20(clearingHouse.getQuote()).approve(vault, type(uint256).max);

        // Use the CREATE2 opcode to deploy a new Vault contract.
        // The salt includes the block number to allow to deploy multiple vaults per combination of tokens.
        new VertexStable{salt: salt}(
            id,
            name,
            symbol,
            baseToken,
            quoteToken
        );

        // Store vault given product id
        getVaultByProduct[id] = vault;

        emit VaultDeployed(address(baseToken), address(quoteToken), vault);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Upgrades the implementation of the proxy to new address.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
