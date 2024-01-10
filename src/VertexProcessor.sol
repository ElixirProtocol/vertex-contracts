// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

import {IEndpoint} from "src/interfaces/IEndpoint.sol";
import {IClearinghouse} from "src/interfaces/IClearinghouse.sol";

import {VertexStorage} from "src/VertexStorage.sol";
import {VertexManager} from "src/VertexManager.sol";
import {VertexRouter} from "src/VertexRouter.sol";

/// @title Elixir pool processor for Vertex
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Back-end contract to process queue deposits and withdrawals. This contract is delegatecalled from VertexManager.
contract VertexProcessor is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard, VertexStorage {
    using SafeERC20 for IERC20Metadata;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a deposit is made.
    /// @param router The router of the pool deposited to.
    /// @param caller The caller of the deposit function, for which tokens are taken from.
    /// @param receiver The receiver of the LP balance.
    /// @param id The ID of the pool deposting to.
    /// @param token The token deposited.
    /// @param amount The token amount deposited.
    /// @param shares The amount of shares received.
    event Deposit(
        address indexed router,
        address caller,
        address indexed receiver,
        uint256 indexed id,
        address token,
        uint256 amount,
        uint256 shares
    );

    /// @notice Emitted when a withdraw is made.
    /// @param router The router of the pool withdrawn from.
    /// @param user The user who withdrew.
    /// @param tokenId The Vertex product ID of the token withdrawn.
    /// @param amount The token amount the user receives.
    event Withdraw(address indexed router, address indexed user, uint32 tokenId, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a token is not supported for a pool.
    /// @param token The address of the unsupported token.
    /// @param id The ID of the pool.
    error UnsupportedToken(address token, uint256 id);

    /// @notice Emitted when the queue spot type is invalid.
    error InvalidSpotType(Spot spot);

    /// @notice Emitted when the slippage is too high.
    /// @param amount The amount of tokens given.
    /// @param amountLow The low limit of token amounts.
    /// @param amountHigh The high limit of token amounts.
    error SlippageTooHigh(uint256 amount, uint256 amountLow, uint256 amountHigh);

    /// @notice Emitted when the hardcap of a pool would be exceeded.
    /// @param token The token address being deposited.
    /// @param hardcap The hardcap of the pool given the token.
    /// @param activeAmount The active amount of tokens in the pool.
    /// @param amount The amount of tokens being deposited.
    error HardcapReached(address token, uint256 hardcap, uint256 activeAmount, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                    INTERNAL DEPOSIT/WITHDRAW LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal deposit logic for both spot and perp pools.
    /// @param caller The user who is depositing.
    /// @param id The id of the pool.
    /// @param pool The data of the pool to deposit.
    /// @param token The tokens to deposit.
    /// @param amount The amounts of token to deposit.
    /// @param receiver The receiver of the virtual LP balance.
    function _deposit(
        address caller,
        uint256 id,
        Pool storage pool,
        address token,
        uint256 amount,
        uint256 shares,
        address receiver
    ) private {
        // Establish empty token data.
        Token storage tokenData;

        // If token is the Clearinghouse quote token, point to the old quote token data.
        if (oldQuoteToken != address(0) && token == IClearinghouse(endpoint.clearinghouse()).getQuote()) {
            tokenData = pool.tokens[oldQuoteToken];
        } else {
            tokenData = pool.tokens[token];
        }

        // Check that the token is supported by the pool.
        if (!tokenData.isActive || token == oldQuoteToken) revert UnsupportedToken(token, id);

        // Check if the amount exceeds the token's pool hardcap.
        if (tokenData.activeAmount + shares > tokenData.hardcap) {
            revert HardcapReached(token, tokenData.hardcap, tokenData.activeAmount, shares);
        }

        // Fetch the router of the pool.
        VertexRouter router = VertexRouter(pool.router);

        // Transfer tokens from the caller to this contract.
        IERC20Metadata(token).safeTransferFrom(caller, address(router), amount);

        // Deposit funds to Vertex through router.
        router.submitSlowModeDeposit(tokenToProduct[token], uint128(amount), "9O7rUEUljP");

        // Add amount to the active market making balance of the user.
        tokenData.userActiveAmount[receiver] += shares;

        // Add amount to the active pool market making balance.
        tokenData.activeAmount += shares;

        emit Deposit(address(router), caller, receiver, id, token, amount, shares);
    }

    /// @notice Internal withdraw logic for both spot and perp pools.
    /// @param caller The user who is withdrawing.
    /// @param pool The data of the pool to withdraw from.
    /// @param token The token to withdraw.
    /// @param amount The amount of token to substract from active balances.
    /// @param fee The fee to pay.
    /// @param amountToReceive The amount of tokens the user receives.
    function _withdraw(
        address caller,
        Pool storage pool,
        address token,
        uint256 amount,
        uint256 fee,
        uint256 amountToReceive
    ) private {
        // Establish empty token data.
        Token storage tokenData;

        // If token is the Clearinghouse quote token, point to the old quote token data.
        if (oldQuoteToken != address(0) && token == IClearinghouse(endpoint.clearinghouse()).getQuote()) {
            tokenData = pool.tokens[oldQuoteToken];
        } else {
            tokenData = pool.tokens[token];
        }

        // Substract amount from the active market making balance of the caller.
        tokenData.userActiveAmount[caller] -= amount;

        // Substract amount from the active pool market making balance.
        tokenData.activeAmount -= amount;

        // Add fee to the Elixir balance.
        tokenData.fees[caller] += fee;

        // Update the user pending balance.
        tokenData.userPendingAmount[caller] += (amountToReceive - fee);

        // Create Vertex withdraw payload request.
        IEndpoint.WithdrawCollateral memory withdrawPayload = IEndpoint.WithdrawCollateral(
            VertexRouter(pool.router).contractSubaccount(), tokenToProduct[token], uint128(amountToReceive), 0
        );

        // Fetch payment fee from owner. This can be reimbursed on withdrawals after tokens are received.
        quoteToken.safeTransferFrom(owner(), pool.router, slowModeFee);

        // Submit Withdraw slow-mode tx to Vertex.
        VertexRouter(pool.router).submitSlowModeTransaction(
            abi.encodePacked(uint8(IEndpoint.TransactionType.WithdrawCollateral), abi.encode(withdrawPayload))
        );

        emit Withdraw(pool.router, caller, tokenToProduct[token], amountToReceive);
    }

    /// @notice Processes a spot transaction given a response.
    /// @param spot The spot to process.
    /// @param response The response for the spot in queue.
    /// @param manager The VertexManager contract calling this function.
    function processSpot(Spot calldata spot, bytes memory response, VertexManager manager) public {
        if (spot.spotType == SpotType.DepositSpot) {
            DepositSpot memory spotTxn = abi.decode(spot.transaction, (DepositSpot));

            DepositSpotResponse memory responseTxn = abi.decode(response, (DepositSpotResponse));

            // Check for slippage based on the needed amount1.
            if (responseTxn.amount1 < spotTxn.amount1Low || responseTxn.amount1 > spotTxn.amount1High) {
                revert SlippageTooHigh(responseTxn.amount1, spotTxn.amount1Low, spotTxn.amount1High);
            }

            // Execute deposit logic for token0.
            _deposit(
                spot.sender,
                spotTxn.id,
                pools[spotTxn.id],
                spotTxn.token0,
                spotTxn.amount0,
                responseTxn.token0Shares,
                spotTxn.receiver
            );

            // Execute deposit logic for token1.
            _deposit(
                spot.sender,
                spotTxn.id,
                pools[spotTxn.id],
                spotTxn.token1,
                responseTxn.amount1,
                responseTxn.token1Shares,
                spotTxn.receiver
            );
        } else if (spot.spotType == SpotType.DepositPerp) {
            DepositPerp memory spotTxn = abi.decode(spot.transaction, (DepositPerp));

            DepositPerpResponse memory responseTxn = abi.decode(response, (DepositPerpResponse));

            // Execute the deposit logic.
            _deposit(
                spot.sender,
                spotTxn.id,
                pools[spotTxn.id],
                spotTxn.token,
                spotTxn.amount,
                responseTxn.shares,
                spotTxn.receiver
            );
        } else if (spot.spotType == SpotType.WithdrawPerp) {
            WithdrawPerp memory spotTxn = abi.decode(spot.transaction, (WithdrawPerp));

            WithdrawPerpResponse memory responseTxn = abi.decode(response, (WithdrawPerpResponse));

            // Execute the withdraw logic.
            _withdraw(
                spot.sender,
                pools[spotTxn.id],
                spotTxn.token,
                spotTxn.amount,
                manager.getTransactionFee(spotTxn.token),
                responseTxn.amountToReceive
            );
        } else if (spot.spotType == SpotType.WithdrawSpot) {
            WithdrawSpot memory spotTxn = abi.decode(spot.transaction, (WithdrawSpot));

            WithdrawSpotResponse memory responseTxn = abi.decode(response, (WithdrawSpotResponse));

            // Execute the withdraw logic for token0.
            _withdraw(
                spot.sender,
                pools[spotTxn.id],
                spotTxn.token0,
                spotTxn.amount0,
                manager.getTransactionFee(spotTxn.token0),
                responseTxn.amount0ToReceive
            );
            // Execute the withdraw logic for token1.
            _withdraw(
                spot.sender,
                pools[spotTxn.id],
                spotTxn.token1,
                responseTxn.amount1,
                manager.getTransactionFee(spotTxn.token1),
                responseTxn.amount1ToReceive
            );
        } else {
            revert InvalidSpotType(spot);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Upgrades the implementation of the proxy to new address.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
