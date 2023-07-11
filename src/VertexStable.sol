// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {VertexFactory} from "./VertexFactory.sol";
import {IEndpoint} from "./interfaces/IEndpoint.sol";

/// @title Elixir-based pool for Vertex
/// @author The Elixir Team
/// @notice Liquidity pool aggregator for marketing making in Vertex Protocol.
contract VertexStable is ERC20, Owned {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    // /// @notice The underlying token the Vault accepts.
    // ERC20 public immutable UNDERLYING;

    // /// @notice The base unit of the underlying token and hence rvToken.
    // /// @dev Equal to 10 ** decimals. Used for fixed point arithmetic.
    // uint256 internal immutable BASE_UNIT;

    // /// @notice The total amount of underlying tokens held in strategies at the time of the last harvest.
    // /// @dev Includes maxLockedProfit, must be correctly subtracted to compute available/free holdings.
    // uint256 public totalStrategyHoldings;

    // /// @notice A timestamp representing when the first harvest in the most recent harvest window occurred.
    // /// @dev May be equal to lastHarvest if there was/has only been one harvest in the most last/current window.
    // uint64 public lastHarvestWindowStart;

    // /// @notice A timestamp representing when the most recent harvest occurred.
    // uint64 public lastHarvest;

    // /// @notice The amount of locked profit at the end of the last harvest.
    // uint256 public maxLockedProfit;

    // /// @notice Whether the Vault has been initialized yet.
    // /// @dev Can go from false to true, never from true to false.
    // bool public isInitialized;

    /// @notice The ERC20 instance of the base token.
    ERC20 public immutable baseToken;

    /// @notice Total amount of base tokens managed by this pool.
    uint256 public baseCurrent;

    /// @notice The ERC20 instance of the quote token.
    ERC20 public immutable quoteToken;

    /// @notice Total amount of quote tokens managed by this pool.
    uint256 public quoteCurrent;

    /// @notice The ID of the product this pool targets on Vertex.
    uint32 public immutable productId;

    /// @notice Vertex's Endpoint contract.
    IEndpoint public immutable endpoint;

    bytes32 public immutable contractSubaccount;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    // /// @notice Emitted when the Vault is initialized.
    // /// @param user The authorized user who triggered the initialization.
    // event Initialized(address indexed user);

    // /// @notice Emitted after fees are claimed.
    // /// @param user The authorized user who claimed the fees.
    // /// @param rvTokenAmount The amount of rvTokens that were claimed.
    // event FeesClaimed(address indexed user, uint256 rvTokenAmount);

    event Deposit(
        address indexed caller, address indexed owner, uint256 amountBase, uint256 amountQuote, uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 amountBase,
        uint256 amountQuote,
        uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an unauthorized address attempts to call an authorized function.
    /// @param caller The unauthorized address who attempted the call.
    error Unauthroized(address caller);

    /// @notice Emitted when a deposit function is entered with invalid input amounts.
    error InvalidDepositAmounts();

    /// @notice Emitted when the slippage is too high when calculating the base token amounts.
    error SlippageTooHigh(uint256 amountQuote, uint256 quoteAmountLow, uint256 quoteAmountHigh);

    // TODO: Add Natspec.
    error ZeroShares();

    // TODO: Add Natspec.
    error ZeroAssets();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new Pool that accepts a specific pair of tokens.
    /// @param _productId The ID of the product on Vertex this pool targets.
    /// @param _name The name of the pool.
    /// @param _symbol The symbol of the pool.
    /// @param _quoteToken The quote token of the pair.
    /// @param _baseToken The base token of the pair.
    constructor(uint32 _productId, string memory _name, string memory _symbol, ERC20 _quoteToken, ERC20 _baseToken)
        ERC20(_name, _symbol, 18)
        Owned(VertexFactory(msg.sender).owner())
    {
        productId = _productId;
        quoteToken = _quoteToken;
        baseToken = _baseToken;
        endpoint = IEndpoint(VertexFactory(msg.sender).endpoint());

        // Link smart contract to Elixir's signer.
        contractSubaccount = bytes32(uint256(uint160(address(this))) << 96);
        bytes32 externalSubaccount = bytes32(uint256(uint160(VertexFactory(msg.sender).externalAccount())) << 96);
        IEndpoint.LinkSigner memory linkSigner = IEndpoint.LinkSigner(contractSubaccount, externalSubaccount, 0);
        bytes memory transactionData = abi.encodePacked(abi.encode(19), abi.encode(linkSigner));
        endpoint.submitSlowModeTransaction(transactionData);

        // Approve Vertex to transfer tokens.
        quoteToken.approve(address(endpoint), type(uint256).max);
        baseToken.approve(address(endpoint), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 amountBase, uint256 quoteAmountLow, uint256 quoteAmountHigh, address receiver)
        external
        returns (uint256 shares)
    {
        if (!(amountBase > 0) || !(quoteAmountLow > 0) || !(quoteAmountHigh > 0) || !(quoteAmountLow < quoteAmountHigh))
        {
            revert InvalidDepositAmounts();
        }

        // Get the amount of base tokens based on the quote token amount.
        uint256 amountQuote = calculateQuoteAmount(amountBase);

        // Check for slippage based on the given base amount and the calculated quote amount.
        if (amountQuote < quoteAmountLow || amountQuote > quoteAmountHigh) {
            revert SlippageTooHigh(amountQuote, quoteAmountLow, quoteAmountHigh);
        }

        // Check for rounding error since we round down in previewDeposit.
        if ((shares = previewDeposit(amountBase, amountQuote)) == 0) revert ZeroShares();

        // Transfer both tokens before minting or ERC777s could reenter.
        baseToken.safeTransferFrom(msg.sender, address(this), amountBase);
        quoteToken.safeTransferFrom(msg.sender, address(this), amountQuote);

        // Deposit liquidity on Vertex.
        endpoint.depositCollateral(bytes12(contractSubaccount), productId, uint128(amountBase));

        // NOTE: Assuming for token 1 to be USDC as it's the currently supported quote token.
        endpoint.depositCollateral(bytes12(contractSubaccount), 0, uint128(amountQuote));

        // Add the current amounts of base and quote tokens.
        baseCurrent += amountBase;
        quoteCurrent += amountQuote;

        // Mint shares equivalent to deposit liquidity.
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amountBase, amountQuote, shares);

        afterDeposit(amountBase, amountQuote, shares);
    }

    function mint(uint256 shares, address receiver) external returns (uint256 amountBase, uint256 amountQuote) {
        (amountBase, amountQuote) = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Transfer both tokens before minting or ERC777s could reenter.
        baseToken.safeTransferFrom(msg.sender, address(this), amountBase);
        quoteToken.safeTransferFrom(msg.sender, address(this), amountQuote);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amountBase, amountQuote, shares);

        afterDeposit(amountBase, amountQuote, shares);
    }

    function withdraw(uint256 amountBase, address receiver, address owner) external returns (uint256 shares) {
        shares = previewWithdraw(amountBase); // No need to check for rounding error, previewWithdraw rounds up.
        // Fetch amount of quote token to withdraw respective to the amount of base token.
        uint256 amountQuote = calculateQuoteAmount(amountBase);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(amountBase, amountQuote, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, amountBase, amountQuote, shares);

        baseToken.safeTransfer(receiver, amountBase);
        quoteToken.safeTransfer(receiver, amountQuote);
    }

    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 amountBase, uint256 amountQuote) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        (amountBase, amountQuote) = previewRedeem(shares);
        if (amountBase == 0 && amountQuote == 0) revert ZeroAssets();

        beforeWithdraw(amountBase, amountQuote, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, amountBase, amountQuote, shares);

        baseToken.safeTransfer(receiver, amountBase);
        quoteToken.safeTransfer(receiver, amountQuote);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view returns (uint256) {
        // TODO: Implement correctly
        return 0;
    }

    function calculateQuoteAmount(uint256 amountBase) public view returns (uint256) {
        return baseCurrent == 0
            ? amountBase.unsafeMod(endpoint.getPriceX18(productId))
            : amountBase.unsafeMod(quoteCurrent.unsafeDiv(baseCurrent));
    }

    function convertToShares(uint256 amountBase, uint256 amountQuote) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        // TODO: Compare calculation when supply != 0 to solmate's ERC4626 implementation and also to Vertex's implementation.
        return supply == 0 ? amountBase + amountQuote : amountBase.mulDivDown(supply, baseCurrent);
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256, uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        // TODO: Check math calculation for both cases
        return supply == 0
            ? (shares, shares)
            : (shares.mulDivUp(totalAssets(), supply), shares.mulDivUp(totalAssets(), supply));
    }

    function previewDeposit(uint256 amountBase, uint256 amountQuote) public view returns (uint256) {
        return convertToShares(amountBase, amountQuote);
    }

    function previewMint(uint256 shares) public view returns (uint256, uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        // TODO: Check for the calculation when supply is not 0 (especially withe ach return value depending on totalAssets)
        return supply == 0
            ? (shares, shares)
            : (shares.mulDivUp(totalAssets(), supply), shares.mulDivUp(totalAssets(), supply));
    }

    function previewWithdraw(uint256 amountBase) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        // TODO: Check math calculation when supply is 0 and when it's not
        return supply == 0 ? amountBase : amountBase.mulDivUp(supply, baseCurrent);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256, uint256) {
        return convertToAssets(shares);
    }

    // /*//////////////////////////////////////////////////////////////
    //                  DEPOSIT/WITHDRAWAL LIMIT LOGIC
    // //////////////////////////////////////////////////////////////*/

    // function maxDeposit(address) public view virtual returns (uint256) {
    //     return type(uint256).max;
    // }

    // function maxMint(address) public view virtual returns (uint256) {
    //     return type(uint256).max;
    // }

    // function maxWithdraw(address owner) public view virtual returns (uint256) {
    //     return convertToAssets(balanceOf[owner]);
    // }

    // function maxRedeem(address owner) public view virtual returns (uint256) {
    //     return balanceOf[owner];
    // }

    // /*//////////////////////////////////////////////////////////////
    //                       INTERNAL HOOKS LOGIC
    // //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 amountBase, uint256 amountQuote, uint256 shares) internal virtual {
        // TODO: Check anything before withdraw?
    }

    function afterDeposit(uint256 amountBase, uint256 amountQuote, uint256 shares) internal virtual {
        // TODO: Checks after deposit?
    }

    // /// @dev Retrieves a specific amount of underlying tokens held in strategies and/or float.
    // /// @dev Only withdraws from strategies if needed and maintains the target float percentage if possible.
    // /// @param underlyingAmount The amount of underlying tokens to retrieve.
    // function retrieveUnderlying(uint256 underlyingAmount) internal {
    //     // Get the Vault's floating balance.
    //     uint256 float = totalFloat();

    //     // If the amount is greater than the float, withdraw from strategies.
    //     if (underlyingAmount > float) {
    //         // Compute the amount needed to reach our target float percentage.
    //         uint256 floatMissingForTarget = (totalAssets() - underlyingAmount).mulWadDown(targetFloatPercent);

    //         // Compute the bare minimum amount we need for this withdrawal.
    //         uint256 floatMissingForWithdrawal = underlyingAmount - float;

    //         // Pull enough to cover the withdrawal and reach our target float percentage.
    //         pullFromWithdrawalStack(floatMissingForWithdrawal + floatMissingForTarget);
    //     }
    // }

    // /// @notice Calculates the total amount of underlying tokens the Vault holds.
    // /// @return totalUnderlyingHeld The total amount of underlying tokens the Vault holds.
    // function totalAssets() public view override returns (uint256 totalUnderlyingHeld) {
    //     unchecked {
    //         // Cannot underflow as locked profit can't exceed total strategy holdings.
    //         totalUnderlyingHeld = totalStrategyHoldings - lockedProfit();
    //     }

    //     // Include our floating balance in the total.
    //     totalUnderlyingHeld += totalFloat();
    // }

    // /// @notice Calculates the current amount of locked profit.
    // /// @return The current amount of locked profit.
    // function lockedProfit() public view returns (uint256) {
    //     // Get the last harvest and harvest delay.
    //     uint256 previousHarvest = lastHarvest;
    //     uint256 harvestInterval = harvestDelay;

    //     unchecked {
    //         // If the harvest delay has passed, there is no locked profit.
    //         // Cannot overflow on human timescales since harvestInterval is capped.
    //         if (block.timestamp >= previousHarvest + harvestInterval) return 0;

    //         // Get the maximum amount we could return.
    //         uint256 maximumLockedProfit = maxLockedProfit;

    //         // Compute how much profit remains locked based on the last harvest and harvest delay.
    //         // It's impossible for the previous harvest to be in the future, so this will never underflow.
    //         return maximumLockedProfit - (maximumLockedProfit * (block.timestamp - previousHarvest)) / harvestInterval;
    //     }
    // }

    // /// @notice Returns the amount of underlying tokens that idly sit in the Vault.
    // /// @return The amount of underlying tokens that sit idly in the Vault.
    // function totalFloat() public view returns (uint256) {
    //     return UNDERLYING.balanceOf(address(this));
    // }

    // /// @notice Sets a new fee percentage.
    // /// @param newFeePercent The new fee percentage.
    // function setFeePercent(uint256 newFeePercent) external requiresAuth {
    //     // A fee percentage over 100% doesn't make sense.
    //     require(newFeePercent <= 1e18, "FEE_TOO_HIGH");

    //     // Update the fee percentage.
    //     feePercent = newFeePercent;

    //     emit FeePercentUpdated(msg.sender, newFeePercent);
    // }

    // /// @notice Deposit a specific amount of float into a trusted strategy.
    // /// @param strategy The trusted strategy to deposit into.
    // /// @param underlyingAmount The amount of underlying tokens in float to deposit.
    // function depositIntoStrategy(Strategy strategy, uint256 underlyingAmount) external requiresAuth {
    //     // A strategy must be trusted before it can be deposited into.
    //     require(getStrategyData[strategy].trusted, "UNTRUSTED_STRATEGY");

    //     // Increase totalStrategyHoldings to account for the deposit.
    //     totalStrategyHoldings += underlyingAmount;

    //     unchecked {
    //         // Without this the next harvest would count the deposit as profit.
    //         // Cannot overflow as the balance of one strategy can't exceed the sum of all.
    //         getStrategyData[strategy].balance += underlyingAmount.safeCastTo248();
    //     }

    //     emit StrategyDeposit(msg.sender, strategy, underlyingAmount);

    //     // We need to deposit differently if the strategy takes ETH.
    //     if (strategy.isCEther()) {
    //         // Unwrap the right amount of WETH.
    //         WETH(payable(address(UNDERLYING))).withdraw(underlyingAmount);

    //         // Deposit into the strategy and assume it will revert on error.
    //         ETHStrategy(address(strategy)).mint{value: underlyingAmount}();
    //     } else {
    //         // Approve underlyingAmount to the strategy so we can deposit.
    //         UNDERLYING.safeApprove(address(strategy), underlyingAmount);

    //         // Deposit into the strategy and revert if it returns an error code.
    //         require(ERC20Strategy(address(strategy)).mint(underlyingAmount) == 0, "MINT_FAILED");
    //     }
    // }

    // /// @notice Withdraw a specific amount of underlying tokens from a strategy.
    // /// @param strategy The strategy to withdraw from.
    // /// @param underlyingAmount  The amount of underlying tokens to withdraw.
    // /// @dev Withdrawing from a strategy will not remove it from the withdrawal stack.
    // function withdrawFromStrategy(Strategy strategy, uint256 underlyingAmount) external requiresAuth {
    //     // A strategy must be trusted before it can be withdrawn from.
    //     require(getStrategyData[strategy].trusted, "UNTRUSTED_STRATEGY");

    //     // Without this the next harvest would count the withdrawal as a loss.
    //     getStrategyData[strategy].balance -= underlyingAmount.safeCastTo248();

    //     unchecked {
    //         // Decrease totalStrategyHoldings to account for the withdrawal.
    //         // Cannot underflow as the balance of one strategy will never exceed the sum of all.
    //         totalStrategyHoldings -= underlyingAmount;
    //     }

    //     emit StrategyWithdrawal(msg.sender, strategy, underlyingAmount);

    //     // Withdraw from the strategy and revert if it returns an error code.
    //     require(strategy.redeemUnderlying(underlyingAmount) == 0, "REDEEM_FAILED");

    //     // Wrap the withdrawn Ether into WETH if necessary.
    //     if (strategy.isCEther()) WETH(payable(address(UNDERLYING))).deposit{value: underlyingAmount}();
    // }

    // /// @notice Claims fees accrued from harvests.
    // /// @param rvTokenAmount The amount of rvTokens to claim.
    // /// @dev Accrued fees are measured as rvTokens held by the Vault.
    // function claimFees(uint256 rvTokenAmount) external requiresAuth {
    //     emit FeesClaimed(msg.sender, rvTokenAmount);

    //     // Transfer the provided amount of rvTokens to the caller.
    //     ERC20(this).safeTransfer(msg.sender, rvTokenAmount);
    // }

    // /// @notice Initializes the Vault, enabling it to receive deposits.
    // /// @dev All critical parameters must already be set before calling.
    // function initialize() external requiresAuth {
    //     // Ensure the Vault has not already been initialized.
    //     require(!isInitialized, "ALREADY_INITIALIZED");

    //     // Mark the Vault as initialized.
    //     isInitialized = true;

    //     // Open for deposits.
    //     totalSupply = 0;

    //     emit Initialized(msg.sender);
    // }

    // /// @notice Self destructs a Vault, enabling it to be redeployed.
    // /// @dev Caller will receive any ETH held as float in the Vault.
    // function destroy() external requiresAuth {
    //     selfdestruct(payable(msg.sender));
    // }

    // /*///////////////////////////////////////////////////////////////
    //                       RECIEVE ETHER LOGIC
    // //////////////////////////////////////////////////////////////*/

    // /// @dev Required for the Vault to receive unwrapped ETH.
    // receive() external payable {}
}
