// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin/utils/cryptography/EIP712.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

/// @title Elixir distributor contract
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Allows users to claim a token amount, approved by Elixir.
contract Distributor is Ownable, EIP712 {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Track claimed actions.
    mapping(bytes32 => bool) public claimed;

    /// @notice The reward signer address.
    address public immutable signer;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user claims a token amount.
    /// @param user The user who claimed the rewards.
    /// @param token The token claimed.
    /// @param nonce The nonce of the action.
    /// @param amount The amount of rewards claimed.
    event Claimed(address indexed user, address indexed token, uint256 nonce, uint256 indexed amount);

    /// @notice Emitted when the owner withdraws a token.
    event Withdraw(address indexed token, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error emitted when the ECDSA signer is not correct.
    error InvalidSignature();

    /// @notice Error emitted when the user has already claimed the rewards.
    error AlreadyClaimed();

    /// @notice Error emitted when the amount is zero.
    error InvalidAmount();

    /// @notice Error emitted when the nonce is zero.
    error InvalidNonce();

    /// @notice Error emitted when the token is zero.
    error InvalidToken();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the storage variables.
    /// @param _name The name of the contract.
    /// @param _version The version of the contract.
    /// @param _signer The Vertex reward signer address.
    constructor(string memory _name, string memory _version, address _signer) EIP712(_name, _version) {
        // Set the signer address.
        signer = _signer;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims tokens approved by Elixir.
    /// @param token The token to claim.
    /// @param nonce The nonce of the action.
    /// @param amount The amount of token to claim.
    /// @param signature The signature of the Vertex signer.
    function claim(address token, uint256 nonce, uint256 amount, bytes memory signature) external {
        // Check that the token is not zero.
        if (token == address(0)) revert InvalidToken();

        // Check that the nonce is not zero.
        if (nonce == 0) revert InvalidNonce();

        // Check that the amount is not zero.
        if (amount == 0) revert InvalidAmount();

        // Generate digest.
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256("Claim(address user,address token,uint256 nonce,uint256 amount)"),
                    msg.sender,
                    token,
                    nonce,
                    amount
                )
            )
        );

        // Check if the user already claimed.
        if (claimed[digest]) revert AlreadyClaimed();

        // Check if the signature is valid.
        if (ECDSA.recover(digest, signature) != signer) revert InvalidSignature();

        // Mark nonce as claimed.
        claimed[digest] = true;

        // Transfer tokens to user.
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, token, nonce, amount);
    }

    /// @notice Withdraw a given amount of tokens.
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);

        emit Withdraw(token, amount);
    }
}
