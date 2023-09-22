// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

import {IClearinghouse} from "./interfaces/IClearinghouse.sol";
import {IEndpoint} from "./interfaces/IEndpoint.sol";
import {IEngine} from "../src/interfaces/IEngine.sol";

import {VertexRouter} from "./VertexRouter.sol";

/// @title Elixir pool manager for Vertex
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Pool manager contract to provide liquidity for spot and perp market making on Vertex Protocol.
contract VertexManager is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20Metadata;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The types of pools supported by this contract.
    enum PoolType {
        Spot,
        Perp
    }

    /// @notice The data structure of pools.
    struct Pool {
        // The router address of the pool.
        address router;
        // The type of the pool.
        PoolType poolType;
        // The data of the supported tokens in the pool.
        mapping(address token => Token data) tokens;
    }

    /// @notice The data structure of tokens.
    struct Token {
        // The active market making balance of users for a token within a pool.
        mapping(address user => uint256 balance) userActiveAmount;
        // The total active amounts of a token within a pool.
        uint256 activeAmount;
        // The hardcap of the token within a pool.
        uint256 hardcap;
        // The status of the token within a pool. True if token is supported.
        bool isActive;
    }

    /// @notice The pools managed by this contract given their ID.
    mapping(uint256 id => Pool pool) public pools;

    /// @notice The pending balance of users.
    mapping(address user => mapping(address token => uint256 balance)) public pendingBalances;

    /// @notice The Vertex product ID of token addresses.
    mapping(address token => uint32 id) public tokenToProduct;

    /// @notice Helper mappings for Vertex balances.
    mapping(uint32 id => uint256 balance) tokenBalances;

    /// @notice The Elixir fee reimbursements for users and a token address.
    mapping(address user => mapping(address token => uint256 amount)) public fees;

    /// @notice The Vertex slow mode fee
    uint256 public slowModeFee;

    /// @notice Vertex's Endpoint contract.
    IEndpoint public endpoint;

    /// @notice Fee payment token for slow mode transactions through Vertex.
    IERC20Metadata public paymentToken;

    /// @notice The pause status of deposits. True if deposits are paused.
    bool public depositPaused;

    /// @notice The pause status of withdrawals. True if withdrawals are paused.
    bool public withdrawPaused;

    /// @notice The pause status of claims. True if claims are paused.
    bool public claimPaused;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a deposit is made.
    /// @param caller The caller of the deposit function, for which tokens are taken from.
    /// @param receiver The receiver of the virtual LP balance.
    /// @param id The ID of the pool deposting to.
    /// @param tokens The list of tokens deposited.
    /// @param amounts The amount of tokens deposited.
    event Deposit(address indexed caller, address indexed receiver, uint256 id, address[] tokens, uint256[] amounts);

    /// @notice Emitted when a withdraw is made.
    /// @param user The user who withdrew.
    /// @param id The ID of the pool withdrawn from.
    /// @param tokens The list of tokens withdrawn.
    /// @param amounts The amounts of tokens withdrawn.
    event Withdraw(address indexed user, uint256 id, address[] tokens, uint256[] amounts);

    /// @notice Emitted when a claim is made.
    /// @param user The user for which the tokens were claimed.
    /// @param tokens The tokens claimed.
    event Claim(address indexed user, address[] tokens);

    /// @notice Emitted when the statuses are updated.
    /// @param depositPaused True if deposits are paused, false otherwise.
    /// @param withdrawPaused True if withdrawals are paused, false otherwise.
    /// @param claimPaused True if claims are paused, false otherwise.
    event PauseUpdated(bool depositPaused, bool withdrawPaused, bool claimPaused);

    /// @notice Emitted when a pool is added.
    /// @param id The ID of the pool.
    /// @param poolType The type of the pool.
    /// @param router The router address of the pool.
    /// @param tokens The tokens of the pool.
    /// @param hardcaps The hardcaps of the pool.
    event PoolAdded(
        uint256 indexed id, PoolType poolType, address indexed router, address[] tokens, uint256[] hardcaps
    );

    /// @notice Emitted when tokens are added to a pool.
    /// @param id The ID of the pool.
    /// @param tokens The new tokens of the pool.
    /// @param hardcaps The hardcaps of the tokens.
    event PoolTokensAdded(uint256 indexed id, address[] tokens, uint256[] hardcaps);

    /// @notice Emitted when a pool's harcaps are updated.
    /// @param id The ID of the pool.
    /// @param hardcaps The new hardcaps of the pool.
    event PoolHardcapsUpdated(uint256 indexed id, uint256[] hardcaps);

    /// @notice Emitted when the Vertex product ID of a token is updated.
    /// @param token The token address to update the product ID of.
    /// @param productId The new product ID of the token.
    event TokenUpdated(address indexed token, uint256 indexed productId);

    /// @notice Emitted when the slow mode fee is updated.
    /// @param newFee The new fee.
    event SlowModeFeeUpdated(uint256 newFee);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a tokens array is empty.
    /// @param array The array input.
    error EmptyInput(address[] array);

    /// @notice Emitted when the receiver address is the zero address.
    error ZeroAddress();

    /// @notice Emitted when the fee index is not within the tokens array.
    /// @param index The index input.
    /// @param array The array input.
    error InvalidFeeIndex(uint256 index, address[] array);

    /// @notice Emitted when deposits (deposit and mint) are paused.
    error DepositsPaused();

    /// @notice Emitted when withdrawals (withdraw and redeem) are paused.
    error WithdrawalsPaused();

    /// @notice Emitted when claims are paused.
    error ClaimsPaused();

    /// @notice Emitted when the length of an array input doesn't match number of pool tokes supported.
    /// @param array1 The uint256 array input.
    /// @param array2 The address array input.
    error InvalidLength(uint256[] array1, address[] array2);

    /// @notice Emitted when the amount of tokens given are for a spot product and are not balanced.
    /// @param id The ID of the pool.
    /// @param amounts The list of amounts given.
    error UnbalancedAmounts(uint256 id, uint256[] amounts);

    /// @notice Emitted when the hardcap of a pool is reached.
    /// @param token The token address being deposited that exceeds the hardcap.
    /// @param hardcap The hardcap of the pool given the token.
    /// @param activeAmount The active amount of tokens in the pool.
    /// @param amount The amount of tokens being deposited.
    error HardcapReached(address token, uint256 hardcap, uint256 activeAmount, uint256 amount);

    /// @notice Emitted when the slippage is too high.
    /// @param amount1 The amount of quote tokens given.
    /// @param amount1Low The low limit of the quote amount.
    /// @param amount1High The high limit of the quote amount.
    error SlippageTooHigh(uint256 amount1, uint256 amount1Low, uint256 amount1High);

    /// @notice Emitted when the pool ID is not valid or used in the incorrect function.
    /// @param id The ID of the pool.
    error InvalidPool(uint256 id);

    /// @notice Emitted when a token is not supported for a pool.
    /// @param token The address of the unsupported token.
    /// @param id The ID of the pool.
    error UnsupportedToken(address token, uint256 id);

    /// @notice Emitted when the token is not valid because it has more than 18 decimals.
    /// @param token The address of the token.
    error InvalidToken(address token);

    /// @notice Emitted when the new fee is above 100 USDC.
    /// @param newFee The new fee.
    error FeeTooHigh(uint256 newFee);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts when deposits are paused.
    modifier whenDepositNotPaused() {
        if (depositPaused) revert DepositsPaused();
        _;
    }

    /// @notice Reverts when withdrawals are paused.
    modifier whenWithdrawNotPaused() {
        if (withdrawPaused) revert WithdrawalsPaused();
        _;
    }

    /// @notice Reverts when claims are paused.
    modifier whenClaimNotPaused() {
        if (claimPaused) revert ClaimsPaused();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Prevent the implementation contract from being initialized.
    /// @dev The proxy contract state will still be able to call this function because the constructor does not affect the proxy state.
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                               INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice No constructor in upgradable contracts, so initialized with this function.
    /// @param _endpoint The address of the Vertex Endpoint contract.
    /// @param _slowModeFee The fee to pay Vertex for slow mode transactions.
    function initialize(address _endpoint, uint256 _slowModeFee) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();

        // Set Vertex's endpoint address.
        endpoint = IEndpoint(_endpoint);

        // Set the slow mode fee value.
        slowModeFee = _slowModeFee;

        // It may happen that the quote token of endpoint payments is not the quote token of the vault/product.
        paymentToken = IERC20Metadata(IClearinghouse(endpoint.clearinghouse()).getQuote());
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL ENTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits tokens into a perp pool to market make on Vertex. Amounts can be unbalanced.
    /// @param id The pool ID to deposit tokens to.
    /// @param tokens The list of tokens to deposit.
    /// @param amounts The list of token amounts to deposit.
    /// @param receiver The receiver of the virtual LP balance.
    function depositPerp(uint256 id, address[] memory tokens, uint256[] memory amounts, address receiver)
        external
        whenDepositNotPaused
        nonReentrant
    {
        // Fetch the pool data.
        Pool storage pool = pools[id];

        // Check that the pool is perp.
        if (pool.poolType != PoolType.Perp) revert InvalidPool(id);

        // Check that the tokens array is not empty.
        if (tokens.length == 0) revert EmptyInput(tokens);

        // Check that the length of the tokens and amounts arrays match.
        if (tokens.length != amounts.length) revert InvalidLength(amounts, tokens);

        // Check that the receiver is not the zero address.
        if (receiver == address(0)) revert ZeroAddress();

        // Execute the deposit logic.
        _deposit(id, pool, tokens, amounts, receiver);
    }

    /// @notice Deposits tokens into a spot pool to market make on Vertex. Amounts must be balanced.
    /// @param id The ID of the pool to deposit to.
    /// @param tokens The list of tokens to deposit.
    /// @param amount0 The amount of base tokens.
    /// @param amount1Low The low limit of the quote amount.
    /// @param amount1High The high limit of the quote amount.
    /// @param receiver The receiver of the virtual LP balance.
    function depositSpot(
        uint256 id,
        address[] memory tokens,
        uint256 amount0,
        uint256 amount1Low,
        uint256 amount1High,
        address receiver
    ) external whenDepositNotPaused nonReentrant {
        // Fetch the pool data.
        Pool storage pool = pools[id];

        // Check that the pool is soit.
        if (pool.poolType != PoolType.Spot) revert InvalidPool(id);

        // Check that the tokens array is not empty.
        if (tokens.length == 0) revert EmptyInput(tokens);

        // Check that the receiver is not the zero address.
        if (receiver == address(0)) revert ZeroAddress();

        // Get the balanced amount of quote tokens.
        uint256 amount1 = getBalancedAmount(tokens[0], tokens[1], amount0);

        // Check for slippage based on the given quote amount (amount1) range.
        if (amount1 < amount1Low || amount1 > amount1High) {
            revert SlippageTooHigh(amount1, amount1Low, amount1High);
        }

        // Create amounts array.
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;

        // Execute the deposit logic.
        _deposit(id, pool, tokens, amounts, receiver);
    }

    /// @notice Withdraws tokens from a perp pool.
    /// @dev After requests are processed by Vertex, user (or anyone on behalf of it) should call the claim function.
    /// @param id The ID of the pool to withdraw from.
    /// @param tokens The list of tokens to withdraw.
    /// @param amounts The list of token amounts to withdraw.
    /// @param feeIndex The index of the token list to apply to the withdrawal fee to.
    function withdrawPerp(uint256 id, address[] memory tokens, uint256[] memory amounts, uint256 feeIndex)
        external
        whenWithdrawNotPaused
        nonReentrant
    {
        // Fetch the pool data.
        Pool storage pool = pools[id];

        // Check that the pool is perp.
        if (pool.poolType != PoolType.Perp) revert InvalidPool(id);

        // Check that the tokens array is not empty.
        if (tokens.length == 0) revert EmptyInput(tokens);

        // Check that the length of the tokens and amounts arrays match.
        if (tokens.length != amounts.length) revert InvalidLength(amounts, tokens);

        // Check that the feeIndex is within the tokens array.
        if (feeIndex > tokens.length) revert InvalidFeeIndex(feeIndex, tokens);

        // Execute the withdraw logic.
        _withdraw(id, pool, tokens, amounts, feeIndex);
    }

    /// @notice Withdraws tokens from a spot pool.
    /// @dev After requests are processed by Vertex, user (or anyone on behalf of it) should call the claim function.
    /// @param id The ID of the pool to withdraw from.
    /// @param tokens The list of tokens to withdraw.
    /// @param amount0 The amount of base tokens.
    /// @param feeIndex The index of the token list to apply to the withdrawal fee to.
    function withdrawSpot(uint256 id, address[] memory tokens, uint256 amount0, uint256 feeIndex)
        external
        whenWithdrawNotPaused
        nonReentrant
    {
        // Fetch the pool data.
        Pool storage pool = pools[id];

        // Check that the pool is spot.
        if (pool.poolType != PoolType.Spot) revert InvalidPool(id);

        // Check that the tokens array is not empty.
        if (tokens.length == 0) revert EmptyInput(tokens);

        // Check that the feeIndex is within the tokens array.
        if (feeIndex > tokens.length) revert InvalidFeeIndex(feeIndex, tokens);

        // Get the balanced amount of quote tokens.
        uint256 amount1 = getBalancedAmount(tokens[0], tokens[1], amount0);

        // Create amounts array.
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;

        // Execute the withdraw logic.
        _withdraw(id, pool, tokens, amounts, feeIndex);
    }

    /// @notice Claims received tokens from the pending balance and fees.
    /// @param user The address to claim the tokens for.
    /// @param tokens The tokens to claim for the user.
    /// @param id The ID of the pool to claim the tokens from.
    function claim(address user, address[] memory tokens, uint256 id) external whenClaimNotPaused nonReentrant {
        // Check that the pool exists.
        if (pools[id].router == address(0)) revert InvalidPool(id);

        // Check that the tokens array is not empty.
        if (tokens.length == 0) revert EmptyInput(tokens);

        // Check that the user is not the zero address.
        if (user == address(0)) revert ZeroAddress();

        // Fetch the pool router.
        VertexRouter router = VertexRouter(pools[id].router);

        // Loop over tokens and claim them if there is a pending balance and they are available.
        for (uint256 i = 0; i < tokens.length; i++) {
            // Fetch the user's pending balance. No danger if amount is 0.
            uint256 amount = pendingBalances[user][tokens[i]];

            // Fetch Elixir's pending fee balance.
            uint256 fee = fees[user][tokens[i]];

            // Resets the pending balance of the user.
            pendingBalances[user][tokens[i]] = 0;

            // Resets the Elixir pending fee balance.
            fees[user][tokens[i]] = 0;

            // Fetch the tokens from the Router.
            router.claimToken(tokens[i], amount + fee);

            // Transfers the tokens after to prevent reentrancy.
            IERC20Metadata(tokens[i]).safeTransfer(owner(), fee);
            IERC20Metadata(tokens[i]).safeTransfer(user, amount);
        }

        emit Claim(user, tokens);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL DEPOSIT/WITHDRAW LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal deposit logic for both spot and perp pools.
    /// @param id The id of the pool.
    /// @param pool The data of the pool to deposit.
    /// @param tokens The list of tokens to deposit.
    /// @param amounts The list of token amounts to deposit.
    /// @param receiver The receiver of the virtual LP balance.
    function _deposit(
        uint256 id,
        Pool storage pool,
        address[] memory tokens,
        uint256[] memory amounts,
        address receiver
    ) private {
        // TODO: What if the user tries to deposit two same tokens in the token array?

        // Fetch the router of the pool.
        VertexRouter router = VertexRouter(pool.router);

        // Loop over amounts to fetch and redirect tokens to Vertex.
        for (uint256 i = 0; i < amounts.length; i++) {
            // Get the token address.
            address token = tokens[i];
            // Get the token data.
            Token storage tokenData = pool.tokens[token];
            // Get the amount of token to deposit.
            uint256 amount = amounts[i];

            // Check that the token is supported in this pool.
            if (!tokenData.isActive) revert UnsupportedToken(token, id);

            // Check if the amount exceeds the token's pool hardcap.
            if (tokenData.activeAmount + amount > tokenData.hardcap) {
                revert HardcapReached(token, tokenData.hardcap, tokenData.activeAmount, amount);
            }

            // Transfer tokens from the caller to this contract.
            IERC20Metadata(token).safeTransferFrom(msg.sender, address(router), amount);

            // Create Vertex deposit payload request.
            IEndpoint.DepositCollateral memory depositPayload =
                IEndpoint.DepositCollateral(router.contractSubaccount(), tokenToProduct[token], uint128(amount));

            // Send deposit request to router.
            _sendTransaction(
                router, abi.encodePacked(uint8(IEndpoint.TransactionType.DepositCollateral), abi.encode(depositPayload))
            );

            // Add amount to the active market making balance of the user.
            tokenData.userActiveAmount[receiver] += amount;
            // Add amount to the active pool market making balance.
            tokenData.activeAmount += amount;
        }

        emit Deposit(msg.sender, receiver, id, tokens, amounts);
    }

    /// @notice Internal withdraw logic for both spot and perp pools.
    /// @param id The ID of the pool to withdraw from.
    /// @param pool The data of the pool to withdraw from.
    /// @param tokens The list of tokens to withdraw.
    /// @param amounts The list of token amounts to withdraw.
    /// @param feeIndex The index of the token list to apply to the withdrawal fee to.
    function _withdraw(
        uint256 id,
        Pool storage pool,
        address[] memory tokens,
        uint256[] memory amounts,
        uint256 feeIndex
    ) private {
        // Fetch the router of the pool.
        VertexRouter router = VertexRouter(pool.router);

        // Get the Vertex balances.
        uint256[] memory balances = getVertexBalances(router, tokens);

        // Loop over amounts and send withdraw requests to Vertex.
        for (uint256 i = 0; i < amounts.length; i++) {
            // Skip zero amounts if not fee index.
            if (amounts[i] == 0 && i != feeIndex) continue;

            // Get the token address.
            address token = tokens[i];
            // Get the token data.
            Token storage tokenData = pool.tokens[token];
            // Get the requested amount of token to withdraw.
            uint256 amount = amounts[i];

            // TODO: CHECK THAT TOKEN IS SUPPORTED BY POOL!!!

            // Calculate the amount to receive.
            uint256 amountToReceive = getWithdrawAmount(balances[i], amount, tokenData.activeAmount);

            // Substract requested amount from the active market making balance.
            tokenData.userActiveAmount[msg.sender] -= amount;

            // Substract requested amount from the active pool market making balance.
            tokenData.activeAmount -= amount;

            // Add amount to the user pending balance.
            if (i == feeIndex) {
                // Calculate the reimburse fee amount for the token.
                uint256 fee = getWithdrawFee(token);

                // Add fee to the Elixir balance.
                fees[msg.sender][token] += fee;

                pendingBalances[msg.sender][token] += (amountToReceive - fee);
            } else {
                pendingBalances[msg.sender][token] += amountToReceive;
            }

            // Create Vertex withdraw payload request.
            IEndpoint.WithdrawCollateral memory withdrawPayload = IEndpoint.WithdrawCollateral(
                router.contractSubaccount(), tokenToProduct[token], uint128(amountToReceive), 0
            );

            // Send withdraw requests to Vertex.
            _sendTransaction(
                router,
                abi.encodePacked(uint8(IEndpoint.TransactionType.WithdrawCollateral), abi.encode(withdrawPayload))
            );
        }

        // TODO: Check gas of below vs having it inside the loop.
        // // Get the fee token address as gas optimization.
        // address feeToken = tokens[feeIndex];

        // // Calculate the reimburse fee amount for the token.
        // uint256 fee = getWithdrawFee(feeToken);

        // // Add fee to the Elixir balance.
        // fees[msg.sender][feeToken] += fee;

        // // Substract from the user pending balance of the fee token.
        // pendingBalances[msg.sender][feeToken] -= fee;

        emit Withdraw(msg.sender, id, tokens, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the price on Vertex of a given by product.
    /// @param id The ID of the product to get the price of.
    function getPrice(uint32 id) public view returns (uint256) {
        return IClearinghouse(endpoint.clearinghouse()).getOraclePriceX18(id);
    }

    /// @notice Returns the data a pool and a token within it.
    /// @param id The ID of the pool supporting the token.
    /// @param token The token to fetch the data of.
    function getPool(uint256 id, address token) public view returns (address, uint256, uint256, bool) {
        // Get the pool data.
        Pool storage pool = pools[id];

        // Get the token data.
        Token storage tokenData = pool.tokens[token];

        return (pool.router, tokenData.activeAmount, tokenData.hardcap, tokenData.isActive);
    }

    /// @notice Returns the withdrawal fee for a given pool and token.
    /// @param token The token to fetch the fee from.
    function getWithdrawFee(address token) public view returns (uint256) {
        return slowModeFee.mulDiv(
            10 ** (18 + IERC20Metadata(token).decimals() - paymentToken.decimals()),
            getPrice(tokenToProduct[token]),
            Math.Rounding.Up
        );
    }

    /// @notice Returns a user's active amount for a token within a pool.
    /// @param id The ID of the pool to fetch the active amounts of.
    /// @param token The token to fetch the active amounts of.
    /// @param user The user to fetch the active amounts of.
    function getUserActiveAmount(uint256 id, address token, address user) public view returns (uint256) {
        return pools[id].tokens[token].userActiveAmount[user];
    }

    /// @notice Returns the pool balance of a product on Vertex.
    /// @param router The router of the pool.
    /// @param tokens The tokens to fetch the balance of.
    function getVertexBalances(VertexRouter router, address[] memory tokens)
        public
        returns (uint256[] memory balances)
    {
        // Set the balances length.
        balances = new uint256[](tokens.length);

        // Loop over tokens and get the balances.
        for (uint256 i = 0; i < tokens.length; i++) {
            // Get the token address.
            address token = tokens[i];

            // Get the token Vertex product ID.
            uint32 productId = tokenToProduct[token];

            // Get the Vertex balance fo the token by product.
            IEngine.Balance memory balance = IEngine(
                IClearinghouse(endpoint.clearinghouse()).getEngineByProduct(productId)
            ).getBalance(productId, router.contractSubaccount());

            // Format the balance back to the original decimals, as Vertex uses 18 decimals and rounds down.
            uint256 decimals = 10 ** (18 - IERC20Metadata(token).decimals());

            // Convert back to native decimals. Round up if the token has less than 18 decimals.
            tokenBalances[productId] =
                decimals == 1 ? uint256(balance.amount) : uint256(balance.amount).ceilDiv(decimals);
        }

        // Substract or add pending balance changes in Vertex sequencer queue.
        IEndpoint.SlowModeConfig memory queue = endpoint.slowModeConfig();

        // Loop over queue and check transaction to get the pending balance changes.
        for (uint64 i = queue.txUpTo; i < queue.txCount; i++) {
            // Fetch the transaction.
            (, address sender, bytes memory transaction) = endpoint.slowModeTxs(i);

            // Skip if the router is not the one given.
            if (sender != address(router)) continue;

            // Decode the transaction type.
            (uint8 txType, bytes memory payload) = this.decodeTx(transaction);

            // If the transaction is a withdraw, substract the amount from the balance.
            if (txType == uint8(IEndpoint.TransactionType.WithdrawCollateral)) {
                // Decode the withdraw payload.
                IEndpoint.WithdrawCollateral memory withdrawPayload =
                    abi.decode(payload, (IEndpoint.WithdrawCollateral));

                // Substract the amount from the token balance.
                tokenBalances[withdrawPayload.productId] -= withdrawPayload.amount;
            }
            // If the transaction is a deposit, add the amount to the balance.
            else if (txType == uint8(IEndpoint.TransactionType.DepositCollateral)) {
                // Decode the deposit payload.
                IEndpoint.DepositCollateral memory depositPayload = abi.decode(payload, (IEndpoint.DepositCollateral));

                // Add the amount to the token balance.
                tokenBalances[depositPayload.productId] += depositPayload.amount;
            } else {
                continue;
            }
        }

        // Convert the balances mapping to an array.
        for (uint256 i = 0; i < tokens.length; i++) {
            // Get the token Vertex product ID.
            uint32 productId = tokenToProduct[tokens[i]];

            // Add balance to array index.
            balances[i] = tokenBalances[productId];

            // Delete the balances mapping.
            delete tokenBalances[productId];
        }

        return balances;
    }

    /// @notice Returns the calculated amount of tokens to receive when withdrawing, given an amount of tokens and the pool balance on Vertex.
    /// @param balance The Vertex balance of the pool.
    /// @param amount The amount of tokens withdrawing.
    /// @param activeAmount The active amount of tokens in the pool.
    function getWithdrawAmount(uint256 balance, uint256 amount, uint256 activeAmount) public pure returns (uint256) {
        // Calculate the amount to receive via percentage of ownership, accounting for any trading losses.
        return amount.mulDiv(balance, activeAmount, Math.Rounding.Down);
    }

    /// @notice Returns the balanced amount of quote tokens given an amount of base tokens.
    /// @param token0 The base token.
    /// @param token1 The quote token.
    /// @param amount0 The amount of base tokens.
    function getBalancedAmount(address token0, address token1, uint256 amount0) public view returns (uint256) {
        return amount0.mulDiv(
            getPrice(tokenToProduct[address(token0)]),
            10 ** (18 + (IERC20Metadata(token0).decimals() - IERC20Metadata(token1).decimals())),
            Math.Rounding.Down
        );
    }

    /// @notice Returns the type and payload of a Vertex slow-mode transaction.
    /// @param transaction The transaction to decode.
    function decodeTx(bytes calldata transaction) public pure returns (uint8, bytes memory) {
        return (uint8(transaction[0]), transaction[1:]);
    }

    /// @notice Returns true if the given amounts of base and quote tokes are balanced.
    /// @param tokens The list of tokens to check the balance of. First item must be the base and the second the quote.
    /// @param amounts The list of amounts to check the balance of. First item msut be the base amount and the second the quote amount.
    function checkBalanced(address[] memory tokens, uint256[] memory amounts) public view returns (bool) {
        // Get the price of the product on Vertex and calculate the expected quote amount, rounding down.
        return getBalancedAmount(tokens[0], tokens[1], amounts[0]) == amounts[1];
    }

    /*//////////////////////////////////////////////////////////////
                        VERTEX SLOW TRANSACTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Sends a slow mode transaction to the pool Router.
    /// @param router The pool Router.
    /// @param transaction The transaction to submit.
    function _sendTransaction(VertexRouter router, bytes memory transaction) internal {
        // Deposit collateral doens't have fees.
        if (uint8(transaction[0]) != uint8(IEndpoint.TransactionType.DepositCollateral)) {
            // Fetch payment fee from owner. This can be reimbursed on withdrawals after tokens are received.
            paymentToken.safeTransferFrom(owner(), address(router), slowModeFee);
        }

        router.submitSlowModeTransaction(transaction);
    }

    /*//////////////////////////////////////////////////////////////
                          PERMISSIONED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Manages the paused status of deposits, withdrawals, and claims
    /// @param _depositPaused True to pause deposits, false otherwise.
    /// @param _withdrawPaused True to pause withdrawals, false otherwise.
    /// @param _claimPaused True to pause claims, false otherwise.
    function pause(bool _depositPaused, bool _withdrawPaused, bool _claimPaused) external onlyOwner {
        depositPaused = _depositPaused;
        withdrawPaused = _withdrawPaused;
        claimPaused = _claimPaused;

        emit PauseUpdated(depositPaused, withdrawPaused, claimPaused);
    }

    /// @notice Adds a new pool.
    /// @dev ID should match Vertex's.
    /// @param id The ID of the new pool.
    /// @param tokens The tokens to add.
    /// @param hardcaps The hardcaps for the tokens.
    /// @param poolType The type of the pool.
    /// @param externalAccount The external account to link to the Vertex Endpoint.
    function addPool(
        uint256 id,
        address[] memory tokens,
        uint256[] memory hardcaps,
        PoolType poolType,
        address externalAccount
    ) external onlyOwner {
        // Check that the pool is not already added.
        if (pools[id].router != address(0)) revert InvalidPool(id);

        // Check that the tokens are not duplicated.
        // TODO: Add better errors.
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = i + 1; j < tokens.length; j++) {
                if (tokens[i] == tokens[j]) revert InvalidLength(new uint256[](0), tokens);
            }
        }

        // Deploy a new Router contract.
        VertexRouter router = new VertexRouter(address(endpoint), externalAccount);

        // Approve the fee token to the Router.
        router.makeApproval(address(paymentToken));

        // Create LinkSigner request for Vertex.
        IEndpoint.LinkSigner memory linkSigner =
            IEndpoint.LinkSigner(router.contractSubaccount(), router.externalSubaccount(), 0);

        // Send LinkSigner request to Router.
        _sendTransaction(router, abi.encodePacked(uint8(IEndpoint.TransactionType.LinkSigner), abi.encode(linkSigner)));

        // Set the Router address of the pool.
        pools[id].router = address(router);

        // Set the pool type.
        pools[id].poolType = poolType;

        // Add tokens to pool.
        addPoolTokens(id, tokens, hardcaps);

        emit PoolAdded(id, poolType, address(router), tokens, hardcaps);
    }

    /// @notice Adds new tokens to a pool.
    /// @param id The ID of the pool.
    /// @param tokens The tokens to add.
    /// @param hardcaps The hardcaps for the tokens.
    function addPoolTokens(uint256 id, address[] memory tokens, uint256[] memory hardcaps) public onlyOwner {
        // Fetch the pool Router.
        VertexRouter router = VertexRouter(pools[id].router);

        // Loop over tokens to add.
        for (uint256 i = 0; i < tokens.length; i++) {
            // Get the token address.
            address token = tokens[i];

            // Check that the token decimals are below the Vertex maximum.
            if (IERC20Metadata(token).decimals() > 18) revert InvalidToken(token);

            // Fetch the token data storage within the pool.
            Token storage tokenData = pools[id].tokens[token];

            // Add the hardcap to the token data.
            tokenData.hardcap = hardcaps[i];

            // Enable the token support.
            tokenData.isActive = true;

            // Make router approve tokens to Vertex endpoint.
            router.makeApproval(token);
        }

        emit PoolTokensAdded(id, tokens, hardcaps);
    }

    /// @notice Updates the hardcaps of a pool.
    /// @param id The ID of the pool.
    /// @param tokens The list of tokens to update the hardcaps of.
    /// @param hardcaps The hardcaps for the tokens.
    function updatePoolHardcaps(uint256 id, address[] memory tokens, uint256[] memory hardcaps) external onlyOwner {
        // Check that the length of the hardcaps array matches the pool tokens length.
        // TODO: Do similar checks like in deposit, where hardcaps cannot be 0 nor tokens and that they match
        if (hardcaps.length != tokens.length) revert InvalidLength(hardcaps, tokens);

        // Loop over hardcaps to update.
        for (uint256 i = 0; i < hardcaps.length; i++) {
            pools[id].tokens[tokens[i]].hardcap = hardcaps[i];
        }

        emit PoolHardcapsUpdated(id, hardcaps);
    }

    /// @notice Updates the product ID of a token address.
    /// @param token The token to update.
    /// @param productId The new Vertex product ID to represent this token.
    function updateToken(address token, uint32 productId) external onlyOwner {
        // Update the token to product ID mapping.
        tokenToProduct[token] = productId;

        emit TokenUpdated(token, productId);
    }

    /// @notice Updates the Vertex slow mode fee.
    /// @param newFee The new fee.
    function updateSlowModeFee(uint256 newFee) external onlyOwner {
        // Check that the new fee is no more than 100 USDC.
        if (newFee > 100000000) revert FeeTooHigh(newFee);

        slowModeFee = newFee;

        emit SlowModeFeeUpdated(newFee);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Upgrades the implementation of the proxy to new address.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
