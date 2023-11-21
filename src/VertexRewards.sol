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

    /// @notice The Vertex token.
    address public immutable vrtx;

    /// @notice The reward signer address.
    address public immutable signer;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error emitted when the ECDSA signer is not correct.
    error NotSigner();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the storage variables.
    /// @param _name The name of the Vertex rewards contract.
    /// @param _version The version of the Vertex rewards contract.
    /// @param _vrtx The Vertex token address.
    /// @param _signer The Vertex reward signer address.
    constructor(string memory _name, string memory _version, address _vrtx, address _signer) EIP712(_name, _version) {
        // Set the token address.
        vrtx = _vrtx;

        // Set the signer address.
        signer = _signer;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims accrued Vertex rewards from Elixir.
    /// @param amount The amount of rewards to claim.
    /// @param epoch The epoch of the rewards to claim.
    /// @param signature The signature of the Vertex reward signer.
    function claim(uint256 amount, uint256 epoch, bytes memory signature) external {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(keccak256("Claim(address user,uint256 amount,uint256 epoch)"), msg.sender, amount, epoch)
            )
        );

        // TODO check that hash has not been used before.

        if (ECDSA.recover(digest, signature) != signer) revert NotSigner();

        // TODO mark as used.

        // TODO: distribute the airdrop to user

        // emit Claimed(msg.sender, _amount);
    }
}
