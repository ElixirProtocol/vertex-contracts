// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

import {IVertexManager} from "src/interfaces/IVertexManager.sol";
import {IEndpoint} from "src/interfaces/IEndpoint.sol";
import {IClearinghouse} from "src/interfaces/IClearinghouse.sol";

import {VertexProcessor} from "src/VertexProcessor.sol";
import {VertexStorage} from "src/VertexStorage.sol";
import {VertexRouter} from "src/VertexRouter.sol";

/// @title Elixir pool manager for Vertex
/// @author The Elixir Team
/// @custom:security-contact security@elixir.finance
/// @notice Pool manager contract to provide liquidity for spot and perp market making on Vertex Protocol.
contract VertexManager is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard, VertexStorage {
    using Math for uint256;
    using SafeERC20 for IERC20Metadata;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

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

    /// @notice Emitted when the pool is not valid or used in the incorrect function.
    /// @param id The ID of the pool.
    error InvalidPool(uint256 id);

    /// @notice Emitted when the token is not valid because it has more than 18 decimals.
    /// @param token The address of the token.
    error InvalidToken(address token);

    /// @notice Emitted when the amount given to withdraw is less than the fee to pay.
    /// @param amount The amount given to withdraw.
    /// @param fee The fee to pay.
    error AmountTooLow(uint256 amount, uint256 fee);

    /// @notice Emitted when the given spot ID to unqueue is not valid.
    error InvalidSpot(uint128 spotId, uint128 queueUpTo);

    /// @notice Emitted when the caller is not the external account of the pool's router.
    error NotExternalAccount(address router, address externalAccount, address caller);

    /// @notice Emitted when the msg.value of the call is too low for the fee.
    /// @param value The msg.value.
    /// @param fee The fee to pay.
    error FeeTooLow(uint256 value, uint256 fee);

    /// @notice Emitted when the fee transfer fails.
    error FeeTransferFailed();

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
    /// @param _processor The address of the VertexProcessor contract.
    /// @param _slowModeFee The fee to pay Vertex for slow mode transactions.
    function initialize(address _endpoint, address _processor, uint256 _slowModeFee) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();

        // Set Vertex's endpoint address.
        endpoint = IEndpoint(_endpoint);

        // Set the processor address.
        processor = _processor;

        // Set the slow mode fee.
        slowModeFee = _slowModeFee;

        // Set the quote token for slow-mode transactions through Vertex.
        quoteToken = IERC20Metadata(IClearinghouse(endpoint.clearinghouse()).getQuote());
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
        payable
        whenDepositNotPaused
        nonReentrant
    {
        // Fetch the pool storage.
        Pool storage pool = pools[id];

        // Check that the pool is perp.
        if (pool.poolType != PoolType.Perp) revert InvalidPool(id);

        // Check that the receiver is not the zero address.
        if (receiver == address(0)) revert ZeroAddress();

        // Take fee for unqueue transaction.
        takeElixirFee(pool.router);

        // Add to queue.
        queue[queueCount++] = Spot(
            msg.sender,
            pool.router,
            SpotType.DepositPerp,
            abi.encode(DepositPerp({id: id, token: token, amount: amount, receiver: receiver}))
        );

        emit Queued(queue[queueCount - 1], queueCount, queueUpTo);
    }

    /// @notice Deposits tokens into a spot pool.
    /// @dev Requests are placed into a FIFO queue, which is processed by the Elixir market-making network and passed on to Vertex via the `unqueue` function.
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
    ) external payable whenDepositNotPaused nonReentrant {
        // Fetch the pool storage.
        Pool storage pool = pools[id];

        // Check that the pool is spot.
        if (pool.poolType != PoolType.Spot) revert InvalidPool(id);

        // Check that the tokens are not duplicated.
        if (token0 == token1) revert DuplicatedToken(token0);

        // Check that the receiver is not the zero address.
        if (receiver == address(0)) revert ZeroAddress();

        // Take fee for unqueue transaction.
        takeElixirFee(pool.router);

        // Add to queue.
        queue[queueCount++] = Spot(
            msg.sender,
            pool.router,
            SpotType.DepositSpot,
            abi.encode(
                DepositSpot({
                    id: id,
                    token0: token0,
                    token1: token1,
                    amount0: amount0,
                    amount1Low: amount1Low,
                    amount1High: amount1High,
                    receiver: receiver
                })
            )
        );

        emit Queued(queue[queueCount - 1], queueCount, queueUpTo);
    }

    /// @notice Requests to withdraw a token from a perp pool.
    /// @dev Requests are placed into a FIFO queue, which is processed by the Elixir market-making network and passed on to Vertex via the `unqueue` function.
    /// @dev After processed by Vertex, the user (or anyone on behalf of it) can call the `claim` function.
    /// @param id The ID of the pool to withdraw from.
    /// @param token The token to withdraw.
    /// @param amount The amount of token shares to withdraw.
    function withdrawPerp(uint256 id, address token, uint256 amount)
        external
        payable
        whenWithdrawNotPaused
        nonReentrant
    {
        // Fetch the pool storage.
        Pool storage pool = pools[id];

        // Check that the pool is perp.
        if (pool.poolType != PoolType.Perp) revert InvalidPool(id);

        // Check that the amount is at least the Vertex fee to pay.
        uint256 fee = getTransactionFee(token);

        if (amount < fee) revert AmountTooLow(amount, fee);

        // Take fee for unqueue transaction.
        takeElixirFee(pool.router);

        // Add to queue.
        queue[queueCount++] = Spot(
            msg.sender,
            pool.router,
            SpotType.WithdrawPerp,
            abi.encode(WithdrawPerp({id: id, token: token, amount: amount}))
        );

        emit Queued(queue[queueCount - 1], queueCount, queueUpTo);
    }

    /// @notice Withdraws tokens from a spot pool.
    /// @dev Requests are placed into a FIFO queue, which is processed by the Elixir market-making network and passed on to Vertex via the `unqueue` function.
    /// @param id The ID of the pool to withdraw from.
    /// @param token0 The base token.
    /// @param token1 The quote token.
    /// @param amount0 The amount of base tokens.
    function withdrawSpot(uint256 id, address token0, address token1, uint256 amount0)
        external
        payable
        whenWithdrawNotPaused
        nonReentrant
    {
        // Fetch the pool data.
        Pool storage pool = pools[id];

        // Check that the pool is spot.
        if (pool.poolType != PoolType.Spot) revert InvalidPool(id);

        // Check that the tokens are not duplicated.
        if (token0 == token1) revert DuplicatedToken(token0);

        // Take fee for unqueue transaction.
        takeElixirFee(pool.router);

        // Add to queue.
        queue[queueCount++] = Spot(
            msg.sender,
            pool.router,
            SpotType.WithdrawSpot,
            abi.encode(WithdrawSpot({id: id, token0: token0, token1: token1, amount0: amount0}))
        );

        emit Queued(queue[queueCount - 1], queueCount, queueUpTo);
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

        // Establish empty token data.
        Token storage tokenData;

        // If token is the Clearinghouse quote token, point to the old quote token data.
        if (oldQuoteToken != address(0) && token == IClearinghouse(endpoint.clearinghouse()).getQuote()) {
            tokenData = pool.tokens[oldQuoteToken];
        } else {
            tokenData = pool.tokens[token];
        }

        // Get Elixir's pending fee balance.
        uint256 fee = tokenData.fees[user];

        // Calculate the user's claim amount.
        uint256 claim =
            Math.min(tokenData.userPendingAmount[user] + fee, IERC20Metadata(token).balanceOf(address(router)));

        // Resets the pending balance of the user.
        tokenData.userPendingAmount[user] -= claim - fee;

        // Resets the Elixir pending fee balance.
        tokenData.fees[user] -= fee;

        // Fetch the tokens from the router.
        router.claimToken(token, claim);

        // Transfers the tokens after to prevent reentrancy.
        IERC20Metadata(token).safeTransfer(owner(), fee);
        IERC20Metadata(token).safeTransfer(user, claim - fee);

        emit Claim(user, token, claim - fee);
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

        // Establish empty token data.
        Token storage tokenData;

        // If token is the Clearinghouse quote token, point to the old quote token data.
        if (oldQuoteToken != address(0) && token == IClearinghouse(endpoint.clearinghouse()).getQuote()) {
            tokenData = pool.tokens[oldQuoteToken];
        } else {
            tokenData = pool.tokens[token];
        }

        return (pool.router, tokenData.activeAmount, tokenData.hardcap, tokenData.isActive);
    }

    /// @notice Returns the slow-mode fee for a given pool and token.
    /// @param token The token to fetch the fee from.
    function getTransactionFee(address token) public view returns (uint256) {
        return slowModeFee.mulDiv(
            10 ** (18 + IERC20Metadata(token).decimals() - quoteToken.decimals()),
            getPrice(tokenToProduct[token]),
            Math.Rounding.Up
        );
    }

    /// @notice Returns a user's active amount for a token within a pool.
    /// @param id The ID of the pool to fetch the active amounts of.
    /// @param token The token to fetch the active amounts of.
    /// @param user The user to fetch the active amounts of.
    function getUserActiveAmount(uint256 id, address token, address user) external view returns (uint256) {
        // If token is the Clearinghouse quote token, point to the old quote token.
        if (oldQuoteToken != address(0) && token == IClearinghouse(endpoint.clearinghouse()).getQuote()) {
            token = oldQuoteToken;
        }

        return pools[id].tokens[token].userActiveAmount[user];
    }

    /// @notice Returns a user's pending amount for a token within a pool.
    /// @param id The ID of the pool to fetch the pending amount of.
    /// @param token The token to fetch the pending amount of.
    /// @param user The user to fetch the pending amount of.
    function getUserPendingAmount(uint256 id, address token, address user) external view returns (uint256) {
        // If token is the Clearinghouse quote token, point to the old quote token.
        if (oldQuoteToken != address(0) && token == IClearinghouse(endpoint.clearinghouse()).getQuote()) {
            token = oldQuoteToken;
        }

        return pools[id].tokens[token].userPendingAmount[user];
    }

    /// @notice Returns a user's reimbursement fee for a token within a pool.
    /// @param id The ID of the pool to fetch the fee for.
    /// @param token The token to fetch the fee for.
    /// @param user The user to fetch the fee for.
    function getUserFee(uint256 id, address token, address user) external view returns (uint256) {
        // If token is the Clearinghouse quote token, point to the old quote token.
        if (oldQuoteToken != address(0) && token == IClearinghouse(endpoint.clearinghouse()).getQuote()) {
            token = oldQuoteToken;
        }

        return pools[id].tokens[token].fees[user];
    }

    /// @notice Returns the balanced amount of quote tokens given an amount of base tokens.
    /// @param token0 The base token.
    /// @param token1 The quote token.
    /// @param amount0 The amount of base tokens.
    function getBalancedAmount(address token0, address token1, uint256 amount0) external view returns (uint256) {
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

    /// @notice Returns the external account of a pool router.
    function getExternalAccount(address router) private view returns (address) {
        return address(uint160(bytes20(VertexRouter(router).externalSubaccount())));
    }

    /// @notice Enforce the Elixir fee in native ETH.
    /// @param router The pool router.
    function takeElixirFee(address router) private {
        // Get the Elixir processing fee for unqueue transaction using WETH as token.
        // Safely assumes that WETH ID on Vertex is 3.
        uint256 fee = getTransactionFee(productToToken[3]);

        // Check that the msg.value is equal or more than the fee.
        if (msg.value < fee) revert FeeTooLow(msg.value, fee);

        // Transfer fee to the external account EOA.
        (bool sent,) = payable(getExternalAccount(router)).call{value: msg.value}("");
        if (!sent) revert FeeTransferFailed();
    }

    /// @notice Returns the next spot in the queue to process.
    function nextSpot() external view returns (Spot memory) {
        return queue[queueUpTo];
    }

    /*//////////////////////////////////////////////////////////////
                          PERMISSIONED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes the next spot in the withdraw perp queue.
    /// @param spotId The ID of the spot queue to process.
    /// @param response The response to the spot transaction.
    function unqueue(uint128 spotId, bytes memory response) external {
        // Get the spot data from the queue.
        Spot memory spot = queue[queueUpTo];

        // Get the external account of the router.
        address externalAccount = getExternalAccount(spot.router);

        // Check that the sender is the external account of the router.
        if (msg.sender != externalAccount) revert NotExternalAccount(spot.router, externalAccount, msg.sender);

        if (response.length != 0) {
            // Check that next spot in queue matches the given spot ID.
            if (spotId != queueUpTo + 1) revert InvalidSpot(spotId, queueUpTo);

            // Process spot. Skips if fail or revert.
            bytes memory processorCall =
                abi.encodeWithSelector(VertexProcessor.processSpot.selector, spot, response, address(this));
            processor.delegatecall(processorCall);
        } else {
            // Intetionally skip.
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
        router.makeApproval(address(quoteToken));

        // Create LinkSigner request for Vertex.
        IEndpoint.LinkSigner memory linkSigner =
            IEndpoint.LinkSigner(router.contractSubaccount(), router.externalSubaccount(), 0);

        // Fetch payment fee from owner. This can be reimbursed on withdrawals after tokens are received.
        quoteToken.safeTransferFrom(owner(), address(router), slowModeFee);

        // Submit slow-mode tx to Vertex.
        router.submitSlowModeTransaction(
            abi.encodePacked(uint8(IEndpoint.TransactionType.LinkSigner), abi.encode(linkSigner))
        );

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
            Token storage tokenData;

            // If token is the Clearinghouse quote token, point to the old quote token data.
            if (oldQuoteToken != address(0) && token == IClearinghouse(endpoint.clearinghouse()).getQuote()) {
                tokenData = pools[id].tokens[oldQuoteToken];
            } else {
                tokenData = pools[id].tokens[token];
            }

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
            // Get the token.
            address token = tokens[i];

            // If token is the Clearinghouse quote token, point to the old quote token.
            if (oldQuoteToken != address(0) && token == IClearinghouse(endpoint.clearinghouse()).getQuote()) {
                token = oldQuoteToken;
            }

            pools[id].tokens[token].hardcap = hardcaps[i];
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

    /// @notice Rescues any stuck tokens in the contract.
    /// @param token The token to rescue.
    /// @param amount The amount of token to rescue.
    function rescue(address token, uint256 amount) external onlyOwner {
        IERC20Metadata(token).safeTransfer(owner(), amount);
    }

    /// @notice Updates the Processor implementation address.
    /// @param _processor The new Processor implementation address.
    function updateProcessor(address _processor) external onlyOwner {
        processor = _processor;
    }

    /// @notice Update the quote token.
    /// @param _quoteToken The new quote token.
    function updateQuoteToken(address _quoteToken) external onlyOwner {
        oldQuoteToken = address(quoteToken);
        quoteToken = IERC20Metadata(_quoteToken);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Upgrades the implementation of the proxy to new address.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
