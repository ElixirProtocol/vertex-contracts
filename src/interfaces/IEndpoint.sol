// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IClearinghouse} from "./IClearinghouse.sol";

interface IEndpoint {
    // events that we parse transactions into
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

    struct SlowModeConfig {
        uint64 timeout;
        uint64 txCount;
        uint64 txUpTo;
    }

    function clearinghouse() external view returns (IClearinghouse);

    function slowModeConfig() external view returns (SlowModeConfig memory);

    function executeSlowModeTransactions(uint32 count) external;

    function submitSlowModeTransaction(bytes calldata transaction) external;

    function getPriceX18(uint32 productId) external view returns (uint256);
}
