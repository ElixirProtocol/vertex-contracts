// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {VertexFactory} from "./VertexFactory.sol";
import {IClearinghouse} from "./interfaces/IClearinghouse.sol";
import {IEndpoint} from "./interfaces/IEndpoint.sol";

import "openzeppelin/utils/math/Math.sol";
/// @title Elixir Spot Vault for Vertex
/// @author The Elixir Team
/// @notice Liquidity vault aggregator for market making on stable pairs in Vertex Protocol.
contract VertexSpotVault is ERC20, Owned {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The ERC20 instance of the base token.
    ERC20 public immutable baseToken;

    /// @notice Total amount of base tokens managed by this vault.
    uint256 public baseActive;

    /// @notice The ERC20 instance of the quote token.
    ERC20 public immutable quoteToken;

    /// @notice Total amount of quote tokens managed by this vault.
    uint256 public quoteActive;

    /// @notice The ID of the product this vault targets on Vertex.
    uint32 public immutable productId;

    /// @notice Vertex's Endpoint contract.
    IEndpoint public immutable endpoint;

    /// @notice Bytes of vault's subaccount.
    bytes32 public immutable contractSubaccount;

    /// @notice Pending balance of base tokens of a user.
    mapping(address => uint256) public basePending;

    /// @notice Pending balance of quote tokens of a user.
    mapping(address => uint256) public quotePending;

    /// @notice Factory that deployed this vault.
    address public immutable factory;

    /// @notice Payment token for slow mode transactions through Vertex.
    ERC20 public immutable paymentToken;

    /// @notice The pause status of deposits.
    bool public depositPaused;

    /// @notice The pause status of withdrawals.
    bool public withdrawPaused;

    /// @notice The pause status of claims.
    bool public claimPaused;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a deposit is made.
    /// @param caller The caller of the deposit function, for which tokens are taken from.
    /// @param receiver The receiver of the shares.
    /// @param amountBase The amount of base tokens deposited.
    /// @param amountQuote The amount of quote tokens deposited.
    /// @param shares The amount of shares minted.
    event Deposit(
        address indexed caller, address indexed receiver, uint256 amountBase, uint256 amountQuote, uint256 shares
    );

    /// @notice Emitted when a withdraw is made.
    /// @param caller The caller of the withdraw function, which will be able to call the claim function.
    /// @param owner The owner of the shares to withdraw.
    /// @param amountBase The amount of base tokens requested to withdraw.
    /// @param amountQuote The amount of quote tokens requested to withdraw.
    /// @param shares The amount of shares burned.
    event Withdraw(
        address indexed caller, address indexed owner, uint256 amountBase, uint256 amountQuote, uint256 shares
    );

    /// @notice Emitted when a claim is made.
    /// @param caller The caller of the claim function, for which tokens are taken from.
    /// @param receiver The receiver of the claimed tokens.
    /// @param claimBase The amount of base tokens claimed.
    /// @param claimQuote The amount of quote tokens claimed.
    event Claim(address indexed caller, address indexed receiver, uint256 claimBase, uint256 claimQuote);

    /// @notice Emitted when pause statuses are updated.
    /// @param depositPaused True when deposits are paused, false otherwise.
    /// @param withdrawPaused True when withdrawals are paused, false otherwise.
    /// @param claimPaused True when claims are paused, false otherwise.
    event PauseUpdated(bool depositPaused, bool withdrawPaused, bool claimPaused);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an unauthorized address attempts to call an authorized function.
    /// @param caller The unauthorized address who attempted the call.
    error Unauthroized(address caller);

    /// @notice Emitted when a deposit function is entered with invalid input amounts.
    /// @param amountBase The amount of base tokens to deposit.
    /// @param quoteAmountLow The minimum amount of quote tokens to deposit.
    /// @param quoteAmountHigh The maximum amount of quote tokens to deposit.
    error InvalidDepositAmounts(uint256 amountBase, uint256 quoteAmountLow, uint256 quoteAmountHigh);

    /// @notice Emitted when the slippage is too high when calculating the base token amounts.
    /// @param amountQuote The amount of quote tokens to deposit.
    /// @param quoteAmountLow The minimum amount of base tokens to deposit.
    /// @param quoteAmountHigh The maximum amount of base tokens to deposit.
    error SlippageTooHigh(uint256 amountQuote, uint256 quoteAmountLow, uint256 quoteAmountHigh);

    /// @notice Emitted when a deposit function is entered with a calculated amount of zero amount of shares.
    error ZeroShares();

    /// @notice Emitted when a redeem function is entered with an amount of shares that is equivalent to zero assets.
    error ZeroAssets();

    /// @notice Emitted when a claim function is entered with a pending balance of zero for the quote or base tokens.
    error ZeroClaim();

    /// @notice Emitted when there is a mismatch between the calculation of base tokens, shares and the actual amount.
    /// @param shares The amount of shares calculated from the amount of base tokens.
    /// @param amountBase The amount of base tokens given as a parameter in the withdraw function.
    /// @param calculatedAmountBase The amount of base tokens calculated.
    error InvalidCalculation(uint256 shares, uint256 amountBase, uint256 calculatedAmountBase);

    /// @notice Emitted when deposits (deposit and mint) are paused.
    error DepositsPaused();

    /// @notice Emitted when withdrawals (withdraw and redeem) are paused.
    error WithdrawalsPaused();

    /// @notice Emitted when claims are paused.
    error ClaimsPaused();

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

    /// @notice Creates a new Vault that accepts a specific pair of tokens.
    /// @param _productId The ID of the product on Vertex this vault targets.
    /// @param _name The name of the vault.
    /// @param _symbol The symbol of the vault.
    /// @param _baseToken The base token of the vault.
    /// @param _quoteToken The quote token of the vault.
    constructor(uint32 _productId, string memory _name, string memory _symbol, ERC20 _baseToken, ERC20 _quoteToken)
        ERC20(_name, _symbol, 18)
        Owned(VertexFactory(msg.sender).owner())
    {
        productId = _productId;
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        factory = msg.sender;
        endpoint = IEndpoint(VertexFactory(msg.sender).endpoint());

        // It may happen that the quote token of endpoint payments is not the quote token of the vault/product.
        paymentToken = ERC20(IClearinghouse(endpoint.clearinghouse()).getQuote());

        // Allow endpoint to transfer payout token from this vault.
        paymentToken.approve(address(endpoint), type(uint256).max);

        // Link smart contract to Elixir's signer.
        contractSubaccount = bytes32(uint256(uint160(address(this))) << 96);
        bytes32 externalSubaccount = bytes32(uint256(uint160(VertexFactory(msg.sender).externalAccount())) << 96);
        IEndpoint.LinkSigner memory linkSigner = IEndpoint.LinkSigner(contractSubaccount, externalSubaccount, 0);

        // Submit transaction to Vertex after fetching fee to pay.
        _submitSlowModeTransaction(
            abi.encodePacked(uint8(IEndpoint.TransactionType.LinkSigner), abi.encode(linkSigner))
        );

        // Approve Vertex to transfer tokens.
        baseToken.approve(address(endpoint), type(uint256).max);
        quoteToken.approve(address(endpoint), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL ENTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits base and quote tokens into the vault, which are sent to Vertex, before minting the equivalent shares.
    /// @param amountBase The amount of base tokens to deposit.
    /// @param quoteAmountLow The minimum amount of quote tokens to deposit.
    /// @param quoteAmountHigh The maximum amount of quote tokens to deposit.
    /// @param receiver The address that will receive the shares.
    function deposit(uint256 amountBase, uint256 quoteAmountLow, uint256 quoteAmountHigh, address receiver)
        external
        whenDepositNotPaused
        returns (uint256 shares)
    {
        if (!(amountBase > 0) || !(quoteAmountLow > 0) || !(quoteAmountHigh > 0) || !(quoteAmountLow < quoteAmountHigh))
        {
            revert InvalidDepositAmounts(amountBase, quoteAmountLow, quoteAmountHigh);
        }

        // Get the amount of base tokens based on the quote token amount.
        uint256 amountQuote = calculateQuoteAmount(amountBase);

        // Check for slippage based on the given base amount and the calculated quote amount.
        if (amountQuote < quoteAmountLow || amountQuote > quoteAmountHigh) {
            revert SlippageTooHigh(amountQuote, quoteAmountLow, quoteAmountHigh);
        }

        // Check for rounding error since we round down in previewDeposit.
        if ((shares = previewDeposit(amountBase, amountQuote)) == 0) revert ZeroShares();

        // Execute the universal deposit logic.
        _depositLogic(amountBase, amountQuote, receiver, shares);
    }

    /// @notice Given an amount of shares, deposits base and quote tokens into the vault, which are sent to Vertex, before minting the shares.
    /// @param shares The amount of shares to mint.
    /// @param receiver The address that will receive the shares.
    function mint(uint256 shares, address receiver)
        external
        whenDepositNotPaused
        returns (uint256 amountBase, uint256 amountQuote)
    {
        (amountBase, amountQuote) = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Execute the universal deposit logic.
        _depositLogic(amountBase, amountQuote, receiver, shares);
    }

    /// @notice Sends a withdraw request to Vertex for a given amount of base tokens and the equivalent amount of quote tokens.
    /// @param amountBase The amount of base tokens to withdraw.
    /// @param owner The owner of the shares to withdraw.
    function withdraw(uint256 amountBase, address owner) external whenWithdrawNotPaused returns (uint256 shares) {
        shares = previewWithdraw(amountBase); // No need to check for rounding error, previewWithdraw rounds up.

        // Fetch amount of quote token to withdraw respective to the amount of base token.
        (uint256 calculatedAmountBase, uint256 amountQuote) = convertToAssets(shares);

        if (amountBase != calculatedAmountBase) revert InvalidCalculation(shares, amountBase, calculatedAmountBase);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        _withdrawLogic(amountBase, amountQuote, owner, shares);
    }

    /// @notice Sends a redeem request to Vertex for a given amount of shares for the equivalent amount of base and quote tokens.
    /// @param shares The amount of shares to redeem.
    /// @param owner The owner of the shares to redeem.
    function redeem(uint256 shares, address owner)
        external
        whenWithdrawNotPaused
        returns (uint256 amountBase, uint256 amountQuote)
    {
        // Check for rounding error since we round down in previewRedeem.
        (amountBase, amountQuote) = previewRedeem(shares);
        if (amountBase == 0 && amountQuote == 0) revert ZeroAssets();

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        _withdrawLogic(amountBase, amountQuote, owner, shares);
    }

    /// @notice Claims all received base and quote tokens from the pending balance.
    /// @param receiver The address to receive the claimed tokens.
    function claim(address receiver) external whenClaimNotPaused returns (uint256 claimBase, uint256 claimQuote) {
        claimBase = basePending[msg.sender];
        claimQuote = quotePending[msg.sender];

        if (claimBase == 0 || claimQuote == 0) revert ZeroClaim();

        // Resets the pending balance of the receiver.
        basePending[msg.sender] = 0;
        quotePending[msg.sender] = 0;

        // Transfers the tokens after to prevent reentrancy.
        baseToken.safeTransfer(receiver, claimBase);
        quoteToken.safeTransfer(receiver, claimQuote);

        emit Claim(msg.sender, receiver, claimBase, claimQuote);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the amount of active base tokens and quote tokens used for market making on Vertex.
    function totalAssets() public view returns (uint256, uint256) {
        return (baseActive, quoteActive);
    }
    /// @notice Performs the calculation for conversion of base tokens to quote tokens.
    function assetEquivalenceCalculation(uint256 bamount, uint256 qactive, uint256 bactive) public pure returns (uint256 result) {
        // amountBase * (quoteActive / baseActive)
        result = bamount.mulDiv(qactive, bactive);
    }
    /// @notice Returns an amount of quote tokens based on a given amount of base tokens.
    function calculateQuoteAmount(uint256 amountBase) public view returns (uint256) {
        return baseActive == 0
            ? amountBase.mulDivDown(
                endpoint.getPriceX18(productId),
                10 ** (18 + (baseToken.decimals() - quoteToken.decimals()))
            )
            : assetEquivalenceCalculation(amountBase, baseActive, quoteActive);
    }

    /// @notice Returns an amount of shares given an amount of base and quote tokens.
    /// @param amountBase The amount of base tokens.
    /// @param amountQuote The amount of quote tokens.
    function convertToShares(uint256 amountBase, uint256 amountQuote) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        // TODO: Compare calculation when supply != 0 to solmate's ERC4626 implementation and also to Vertex's implementation.
        return supply == 0 ? amountBase + amountQuote : amountBase.mulDivDown(supply, baseActive);
    }

    /// @notice Returns an amount of base and quote tokens given an amount of shares.
    /// @param shares The amount of shares.
    function convertToAssets(uint256 shares) public view virtual returns (uint256, uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        // TODO: Check math calculation for both cases
        return supply == 0
            ? (shares, shares)
            : (shares.mulDivDown(baseActive, supply), shares.mulDivDown(quoteActive, supply));
    }

    /// @notice Calculates an amount of shares to mint based on an amount of base and quote tokens.
    function previewDeposit(uint256 amountBase, uint256 amountQuote) public view returns (uint256) {
        return convertToShares(amountBase, amountQuote);
    }

    /// @notice Calculates an amount of base and quote tokens to deposit based on an amount of shares.
    function previewMint(uint256 shares) public view returns (uint256, uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        // TODO: Check for the calculation when supply is not 0 (especially withe ach return value depending on totalAssets)
        return supply == 0
            ? (shares, calculateQuoteAmount(shares))
            : (shares.mulDivUp(baseActive, supply), shares.mulDivUp(quoteActive, supply));
    }

    /// @notice Calculates an amount of shares to withdraw based on an amount of base tokens.
    function previewWithdraw(uint256 amountBase) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        // TODO: Check math calculation when supply is 0 and when it's not
        return supply == 0 ? amountBase : amountBase.mulDivUp(supply, baseActive);
    }

    /// @notice Calculates an amount of base and quote tokens to withdraw based on an amount of shares.
    function previewRedeem(uint256 shares) public view returns (uint256, uint256) {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the maximum deposit amount of a given address.
    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Returns the maximum mint amount of a given address.
    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Returns the available amount of base and quote tokens to withdraw for a given owner.
    function maxWithdraw(address owner) public view returns (uint256, uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    /// @notice Returns the available shares to redeem for a given owner.
    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                        VERTEX SLOW TRANSACTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Submits a slow mode transaction to Vertex.
    /// @dev More information about slow mode transactions:
    /// https://vertex-protocol.gitbook.io/docs/developer-resources/api/withdrawing-on-chain
    /// @param transaction The transaction to submit.
    function _submitSlowModeTransaction(bytes memory transaction) internal {
        // Deposit collateral doens't have fees.
        if (uint8(transaction[0]) != uint8(IEndpoint.TransactionType.DepositCollateral)) {
            // Fetch payment fee.
            paymentToken.transferFrom(factory, address(this), 1000000);
        }

        endpoint.submitSlowModeTransaction(transaction);
    }

    /*//////////////////////////////////////////////////////////////
                       DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Hook executed in a deposit or mint function.
    /// @dev This function transfers the tokens from the user, sends two slow-mode transactions
    // to Vertex, and updates internal balances.
    /// @param amountBase The amount of base tokens to deposit.
    /// @param amountQuote The amount of quote tokens to deposit.
    /// @param receiver The address that will receive the shares.
    /// @param shares The amount of shares to mint.
    function _depositLogic(uint256 amountBase, uint256 amountQuote, address receiver, uint256 shares) internal {
        // Transfer both tokens before minting or ERC777s could reenter.
        baseToken.safeTransferFrom(msg.sender, address(this), amountBase);
        quoteToken.safeTransferFrom(msg.sender, address(this), amountQuote);

        IEndpoint.DepositCollateral memory depositBase =
            IEndpoint.DepositCollateral(contractSubaccount, productId, uint128(amountBase));
        // NOTE: Assumes quote token is USDC, so product id is 0.
        IEndpoint.DepositCollateral memory depositQuote =
            IEndpoint.DepositCollateral(contractSubaccount, 0, uint128(amountQuote));

        // Send deposit requests to Vertex.
        _submitSlowModeTransaction(
            abi.encodePacked(uint8(IEndpoint.TransactionType.DepositCollateral), abi.encode(depositBase))
        );
        _submitSlowModeTransaction(
            abi.encodePacked(uint8(IEndpoint.TransactionType.DepositCollateral), abi.encode(depositQuote))
        );

        // Add the current amounts of base and quote tokens.
        baseActive += amountBase;
        quoteActive += amountQuote;

        // Mint shares equivalent to deposit liquidity.
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amountBase, amountQuote, shares);
    }

    /// @notice Hook executed in a withdraw or redeem function.
    /// @dev This function sends two slow-mode transactions to Vertex, and updates internal balances.
    /// @param amountBase The amount of base tokens to withdraw from Vertex.
    /// @param amountQuote The amount of quote tokens to withdraw from Vertex.
    /// @param owner The address from which the shares are burned from.
    /// @param shares The amount of shares to burn.
    function _withdrawLogic(uint256 amountBase, uint256 amountQuote, address owner, uint256 shares) internal {
        // TODO: Fetch fees from Vertex (add it as extra of baes and quote amounts)
        IEndpoint.WithdrawCollateral memory withdrawalBase =
            IEndpoint.WithdrawCollateral(contractSubaccount, productId, uint128(amountBase), 0);
        // NOTE: Assumes quote token is USDC, so product id is 0.
        IEndpoint.WithdrawCollateral memory withdrawalQuote =
            IEndpoint.WithdrawCollateral(contractSubaccount, 0, uint128(amountQuote), 0);

        // Send withdraw requests to Vertex.
        _submitSlowModeTransaction(
            abi.encodePacked(uint8(IEndpoint.TransactionType.WithdrawCollateral), abi.encode(withdrawalBase))
        );
        _submitSlowModeTransaction(
            abi.encodePacked(uint8(IEndpoint.TransactionType.WithdrawCollateral), abi.encode(withdrawalQuote))
        );

        // Subtract the amounts of each token from the active market making balance.
        baseActive -= amountBase;
        quoteActive -= amountQuote;

        // Add the amounts of each token as pending.
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            basePending[msg.sender] += amountBase;
            quotePending[msg.sender] += amountQuote;
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, owner, amountBase, amountQuote, shares);
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
}
