// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {IEndpoint} from "./interfaces/IEndpoint.sol";

/// @title Elixir pool router for Vertex
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @dev This contract is needed because an address can only have one Vertex linked signer at a time,
/// which is incompatible with the VertexManager singleton approach.
/// @notice Pool router contract to send slow-mode transactions to Vertex.
contract VertexRouter {
    using SafeERC20 for IERC20Metadata;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Vertex's Endpoint contract.
    IEndpoint public immutable endpoint;

    /// @notice Bytes of this contract's subaccount.
    bytes32 public immutable contractSubaccount;

    /// @notice Bytes of the external account's subaccount.
    bytes32 public immutable externalSubaccount;

    /// @notice The Manager contract associated with this Router.
    address public immutable manager;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when the sender is not the manager.
    error NotManager();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when the sender is not the manager.
    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the manager, Vertex Endpoint, and subaccounts.
    /// @param _endpoint The address of the Vertex Endpoint contract.
    /// @param _externalAccount The address of the external account to link to the Vertex Endpoint.
    constructor(address _endpoint, address _externalAccount) {
        // Set the Manager as the owner.
        manager = msg.sender;

        // Set Vertex's endpoint address.
        endpoint = IEndpoint(_endpoint);

        // Store this contract's internal and external subaccount.
        contractSubaccount = bytes32(uint256(uint160(address(this))) << 96);
        externalSubaccount = bytes32(uint256(uint160(_externalAccount)) << 96);
    }

    /*//////////////////////////////////////////////////////////////
                        VERTEX SLOW TRANSACTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Submits a slow mode transaction to Vertex.
    /// @dev More information about slow mode transactions:
    /// https://vertex-protocol.gitbook.io/docs/developer-resources/api/withdrawing-on-chain
    /// @param transaction The transaction to submit.
    function submitSlowModeTransaction(bytes memory transaction) external onlyManager {
        endpoint.submitSlowModeTransaction(transaction);
    }

    /*//////////////////////////////////////////////////////////////
                             TOKEN TRANSFER
    //////////////////////////////////////////////////////////////*/

    /// @notice Approves Vertex to transfer a token.
    /// @param token The token to approve.
    function makeApproval(address token) external onlyManager {
        // Approve the token transfer.
        IERC20Metadata(token).approve(address(endpoint), type(uint256).max);
    }

    /// @notice Allow claims from VertexManager contract.
    /// @param token The token to transfer.
    /// @param amount The amount to transfer.
    function claimToken(address token, uint256 amount) external onlyManager {
        // Transfer the token to the manager.
        IERC20Metadata(token).safeTransfer(manager, amount);
    }
}
