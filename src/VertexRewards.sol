// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin/utils/cryptography/EIP712.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

/// @title Elixir VRTX rewards contract
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Allows users to claim Vertex rewards accrued through Elixir.
contract VertexRewards is EIP712 {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The amount of Vertex rewards claimed by each user and epoch.
    mapping(address => mapping(uint32 => uint256)) public claimed;

    /// @notice The Vertex token.
    IERC20 public immutable vrtx;

    /// @notice The reward signer address.
    address public immutable signer;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user claims Vertex rewards.
    /// @param user The user who claimed the rewards.
    /// @param epoch The epoch of the rewards claimed.
    /// @param amount The amount of rewards claimed.
    event Claimed(address indexed user, uint32 indexed epoch, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error emitted when the ECDSA signer is not correct.
    error NotSigner();

    /// @notice Error emitted when the user has already claimed the rewards.
    error AlreadyClaimed();

    /// @notice Error emitted when the amount is zero.
    error InvalidAmount();

    /// @notice Error emitted when the epoch is zero.
    error InvalidEpoch();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the storage variables.
    /// @param _name The name of the Vertex rewards contract.
    /// @param _version The version of the Vertex rewards contract.
    /// @param _vrtx The Vertex token address.
    /// @param _signer The Vertex reward signer address.
    constructor(string memory _name, string memory _version, IERC20 _vrtx, address _signer) EIP712(_name, _version) {
        // Set the token address.
        vrtx = _vrtx;

        // Set the signer address.
        signer = _signer;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims accrued Vertex rewards from Elixir.
    /// @param epoch The epoch of the rewards to claim.
    /// @param amount The amount of rewards to claim.
    /// @param signature The signature of the Vertex reward signer.
    function claim(uint32 epoch, uint256 amount, bytes memory signature) external {
        // Check if the user already claimed rewards for this epoch.
        if (claimed[msg.sender][epoch] != 0) revert AlreadyClaimed();

        // Check that the amount is not zero.
        if (amount == 0) revert InvalidAmount();

        // Check that the epoch is not zero.
        if (epoch == 0) revert InvalidEpoch();

        // Generate digest.
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(keccak256("Claim(address user,uint32 epoch,uint256 amount)"), msg.sender, epoch, amount)
            )
        );

        // Check if the signature is valid.
        if (ECDSA.recover(digest, signature) != signer) revert NotSigner();

        // Mark epoch as claimed.
        claimed[msg.sender][epoch] = amount;

        // Transfer VRTX to user.
        vrtx.safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, epoch, amount);
    }
}
