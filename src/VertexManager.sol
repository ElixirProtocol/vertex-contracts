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
        Inactive,
        Spot,
        Perp
    }

    /// @notice The types of spots supported by this contract.
    enum SpotType {
        DepositSpot,
        WithdrawPerp
    }

    /// @notice The structure for spot deposits to be processed by Elixir.
    struct DepositSpot {
        // The ID of the pool.
        uint256 id;
        // The router address of the pool.
        address router;
        // The token0 address.
        address token0;
        // The token1 address.
        address token1;
        // The amount of token0 to deposit.
        uint256 amount0;
        // The low limit of token1 to deposit.
        uint256 amount1Low;
        // The high limit of token1 to deposit.
        uint256 amount1High;
        // The receiver of the virtual LP balance.
        address receiver;
    }

    /// @notice The structure of perp withdrawals to be processed by Elixir.
    struct WithdrawPerp {
        // The ID of the pool.
        uint256 id;
        // The router address of the pool.
        address router;
        // The Vertex product ID of the token.
        uint32 tokenId;
        // The amount of token shares to withdraw.
        uint256 amount;
    }

    /// @notice The data structure of pools.
    struct Pool {
        // The router address of the pool.
        address router;
        // The pool type. True for spot, false for perp.
        PoolType poolType;
        // The data of the supported tokens in the pool.
        mapping(address token => Token data) tokens;
    }

    /// @notice The data structure of tokens.
    struct Token {
        // The active market making balance of users for a token within a pool.
        mapping(address user => uint256 balance) userActiveAmount;
        // The pending amounts of users for a token within a pool.
        mapping(address user => uint256 amount) userPendingAmount;
        // The pending fees of a token within a pool.
        mapping(address user => uint256 amount) fees;
        // The total active amounts of a token within a pool.
        uint256 activeAmount;
        // The hardcap of the token within a pool.
        uint256 hardcap;
        // The status of the token within a pool. True if token is supported.
        bool isActive;
    }

    /// @notice The data structure of queue spots.
    struct Spot {
        // The sender of the withdrawal.
        address sender;
        // The transaction to process.
        bytes transaction;
    }

    /// @notice The pools managed given an ID.
    mapping(uint256 id => Pool pool) public pools;

    /// @notice The Vertex product IDs of token addresses.
    mapping(address token => uint32 id) public tokenToProduct;

    /// @notice The token addresses of Vertex product IDs.
    mapping(uint32 id => address token) public productToToken;

    /// @notice The queue for Elixir to process.
    mapping(uint128 => Spot) public queue;

    /// @notice The queue count.
    uint128 public queueCount;

    /// @notice The queue up to.
    uint128 public queueUpTo;

    /// @notice The Vertex slow mode fee.
    uint256 public slowModeFee = 1000000;

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
    /// @param receiver The receiver of the LP balance.
    /// @param id The ID of the pool deposting to.
    /// @param token The token deposited.
    /// @param amount The token amount deposited.
    event Deposit(address indexed caller, address indexed receiver, uint256 indexed id, address token, uint256 amount);

    /// @notice Emitted when a withdraw is made.
    /// @param user The user who withdrew.
    /// @param router The router of the pool withdrawn from.
    /// @param tokenId The Vertex product ID of the token withdrawn.
    /// @param amount The token amount the user receives.
    event Withdraw(address indexed user, address indexed router, uint32 tokenId, uint256 indexed amount);

    /// @notice Emitted when a perp withdrawal is queued.
    /// @param spot The spot added to the queue.
    /// @param queueCount The queue count.
    /// @param queueUpTo The queue up to.
    event Queued(Spot spot, uint128 queueCount, uint128 queueUpTo);

    /// @notice Emitted when a claim is made.
    /// @param user The user for which the tokens were claimed.
    /// @param token The token claimed.
    /// @param amount The token amount claimed.
    event Claim(address indexed user, address indexed token, uint256 indexed amount);

    /// @notice Emitted when the pause statuses are updated.
    /// @param depositPaused True if deposits are paused, false otherwise.
    /// @param withdrawPaused True if withdrawals are paused, false otherwise.
    /// @param claimPaused True if claims are paused, false otherwise.
    event PauseUpdated(bool indexed depositPaused, bool indexed withdrawPaused, bool indexed claimPaused);

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
    /// @param hardcaps The hardcaps of the added tokens.
    event PoolTokensAdded(uint256 indexed id, address[] tokens, uint256[] hardcaps);

    /// @notice Emitted when a pool's hardcaps are updated.
    /// @param id The ID of the pool.
    /// @param hardcaps The new hardcaps of the pool.
    event PoolHardcapsUpdated(uint256 indexed id, uint256[] hardcaps);

    /// @notice Emitted when the Vertex product ID of a token is updated.
    /// @param token The token address.
    /// @param productId The new Vertex product ID of the token.
    event TokenUpdated(address indexed token, uint256 indexed productId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the receiver is the zero address.
    error ZeroAddress();

    /// @notice Emitted when a token is duplicated.
    /// @param token The duplicated token.
    error DuplicatedToken(address token);

    /// @notice Emitted when a token is already supported.
    /// @param token The token address.
    /// @param id The ID of the pool.
    error AlreadySupported(address token, uint256 id);

    /// @notice Emitted when the fee index is not outside the range.
    /// @param index The index input.
    /// @param array The array input.
    error InvalidFeeIndex(uint256 index, address[] array);

    /// @notice Emitted when deposits are paused.
    error DepositsPaused();

    /// @notice Emitted when withdrawals are paused.
    error WithdrawalsPaused();

    /// @notice Emitted when claims are paused.
    error ClaimsPaused();

    /// @notice Emitted when the length of two arrays don't match.
    /// @param array1 The uint256 array input.
    /// @param array2 The address array input.
    error MismatchInputs(uint256[] array1, address[] array2);

    /// @notice Emitted when the hardcap of a pool would be exceeded.
    /// @param token The token address being deposited.
    /// @param hardcap The hardcap of the pool given the token.
    /// @param activeAmount The active amount of tokens in the pool.
    /// @param amount The amount of tokens being deposited.
    error HardcapReached(address token, uint256 hardcap, uint256 activeAmount, uint256 amount);

    /// @notice Emitted when the slippage is too high.
    /// @param amount The amount of tokens given.
    /// @param amountLow The low limit of token amounts.
    /// @param amountHigh The high limit of token amounts.
    error SlippageTooHigh(uint256 amount, uint256 amountLow, uint256 amountHigh);

    /// @notice Emitted when the pool is not valid or used in the incorrect function.
    /// @param id The ID of the pool.
    error InvalidPool(uint256 id);

    /// @notice Emitted when a token is not supported for a pool.
    /// @param token The address of the unsupported token.
    /// @param id The ID of the pool.
    error UnsupportedToken(address token, uint256 id);

    /// @notice Emitted when the token is not valid because it has more than 18 decimals.
    /// @param token The address of the token.
    error InvalidToken(address token);

    /// @notice Emitted when the tokens array length is not two.
    /// @param tokens The tokens array input.
    error InvalidTokens(address[] tokens);

    /// @notice Emitted when the new fee is above 100 USDC.
    /// @param newFee The new fee.
    error FeeTooHigh(uint256 newFee);

    /// @notice Emitted when the amount given to withdraw is less than the fee to pay.
    /// @param amount The amount given to withdraw.
    /// @param fee The fee to pay.
    error AmountTooLow(uint256 amount, uint256 fee);

    /// @notice Emitted when the given spot ID to unqueue is not valid.
    error InvalidSpot(uint128 spotId, uint128 queueUpTo);

    /// @notice Emitted when the caller is not the external account of the pool's router.
    error NotExternalAccount(address router, address externalAccount, address caller);

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

        // Set the slow mode fee.
        slowModeFee = _slowModeFee;

        // Set the payment token for slow-mode transactions through Vertex.
        paymentToken = IERC20Metadata(IClearinghouse(endpoint.clearinghouse()).getQuote());
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL ENTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit a token into a perp pool.
    /// @param id The pool ID.
    /// @param token The token to deposit.
    /// @param amount The token amount to deposit.
    /// @param receiver The receiver of the virtual LP balance.
    function depositPerp(uint256 id, address token, uint256 amount, address receiver)
        external
        whenDepositNotPaused
        nonReentrant
    {
        // Fetch the pool storage.
        Pool storage pool = pools[id];

        // Check that the pool is perp.
        if (pool.poolType != PoolType.Perp) revert InvalidPool(id);

        // Check that the receiver is not the zero address.
        if (receiver == address(0)) revert ZeroAddress();

        // Execute the deposit logic.
        _deposit(id, pool, token, amount, receiver);
    }

    /// @notice Deposits tokens into a spot pool.
    /// @param id The ID of the pool to deposit.
    /// @param token0 The base token.
    /// @param token1 The quote token.
    /// @param amount0 The amount of base tokens.
    /// @param amount1Low The low limit of the quote token amount.
    /// @param amount1High The high limit of the quote token amount.
    /// @param receiver The receiver of the virtual LP balance.
    function depositSpot(
        uint256 id,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1Low,
        uint256 amount1High,
        address receiver
    ) external whenDepositNotPaused nonReentrant {
        // Fetch the pool storage.
        Pool storage pool = pools[id];

        // Check that the pool is spot.
        if (pool.poolType != PoolType.Spot) revert InvalidPool(id);

        // Check that the tokens are not duplicated.
        if (token0 == token1) revert DuplicatedToken(token0);

        // Check that the receiver is not the zero address.
        if (receiver == address(0)) revert ZeroAddress();

        // bytes memory encodedTx = abi.encode(txn);
        bytes memory transaction = abi.encodePacked(
            uint8(SpotType.DepositSpot),
            abi.encode(
                DepositSpot({
                    id: id,
                    router: pool.router,
                    token0: token0,
                    token1: token1,
                    amount0: amount0,
                    amount1Low: amount1Low,
                    amount1High: amount1High,
                    receiver: receiver
                })
            )
        );

        // Add to queue.
        queue[queueCount++] = Spot(msg.sender, transaction);

        emit Queued(queue[queueCount], queueCount, queueUpTo);
    }

    /// @notice Requests to withdraw a token from a perp pool.
    /// @dev Requests are placed into a FIFO queue, which is processed by the Elixir market-making network and passed on to Vertex via the `unqueue` function.
    /// @dev After processed by Vertex, the user (or anyone on behalf of it) can call the `claim` function.
    /// @param id The ID of the pool to withdraw from.
    /// @param token The token to withdraw.
    /// @param amount The amount of token shares to withdraw.
    function withdrawPerp(uint256 id, address token, uint256 amount) external whenWithdrawNotPaused nonReentrant {
        // Fetch the pool storage.
        Pool storage pool = pools[id];

        // Check that the pool is perp.
        if (pool.poolType != PoolType.Perp) revert InvalidPool(id);

        // Get the token storage.
        Token storage tokenData = pool.tokens[token];

        // Check that the token is supported by the pool.
        if (!tokenData.isActive) revert UnsupportedToken(token, id);

        // Check that the amount is at least the fee to pay.
        if (amount < getWithdrawFee(token)) revert AmountTooLow(amount, getWithdrawFee(token));

        // Substract amount from the active market making balance of the caller.
        tokenData.userActiveAmount[msg.sender] -= amount;

        // Substract amount from the active pool market making balance.
        tokenData.activeAmount -= amount;

        bytes memory transaction = abi.encodePacked(
            uint8(SpotType.WithdrawPerp),
            abi.encode(WithdrawPerp({id: id, router: pool.router, tokenId: tokenToProduct[token], amount: amount}))
        );

        // Add to queue.
        queue[queueCount++] = Spot(msg.sender, transaction);

        emit Queued(queue[queueCount], queueCount, queueUpTo);
    }

    /// @notice Withdraws tokens from a spot pool.
    /// @dev After processed by Vertex, the user (or anyone on behalf of it) can call the `claim` function.
    /// @param id The ID of the pool to withdraw from.
    /// @param tokens The tokens to withdraw.
    /// @param amount0 The amount of base tokens.
    /// @param feeIndex The index of the token list to apply to the withdrawal fee to.
    function withdrawSpot(uint256 id, address[] calldata tokens, uint256 amount0, uint256 feeIndex)
        external
        whenWithdrawNotPaused
        nonReentrant
    {
        // Fetch the pool data.
        Pool storage pool = pools[id];

        // Check that the pool is spot.
        if (pool.poolType != PoolType.Spot) revert InvalidPool(id);

        // Check that the tokens array only includes two tokens.
        if (tokens.length != 2) revert InvalidTokens(tokens);

        // Check that the tokens are not duplicated.
        if (tokens[0] == tokens[1]) revert DuplicatedToken(tokens[0]);

        // Check that the feeIndex is within the tokens array.
        if (feeIndex >= tokens.length) revert InvalidFeeIndex(feeIndex, tokens);

        // Get the balanced amount of quote tokens.
        uint256 amount1 = getBalancedAmount(tokens[0], tokens[1], amount0);

        // Fetch the router of the pool.
        VertexRouter router = VertexRouter(pool.router);

        // Get the Vertex balances.
        uint256[] memory balances = getUpdatedVertexBalances(router, getCurrentVertexBalances(router, tokens), tokens);

        // Loop over amounts and send withdraw requests to Vertex.
        for (uint256 i = 0; i < tokens.length; i++) {
            // Get the token address.
            address token = tokens[i];

            // Get the token data.
            Token storage tokenData = pool.tokens[token];

            // Check that the token is supported in this pool.
            if (!tokenData.isActive) revert UnsupportedToken(token, id);

            // Get the requested amount of token to withdraw.
            uint256 amount = i == 0 ? amount0 : amount1;

            // Calculate the amount to receive.
            uint256 amountToReceive = getWithdrawAmount(balances[i], amount, tokenData.activeAmount);

            // Substract requested amount from the active market making balance.
            tokenData.userActiveAmount[msg.sender] -= amount;

            // Substract requested amount from the active pool market making balance.
            tokenData.activeAmount -= amount;

            // Execute the withdraw logic.
            _withdraw(
                tokenData,
                msg.sender,
                i == feeIndex ? getWithdrawFee(token) : 0,
                tokenToProduct[token],
                amountToReceive,
                router
            );
        }
    }

    /// @notice Claim received tokens from the pending balance and fees.
    /// @param user The address to claim for.
    /// @param token The token to claim.
    /// @param id The ID of the pool to claim from.
    function claim(address user, address token, uint256 id) external whenClaimNotPaused nonReentrant {
        // Fetch the pool data.
        Pool storage pool = pools[id];

        // Check that the pool exists.
        if (pool.router == address(0)) revert InvalidPool(id);

        // Check that the user is not the zero address.
        if (user == address(0)) revert ZeroAddress();

        // Fetch the pool router.
        VertexRouter router = VertexRouter(pool.router);

        // Get the token data.
        Token storage tokenData = pool.tokens[token];

        // Fetch the user's pending balance. No danger if amount is 0.
        uint256 amount = tokenData.userPendingAmount[user];

        // Fetch Elixir's pending fee balance.
        uint256 fee = tokenData.fees[user];

        // Resets the pending balance of the user.
        tokenData.userPendingAmount[user] = 0;

        // Resets the Elixir pending fee balance.
        tokenData.fees[user] = 0;

        // Fetch the tokens from the router.
        router.claimToken(token, amount + fee);

        // Transfers the tokens after to prevent reentrancy.
        IERC20Metadata(token).safeTransfer(owner(), fee);
        IERC20Metadata(token).safeTransfer(user, amount);

        emit Claim(user, token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL DEPOSIT/WITHDRAW LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal deposit logic for both spot and perp pools.
    /// @param id The id of the pool.
    /// @param pool The data of the pool to deposit.
    /// @param token The tokens to deposit.
    /// @param amount The amounts of token to deposit.
    /// @param receiver The receiver of the virtual LP balance.
    function _deposit(uint256 id, Pool storage pool, address token, uint256 amount, address receiver) private {
        // Fetch the router of the pool.
        VertexRouter router = VertexRouter(pool.router);

        // Get the token data.
        Token storage tokenData = pool.tokens[token];

        // Check that the token is supported in this pool.
        if (!tokenData.isActive) revert UnsupportedToken(token, id);

        // Check if the amount exceeds the token's pool hardcap.
        if (tokenData.activeAmount + amount > tokenData.hardcap) {
            revert HardcapReached(token, tokenData.hardcap, tokenData.activeAmount, amount);
        }

        // Transfer tokens from the caller to this contract.
        IERC20Metadata(token).safeTransferFrom(msg.sender, address(router), amount);

        // Deposit funds to Vertex through router.
        router.submitSlowModeDeposit(tokenToProduct[token], uint128(amount), "9O7rUEUljP");

        // Add amount to the active market making balance of the user.
        tokenData.userActiveAmount[receiver] += amount;

        // Add amount to the active pool market making balance.
        tokenData.activeAmount += amount;

        emit Deposit(msg.sender, receiver, id, token, amount);
    }

    /// @notice Internal withdraw logic for both spot and perp pools.
    /// @param tokenData The data of the token to withdraw.
    /// @param sender The sender of the withdraw.
    /// @param fee The fee to pay.
    /// @param tokenId The Vertex product ID of the token to withdraw.
    /// @param amountToReceive The amount of tokens the user receives.
    /// @param router The router of the pool.
    function _withdraw(
        Token storage tokenData,
        address sender,
        uint256 fee,
        uint32 tokenId,
        uint256 amountToReceive,
        VertexRouter router
    ) private {
        // Add fee to the Elixir balance.
        tokenData.fees[sender] += fee;

        // Update the user pending balance.
        tokenData.userPendingAmount[sender] += (amountToReceive - fee);

        // Create Vertex withdraw payload request.
        IEndpoint.WithdrawCollateral memory withdrawPayload =
            IEndpoint.WithdrawCollateral(router.contractSubaccount(), tokenId, uint128(amountToReceive), 0);

        // Send withdraw requests to Vertex.
        _sendTransaction(
            router, abi.encodePacked(uint8(IEndpoint.TransactionType.WithdrawCollateral), abi.encode(withdrawPayload))
        );

        emit Withdraw(sender, address(router), tokenId, amountToReceive);
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
    function getPoolToken(uint256 id, address token) external view returns (address, uint256, uint256, bool) {
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
    function getUserActiveAmount(uint256 id, address token, address user) external view returns (uint256) {
        return pools[id].tokens[token].userActiveAmount[user];
    }

    /// @notice Returns a user's pending amount for a token within a pool.
    /// @param id The ID of the pool to fetch the pending amount of.
    /// @param token The token to fetch the pending amount of.
    /// @param user The user to fetch the pending amount of.
    function getUserPendingAmount(uint256 id, address token, address user) external view returns (uint256) {
        return pools[id].tokens[token].userPendingAmount[user];
    }

    /// @notice Returns a user's reimbursement fee for a token within a pool.
    /// @param id The ID of the pool to fetch the fee for.
    /// @param token The token to fetch the fee for.
    /// @param user The user to fetch the fee for.
    function getUserFee(uint256 id, address token, address user) external view returns (uint256) {
        return pools[id].tokens[token].fees[user];
    }

    /// @notice Fetches the current Vertex balances of a pool.
    /// @param router The router of the pool.
    /// @param tokens The tokens to fetch the balances of.
    function getCurrentVertexBalances(VertexRouter router, address[] memory tokens)
        public
        view
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
            balances[i] = decimals == 1 ? uint256(balance.amount) : uint256(balance.amount).ceilDiv(decimals);
        }
    }

    /// @notice Fetches the updated Vertex balance of a pool.
    /// @param router The router of the pool.
    /// @param balances The balances to update.
    /// @param tokens The tokens to get the updated balances of.
    function getUpdatedVertexBalances(VertexRouter router, uint256[] memory balances, address[] memory tokens)
        public
        view
        returns (uint256[] memory)
    {
        // Substract or add pending balance changes in Vertex sequencer queue.
        IEndpoint.SlowModeConfig memory vertexQueue = endpoint.slowModeConfig();

        // Loop over queue and check transaction to get the pending balance changes.
        for (uint64 i = vertexQueue.txUpTo; i < vertexQueue.txCount; i++) {
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

                // Get the token address from the product ID.
                address token = productToToken[withdrawPayload.productId];

                // Substract from balance if this is a token the user wants to withdraw.
                for (uint256 j = 0; j < tokens.length; j++) {
                    // Break the loop when the token is found.
                    if (token == tokens[j]) {
                        balances[j] -= withdrawPayload.amount;
                        break;
                    }
                }
            }
            // If the transaction is a deposit, add the amount to the balance.
            else if (txType == uint8(IEndpoint.TransactionType.DepositCollateral)) {
                // Decode the deposit payload.
                IEndpoint.DepositCollateral memory depositPayload = abi.decode(payload, (IEndpoint.DepositCollateral));

                // Get the token address from the product ID.
                address token = productToToken[depositPayload.productId];

                // Add to balance if this is a token the user wants to deposit.
                for (uint256 j = 0; j < tokens.length; j++) {
                    // Break the loop when the token is found.
                    if (token == tokens[j]) {
                        balances[j] += depositPayload.amount;
                        break;
                    }
                }
            } else {
                continue;
            }
        }

        return balances;
    }

    /// @notice Returns the balanced amount of quote tokens given an amount of base tokens.
    /// @param token0 The base token.
    /// @param token1 The quote token.
    /// @param amount0 The amount of base tokens.
    function getBalancedAmount(address token0, address token1, uint256 amount0) public view returns (uint256) {
        return amount0.mulDiv(
            (getPrice(tokenToProduct[token0]) * (10 ** 18)) / getPrice(tokenToProduct[token1]),
            10 ** (18 + IERC20Metadata(token0).decimals() - IERC20Metadata(token1).decimals()),
            Math.Rounding.Down
        );
    }

    /// @notice Returns the calculated amount of tokens to receive when withdrawing, given an amount of tokens and the pool balance on Vertex.
    /// @param balance The Vertex balance of the pool.
    /// @param amount The amount of tokens withdrawing.
    /// @param activeAmount The active amount of tokens in the pool.
    function getWithdrawAmount(uint256 balance, uint256 amount, uint256 activeAmount) public pure returns (uint256) {
        // Calculate the amount to receive via percentage of ownership, accounting for any trading losses.
        return amount.mulDiv(balance, activeAmount, Math.Rounding.Down);
    }

    /// @notice Returns the next spot in the queue to process.
    function nextSpot() external view returns (Spot memory) {
        return queue[queueUpTo];
    }

    /// @notice Returns the type and payload of a Vertex slow-mode transaction.
    /// @param transaction The transaction to decode.
    function decodeTx(bytes calldata transaction) public pure returns (uint8, bytes memory) {
        return (uint8(transaction[0]), transaction[1:]);
    }

    /// @notice Reverts if the caller is not the router's external account.
    /// @param router The router to check against.
    function checkCaller(address router) private view {
        // Get the external account of the router.
        address externalAccount = address(uint160(bytes20(VertexRouter(router).externalSubaccount())));

        // Check that the sender is the external account of the router.
        if (msg.sender != externalAccount) revert NotExternalAccount(router, externalAccount, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        VERTEX SLOW TRANSACTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Forward a slow mode transaction to the pool router.
    /// @param router The pool router.
    /// @param transaction The transaction to forward.
    function _sendTransaction(VertexRouter router, bytes memory transaction) private {
        // Fetch payment fee from owner. This can be reimbursed on withdrawals after tokens are received.
        paymentToken.safeTransferFrom(owner(), address(router), slowModeFee);

        // Submit slow-mode tx to Vertex.
        router.submitSlowModeTransaction(transaction);
    }

    /*//////////////////////////////////////////////////////////////
                          PERMISSIONED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes the next spot in the withdraw perp queue.
    /// @param spotId The ID of the spot queue to process.
    /// @param amountToReceive The amount the user should receive from the withdraw.
    function unqueue(uint128 spotId, uint256 amountToReceive) external {
        // Check that next spot in queue matches the given spot ID.
        if (spotId != queueUpTo + 1) revert InvalidSpot(spotId, queueUpTo);

        // Get the spot data from the queue.
        Spot memory spot = queue[queueUpTo];

        // Get the type of transaction of the spot.
        // SpotType spotType = SpotType(uint8(spot.transaction[0]));

        // Decode the spot.
        (uint8 spotType, bytes memory spotTx) = this.decodeTx(spot.transaction);

        if (spotType == uint8(SpotType.DepositSpot)) {
            DepositSpot memory txn = abi.decode(spotTx, (DepositSpot));

            checkCaller(txn.router);

            // TODO: DepositSpot logic
        } else if (spotType == uint8(SpotType.WithdrawPerp)) {
            WithdrawPerp memory txn = abi.decode(spotTx, (WithdrawPerp));

            checkCaller(txn.router);

            // Get the token address.
            address token = productToToken[txn.tokenId];

            // Get the token data.
            Token storage tokenData = pools[txn.id].tokens[token];

            // Skip/revert the spot if the amount is not enough to pay the fee.
            if (amountToReceive < getWithdrawFee(token)) {
                // Add amount from the active market making balance of the spot sender.
                tokenData.userActiveAmount[spot.sender] += txn.amount;

                // Add amount from the active pool market making balance.
                tokenData.activeAmount += txn.amount;
            } else {
                // Execute the withdraw logic.
                _withdraw(
                    tokenData,
                    spot.sender,
                    getWithdrawFee(token),
                    txn.tokenId,
                    amountToReceive,
                    VertexRouter(txn.router)
                );
            }
        } else {
            revert("Invalid transaction type");
        }

        // Increase the queue up to.
        queueUpTo++;
    }

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
    /// @param id The ID of the new pool.
    /// @param tokens The tokens to add.
    /// @param hardcaps The hardcaps for the tokens.
    /// @param poolType The type of the pool.
    /// @param externalAccount The external account to link to the Vertex Endpoint.
    function addPool(
        uint256 id,
        address[] calldata tokens,
        uint256[] calldata hardcaps,
        PoolType poolType,
        address externalAccount
    ) external onlyOwner {
        // Check that the pool doesn't exist.
        if (pools[id].router != address(0)) revert InvalidPool(id);

        // Deploy a new router contract.
        VertexRouter router = new VertexRouter(address(endpoint), externalAccount);

        // Approve the fee token to the router.
        router.makeApproval(address(paymentToken));

        // Create LinkSigner request for Vertex.
        IEndpoint.LinkSigner memory linkSigner =
            IEndpoint.LinkSigner(router.contractSubaccount(), router.externalSubaccount(), 0);

        // Send LinkSigner request to router.
        _sendTransaction(router, abi.encodePacked(uint8(IEndpoint.TransactionType.LinkSigner), abi.encode(linkSigner)));

        // Set the router address of the pool.
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
    function addPoolTokens(uint256 id, address[] calldata tokens, uint256[] calldata hardcaps) public onlyOwner {
        // Fetch the pool router.
        VertexRouter router = VertexRouter(pools[id].router);

        // Loop over tokens to add.
        for (uint256 i = 0; i < tokens.length; i++) {
            // Get the token address.
            address token = tokens[i];

            // Check that the token decimals are below or equal to 18 decimals (Vertex maximum).
            if (IERC20Metadata(token).decimals() > 18) revert InvalidToken(token);

            // Fetch the token data storage within the pool.
            Token storage tokenData = pools[id].tokens[token];

            // Check if the token is already supported, and enable if not.
            if (!tokenData.isActive) {
                tokenData.isActive = true;
            } else {
                revert AlreadySupported(token, id);
            }

            // Add the hardcap to the token data.
            tokenData.hardcap = hardcaps[i];

            // Make router approve tokens to Vertex endpoint.
            router.makeApproval(token);
        }

        emit PoolTokensAdded(id, tokens, hardcaps);
    }

    /// @notice Updates the hardcaps of a pool.
    /// @param id The ID of the pool.
    /// @param tokens The list of tokens to update the hardcaps of.
    /// @param hardcaps The hardcaps for the tokens.
    function updatePoolHardcaps(uint256 id, address[] calldata tokens, uint256[] calldata hardcaps)
        external
        onlyOwner
    {
        // Check that the length of the hardcaps array matches the pool tokens length.
        if (hardcaps.length != tokens.length) revert MismatchInputs(hardcaps, tokens);

        // Loop over hardcaps to update.
        for (uint256 i = 0; i < hardcaps.length; i++) {
            pools[id].tokens[tokens[i]].hardcap = hardcaps[i];
        }

        emit PoolHardcapsUpdated(id, hardcaps);
    }

    /// @notice Updates the Vertex product ID of a token address.
    /// @param token The token to update.
    /// @param productId The new Vertex product ID to represent this token.
    function updateToken(address token, uint32 productId) external onlyOwner {
        // Update the token to product ID and opposite direction mapping.
        tokenToProduct[token] = productId;
        productToToken[productId] = token;

        emit TokenUpdated(token, productId);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Upgrades the implementation of the proxy to new address.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
