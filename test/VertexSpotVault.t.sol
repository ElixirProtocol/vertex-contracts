// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {VertexContracts} from "./VertexContracts.t.sol";
import {VertexSpotVault} from "../src/VertexSpotVault.sol";
import {VertexFactory} from "../src/VertexFactory.sol";

import {IEndpoint} from "../src/interfaces/IEndpoint.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "openzeppelin/utils/math/Math.sol";

contract TestVertexSpotVault is Test, VertexContracts {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    VertexSpotVault internal vault;

    /*//////////////////////////////////////////////////////////////
                                  TESTS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Fork network, deploy factory, and prepare contracts.
        testSetUp();

        // Deploy a VertexSpotVault vault.
        vm.prank(FACTORY_OWNER);
        vault = VertexSpotVault(vertexFactory.deployVault(1, baseToken, quoteToken));

        // Advance time for slow-mode tx.
        vm.warp(block.timestamp + 259200);

        // Fetch slow mode queue.
        IEndpoint.SlowModeConfig memory queue = endpoint.slowModeConfig();

        // Empty queue, which also executes linked signer tx.
        endpoint.executeSlowModeTransactions(uint32(queue.txCount - queue.txUpTo));
    }

    /*//////////////////////////////////////////////////////////////
                             METADATA TESTS
    //////////////////////////////////////////////////////////////*/

    function testMetadata() public {
        assertEq(vault.name(), "Elixir LP Wrapped BTC-USD Coin (Arb1) for Vertex");
        assertEq(vault.symbol(), "elxr-WBTC-USDC");
        assertEq(vault.decimals(), 18);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testSingleDepositWithdraw(uint64 amountBase) public {
        if (amountBase == 0) amountBase = 1;

        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), ALICE, amountBase);
        deal(address(quoteToken), ALICE, amountQuote);

        vm.startPrank(ALICE);
        baseToken.approve(address(vault), amountBase);
        quoteToken.approve(address(vault), amountQuote);

        uint256 preDepositBalBase = baseToken.balanceOf(ALICE);
        uint256 preDepositBalQuote = quoteToken.balanceOf(ALICE);

        uint256 shares = vault.deposit(amountBase, 1, amountQuote, ALICE);

        // Advance time for deposit slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        assertEq(vault.baseActive(), amountBase);
        assertEq(vault.quoteActive(), amountQuote);
        assertEq(amountBase + amountQuote, shares);
        assertEq(vault.previewWithdraw(amountBase), shares);
        assertEq(vault.previewDeposit(amountBase, amountQuote), shares);
        assertEq(vault.totalSupply(), shares);
        (uint256 totalBase, uint256 totalQuote) = vault.totalAssets();
        assertEq(totalBase, amountBase);
        assertEq(totalQuote, amountQuote);
        assertEq(vault.balanceOf(ALICE), shares);
        (uint256 convertedBase, uint256 convertedQuote) = vault.convertToAssets(shares);
        assertEq(convertedBase, amountBase);
        assertEq(convertedQuote, amountQuote);
        assertEq(baseToken.balanceOf(ALICE), preDepositBalBase - amountBase);
        assertEq(quoteToken.balanceOf(ALICE), preDepositBalQuote - amountQuote);

        vault.withdraw(amountBase, ALICE);

        (convertedBase, convertedQuote) = vault.convertToAssets(vault.balanceOf(ALICE));

        assertEq(vault.totalSupply(), 0);
        assertEq(vault.balanceOf(ALICE), 0);
        assertEq(convertedBase, 0);
        assertEq(convertedQuote, 0);
        assertEq(vault.basePending(ALICE), preDepositBalBase);
        assertEq(vault.quotePending(ALICE), preDepositBalQuote);

        // // Advance time for withdraw slow-mode tx.
        // vm.warp(block.timestamp + 259200);
        // endpoint.executeSlowModeTransactions(2);

        // assertEq(baseToken.balanceOf(address(vault)), preDepositBalBase);
        // assertEq(quoteToken.balanceOf(address(vault)), preDepositBalQuote);

        // vault.claim(ALICE);

        // assertEq(baseToken.balanceOf(address(vault)), 0);
        // assertEq(quoteToken.balanceOf(address(vault)), 0);
        // assertEq(vault.baseActive(), 0);
        // assertEq(vault.quoteActive(), 0);
        // assertEq(vault.basePending(ALICE), 0);
        // assertEq(vault.quotePending(ALICE), 0);
        // assertEq(baseToken.balanceOf(ALICE), preDepositBalBase);
        // assertEq(quoteToken.balanceOf(ALICE), preDepositBalQuote);
    }

    function testSingleMintRedeem(uint64 shares) public {
        if (shares == 0) shares = 1;

        uint256 quoteCost = vault.calculateQuoteAmount(shares);

        deal(address(baseToken), ALICE, shares);
        deal(address(quoteToken), ALICE, quoteCost);

        vm.startPrank(ALICE);
        baseToken.approve(address(vault), shares);
        quoteToken.approve(address(vault), quoteCost);

        uint256 preDepositBalBase = baseToken.balanceOf(ALICE);
        uint256 preDepositBalQuote = quoteToken.balanceOf(ALICE);

        (uint256 amountBase, uint256 amountQuote) = vault.mint(shares, ALICE);

        // Advance time for deposit slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        assertEq(vault.baseActive(), amountBase);
        assertEq(vault.quoteActive(), amountQuote);
        assertEq(vault.previewWithdraw(amountBase), shares);
        assertEq(vault.previewDeposit(amountBase, amountQuote), shares);
        assertEq(vault.totalSupply(), shares);
        (uint256 totalBase, uint256 totalQuote) = vault.totalAssets();
        assertEq(totalBase, amountBase);
        assertEq(totalQuote, amountQuote);
        assertEq(vault.balanceOf(ALICE), shares);
        (uint256 convertedBase, uint256 convertedQuote) = vault.convertToAssets(shares);
        assertEq(convertedBase, amountBase);
        assertEq(convertedQuote, amountQuote);
        assertEq(baseToken.balanceOf(ALICE), preDepositBalBase - amountBase);
        assertEq(quoteToken.balanceOf(ALICE), preDepositBalQuote - amountQuote);

        vault.redeem(shares, ALICE);

        (convertedBase, convertedQuote) = vault.convertToAssets(vault.balanceOf(ALICE));

        assertEq(vault.totalSupply(), 0);
        assertEq(vault.balanceOf(ALICE), 0);
        assertEq(convertedBase, 0);
        assertEq(convertedQuote, 0);
        assertEq(vault.basePending(ALICE), preDepositBalBase);
        assertEq(vault.quotePending(ALICE), preDepositBalQuote);
    }

    // function testMultipleMintDepositRedeemWithdraw() public {
    //     // Scenario:
    //     // A = Alice, B = Bob
    //     //  ________________________________________________________
    //     // | Vault shares | A share | A assets | B share | B assets |
    //     // |========================================================|
    //     // | 1. Alice mints 10 shares (costs 10 WBTC and 300k USDC) |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         10   |      10 |(10, 300k)|       0 |        0 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 2. Bob deposits 20 WBTC tokens (mints 20 shares)       |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         30   |      10 |(10, 300k)|      20 |(20, 600k)|
    //     // |--------------|---------|----------|---------|----------|
    //     // | 3. Vault mutates by 30 WBTC and 900k USDC tokens...    |
    //     // |    (simulated yield returned from market making)...    |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         30   |      10 |(20, 600k)|      20 |(40, 1.2m)|
    //     // |--------------|---------|----------|---------|----------|
    //     // | 4. Alice deposits 20 WBTC and 600k USDC (mints 1333 shares)      |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         7333 |    3333 |     4999 |    4000 |     6000 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 5. Bob mints 2000 shares (costs 3001 assets)           |
    //     // |    NOTE: Bob's assets spent got rounded up             |
    //     // |    NOTE: Alice's vault assets got rounded up           |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         9333 |    3333 |     5000 |    6000 |     9000 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 6. Vault mutates by +3000 tokens...                    |
    //     // |    (simulated yield returned from strategy)            |
    //     // |    NOTE: Vault holds 17001 tokens, but sum of          |
    //     // |          assetsOf() is 17000.                          |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         9333 |    3333 |     6071 |    6000 |    10929 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 7. Alice redeem 1333 shares (2428 assets)              |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         8000 |    2000 |     3643 |    6000 |    10929 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 8. Bob withdraws 2928 assets (1608 shares)             |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         6392 |    2000 |     3643 |    4392 |     8000 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 9. Alice withdraws 3643 assets (2000 shares)           |
    //     // |    NOTE: Bob's assets have been rounded back up        |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         4392 |       0 |        0 |    4392 |     8001 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 10. Bob redeem 4392 shares (8001 tokens)               |
    //     // |--------------|---------|----------|---------|----------|
    //     // |            0 |       0 |        0 |       0 |        0 |
    //     // |______________|_________|__________|_________|__________|

    //     uint256 mutationUnderlyingAmount = 3000;

    //     underlying.mint(alice, 4000);

    //     hevm.prank(alice);
    //     underlying.approve(address(vault), 4000);

    //     assertEq(underlying.allowance(alice, address(vault)), 4000);

    //     underlying.mint(bob, 7001);

    //     hevm.prank(bob);
    //     underlying.approve(address(vault), 7001);

    //     assertEq(underlying.allowance(bob, address(vault)), 7001);

    //     // 1. Alice mints 2000 shares (costs 2000 tokens)
    //     hevm.prank(alice);
    //     uint256 aliceUnderlyingAmount = vault.mint(2000, alice);

    //     uint256 aliceShareAmount = vault.previewDeposit(aliceUnderlyingAmount);
    //     assertEq(vault.afterDepositHookCalledCounter(), 1);

    //     // Expect to have received the requested mint amount.
    //     assertEq(aliceShareAmount, 2000);
    //     assertEq(vault.balanceOf(alice), aliceShareAmount);
    //     assertEq(vault.convertToAssets(vault.balanceOf(alice)), aliceUnderlyingAmount);
    //     assertEq(vault.convertToShares(aliceUnderlyingAmount), vault.balanceOf(alice));

    //     // Expect a 1:1 ratio before mutation.
    //     assertEq(aliceUnderlyingAmount, 2000);

    //     // Sanity check.
    //     assertEq(vault.totalSupply(), aliceShareAmount);
    //     assertEq(vault.totalAssets(), aliceUnderlyingAmount);

    //     // 2. Bob deposits 4000 tokens (mints 4000 shares)
    //     hevm.prank(bob);
    //     uint256 bobShareAmount = vault.deposit(4000, bob);
    //     uint256 bobUnderlyingAmount = vault.previewWithdraw(bobShareAmount);
    //     assertEq(vault.afterDepositHookCalledCounter(), 2);

    //     // Expect to have received the requested underlying amount.
    //     assertEq(bobUnderlyingAmount, 4000);
    //     assertEq(vault.balanceOf(bob), bobShareAmount);
    //     assertEq(vault.convertToAssets(vault.balanceOf(bob)), bobUnderlyingAmount);
    //     assertEq(vault.convertToShares(bobUnderlyingAmount), vault.balanceOf(bob));

    //     // Expect a 1:1 ratio before mutation.
    //     assertEq(bobShareAmount, bobUnderlyingAmount);

    //     // Sanity check.
    //     uint256 preMutationShareBal = aliceShareAmount + bobShareAmount;
    //     uint256 preMutationBal = aliceUnderlyingAmount + bobUnderlyingAmount;
    //     assertEq(vault.totalSupply(), preMutationShareBal);
    //     assertEq(vault.totalAssets(), preMutationBal);
    //     assertEq(vault.totalSupply(), 6000);
    //     assertEq(vault.totalAssets(), 6000);

    //     // 3. Vault mutates by +3000 tokens...                    |
    //     //    (simulated yield returned from strategy)...
    //     // The Vault now contains more tokens than deposited which causes the exchange rate to change.
    //     // Alice share is 33.33% of the Vault, Bob 66.66% of the Vault.
    //     // Alice's share count stays the same but the underlying amount changes from 2000 to 3000.
    //     // Bob's share count stays the same but the underlying amount changes from 4000 to 6000.
    //     underlying.mint(address(vault), mutationUnderlyingAmount);
    //     assertEq(vault.totalSupply(), preMutationShareBal);
    //     assertEq(vault.totalAssets(), preMutationBal + mutationUnderlyingAmount);
    //     assertEq(vault.balanceOf(alice), aliceShareAmount);
    //     assertEq(
    //         vault.convertToAssets(vault.balanceOf(alice)),
    //         aliceUnderlyingAmount + (mutationUnderlyingAmount / 3) * 1
    //     );
    //     assertEq(vault.balanceOf(bob), bobShareAmount);
    //     assertEq(vault.convertToAssets(vault.balanceOf(bob)), bobUnderlyingAmount + (mutationUnderlyingAmount / 3) * 2);

    //     // 4. Alice deposits 2000 tokens (mints 1333 shares)
    //     hevm.prank(alice);
    //     vault.deposit(2000, alice);

    //     assertEq(vault.totalSupply(), 7333);
    //     assertEq(vault.balanceOf(alice), 3333);
    //     assertEq(vault.convertToAssets(vault.balanceOf(alice)), 4999);
    //     assertEq(vault.balanceOf(bob), 4000);
    //     assertEq(vault.convertToAssets(vault.balanceOf(bob)), 6000);

    //     // 5. Bob mints 2000 shares (costs 3001 assets)
    //     // NOTE: Bob's assets spent got rounded up
    //     // NOTE: Alices's vault assets got rounded up
    //     hevm.prank(bob);
    //     vault.mint(2000, bob);

    //     assertEq(vault.totalSupply(), 9333);
    //     assertEq(vault.balanceOf(alice), 3333);
    //     assertEq(vault.convertToAssets(vault.balanceOf(alice)), 5000);
    //     assertEq(vault.balanceOf(bob), 6000);
    //     assertEq(vault.convertToAssets(vault.balanceOf(bob)), 9000);

    //     // Sanity checks:
    //     // Alice and bob should have spent all their tokens now
    //     assertEq(underlying.balanceOf(alice), 0);
    //     assertEq(underlying.balanceOf(bob), 0);
    //     // Assets in vault: 4k (alice) + 7k (bob) + 3k (yield) + 1 (round up)
    //     assertEq(vault.totalAssets(), 14001);

    //     // 6. Vault mutates by +3000 tokens
    //     // NOTE: Vault holds 17001 tokens, but sum of assetsOf() is 17000.
    //     underlying.mint(address(vault), mutationUnderlyingAmount);
    //     assertEq(vault.totalAssets(), 17001);
    //     assertEq(vault.convertToAssets(vault.balanceOf(alice)), 6071);
    //     assertEq(vault.convertToAssets(vault.balanceOf(bob)), 10929);

    //     // 7. Alice redeem 1333 shares (2428 assets)
    //     hevm.prank(alice);
    //     vault.redeem(1333, alice, alice);

    //     assertEq(underlying.balanceOf(alice), 2428);
    //     assertEq(vault.totalSupply(), 8000);
    //     assertEq(vault.totalAssets(), 14573);
    //     assertEq(vault.balanceOf(alice), 2000);
    //     assertEq(vault.convertToAssets(vault.balanceOf(alice)), 3643);
    //     assertEq(vault.balanceOf(bob), 6000);
    //     assertEq(vault.convertToAssets(vault.balanceOf(bob)), 10929);

    //     // 8. Bob withdraws 2929 assets (1608 shares)
    //     hevm.prank(bob);
    //     vault.withdraw(2929, bob, bob);

    //     assertEq(underlying.balanceOf(bob), 2929);
    //     assertEq(vault.totalSupply(), 6392);
    //     assertEq(vault.totalAssets(), 11644);
    //     assertEq(vault.balanceOf(alice), 2000);
    //     assertEq(vault.convertToAssets(vault.balanceOf(alice)), 3643);
    //     assertEq(vault.balanceOf(bob), 4392);
    //     assertEq(vault.convertToAssets(vault.balanceOf(bob)), 8000);

    //     // 9. Alice withdraws 3643 assets (2000 shares)
    //     // NOTE: Bob's assets have been rounded back up
    //     hevm.prank(alice);
    //     vault.withdraw(3643, alice, alice);

    //     assertEq(underlying.balanceOf(alice), 6071);
    //     assertEq(vault.totalSupply(), 4392);
    //     assertEq(vault.totalAssets(), 8001);
    //     assertEq(vault.balanceOf(alice), 0);
    //     assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
    //     assertEq(vault.balanceOf(bob), 4392);
    //     assertEq(vault.convertToAssets(vault.balanceOf(bob)), 8001);

    //     // 10. Bob redeem 4392 shares (8001 tokens)
    //     hevm.prank(bob);
    //     vault.redeem(4392, bob, bob);
    //     assertEq(underlying.balanceOf(bob), 10930);
    //     assertEq(vault.totalSupply(), 0);
    //     assertEq(vault.totalAssets(), 0);
    //     assertEq(vault.balanceOf(alice), 0);
    //     assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
    //     assertEq(vault.balanceOf(bob), 0);
    //     assertEq(vault.convertToAssets(vault.balanceOf(bob)), 0);

    //     // Sanity check
    //     assertEq(underlying.balanceOf(address(vault)), 0);
    // }

    function testDepositWithdrawProcessed() public {}

    // These two tests below work as the deposit slow transaction will always be before the withdraw slow
    // transaction. Meaning that when the slow transaction are executed, the vault will have the funds to
    // withdraw. Important to point out that a user can deposit, withdraw, and claim when there are enough
    // funds in the vault from other users that haven't claimed yet, without needing Vertex to process the
    // slow transactions at all. The user whose funds were front-runned will be available as soon as the
    // first user's slow mode transactions are processed by Vertex, which will deposit and withdraw funds
    // to the vault, claimable by the front-runned user at that point.
    function testDepositWithdrawUnprocessed() public {
        uint256 amountBase = 10 ** baseToken.decimals();
        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), address(this), amountBase);
        deal(address(quoteToken), address(this), amountQuote);

        baseToken.approve(address(vault), amountBase);
        quoteToken.approve(address(vault), amountQuote);

        vault.deposit(amountBase, 1, amountQuote, address(this));

        vault.withdraw(amountBase, address(this));
    }

    function testDepositRedeemUnprocessed() public {
        uint256 amountBase = 10 ** baseToken.decimals();
        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), address(this), amountBase);
        deal(address(quoteToken), address(this), amountQuote);

        baseToken.approve(address(vault), amountBase);
        quoteToken.approve(address(vault), amountQuote);

        uint256 shares = vault.deposit(amountBase, 1, amountQuote, address(this));

        vault.previewRedeem(shares);

        vault.redeem(shares, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                 DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    function testFailDepositWithNotEnoughApproval(uint256 amountBase) public {
        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), address(this), amountBase);
        deal(address(quoteToken), address(this), amountQuote);

        baseToken.approve(address(vault), amountBase / 2);
        quoteToken.approve(address(vault), amountQuote / 2);

        vault.deposit(amountBase, 1, amountQuote, address(this));
    }

    function testFailWithdrawWithNotEnoughBalance(uint256 amountBase) public {
        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), address(this), amountBase / 2);
        deal(address(quoteToken), address(this), amountQuote / 2);

        vault.deposit(amountBase / 2, 1, amountQuote, address(this));

        // Advance time for deposit slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        vault.withdraw(amountBase, address(this));
    }

    function testFailRedeemWithNotEnoughBalance(uint256 amountBase) public {
        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), address(this), amountBase / 2);
        deal(address(quoteToken), address(this), amountQuote / 2);

        vault.deposit(amountBase / 2, 1, amountQuote, address(this));

        // Advance time for deposit slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        vault.redeem(amountBase, address(this));
    }

    function testFailWithdrawWithNoBalance(uint256 amountBase) public {
        if (amountBase == 0) amountBase = 1;
        vault.withdraw(amountBase, address(this));
    }

    function testFailRedeemWithNoBalance(uint256 amountBase) public {
        vault.redeem(amountBase, address(this));
    }

    function testFailDepositWithNoApproval(uint256 amountBase) public {
        vault.deposit(amountBase, 1, type(uint256).max, address(this));
    }

    function testFailMintWithNoApproval() public {
        vault.mint(1e18, address(this));
    }

    function testFailDepositZero() public {
        vault.deposit(0, 1, 2, address(this));
    }

    function testMintZero() public {
        vault.mint(0, address(this));

        assertEq(vault.balanceOf(address(this)), 0);
        (uint256 convertedBase, uint256 convertedQuote) = vault.convertToAssets(vault.balanceOf(address(this)));
        assertEq(convertedBase, 0);
        assertEq(convertedQuote, 0);
        assertEq(vault.totalSupply(), 0);
        (uint256 totalBase, uint256 totalQuote) = vault.totalAssets();
        assertEq(totalBase, 0);
        assertEq(totalQuote, 0);
    }

    function testFailRedeemZero() public {
        vault.redeem(0, address(this));
    }

    function testWithdrawZero() public {
        vault.withdraw(0, address(this));

        assertEq(vault.balanceOf(address(this)), 0);
        (uint256 convertedBase, uint256 convertedQuote) = vault.convertToAssets(vault.balanceOf(address(this)));
        assertEq(convertedBase, 0);
        assertEq(convertedQuote, 0);
        assertEq(vault.totalSupply(), 0);
        (uint256 totalBase, uint256 totalQuote) = vault.totalAssets();
        assertEq(totalBase, 0);
        assertEq(totalQuote, 0);
    }

    // function testVaultInteractionsForSomeoneElse() public {
    //     // init 2 users with a 1e18 balance
    //     address alice = address(0xABCD);
    //     address bob = address(0xDCBA);
    //     underlying.mint(alice, 1e18);
    //     underlying.mint(bob, 1e18);

    //     hevm.prank(alice);
    //     underlying.approve(address(vault), 1e18);

    //     hevm.prank(bob);
    //     underlying.approve(address(vault), 1e18);

    //     // alice deposits 1e18 for bob
    //     hevm.prank(alice);
    //     vault.deposit(1e18, bob);

    //     assertEq(vault.balanceOf(alice), 0);
    //     assertEq(vault.balanceOf(bob), 1e18);
    //     assertEq(underlying.balanceOf(alice), 0);

    //     // bob mint 1e18 for alice
    //     hevm.prank(bob);
    //     vault.mint(1e18, alice);
    //     assertEq(vault.balanceOf(alice), 1e18);
    //     assertEq(vault.balanceOf(bob), 1e18);
    //     assertEq(underlying.balanceOf(bob), 0);

    //     // alice redeem 1e18 for bob
    //     hevm.prank(alice);
    //     vault.redeem(1e18, bob, alice);

    //     assertEq(vault.balanceOf(alice), 0);
    //     assertEq(vault.balanceOf(bob), 1e18);
    //     assertEq(underlying.balanceOf(bob), 1e18);

    //     // bob withdraw 1e18 for alice
    //     hevm.prank(bob);
    //     vault.withdraw(1e18, alice, bob);

    //     assertEq(vault.balanceOf(alice), 0);
    //     assertEq(vault.balanceOf(bob), 0);
    //     assertEq(underlying.balanceOf(alice), 1e18);
    // }

    function testFailSlippageDeposit(uint256 amountBase) public {
        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), address(this), amountBase);
        deal(address(quoteToken), address(this), amountQuote);

        baseToken.approve(address(vault), amountBase);
        quoteToken.approve(address(vault), amountQuote);

        vault.deposit(amountBase, 1, amountQuote - 1, address(this));
    }

    function testFailDepositWithdrawClaimUnprocessed(uint256 amountBase) public {
        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), address(this), amountBase);
        deal(address(quoteToken), address(this), amountQuote);

        baseToken.approve(address(vault), amountBase);
        quoteToken.approve(address(vault), amountQuote);

        vault.deposit(amountBase, 1, amountQuote, address(this));

        // Advance time for deposit slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        vault.withdraw(amountBase, address(this));

        vault.claim(address(this));
    }

    function testFailDepositRedeemClaimUnprocessed(uint256 amountBase) public {
        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), address(this), amountBase);
        deal(address(quoteToken), address(this), amountQuote);

        baseToken.approve(address(vault), amountBase);
        quoteToken.approve(address(vault), amountQuote);

        uint256 shares = vault.deposit(amountBase, 1, amountQuote, address(this));

        // Advance time for deposit slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        vault.redeem(shares, address(this));

        vault.claim(address(this));
    }

    function testFailDoubleClaim(uint256 amountBase) public {
        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), address(this), amountBase);
        deal(address(quoteToken), address(this), amountQuote);

        baseToken.approve(address(vault), amountBase);
        quoteToken.approve(address(vault), amountQuote);

        uint256 shares = vault.deposit(amountBase, 1, amountQuote, address(this));

        // Advance time for deposit slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        vault.redeem(shares, address(this));

        // Advance time for redeem slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        vault.claim(address(this));

        vault.claim(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL PAUSED TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositsPaused() public {
        vm.prank(FACTORY_OWNER);
        vault.pause(true, false, false);

        vm.expectRevert(VertexSpotVault.DepositsPaused.selector);
        vault.deposit(1, 1, 1, address(this));

        vm.expectRevert(VertexSpotVault.DepositsPaused.selector);
        vault.mint(1, address(this));
    }

    function testWithdrawalsPaused() public {
        vm.prank(FACTORY_OWNER);
        vault.pause(false, true, false);

        vm.expectRevert(VertexSpotVault.WithdrawalsPaused.selector);
        vault.withdraw(1, address(this));

        vm.expectRevert(VertexSpotVault.WithdrawalsPaused.selector);
        vault.redeem(1, address(this));
    }

    function testClaimsPaused() public {
        vm.prank(FACTORY_OWNER);
        vault.pause(false, false, true);

        vm.expectRevert(VertexSpotVault.ClaimsPaused.selector);
        vault.claim(address(this));
    }
}
