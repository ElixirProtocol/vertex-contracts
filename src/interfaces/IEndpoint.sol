// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IClearinghouse} from "src/interfaces/IClearinghouse.sol";

interface IEndpoint {
    enum TransactionType {
        LiquidateSubaccount,
        DepositCollateral,
        WithdrawCollateral,
        SpotTick,
        UpdatePrice,
        SettlePnl,
        MatchOrders,
        DepositInsurance,
        ExecuteSlowMode,
        MintLp,
        BurnLp,
        SwapAMM,
        MatchOrderAMM,
        DumpFees,
        ClaimSequencerFees,
        PerpTick,
        ManualAssert,
        Rebate,
        UpdateProduct,
        LinkSigner,
        UpdateFeeRates
    }

    struct DepositCollateral {
        bytes32 sender;
        uint32 productId;
        uint128 amount;
    }

    struct WithdrawCollateral {
        bytes32 sender;
        uint32 productId;
        uint128 amount;
        uint64 nonce;
    }

    struct LinkSigner {
        bytes32 sender;
        bytes32 signer;
        uint64 nonce;
    }

    struct SlowModeTx {
        uint64 executableAt;
        address sender;
        bytes tx;
    }

    /// @notice Returns the Clearinghouse contract.
    function clearinghouse() external view returns (IClearinghouse);

    /// @notice Returns the slow-mode queue state.
    function getSlowModeTx(uint64 idx) external view returns (SlowModeTx memory, uint64, uint64);

    /// @notice Executes a submitted slow-mode transaction.
    function executeSlowModeTransaction() external;

    /// @notice Submits a slow-mode transaction to Vertex.
    function submitSlowModeTransaction(bytes calldata transaction) external;

    /// @notice Submits a deposit transaction to Vertex.
    function depositCollateralWithReferral(
        bytes12 subaccountName,
        uint32 productId,
        uint128 amount,
        string calldata referralCode
    ) external;

    /// @notice Returns a slow-mode transaction.
    function slowModeTxs(uint64 txId) external view returns (uint64 executableAt, address sender, bytes calldata tx);

    /// @notice Gets the price of a product.
    function getPriceX18(uint32 productId) external view returns (uint256);
}
