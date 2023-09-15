// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {Utils} from "./utils/Utils.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

import {IClearinghouse} from "../src/interfaces/IClearinghouse.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";

import {VertexManager} from "../src/VertexManager.sol";
import {VertexRouter} from "../src/VertexRouter.sol";

contract TestVertexManager is Test {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // Arbitrum mainnet addresses
    IEndpoint public endpoint = IEndpoint(0xbbEE07B3e8121227AfCFe1E2B82772246226128e);
    IERC20Metadata public paymentToken;
    IClearinghouse public clearingHouse;

    // Elixir contracts
    VertexManager public vertexManagerImplementation;
    ERC1967Proxy public proxy;
    VertexManager public manager;

    // Tokens
    IERC20Metadata public BTC = IERC20Metadata(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20Metadata public USDC = IERC20Metadata(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20Metadata public WETH = IERC20Metadata(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    /*//////////////////////////////////////////////////////////////
                                  USERS
    //////////////////////////////////////////////////////////////*/

    // Neutral users
    address public alice;
    address public bob;

    // Elixir users
    address public owner;

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    // Utils contract.
    Utils public utils;

    // Network fork ID.
    uint256 public networkFork;

    // RPC URL for Arbitrum fork.
    string public networkRpcUrl = vm.envString("ARBITRUM_RPC_URL");

    // Off-chain validator account that makes request on behalf of the vaults.
    address public externalAccount;

    // Spot tokens
    address[] public spotTokens;

    // Perp tokens
    address[] public perpTokens;

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        utils = new Utils();
        address payable[] memory users = utils.createUsers(4);

        alice = users[0];
        vm.label(alice, "Alice");

        bob = users[1];
        vm.label(bob, "Bob");

        owner = users[2];
        vm.label(owner, "Owner");

        externalAccount = users[3];
        vm.label(externalAccount, "External Account");

        networkFork = vm.createFork(networkRpcUrl);

        vm.selectFork(networkFork);

        clearingHouse = IClearinghouse(endpoint.clearinghouse());

        paymentToken = IERC20Metadata(clearingHouse.getQuote());

        vm.startPrank(owner);

        // Deploy Manager implementation
        vertexManagerImplementation = new VertexManager();

        // Deploy proxy contract and point it to implementation
        proxy = new ERC1967Proxy(address(vertexManagerImplementation), "");

        // Wrap in ABI to support easier calls
        manager = VertexManager(address(proxy));

        // Approve the manager to move USDC for fee payments.
        paymentToken.approve(address(manager), type(uint256).max);

        // Deal payment token to the factory, which pays for the slow mode transactions of all the vaults.
        deal(address(paymentToken), owner, type(uint256).max);

        // Set the endpoint and external account of the contract.
        manager.initialize(address(endpoint), 1000000);

        vm.stopPrank();

        // Clear any external slow-mode txs from the Vertex queue.
        processSlowModeTxs();
    }

    function spotDepositSetUp() public {
        vm.startPrank(owner);

        // Create BTC spot pool with BTC and USDC as tokens.
        spotTokens = new address[](2);
        spotTokens[0] = address(BTC);
        spotTokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        // Add spot pool.
        manager.addPool(1, externalAccount, spotTokens, hardcaps);

        // Add token support.
        manager.updateToken(address(USDC), 0);
        manager.updateToken(address(BTC), 1);

        vm.stopPrank();
    }

    function perpDepositSetUp() public {
        vm.startPrank(owner);

        // Create BTC PERP pool with BTC, USDC, and ETH as tokens.
        perpTokens = new address[](3);
        perpTokens[0] = address(BTC);
        perpTokens[1] = address(USDC);
        perpTokens[2] = address(WETH);

        uint256[] memory hardcaps = new uint256[](3);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;
        hardcaps[2] = type(uint256).max;

        // Add perp pool.
        manager.addPool(2, externalAccount, perpTokens, hardcaps);

        // Add token support.
        manager.updateToken(address(USDC), 0);
        manager.updateToken(address(BTC), 1);
        manager.updateToken(address(WETH), 3);

        vm.stopPrank();
    }

    function processSlowModeTxs() public {
        // Clear any external slow-mode txs from the Vertex queue.
        vm.warp(block.timestamp + 259200);
        IEndpoint.SlowModeConfig memory queue = endpoint.slowModeConfig();
        endpoint.executeSlowModeTransactions(uint32(queue.txCount - queue.txUpTo));
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testSingleDepositSpot() public {
        spotDepositSetUp();

        uint256 amountBTC = 1 * 10 ** 8 + manager.getWithdrawFee(address(BTC));
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        manager.deposit(1, spotTokens, amounts, address(this));

        (address router, uint256 activeAmountBTC,,) = manager.getPool(1, address(BTC));
        (, uint256 activeAmountUSDC,,) = manager.getPool(1, address(USDC));

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, amounts[0]);
        assertEq(userActiveAmountUSDC, amounts[1]);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.withdraw(1, spotTokens, amounts, 0);

        (, activeAmountBTC,,) = manager.getPool(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPool(1, address(USDC));

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(manager.pendingBalances(address(this), address(BTC)), 1 * 10 ** 8);
        assertEq(manager.pendingBalances(address(this), address(USDC)), amounts[1]);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), router, amountUSDC);

        // Claim tokens for user and owner.
        manager.claim(address(this), spotTokens, 1);

        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);
        assertEq(BTC.balanceOf(address(this)), 1 * 10 ** 8);
        assertEq(USDC.balanceOf(address(this)), amounts[1]);
        assertEq(BTC.balanceOf(owner), manager.getWithdrawFee(address(BTC)));
    }

    function testDoubleDepositSpot() public {
        spotDepositSetUp();

        uint256 amountBTC = 1 * 10 ** 8;
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC * 2);
        deal(address(USDC), address(this), amountUSDC * 2);

        BTC.approve(address(manager), amountBTC * 2);
        USDC.approve(address(manager), amountUSDC * 2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        manager.deposit(1, spotTokens, amounts, address(this));

        (address router, uint256 activeAmountBTC,,) = manager.getPool(1, address(BTC));
        (, uint256 activeAmountUSDC,,) = manager.getPool(1, address(USDC));

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, amounts[0]);
        assertEq(userActiveAmountUSDC, amounts[1]);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.deposit(1, spotTokens, amounts, address(this));

        (, activeAmountBTC,,) = manager.getPool(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPool(1, address(USDC));

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, amountBTC * 2);
        assertEq(userActiveAmountUSDC, amountUSDC * 2);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        amountBTC = 1 * 10 ** 8;
        amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        manager.withdraw(1, spotTokens, amounts, 0);

        (, activeAmountBTC,,) = manager.getPool(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPool(1, address(USDC));

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, amounts[0]);
        assertEq(userActiveAmountUSDC, amounts[1]);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(
            manager.pendingBalances(address(this), address(BTC)), 1 * 10 ** 8 - manager.getWithdrawFee(address(BTC))
        );
        assertEq(manager.pendingBalances(address(this), address(USDC)), amountUSDC);

        manager.withdraw(1, spotTokens, amounts, 0);

        (, activeAmountBTC,,) = manager.getPool(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPool(1, address(USDC));

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(
            manager.pendingBalances(address(this), address(BTC)),
            2 * (1 * 10 ** 8 - manager.getWithdrawFee(address(BTC)))
        );
        assertEq(manager.pendingBalances(address(this), address(USDC)), 2 * amountUSDC);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), address(router), amountUSDC * 2);

        // Claim tokens for user and owner.
        manager.claim(address(this), spotTokens, 1);

        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);
        assertEq(BTC.balanceOf(address(this)), 2 * (1 * 10 ** 8 - manager.getWithdrawFee(address(BTC))));
        assertEq(USDC.balanceOf(address(this)), 2 * amountUSDC);
        assertEq(BTC.balanceOf(owner), 2 * manager.getWithdrawFee(address(BTC)));
    }

    function testSingleDepositSpotBalanced() public {
        spotDepositSetUp();

        uint256 amountBTC = 1 * 10 ** 8 + manager.getWithdrawFee(address(BTC));
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        manager.depositBalanced(1, spotTokens, amountBTC, 0, type(uint256).max, address(this));

        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = amountBTC;
        expectedAmounts[1] = amountUSDC;

        (address router, uint256 activeAmountBTC,,) = manager.getPool(1, address(BTC));
        (, uint256 activeAmountUSDC,,) = manager.getPool(1, address(USDC));

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, expectedAmounts[0]);
        assertEq(userActiveAmountUSDC, expectedAmounts[1]);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.withdrawBalanced(1, spotTokens, amountBTC, 0);

        (, activeAmountBTC,,) = manager.getPool(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPool(1, address(USDC));

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(manager.pendingBalances(address(this), address(BTC)), 1 * 10 ** 8);
        assertEq(manager.pendingBalances(address(this), address(USDC)), amountUSDC);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), router, amountUSDC);

        // Claim tokens for user and owner.
        manager.claim(address(this), spotTokens, 1);

        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);
        assertEq(BTC.balanceOf(address(this)), 1 * 10 ** 8);
        assertEq(USDC.balanceOf(address(this)), amountUSDC);
        assertEq(BTC.balanceOf(owner), manager.getWithdrawFee(address(BTC)));
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

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);
        WETH.approve(address(manager), amountWETH);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;
        amounts[2] = amountWETH;

        manager.deposit(2, perpTokens, amounts, address(this));

        (,uint256 activeAmountBTC,,) = manager.getPool(2, address(BTC));
        (,uint256 activeAmountUSDC,,) = manager.getPool(2, address(USDC));
        (,uint256 activeAmountWETH,,) = manager.getPool(2, address(WETH));

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        uint256 userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        assertEq(userActiveAmountBTC, amounts[0]);
        assertEq(userActiveAmountUSDC, amounts[1]);
        assertEq(activeAmountWETH, amounts[2]);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);
        assertEq(userActiveAmountWETH, activeAmountWETH);

        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);
        assertEq(manager.pendingBalances(address(this), address(WETH)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.withdraw(2, perpTokens, amounts, 0);

        (, activeAmountBTC,,) = manager.getPool(2, address(BTC));
        (, activeAmountUSDC,,) = manager.getPool(2, address(USDC));
        (, activeAmountWETH,,) = manager.getPool(2, address(WETH));

        userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);
        assertEq(activeAmountWETH, 0);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);
        assertEq(userActiveAmountWETH, activeAmountWETH);

        assertEq(
            manager.pendingBalances(address(this), address(BTC)), amounts[0] - manager.getWithdrawFee(address(BTC))
        );
        assertEq(manager.pendingBalances(address(this), address(USDC)), amounts[1]);
        assertEq(manager.pendingBalances(address(this), address(WETH)), amounts[2]);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();

        // Claim tokens for user and owner.
        manager.claim(address(this), perpTokens, 2);

        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);
        assertEq(manager.pendingBalances(address(this), address(WETH)), 0);
        assertEq(BTC.balanceOf(address(this)), amounts[0] - manager.getWithdrawFee(address(BTC)));
        assertEq(USDC.balanceOf(address(this)), amounts[1]);
        assertEq(WETH.balanceOf(address(this)), amounts[2]);
        assertEq(BTC.balanceOf(owner), manager.getWithdrawFee(address(BTC)));
    }

    function testSingleDepositSpotBalancedOtherReceiver() public {
        spotDepositSetUp();

        uint256 amountBTC = 1 * 10 ** 8 + manager.getWithdrawFee(address(BTC));
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        manager.depositBalanced(1, spotTokens, amountBTC, 0, type(uint256).max, address(0x69));

        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = amountBTC;
        expectedAmounts[1] = amountUSDC;

        (address router, uint256 activeAmounBTC,,) = manager.getPool(1, address(BTC));
        (,uint256 activeAmountUSDC,,) = manager.getPool(1, address(USDC));

        uint256 userActiveAmountCallerBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        uint256 userActiveAmountCallerUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        uint256 userActiveAmountReceiverBTC = manager.getUserActiveAmount(1, address(BTC), address(0x69));
        uint256 userActiveAmountReceiverUSDC = manager.getUserActiveAmount(1, address(USDC), address(0x69));

        assertEq(activeAmounBTC, expectedAmounts[0]);
        assertEq(activeAmountUSDC, expectedAmounts[1]);

        assertEq(userActiveAmountCallerBTC, 0);
        assertEq(userActiveAmountCallerUSDC, 0);

        assertEq(userActiveAmountReceiverBTC, expectedAmounts[0]);
        assertEq(userActiveAmountReceiverUSDC, expectedAmounts[1]);

        assertEq(activeAmounBTC, userActiveAmountCallerBTC + userActiveAmountReceiverBTC);
        assertEq(activeAmountUSDC, userActiveAmountCallerUSDC + userActiveAmountReceiverUSDC);

        assertEq(manager.pendingBalances(address(0x69), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(0x69), address(USDC)), 0);
        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        vm.prank(address(0x69));
        manager.withdrawBalanced(1, spotTokens, amountBTC, 0);

        (,activeAmounBTC,,) = manager.getPool(1, address(BTC));
        (,activeAmountUSDC,,) = manager.getPool(1, address(USDC));

        userActiveAmountCallerBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountCallerUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        userActiveAmountReceiverBTC = manager.getUserActiveAmount(1, address(BTC), address(0x69));
        userActiveAmountReceiverUSDC = manager.getUserActiveAmount(1, address(USDC), address(0x69));

        assertEq(activeAmounBTC, 0);
        assertEq(activeAmountUSDC, 0);

        assertEq(userActiveAmountCallerBTC, 0);
        assertEq(userActiveAmountCallerUSDC, 0);

        assertEq(userActiveAmountReceiverBTC, 0);
        assertEq(userActiveAmountReceiverUSDC, 0);

        assertEq(activeAmounBTC, userActiveAmountCallerBTC + userActiveAmountReceiverBTC);
        assertEq(activeAmountUSDC, userActiveAmountCallerUSDC + userActiveAmountReceiverUSDC);

        assertEq(manager.pendingBalances(address(0x69), address(BTC)), 1 * 10 ** 8);
        assertEq(manager.pendingBalances(address(0x69), address(USDC)), amountUSDC);
        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), router, amountUSDC);

        // Claim tokens for user and owner.
        manager.claim(address(0x69), spotTokens, 1);

        assertEq(manager.pendingBalances(address(0x69), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(0x69), address(USDC)), 0);
        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);
        assertEq(BTC.balanceOf(address(0x69)), 1 * 10 ** 8);
        assertEq(USDC.balanceOf(address(0x69)), amountUSDC);
        assertEq(BTC.balanceOf(owner), manager.getWithdrawFee(address(BTC)));
    }

    /*//////////////////////////////////////////////////////////////
                 DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositWithNotEnoughApproval(uint240 amountBTC) public {
        vm.assume(amountBTC > 0);
        spotDepositSetUp();

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC / 2);
        USDC.approve(address(manager), amountUSDC / 2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vm.expectRevert();
        manager.deposit(1, spotTokens, amounts, address(this));
    }

    function testWithdrawWithNotEnoughBalance(uint248 amountBTC) public {
        vm.assume(amountBTC > 1);
        spotDepositSetUp();

        deal(address(BTC), address(this), type(uint256).max);
        deal(address(USDC), address(this), type(uint256).max);

        BTC.approve(address(manager), type(uint256).max);
        USDC.approve(address(manager), type(uint256).max);

        manager.depositBalanced(1, spotTokens, amountBTC / 2, 1, type(uint256).max, address(this));

        processSlowModeTxs();

        vm.expectRevert();
        manager.withdrawBalanced(1, spotTokens, amountBTC, 0);
    }

    function testDepositWithNoBalance(uint240 amountBTC) public {
        vm.assume(amountBTC > 0);
        spotDepositSetUp();

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vm.expectRevert();
        manager.deposit(1, spotTokens, amounts, address(this));
    }

    function testWithdrawWithNoBalance(uint240 amountBTC) public {
        vm.assume(amountBTC > 0);
        spotDepositSetUp();

        vm.expectRevert();
        manager.withdrawBalanced(1, spotTokens, amountBTC, 0);
    }

    function testDepositWithNoApproval(uint240 amountBTC) public {
        vm.assume(amountBTC > 0);
        spotDepositSetUp();

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vm.expectRevert();
        manager.deposit(1, spotTokens, amounts, address(this));
    }

    function testDepositInvalidInputs() public {
        uint256[] memory amounts = new uint256[](0);
        address[] memory tokens = new address[](0);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidLength.selector, amounts, tokens));
        manager.deposit(0, tokens, amounts, address(this));

        amounts = new uint256[](2);
        tokens = new address[](1);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidLength.selector, amounts, tokens));
        manager.deposit(0, tokens, amounts, address(this));
    }

    function testUnbalancedDeposit() public {
        spotDepositSetUp();

        uint256[] memory amounts = new uint256[](2);
        // 1 BTC
        amounts[0] = 1 ether;
        // 1 USDC
        amounts[1] = 1;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.UnbalancedAmounts.selector, 1, amounts));
        manager.deposit(1, spotTokens, amounts, address(this));
    }

    function testUnbalancedWithdraw() public {
        spotDepositSetUp();

        uint256[] memory amounts = new uint256[](2);
        // 1 BTC
        amounts[0] = 1 ether;
        // 1 USDC
        amounts[1] = 1;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.UnbalancedAmounts.selector, 1, amounts));
        manager.withdraw(1, spotTokens, amounts, 0);
    }

    function testWithdrawInvalidFee() public {
        spotDepositSetUp();

        uint256 amountBTC = 1 * 10 ** 8;
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidLength.selector, amounts, spotTokens));
        manager.withdraw(1, spotTokens, amounts, 69);
    }

    function testHardcapReached() public {
        spotDepositSetUp();

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = 0;
        hardcaps[1] = 0;

        vm.prank(owner);
        manager.updatePoolHardcaps(1, spotTokens, hardcaps);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        // Deposit should succeed because amounts are 0 and hardcap is 0 too.
        manager.deposit(1, spotTokens, amounts, address(this));

        uint256 amountBTC = 1 * 10 ** 8;
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.HardcapReached.selector, address(BTC), 0, 0, amountBTC));
        manager.deposit(1, spotTokens, amounts, address(this));

        hardcaps[0] = type(uint256).max;
        hardcaps[1] = 0;

        vm.prank(owner);
        manager.updatePoolHardcaps(1, spotTokens, hardcaps);

        deal(address(BTC), address(this), amountBTC);
        BTC.approve(address(manager), amountBTC);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.HardcapReached.selector, address(USDC), 0, 0, amountUSDC));
        manager.deposit(1, spotTokens, amounts, address(this));

        hardcaps[1] = type(uint256).max;

        vm.prank(owner);
        manager.updatePoolHardcaps(1, spotTokens, hardcaps);

        deal(address(USDC), address(this), amountUSDC);
        USDC.approve(address(manager), amountUSDC);

        manager.deposit(1, spotTokens, amounts, address(this));
    }

    function testNotSpotPool() public {
        perpDepositSetUp();

        vm.expectRevert(abi.encodeWithSelector(VertexManager.NotSpotPool.selector, 2));
        manager.depositBalanced(2, perpTokens, 69, 0, type(uint256).max, address(this));

        vm.expectRevert(abi.encodeWithSelector(VertexManager.NotSpotPool.selector, 2));
        manager.withdrawBalanced(2, perpTokens, 69, 0);
    }

    function testSingleDepositBalancedSlippage() public {
        spotDepositSetUp();

        uint256 amountBTC = 1 * 10 ** 8 + manager.getWithdrawFee(address(BTC));
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        vm.expectRevert(
            abi.encodeWithSelector(VertexManager.SlippageTooHigh.selector, amountUSDC, amountUSDC * 2, amountUSDC * 4)
        );
        manager.depositBalanced(1, spotTokens, amountBTC, amountUSDC * 2, amountUSDC * 4, address(this));
    }

    function testWithdrawUSDCFee() public {
        spotDepositSetUp();

        uint256 amountBTC = 1 * 10 ** 8 + manager.getWithdrawFee(address(BTC));
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        manager.deposit(1, spotTokens, amounts, address(this));

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.withdraw(1, spotTokens, amounts, 1);

        // Get the router address.
        (address router,,,) = manager.getPool(1, address(BTC));

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        // TODO: Check this deal (and throughout codebase).
        deal(address(USDC), router, amountUSDC);

        // Claim tokens for user and owner.
        manager.claim(address(this), spotTokens, 1);
    }

    function testInsufficientFee() public {
        perpDepositSetUp();

        // Deposit 1 BTC, 0 USDC, and 0 WETH
        uint256 amountBTC = 1 * 10 ** 8;
        uint256 amountUSDC = 0;
        uint256 amountWETH = 0;

        deal(address(BTC), address(this), amountBTC);

        BTC.approve(address(manager), amountBTC);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;
        amounts[2] = amountWETH;

        manager.deposit(2, perpTokens, amounts, address(this));

        // Try to withdraw and pay fees with USDC, but should revert because there is no USDC, so not enough to pay fees.
        vm.expectRevert();
        manager.withdraw(2, perpTokens, amounts, 1);
    }

    /*//////////////////////////////////////////////////////////////
                            POOL MANAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function testAddAndUpdatePool() public {
        vm.startPrank(owner);

        // Create BTC spot pool with BTC and USDC as tokens.
        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        manager.addPool(1, externalAccount, tokens, hardcaps);

        // Get the pool data.
        (address routerBTC, uint256 activeAmountBTC, uint256 hardcapBTC, bool activeBTC) = manager.getPool(1, address(BTC));
        (address routerUSDC, uint256 activeAmountUSDC, uint256 hardcapUSDC, bool activeUSDC) = manager.getPool(1, address(USDC));

        assertEq(routerBTC, routerUSDC);
        assertEq(activeAmountBTC, 0);
        assertEq(activeAmountBTC, activeAmountUSDC);
        assertEq(hardcapBTC, hardcaps[0]);
        assertEq(hardcapUSDC, hardcaps[1]);
        assertTrue(activeBTC);
        assertTrue(activeUSDC);

        hardcaps[0] = 0;
        hardcaps[1] = 0;

        manager.updatePoolHardcaps(1, tokens, hardcaps);

        // Get the pool data.
        (,, hardcapBTC, activeBTC) = manager.getPool(1, address(BTC));
        (,, hardcapUSDC, activeUSDC) = manager.getPool(1, address(USDC));

        assertEq(hardcapBTC, hardcaps[0]);
        assertEq(hardcapUSDC, hardcaps[1]);
        assertTrue(activeBTC);
        assertTrue(activeUSDC);
    }

    function testUnauthorizedAddAndUpdate() public {
        address[] memory tokens = new address[](0);
        uint256[] memory hardcaps = new uint256[](0);

        vm.expectRevert();
        manager.updatePoolHardcaps(1, tokens, hardcaps);

        vm.expectRevert();
        manager.addPoolTokens(1, tokens, hardcaps);
    }

    function testAddPoolTokens() public {
        spotDepositSetUp();
        vm.startPrank(owner);

        address[] memory tokens = new address[](1);
        tokens[0] = address(WETH);

        uint256[] memory hardcaps = new uint256[](1);
        hardcaps[0] = type(uint256).max;

        // Convert spot pool to perp by adding WETH as a new token.
        manager.addPoolTokens(1, tokens, hardcaps);
    }

    function testIsPoolAdded() public {
        // Get the pool data.
        (address routerBTC, uint256 activeAmountBTC, uint256 hardcapBTC, bool activeBTC) = manager.getPool(1, address(BTC));

        assertEq(routerBTC, address(0));
        assertEq(activeAmountBTC, 0);
        assertEq(hardcapBTC, 0);
        assertFalse(activeBTC);
    }

    function testPoolAdd() public {
        vm.startPrank(owner);

        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        // Remove allowance to simulate not having funds to pay for the LinkedSigner fee.
        paymentToken.approve(address(manager), 0);

        // Expect revert when trying to create a pool as owner doesn't have funds to cover LinkedSigner fee.
        vm.expectRevert();
        manager.addPool(1, externalAccount, tokens, hardcaps);

        // Approve the manager to move USDC for fee payments.
        paymentToken.approve(address(manager), type(uint256).max);

        manager.addPool(1, externalAccount, tokens, hardcaps);
    }

    /*//////////////////////////////////////////////////////////////
                             PAUSED TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositsPaused() public {
        vm.prank(owner);
        manager.pause(true, false, false);

        uint256[] memory amounts = new uint256[](2);
        address[] memory tokens = new address[](2);

        vm.expectRevert(VertexManager.DepositsPaused.selector);
        manager.deposit(1, tokens, amounts, address(this));
    }

    function testWithdrawalsPaused() public {
        vm.prank(owner);
        manager.pause(false, true, false);

        uint256[] memory amounts = new uint256[](2);
        address[] memory tokens = new address[](2);

        vm.expectRevert(VertexManager.WithdrawalsPaused.selector);
        manager.withdraw(1, tokens, amounts, 0);
    }

    function testClaimsPaused() public {
        vm.prank(owner);
        manager.pause(false, false, true);

        address[] memory tokens = new address[](0);

        vm.expectRevert(VertexManager.ClaimsPaused.selector);
        manager.claim(address(this), tokens, 1);
    }

    /*//////////////////////////////////////////////////////////////
                              TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateToken() public {
        vm.startPrank(owner);

        assertEq(manager.tokenToProduct(address(BTC)), 0);

        manager.updateToken(address(BTC), 1);

        assertEq(manager.tokenToProduct(address(BTC)), 1);

        manager.updateToken(address(BTC), 2);

        assertEq(manager.tokenToProduct(address(BTC)), 2);
    }

    function testFailUpdateToken() public {
        manager.updateToken(address(BTC), 69);
    }

    /*//////////////////////////////////////////////////////////////
                              PROXY TESTS
    //////////////////////////////////////////////////////////////*/

    function testInitialize() public {
        // Deploy proxy contract and point it to implementation
        ERC1967Proxy tempProxy = new ERC1967Proxy(address(vertexManagerImplementation), "");
        VertexManager tempVertexManager = VertexManager(address(tempProxy));

        tempVertexManager.initialize(address(endpoint), 1000000);
    }

    function testFailDoubleInitiliaze() public {
        manager.initialize(address(0), 0);
    }

    function testAuthorizedUpgrade() public {
        vm.startPrank(owner);

        // Deploy 2nd implementation
        VertexManager vertexManager2 = new VertexManager();

        manager.upgradeTo(address(vertexManager2));
    }

    function testFailUnauthorizedUpgrade() public {
        manager.upgradeTo(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                              OTHER TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetWithdrawFee() public {
        vm.expectRevert();
        manager.getWithdrawFee(address(0xdead));
    }

    function testUpdateSlowModeFee() public {
        vm.expectRevert();
        manager.updateSlowModeFee(69);

        vm.prank(owner);
        manager.updateSlowModeFee(69);
    }

    function testPrice() public {
        spotDepositSetUp();

        // Revert for non-created pool.
        vm.expectRevert();
        manager.getPrice(69);

        manager.getPrice(1);
    }

    function testBalanced() public {
        spotDepositSetUp();

        address[] memory tokens = new address[](2);
        tokens[0] = address(0x69);
        tokens[1] = address(USDC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 * 10 ** 8;
        amounts[1] = 1;

        // Revert for non-supported token.
        vm.expectRevert();
        manager.checkBalanced(tokens, amounts);

        tokens[0] = address(BTC);

        assertFalse(manager.checkBalanced(tokens, amounts));

        amounts[1] = manager.getBalancedAmount(address(BTC), address(USDC), amounts[0]);

        assertTrue(manager.checkBalanced(tokens, amounts));
    }

    function testVertexBalance() public {
        spotDepositSetUp();
        perpDepositSetUp();

        uint256 amountBTC = 1 * 10 ** 8;

        IEndpoint.DepositCollateral memory depositPayload =
            IEndpoint.DepositCollateral(bytes32(abi.encodePacked(address(this), bytes12(0))), 1, uint128(amountBTC));

        deal(address(BTC), address(this), amountBTC * 2);
        BTC.approve(address(endpoint), amountBTC);
        BTC.approve(address(manager), amountBTC);

        endpoint.submitSlowModeTransaction(
            abi.encodePacked(uint8(IEndpoint.TransactionType.DepositCollateral), abi.encode(depositPayload))
        );

        uint256 vertexBalanceBTC = manager.getVertexBalance(2, address(BTC));
        uint256 vertexBalanceUSDC = manager.getVertexBalance(2, address(USDC));
        uint256 vertexBalanceWETH = manager.getVertexBalance(2, address(WETH));

        // Vertex balance should be 0 as there is no deposit through the VertexManager.
        assertEq(vertexBalanceBTC, 0);
        assertEq(vertexBalanceUSDC, 0);
        assertEq(vertexBalanceWETH, 0);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountBTC;
        amounts[1] = 0;
        amounts[2] = 0;

        manager.deposit(2, perpTokens, amounts, address(this));

        vertexBalanceBTC = manager.getVertexBalance(2, address(BTC));
        vertexBalanceUSDC = manager.getVertexBalance(2, address(USDC));
        vertexBalanceWETH = manager.getVertexBalance(2, address(WETH));

        // Vertex balance should be equal to the BTC deposit (and other tokens equal to 0).
        assertEq(vertexBalanceBTC, amounts[0]);
        assertEq(vertexBalanceUSDC, amounts[1]);
        assertEq(vertexBalanceWETH, amounts[2]);

        manager.withdraw(2, perpTokens, amounts, 0);
    
        vertexBalanceBTC = manager.getVertexBalance(2, address(BTC));
        vertexBalanceUSDC = manager.getVertexBalance(2, address(USDC));
        vertexBalanceWETH = manager.getVertexBalance(2, address(WETH));

        // Vertex balances should be 0 after withdrawal.
        assertEq(vertexBalanceBTC, 0);
        assertEq(vertexBalanceUSDC, 0);
        assertEq(vertexBalanceWETH, 0);
    }
}
