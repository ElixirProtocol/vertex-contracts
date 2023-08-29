// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {Utils} from "./utils/Utils.t.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

import {IClearinghouse} from "../src/interfaces/IClearinghouse.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";
import {VertexManager} from "../src/VertexManager.sol";

contract TestVertexManager is Test {
    using Math for uint256;

    Utils internal utils;

    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // Arbitrum mainnet addresses
    IEndpoint internal endpoint = IEndpoint(0xbbEE07B3e8121227AfCFe1E2B82772246226128e);
    IERC20Metadata internal paymentToken;
    IClearinghouse internal clearingHouse;

    // Elixir contracts
    VertexManager internal vertexManagerImplementation;
    ERC1967Proxy internal proxy;
    VertexManager internal vertexManager;

    // Tokens
    IERC20Metadata internal BTC = IERC20Metadata(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20Metadata internal USDC = IERC20Metadata(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20Metadata internal WETH = IERC20Metadata(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    /*//////////////////////////////////////////////////////////////
                                  USERS
    //////////////////////////////////////////////////////////////*/

    // Neutral users
    address internal ALICE;
    address internal BOB;

    // Elixir users
    address internal OWNER;

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    uint256 internal networkFork;
    string internal NETWORK_RPC_URL = vm.envString("ARBITRUM_RPC_URL");

    // Off-chain validator account that makes request on behalf of the vaults.
    address internal EXTERNAL_ACCOUNT;

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        utils = new Utils();
        address payable[] memory users = utils.createUsers(4);

        ALICE = users[0];
        vm.label(ALICE, "Alice");

        BOB = users[1];
        vm.label(BOB, "Bob");

        OWNER = users[2];
        vm.label(OWNER, "Owner");

        EXTERNAL_ACCOUNT = users[3];
        vm.label(EXTERNAL_ACCOUNT, "External Account");

        networkFork = vm.createFork(NETWORK_RPC_URL);

        vm.selectFork(networkFork);

        clearingHouse = IClearinghouse(endpoint.clearinghouse());

        paymentToken = IERC20Metadata(clearingHouse.getQuote());

        vm.startPrank(OWNER);

        // Deploy Manager implementation
        vertexManagerImplementation = new VertexManager();

        // Deploy proxy contract and point it to implementation
        proxy = new ERC1967Proxy(address(vertexManagerImplementation), "");

        // Wrap in ABI to support easier calls
        vertexManager = VertexManager(address(proxy));

        // Approve the manager to move USDC for fee payments.
        paymentToken.approve(address(vertexManager), type(uint256).max);

        // Deal payment token to the factory, which pays for the slow mode transactions of all the vaults.
        deal(address(paymentToken), OWNER, type(uint256).max);

        // Set the endpoint and external account of the contract.
        vertexManager.initialize(address(endpoint), EXTERNAL_ACCOUNT, 1000000);

        vm.stopPrank();

        // Clear any external slow-mode txs from the Vertex queue.
        processSlowModeTxs();
    }

    function depositSetUp() public {
        vm.selectFork(networkFork);
        vm.startPrank(OWNER);

        // Create BTC spot pool with BTC and USDC as tokens.
        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        for (uint256 i = 0; i < tokens.length; i++) {
            vertexManager.addPoolToken(1, tokens[i], hardcaps[i]);
        }

        // Add token support.
        vertexManager.updateToken(address(USDC), 0);
        vertexManager.updateToken(address(BTC), 1);

        vm.stopPrank();
    }

    function perpDepositSetUp() public {
        vm.selectFork(networkFork);
        vm.startPrank(OWNER);

        // Create BTC PERP pool with BTC, USDC, and ETH as tokens.
        address[] memory tokens = new address[](3);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);
        tokens[2] = address(WETH);

        uint256[] memory hardcaps = new uint256[](3);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;
        hardcaps[2] = type(uint256).max;

        for (uint256 i = 0; i < tokens.length; i++) {
            vertexManager.addPoolToken(2, tokens[i], hardcaps[i]);
        }

        // Add token support.
        vertexManager.updateToken(address(USDC), 0);
        vertexManager.updateToken(address(BTC), 1);
        vertexManager.updateToken(address(WETH), 3);

        vm.stopPrank();
    }

    function processSlowModeTxs() public {
        // Clear any external slow-mode txs from the Vertex queue.
        vm.warp(block.timestamp + 259200);
        IEndpoint.SlowModeConfig memory queue = endpoint.slowModeConfig();
        endpoint.executeSlowModeTransactions(uint32(queue.txCount - queue.txUpTo));
    }

    /*//////////////////////////////////////////////////////////////
                         DEPOSIT/WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositInvalidInputs() public {
        vm.selectFork(networkFork);

        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidAmountsLength.selector, amounts));

        vertexManager.deposit(0, amounts, address(this));

        amounts = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidAmountsLength.selector, amounts));
        vertexManager.deposit(0, amounts, address(this));
    }

    function testUnbalancedDeposit() public {
        depositSetUp();

        uint256[] memory amounts = new uint256[](2);
        // 1 BTC
        amounts[0] = 1 ether;
        // 1 USDC
        amounts[1] = 1;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.UnbalancedAmounts.selector, 1, amounts));
        vertexManager.deposit(1, amounts, address(this));
    }

    function testFailDepositWithNotEnoughApproval(uint256 amountBTC) public {
        if (amountBTC == 0) amountBTC = 1;
        depositSetUp();

        // Calculate USDC needed.
        uint256 amountUSDC = vertexManager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(vertexManager), amountBTC / 2);
        USDC.approve(address(vertexManager), amountUSDC / 2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vertexManager.deposit(1, amounts, address(this));
    }

    function testFailWithdrawWithNoBalance(uint256 amountBTC) public {
        if (amountBTC == 0) amountBTC = 1;
        depositSetUp();

        uint256 amountUSDC = vertexManager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vertexManager.withdraw(1, amounts, 0);
    }

    function testWithdrawInvalidFee() public {
        depositSetUp();

        uint256 amountBTC = 1 * 10 ** 8;
        uint256 amountUSDC = vertexManager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidAmountsLength.selector, amounts));
        vertexManager.withdraw(1, amounts, 69);
    }

    function testUnbalancedWithdraw() public {
        depositSetUp();

        uint256[] memory amounts = new uint256[](2);
        // 1 BTC
        amounts[0] = 1 ether;
        // 1 USDC
        amounts[1] = 1;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.UnbalancedAmounts.selector, 1, amounts));
        vertexManager.withdraw(1, amounts, 0);
    }

    function testHardcapReached() public {
        depositSetUp();

        vm.prank(OWNER);
        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = 0;
        hardcaps[1] = 0;

        vertexManager.updatePoolHardcaps(1, hardcaps);

        uint256 amountBTC = 1 * 10 ** 8;
        uint256 amountUSDC = vertexManager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.HardcapReached.selector, address(BTC), 0, 0, amountBTC));
        vertexManager.deposit(1, amounts, address(this));
    }

    function testSingleDepositSpot() public {
        depositSetUp();

        uint256 amountBTC = 1 * 10 ** 8 + vertexManager.getWithdrawFee(address(BTC));
        uint256 amountUSDC = vertexManager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(vertexManager), amountBTC);
        USDC.approve(address(vertexManager), amountUSDC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vertexManager.deposit(1, amounts, address(this));

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        vertexManager.withdraw(1, amounts, 0);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), address(vertexManager), amountUSDC);

        // Create tokens to claim
        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        vertexManager.claim(address(this), tokens);

        vertexManager.claimFees(tokens);
    }

    function testDoubleDepositSpot() public {
        depositSetUp();

        uint256 amountBTC = 1 * 10 ** 8;
        uint256 amountUSDC = vertexManager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC * 2);
        deal(address(USDC), address(this), amountUSDC * 2);

        BTC.approve(address(vertexManager), amountBTC * 2);
        USDC.approve(address(vertexManager), amountUSDC * 2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vertexManager.deposit(1, amounts, address(this));

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        vertexManager.deposit(1, amounts, address(this));

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        amountBTC = 1 * 10 ** 8;
        amountUSDC = vertexManager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vertexManager.withdraw(1, amounts, 0);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), address(vertexManager), amountUSDC * 2);

        // Create tokens to claim
        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        vertexManager.claim(address(this), tokens);

        vertexManager.claimFees(tokens);
    }

    function testSingleDepositPerp() public {
        perpDepositSetUp();

        // Deposit 1 BTC, 0 USDC, and 1 WETH
        uint256 amountBTC = 1 * 10 ** 8;
        uint256 amountUSDC = 0;
        uint256 amountWETH = 1 ether;

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);
        deal(address(WETH), address(this), amountWETH);

        BTC.approve(address(vertexManager), amountBTC);
        USDC.approve(address(vertexManager), amountUSDC);
        WETH.approve(address(vertexManager), amountWETH);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;
        amounts[2] = amountWETH;

        vertexManager.deposit(2, amounts, address(this));

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        vertexManager.withdraw(2, amounts, 0);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();

        // Create tokens to claim
        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        vertexManager.claim(address(this), tokens);

        vertexManager.claimFees(tokens);
    }

    function testSingleDepositSpotBalanced() public {
        depositSetUp();

        uint256 amountBTC = 1 * 10 ** 8 + vertexManager.getWithdrawFee(address(BTC));
        uint256 amountUSDC = vertexManager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(vertexManager), amountBTC);
        USDC.approve(address(vertexManager), amountUSDC);

        vertexManager.depositBalanced(1, amountBTC, 0, type(uint256).max, address(this));

        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = amountBTC;
        expectedAmounts[1] = amountUSDC;

        assertEq(vertexManager.getUserActiveAmounts(1, address(this)), expectedAmounts);
        assertEq(vertexManager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(vertexManager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        expectedAmounts[0] = 0;
        expectedAmounts[1] = 0;

        vertexManager.withdrawBalanced(1, amountBTC, 0);

        assertEq(vertexManager.getUserActiveAmounts(1, address(this)), expectedAmounts);
        assertEq(vertexManager.pendingBalances(address(this), address(BTC)), 1 * 10 ** 8);
        assertEq(vertexManager.pendingBalances(address(this), address(USDC)), amountUSDC);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), address(vertexManager), amountUSDC);

        // Create tokens to claim
        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        vertexManager.claim(address(this), tokens);

        assertEq(vertexManager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(vertexManager.pendingBalances(address(this), address(USDC)), 0);

        vertexManager.claimFees(tokens);
    }

    function testSingleDepositBalanced() public {
        perpDepositSetUp();

        vm.expectRevert(abi.encodeWithSelector(VertexManager.NotSpotPool.selector, 2));
        vertexManager.depositBalanced(2, 69, 0, type(uint256).max, address(this));

        vm.expectRevert(abi.encodeWithSelector(VertexManager.NotSpotPool.selector, 2));
        vertexManager.withdrawBalanced(2, 69, 0);
    }

    function testSingleDepositBalancedSlippage() public {
        depositSetUp();

        uint256 amountBTC = 1 * 10 ** 8 + vertexManager.getWithdrawFee(address(BTC));
        uint256 amountUSDC = vertexManager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        vm.expectRevert(
            abi.encodeWithSelector(VertexManager.SlippageTooHigh.selector, amountUSDC, amountUSDC * 2, amountUSDC * 4)
        );
        vertexManager.depositBalanced(1, amountBTC, amountUSDC * 2, amountUSDC * 4, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            POOL MANAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function testAddAndUpdatePool() public {
        vm.selectFork(networkFork);
        vm.startPrank(OWNER);

        // Create BTC spot pool with BTC and USDC as tokens.
        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        for (uint256 i = 0; i < tokens.length; i++) {
            vertexManager.addPoolToken(1, tokens[i], hardcaps[i]);
        }

        // Get the pool data.
        (address[] memory tokens_, uint256[] memory hardcaps_,) = vertexManager.getPool(1);

        assertEq(tokens_, tokens);
        assertEq(hardcaps_, hardcaps);

        hardcaps[0] = 0;
        hardcaps[1] = 0;

        vertexManager.updatePoolHardcaps(1, hardcaps);

        // Get the pool data.
        (tokens_, hardcaps_,) = vertexManager.getPool(1);

        assertEq(tokens_, tokens);
        assertEq(hardcaps_, hardcaps);
    }

    function testUnauthorizedAddAndUpdate() public {
        vm.selectFork(networkFork);

        uint256[] memory hardcaps = new uint256[](2);

        vm.expectRevert();
        vertexManager.updatePoolHardcaps(1, hardcaps);

        vm.expectRevert();
        vertexManager.addPoolToken(1, address(0xdead), 69);
    }

    function testIsPoolAdded() public {
        vm.selectFork(networkFork);

        // Get the pool data.
        (address[] memory tokens_, uint256[] memory hardcaps_,) = vertexManager.getPool(2);

        assertTrue(tokens_.length == 0);
        assertTrue(hardcaps_.length == 0);
    }

    /*//////////////////////////////////////////////////////////////
                             PAUSED TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositsPaused() public {
        vm.prank(OWNER);
        vertexManager.pause(true, false, false);

        uint256[] memory amounts = new uint256[](2);

        vm.expectRevert(VertexManager.DepositsPaused.selector);
        vertexManager.deposit(1, amounts, address(this));
    }

    function testWithdrawalsPaused() public {
        vm.prank(OWNER);
        vertexManager.pause(false, true, false);

        uint256[] memory amounts = new uint256[](2);

        vm.expectRevert(VertexManager.WithdrawalsPaused.selector);
        vertexManager.withdraw(1, amounts, 0);
    }

    function testClaimsPaused() public {
        vm.prank(OWNER);
        vertexManager.pause(false, false, true);

        address[] memory tokens = new address[](2);

        vm.expectRevert(VertexManager.ClaimsPaused.selector);
        vertexManager.claim(address(this), tokens);
    }

    /*//////////////////////////////////////////////////////////////
                              TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function testAddAndUpdateToken() public {
        vm.startPrank(OWNER);

        assertEq(vertexManager.tokenToProduct(address(BTC)), 0);

        vertexManager.updateToken(address(BTC), 1);

        assertEq(vertexManager.tokenToProduct(address(BTC)), 1);

        vertexManager.updateToken(address(BTC), 2);

        assertEq(vertexManager.tokenToProduct(address(BTC)), 2);
    }

    function testFailUpdateToken() public {
        vertexManager.updateToken(address(BTC), 69);
    }

    /*//////////////////////////////////////////////////////////////
                              FEES TESTS
    //////////////////////////////////////////////////////////////*/

    function testFailApplyFees() public {
        vm.selectFork(networkFork);

        uint256[] memory fees = new uint256[](0);

        vertexManager.applyFees(1, address(0xdead), fees);
    }

    function testApplyFees() public {
        depositSetUp();

        uint256 amountBTC = 1 * 10 ** 8 + vertexManager.getWithdrawFee(address(BTC));
        uint256 amountUSDC = vertexManager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(vertexManager), amountBTC);
        USDC.approve(address(vertexManager), amountUSDC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vertexManager.deposit(1, amounts, address(this));

        uint256[] memory _fees = new uint256[](2);
        _fees[0] = 1;
        _fees[1] = 1;

        vm.prank(OWNER);
        vertexManager.applyFees(1, address(this), _fees);
    }

    function testFeesTooHigh() public {
        depositSetUp();

        uint256 amountBTC = 1 * 10 ** 8 + vertexManager.getWithdrawFee(address(BTC));
        uint256 amountUSDC = vertexManager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(vertexManager), amountBTC);
        USDC.approve(address(vertexManager), amountUSDC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vertexManager.deposit(1, amounts, address(this));

        uint256[] memory _fees = new uint256[](2);
        _fees[0] = type(uint256).max;
        _fees[1] = 1;

        vm.prank(OWNER);
        vm.expectRevert();
        vertexManager.applyFees(1, address(this), _fees);
    }

    /*//////////////////////////////////////////////////////////////
                              PROXY TESTS
    //////////////////////////////////////////////////////////////*/

    function testInitialize() public {
        // Deploy proxy contract and point it to implementation
        ERC1967Proxy tempProxy = new ERC1967Proxy(address(vertexManagerImplementation), "");
        VertexManager tempVertexManager = VertexManager(address(tempProxy));

        // Expect revert by trying to initliaze the implementation contract.
        vm.expectRevert();
        vertexManagerImplementation.initialize(address(0), address(0), 0);

        // Expect revert for not enough funds to set up linked signer.
        vm.expectRevert();
        tempVertexManager.initialize(address(endpoint), EXTERNAL_ACCOUNT, 1000000);

        // Approve the manager to move USDC for fee payments.
        paymentToken.approve(address(tempVertexManager), type(uint256).max);

        // Deal payment token to the factory, which pays for the slow mode transactions of all the vaults.
        deal(address(paymentToken), address(this), type(uint256).max);

        tempVertexManager.initialize(address(endpoint), EXTERNAL_ACCOUNT, 1000000);
    }

    function testFailDoubleInitiliaze() public {
        vertexManager.initialize(address(0), address(0), 0);
    }

    function testAuthorizedUpgrade() public {
        vm.startPrank(OWNER);

        // Deploy 2nd implementation
        VertexManager vertexManager2 = new VertexManager();

        vertexManager.upgradeTo(address(vertexManager2));
    }

    function testFailUnauthorizedUpgrade() public {
        vertexManager.upgradeTo(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                              OTHER TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetWithdrawFee() public {
        vm.expectRevert();
        vertexManager.getWithdrawFee(address(0xdead));
    }

    function testUpdateSlowModeFee() public {
        vm.expectRevert();
        vertexManager.updateSlowModeFee(69);

        vm.prank(OWNER);
        vertexManager.updateSlowModeFee(69);
    }
}
