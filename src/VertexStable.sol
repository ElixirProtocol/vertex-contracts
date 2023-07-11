// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {VertexFactory} from "./VertexFactory.sol";
import {IClearinghouse} from "./interfaces/clearinghouse/IClearinghouse.sol";
import {IEndpoint} from "./interfaces/IEndpoint.sol";

/// @title Elixir-based vault for Vertex
/// @author The Elixir Team
/// @notice Liquidity vault aggregator for marketing making in Vertex Protocol.
contract VertexStable is ERC20, Owned {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The ERC20 instance of the base token.
    ERC20 public immutable baseToken;

    /// @notice Total amount of base tokens managed by this vault.
    uint256 public baseCurrent;

    /// @notice The ERC20 instance of the quote token.
    ERC20 public immutable quoteToken;

    /// @notice Total amount of quote tokens managed by this vault.
    uint256 public quoteCurrent;

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

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(
        address indexed caller, address indexed owner, uint256 amountBase, uint256 amountQuote, uint256 shares
    );

    event WithdrawRequest(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 amountBase,
        uint256 amountQuote,
        uint256 shares
    );

    event Claim(address indexed receiver, uint256 claimBase, uint256 claimQuote);

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

    /// @notice Emitted when a deposit function is entered with a calculated amount of zero amount of shares.
    error ZeroShares();

    /// @notice Emitted when a redeem function is entered with an amount of shares that is equivalent to zero assets.
    error ZeroAssets();

    /// @notice Emitted when a claim function is entered with a pending balance of zero for the quote or base tokens.
    error ZeroClaim();

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
        endpoint = IEndpoint(VertexFactory(msg.sender).endpoint());

        // It may happen that the quote token of endpoint payments is not the quote token of the vault/product.
        ERC20 paymentToken = ERC20(IClearinghouse(endpoint.clearinghouse()).getQuote());

        // Fetch payment fee for linked signer transaciton.
        paymentToken.transferFrom(msg.sender, address(this), 1000000);
        paymentToken.approve(address(endpoint), type(uint256).max);

        // Link smart contract to Elixir's signer.
        contractSubaccount = bytes32(uint256(uint160(address(this))) << 96);
        bytes32 externalSubaccount = bytes32(uint256(uint160(VertexFactory(msg.sender).externalAccount())) << 96);
        IEndpoint.LinkSigner memory linkSigner = IEndpoint.LinkSigner(contractSubaccount, externalSubaccount, 0);
        bytes memory transactionData = abi.encodePacked(abi.encode(19), abi.encode(linkSigner));
        endpoint.submitSlowModeTransaction(transactionData);

        // Approve Vertex to transfer tokens.
        baseToken.approve(address(endpoint), type(uint256).max);
        quoteToken.approve(address(endpoint), type(uint256).max);
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

        // NOTE: Assumes quote token is USDC, so product id is 0.
        endpoint.depositCollateral(bytes12(contractSubaccount), 0, uint128(amountQuote));

        // Add the current amounts of base and quote tokens.
        baseCurrent += amountBase;
        quoteCurrent += amountQuote;

        // Mint shares equivalent to deposit liquidity.
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amountBase, amountQuote, shares);

        _afterDeposit(amountBase, amountQuote, shares);
    }

    function mint(uint256 shares, address receiver) external returns (uint256 amountBase, uint256 amountQuote) {
        (amountBase, amountQuote) = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Transfer both tokens before minting or ERC777s could reenter.
        baseToken.safeTransferFrom(msg.sender, address(this), amountBase);
        quoteToken.safeTransferFrom(msg.sender, address(this), amountQuote);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amountBase, amountQuote, shares);

        _afterDeposit(amountBase, amountQuote, shares);
    }

    /// @notice Sends a withdraw request for a given amount of base tokens for the equivalent amount of quote tokens.
    /// @param amountBase The amount of base tokens to withdraw.
    /// @param receiver The address to receive the withdrawn tokens.
    /// @param owner The owner of the shares to withdraw.
    function withdraw(uint256 amountBase, address receiver, address owner) external returns (uint256 shares) {
        shares = previewWithdraw(amountBase); // No need to check for rounding error, previewWithdraw rounds up.

        // Fetch amount of quote token to withdraw respective to the amount of base token.
        uint256 amountQuote = calculateQuoteAmount(amountBase);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        _beforeWithdraw(amountBase, amountQuote, shares);

        _burn(owner, shares);

        emit WithdrawRequest(msg.sender, receiver, owner, amountBase, amountQuote, shares);
    }

    /// @notice Sends a redeem request for a given amount of shares for the equivalent amount of base and quote tokens.
    /// @param shares The amount of shares to redeem.
    /// @param receiver The address to receive the redeemed tokens.
    /// @param owner The owner of the shares to redeem.
    function redeem(uint256 shares, address receiver, address owner)
        public
        returns (uint256 amountBase, uint256 amountQuote)
    {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        (amountBase, amountQuote) = previewRedeem(shares);
        if (amountBase == 0 && amountQuote == 0) revert ZeroAssets();

        _beforeWithdraw(amountBase, amountQuote, shares);

        _burn(owner, shares);

        emit WithdrawRequest(msg.sender, receiver, owner, amountBase, amountQuote, shares);
    }

    /// @notice Claims all received base and quote tokens from the pending balance.
    /// @param receiver The address to receive the claimed tokens.
    function claim(address receiver) external returns (uint256 claimBase, uint256 claimQuote) {
        claimBase = basePending[msg.sender];
        claimQuote = quotePending[msg.sender];

        if (claimBase == 0 || claimQuote == 0) revert ZeroClaim();

        // Resets the pending balance of the receiver.
        basePending[msg.sender] = 0;
        quotePending[msg.sender] = 0;

        // Transfers the tokens after to prevent reentrancy.
        baseToken.safeTransfer(receiver, claimBase);
        quoteToken.safeTransfer(receiver, claimQuote);
    }

    /// @notice Sends a request withdrawal transaction to Vertex.
    /// @dev This function is only callable within the redeem and withdraw functions.
    /// @param amountBase The amount of base tokens to withdraw.
    /// @param amountQuote The amount of quote tokens to withdraw.
    function request(uint256 amountBase, uint256 amountQuote) private {
        IEndpoint.WithdrawCollateral memory withdrawalBase =
            IEndpoint.WithdrawCollateral(contractSubaccount, productId, uint128(amountBase), 0);
        // NOTE: Assumes quote token is USDC, so product id is 0.
        IEndpoint.WithdrawCollateral memory withdrawalQuote =
            IEndpoint.WithdrawCollateral(contractSubaccount, 0, uint128(amountQuote), 0);

        // Send base token withdraw request.
        endpoint.submitSlowModeTransaction(abi.encodePacked(abi.encode(2), abi.encode(withdrawalBase)));

        // Send quote token withdraw request.
        endpoint.submitSlowModeTransaction(abi.encodePacked(abi.encode(2), abi.encode(withdrawalQuote)));

        // Add the amounts of each token as pending.
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            basePending[msg.sender] += amountBase;
            quotePending[msg.sender] += amountQuote;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view returns (uint256, uint256) {
        return (baseCurrent, quoteCurrent);
    }

    function calculateQuoteAmount(uint256 amountBase) public view returns (uint256) {
        return baseCurrent == 0
            ? amountBase.mulDivDown(
                endpoint.getPriceX18(productId), 10 ** (18 + (baseToken.decimals() - quoteToken.decimals()))
            )
            : amountBase.mulDivDown(quoteCurrent.unsafeDiv(baseCurrent), 1 ether);
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
            : (shares.mulDivUp(baseCurrent, supply), shares.mulDivUp(quoteCurrent, supply));
    }

    function previewDeposit(uint256 amountBase, uint256 amountQuote) public view returns (uint256) {
        return convertToShares(amountBase, amountQuote);
    }

    function previewMint(uint256 shares) public view returns (uint256, uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        // TODO: Check for the calculation when supply is not 0 (especially withe ach return value depending on totalAssets)
        return supply == 0
            ? (shares, shares)
            : (shares.mulDivUp(baseCurrent, supply), shares.mulDivUp(quoteCurrent, supply));
    }

    function previewWithdraw(uint256 amountBase) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        // TODO: Check math calculation when supply is 0 and when it's not
        return supply == 0 ? amountBase : amountBase.mulDivUp(supply, baseCurrent);
    }

    function previewRedeem(uint256 shares) public view returns (uint256, uint256) {
        return convertToAssets(shares);
    }

    // /*//////////////////////////////////////////////////////////////
    //                  DEPOSIT/WITHDRAWAL LIMIT LOGIC
    // //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view returns (uint256, uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf[owner];
    }

    // /*//////////////////////////////////////////////////////////////
    //                       INTERNAL HOOKS LOGIC
    // //////////////////////////////////////////////////////////////*/

    function _beforeWithdraw(uint256 amountBase, uint256 amountQuote, uint256) internal {
        // TODO: Fetch fees from Vertex (add it as extra of baes and quote amounts)
        request(amountBase, amountQuote);
    }

    function _afterDeposit(uint256 amountBase, uint256 amountQuote, uint256 shares) internal {
        // TODO: Checks after deposit?
    }
}
