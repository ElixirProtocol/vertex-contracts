// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {VertexContracts} from "./VertexContracts.sol";
import {VertexStable} from "../src/VertexStable.sol";
import {VertexFactory} from "../src/VertexFactory.sol";

import {IEndpoint} from "../src/interfaces/IEndpoint.sol";

contract TestVertexStable is Test, VertexContracts {
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    VertexStable internal vault;

    /*//////////////////////////////////////////////////////////////
                                  TESTS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Fork network, deploy factory, and prepare contracts.
        factorySetUp();

        // Deploy a VertexStable vault.
        vm.prank(FACTORY_OWNER);
        vault = VertexStable(vertexFactory.deployVault(1, baseToken, quoteToken));

        // Advance time for slow-mode tx.
        vm.warp(block.timestamp + 259200);

        // Fetch slow mode queue.
        IEndpoint.SlowModeConfig memory queue = endpoint.slowModeConfig();

        // Empty queue, which also executes linked signer tx.
        endpoint.executeSlowModeTransactions(uint32(queue.txCount - queue.txUpTo));
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositWithdraw() public {
        uint256 amountBase = 10 ** baseToken.decimals();
        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), address(this), amountBase);
        deal(address(quoteToken), address(this), amountQuote);

        baseToken.approve(address(vault), amountBase);
        quoteToken.approve(address(vault), amountQuote);

        uint256 preDepositBalBase = baseToken.balanceOf(address(this));
        uint256 preDepositBalQuote = quoteToken.balanceOf(address(this));

        uint256 shares = vault.deposit(amountBase, 1, amountQuote, address(this));

        assertEq(shares, vault.balanceOf(address(this)));

        (uint256 convertedBase, uint256 convertedQuote) = vault.convertToAssets(shares);

        // Advance time for deposit slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        assertEq(convertedBase, amountBase);
        assertEq(convertedQuote, amountQuote);
        assertEq(vault.baseActive(), amountBase);
        assertEq(vault.quoteActive(), amountQuote);
        assertEq(vault.balanceOf(address(this)), amountBase + amountQuote);
        assertEq(baseToken.balanceOf(address(this)), preDepositBalBase - amountBase);
        assertEq(quoteToken.balanceOf(address(this)), preDepositBalQuote - amountQuote);
        assertEq(baseToken.balanceOf(address(vault)), 0);
        assertEq(quoteToken.balanceOf(address(vault)), 0);

        vault.withdraw(amountBase, address(this), address(this));

        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(vault.totalSupply(), 0);

        // Advance time for withdraw slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        assertEq(baseToken.balanceOf(address(vault)), amountBase);
        assertEq(quoteToken.balanceOf(address(vault)), amountQuote);

        vault.claim(address(this));

        assertEq(baseToken.balanceOf(address(vault)), 0);
        assertEq(quoteToken.balanceOf(address(vault)), 0);
        assertEq(vault.baseActive(), 0);
        assertEq(vault.quoteActive(), 0);
        assertEq(baseToken.balanceOf(address(this)), preDepositBalBase);
        assertEq(quoteToken.balanceOf(address(this)), preDepositBalQuote);
    }

    function testDepositRedeem() public {
        uint256 amountBase = 10 ** baseToken.decimals();
        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), address(this), amountBase);
        deal(address(quoteToken), address(this), amountQuote);

        baseToken.approve(address(vault), amountBase);
        quoteToken.approve(address(vault), amountQuote);

        uint256 preDepositBalBase = baseToken.balanceOf(address(this));
        uint256 preDepositBalQuote = quoteToken.balanceOf(address(this));

        uint256 shares = vault.deposit(amountBase, 1, amountQuote, address(this));

        assertEq(shares, vault.balanceOf(address(this)));

        (uint256 convertedBase, uint256 convertedQuote) = vault.convertToAssets(shares);

        // Advance time for deposit slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        assertEq(convertedBase, amountBase);
        assertEq(convertedQuote, amountQuote);
        assertEq(vault.baseActive(), amountBase);
        assertEq(vault.quoteActive(), amountQuote);
        assertEq(vault.balanceOf(address(this)), amountBase + amountQuote);
        assertEq(baseToken.balanceOf(address(this)), preDepositBalBase - amountBase);
        assertEq(quoteToken.balanceOf(address(this)), preDepositBalQuote - amountQuote);
        assertEq(baseToken.balanceOf(address(vault)), 0);
        assertEq(quoteToken.balanceOf(address(vault)), 0);

        vault.redeem(shares, address(this), address(this));

        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(vault.totalSupply(), 0);

        // Advance time for withdraw slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        assertEq(baseToken.balanceOf(address(vault)), amountBase);
        assertEq(quoteToken.balanceOf(address(vault)), amountQuote);

        vault.claim(address(this));

        assertEq(baseToken.balanceOf(address(vault)), 0);
        assertEq(quoteToken.balanceOf(address(vault)), 0);
        assertEq(vault.baseActive(), 0);
        assertEq(vault.quoteActive(), 0);
        assertEq(baseToken.balanceOf(address(this)), preDepositBalBase);
        assertEq(quoteToken.balanceOf(address(this)), preDepositBalQuote);
    }

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

        vault.withdraw(amountBase, address(this), address(this));
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

        vault.redeem(shares, address(this), address(this));
    }

    // TODO: Deposit + withdraw with funds already in vault.
    // TODO: Deposit + redeem with funds already in vault.

    /*///////////////////////////////////////////////////////////////
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

        vault.withdraw(amountBase, address(this), address(this));
    }

    function testFailRedeemWithNotEnoughBalance(uint256 amountBase) public {
        uint256 amountQuote = vault.calculateQuoteAmount(amountBase);

        deal(address(baseToken), address(this), amountBase / 2);
        deal(address(quoteToken), address(this), amountQuote / 2);

        vault.deposit(amountBase / 2, 1, amountQuote, address(this));

        // Advance time for deposit slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        vault.redeem(amountBase, address(this), address(this));
    }

    function testFailWithdrawWithNoBalance(uint256 amountBase) public {
        if (amountBase == 0) amountBase = 1;
        vault.withdraw(amountBase, address(this), address(this));
    }

    function testFailRedeemWithNoBalance(uint256 amountBase) public {
        vault.redeem(amountBase, address(this), address(this));
    }

    function testFailDepositWithNoApproval(uint256 amountBase) public {
        vault.deposit(amountBase, 1, type(uint256).max, address(this));
    }

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

        vault.withdraw(amountBase, address(this), address(this));

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

        vault.redeem(shares, address(this), address(this));

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

        vault.redeem(shares, address(this), address(this));

        // Advance time for redeem slow-mode tx.
        vm.warp(block.timestamp + 259200);
        endpoint.executeSlowModeTransactions(2);

        vault.claim(address(this));

        vault.claim(address(this));
    }
}
