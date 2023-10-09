// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ERC2771Context} from "openzeppelin/metatx/ERC2771Context.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {VertexManager} from "../VertexManager.sol";

/// @title Stargate receiver
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Stargate Finance receiver for deposits in VertexManager pools.
contract StargateReceiver is ERC2771Context {
    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The Elixir VertexManager samrt contract.
    VertexManager public immutable manager;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the transaction caller is not the relayer.
    /// @param caller The function caller.
    error NotRelayer(address caller);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Revert if the caller is not the forwarder.
    modifier onlyForwarder() {
        if (!isTrustedForwarder(msg.sender)) revert NotRelayer(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the VertexManager and relayer addresses.
    /// @param _manager The address of the VertexManager smart contract.
    /// @param _relayer The LayerZero relayer address.
    constructor(address _manager, address _relayer) ERC2771Context(_relayer) {
        manager = VertexManager(_manager);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL ENTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits tokens into a perp pool to market make on Vertex on behalf of a user.
    /// @param id The pool ID to deposit tokens to.
    /// @param tokens The list of tokens to deposit.
    /// @param amounts The list of token amounts to deposit.
    function depositPerpOnBehalf(uint256 id, address[] calldata tokens, uint256[] memory amounts)
        external
        onlyForwarder
    {
        manager.depositPerp(id, tokens, amounts, _msgSender());
    }

    /// @notice Deposits tokens into a spot pool to market make on Vertex on behalf of a user.
    /// @param id The ID of the pool to deposit to.
    /// @param tokens The list of tokens to deposit.
    /// @param amount0 The amount of base tokens.
    /// @param amount1Low The low limit of the quote amount.
    /// @param amount1High The high limit of the quote amount.
    function depositSpotOnBehalf(
        uint256 id,
        address[] calldata tokens,
        uint256 amount0,
        uint256 amount1Low,
        uint256 amount1High
    ) external onlyForwarder {
        manager.depositSpot(id, tokens, amount0, amount1Low, amount1High, _msgSender());
    }

    /// @notice Maximum approves a token to be used by the VertexManager.
    /// @param token The token to approve.
    function approveToken(address token) external {
        IERC20Metadata(token).approve(address(manager), type(uint256).max);
    }
}
