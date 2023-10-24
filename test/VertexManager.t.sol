// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {Utils} from "./utils/Utils.sol";
import {MockTokenDecimals} from "./utils/MockTokenDecimals.sol";

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

        networkFork = vm.createFork(networkRpcUrl, 135327062);

        vm.selectFork(networkFork);

        clearingHouse = IClearinghouse(endpoint.clearinghouse());

        paymentToken = IERC20Metadata(clearingHouse.getQuote());

        vm.startPrank(owner);

        // Deploy Manager implementation
        vertexManagerImplementation = new VertexManager();

        // Deploy and initialize the proxy contract.
        proxy =
        new ERC1967Proxy(address(vertexManagerImplementation), abi.encodeWithSignature("initialize(address,uint256)", address(endpoint), 1000000));

        // Wrap in ABI to support easier calls
        manager = VertexManager(address(proxy));

        // Approve the manager to move USDC for fee payments.
        paymentToken.approve(address(manager), type(uint256).max);

        // Deal payment token to the owner, which pays for the slow mode transactions of the pools.
        deal(address(paymentToken), owner, type(uint256).max);

        vm.stopPrank();

        // Clear any external slow-mode txs from the Vertex queue.
        processSlowModeTxs();
    }

    /// @notice Sets up the VertexManager with a spot pool.
    function spotDepositSetUp() public {
        vm.startPrank(owner);

        // Create spot pool with BTC (base) and USDC (quote) as tokens.
        spotTokens = new address[](2);
        spotTokens[0] = address(BTC);
        spotTokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        // Add spot pool.
        manager.addPool(1, spotTokens, hardcaps, VertexManager.PoolType.Spot, externalAccount);

        // Add token support.
        manager.updateToken(address(USDC), 0);
        manager.updateToken(address(BTC), 1);

        vm.stopPrank();
    }

    /// @notice Sets up the VertexManager with a perp pool.
    function perpDepositSetUp() public {
        vm.startPrank(owner);

        // Create perp pool with BTC, USDC, and ETH as tokens.
        perpTokens = new address[](3);
        perpTokens[0] = address(BTC);
        perpTokens[1] = address(USDC);
        perpTokens[2] = address(WETH);

        uint256[] memory hardcaps = new uint256[](3);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;
        hardcaps[2] = type(uint256).max;

        // Add perp pool.
        manager.addPool(2, perpTokens, hardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Add token support.
        manager.updateToken(address(USDC), 0);
        manager.updateToken(address(BTC), 1);
        manager.updateToken(address(WETH), 3);

        vm.stopPrank();
    }

    /// @notice Processes any transactions in the Vertex queue.
    function processSlowModeTxs() public {
        // Clear any external slow-mode txs from the Vertex queue.
        vm.warp(block.timestamp + 259200);
        IEndpoint.SlowModeConfig memory queue = endpoint.slowModeConfig();
        endpoint.executeSlowModeTransactions(uint32(queue.txCount - queue.txUpTo));
    }

    /// @notice Processes any transactions in the Elixir queue.
    function processQueue() public {
        vm.startPrank(externalAccount);

        // Loop through the queue and process each transaction using the idTo provided.
        for (uint128 i = manager.queueUpTo() + 1; i < manager.queueCount() + 1; i++) {
            VertexManager.Spot memory spot = manager.nextSpot();
            manager.unqueue(i, spot.amount);
        }

        vm.stopPrank();
    }

    /// @notice Returns the sum of pending amounts given a token and user.
    function sumPendingBalance(address token, address user) public view returns (uint256) {
        return manager.getUserPendingAmount(1, token, user) + manager.getUserPendingAmount(2, token, user);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for a single deposit and withdraw flow in a spot pool.
    function testSpotSingle(uint72 amountBTC) public {
        // BTC amount to deposit should be at least the withdraw fee (otherwise not enough to pay fee).
        vm.assume(amountBTC >= manager.getWithdrawFee(address(BTC)));
        spotDepositSetUp();

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, address(this));

        (address router, uint256 activeAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, uint256 activeAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, amountBTC);
        assertEq(userActiveAmountUSDC, amountUSDC);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.withdrawSpot(1, spotTokens, amountBTC, 0);

        (, activeAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(sumPendingBalance(address(BTC), address(this)), amountBTC - manager.getWithdrawFee(address(BTC)));
        assertEq(sumPendingBalance(address(USDC), address(this)), amountUSDC);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), address(router), amountUSDC);

        // Claim tokens for user and owner.
        manager.claim(address(this), spotTokens, 1);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(BTC.balanceOf(address(this)), amountBTC - manager.getWithdrawFee(address(BTC)));
        assertEq(USDC.balanceOf(address(this)), amountUSDC);
        assertEq(BTC.balanceOf(owner), manager.getWithdrawFee(address(BTC)));
    }

    /// @notice Unit test for a double deposit and withdraw flow in a spot pool.
    function testSpotDouble(uint144 amountBTC) public {
        // BTC amount to deposit should be at least twice the withdraw fee (otherwise not enough to pay fee for two withdrawals)
        // and no more than the maximum value for uint72 to not overflow test asserts.
        vm.assume(amountBTC >= manager.getWithdrawFee(address(BTC)) && amountBTC <= type(uint72).max);
        spotDepositSetUp();

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC * 2);
        deal(address(USDC), address(this), amountUSDC * 2);

        BTC.approve(address(manager), amountBTC * 2);
        USDC.approve(address(manager), amountUSDC * 2);

        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, address(this));

        (address router, uint256 activeAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, uint256 activeAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, amountBTC);
        assertEq(userActiveAmountUSDC, amountUSDC);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, address(this));

        (, activeAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, amountBTC * 2);
        assertEq(userActiveAmountUSDC, amountUSDC * 2);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.withdrawSpot(1, spotTokens, amountBTC, 0);

        (, activeAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, amountBTC);
        assertEq(userActiveAmountUSDC, amountUSDC);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(sumPendingBalance(address(BTC), address(this)), amountBTC - manager.getWithdrawFee(address(BTC)));
        assertEq(sumPendingBalance(address(USDC), address(this)), amountUSDC);

        manager.withdrawSpot(1, spotTokens, amountBTC, 0);

        (, activeAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(sumPendingBalance(address(BTC), address(this)), 2 * (amountBTC - manager.getWithdrawFee(address(BTC))));
        assertEq(sumPendingBalance(address(USDC), address(this)), 2 * amountUSDC);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), address(router), amountUSDC * 2);

        // Claim tokens for user and owner.
        manager.claim(address(this), spotTokens, 1);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(BTC.balanceOf(address(this)), 2 * (amountBTC - manager.getWithdrawFee(address(BTC))));
        assertEq(USDC.balanceOf(address(this)), 2 * amountUSDC);
        assertEq(BTC.balanceOf(owner), 2 * manager.getWithdrawFee(address(BTC)));
    }

    /// @notice Unit test for a single deposit and withdraw flow in a spot pool for a different receiver.
    function testSpotOtherReceiver(uint72 amountBTC) public {
        // BTC amount to deposit should be at least the withdraw fee (otherwise not enough to pay fee).
        vm.assume(amountBTC >= manager.getWithdrawFee(address(BTC)));
        spotDepositSetUp();

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, address(0x69));

        (address router, uint256 activeAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, uint256 activeAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        uint256 userActiveAmountCallerBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        uint256 userActiveAmountCallerUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        uint256 userActiveAmountReceiverBTC = manager.getUserActiveAmount(1, address(BTC), address(0x69));
        uint256 userActiveAmountReceiverUSDC = manager.getUserActiveAmount(1, address(USDC), address(0x69));

        assertEq(activeAmountBTC, amountBTC);
        assertEq(activeAmountUSDC, amountUSDC);

        assertEq(userActiveAmountCallerBTC, 0);
        assertEq(userActiveAmountCallerUSDC, 0);

        assertEq(userActiveAmountReceiverBTC, amountBTC);
        assertEq(userActiveAmountReceiverUSDC, amountUSDC);

        assertEq(activeAmountBTC, userActiveAmountCallerBTC + userActiveAmountReceiverBTC);
        assertEq(activeAmountUSDC, userActiveAmountCallerUSDC + userActiveAmountReceiverUSDC);

        assertEq(sumPendingBalance(address(BTC), address(0x69)), 0);
        assertEq(sumPendingBalance(address(USDC), address(0x69)), 0);
        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        vm.prank(address(0x69));
        manager.withdrawSpot(1, spotTokens, amountBTC, 0);

        (, activeAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        userActiveAmountCallerBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountCallerUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        userActiveAmountReceiverBTC = manager.getUserActiveAmount(1, address(BTC), address(0x69));
        userActiveAmountReceiverUSDC = manager.getUserActiveAmount(1, address(USDC), address(0x69));

        assertEq(activeAmountBTC, 0);
        assertEq(activeAmountUSDC, 0);

        assertEq(userActiveAmountCallerBTC, 0);
        assertEq(userActiveAmountCallerUSDC, 0);

        assertEq(userActiveAmountReceiverBTC, 0);
        assertEq(userActiveAmountReceiverUSDC, 0);

        assertEq(activeAmountBTC, userActiveAmountCallerBTC + userActiveAmountReceiverBTC);
        assertEq(activeAmountUSDC, userActiveAmountCallerUSDC + userActiveAmountReceiverUSDC);

        assertEq(sumPendingBalance(address(BTC), address(0x69)), amountBTC - manager.getWithdrawFee(address(BTC)));
        assertEq(sumPendingBalance(address(USDC), address(0x69)), amountUSDC);
        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), address(router), amountUSDC);

        // Claim tokens for user and owner.
        manager.claim(address(0x69), spotTokens, 1);

        assertEq(sumPendingBalance(address(BTC), address(0x69)), 0);
        assertEq(sumPendingBalance(address(USDC), address(0x69)), 0);
        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(BTC.balanceOf(address(0x69)), amountBTC - manager.getWithdrawFee(address(BTC)));
        assertEq(USDC.balanceOf(address(0x69)), amountUSDC);
        assertEq(BTC.balanceOf(owner), manager.getWithdrawFee(address(BTC)));
    }

    /// @notice Unit test for a single deposit and withdraw flor in a perp pool.
    function testPerpSingle(uint72 amountBTC, uint80 amountUSDC, uint256 amountWETH) public {
        // Amounts to deposit should be at least the withdraw fee (otherwise not enough to pay fee).
        vm.assume(amountBTC >= manager.getWithdrawFee(address(BTC)));
        vm.assume(amountUSDC >= manager.getWithdrawFee(address(USDC)));
        vm.assume(amountWETH >= manager.getWithdrawFee(address(WETH)));

        perpDepositSetUp();

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

        manager.depositPerp(2, perpTokens, amounts, address(this));

        (address router, uint256 activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, uint256 activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, uint256 activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        uint256 userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        assertEq(userActiveAmountBTC, amounts[0]);
        assertEq(userActiveAmountUSDC, amounts[1]);
        assertEq(activeAmountWETH, amounts[2]);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);
        assertEq(userActiveAmountWETH, activeAmountWETH);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.withdrawPerp(2, perpTokens, amounts);

        (, activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);
        assertEq(activeAmountWETH, 0);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);
        assertEq(userActiveAmountWETH, activeAmountWETH);

        assertEq(uint256(manager.queueCount()), perpTokens.length);

        // Process queue.
        processQueue();

        assertEq(sumPendingBalance(address(BTC), address(this)), amounts[0] - manager.getWithdrawFee(address(BTC)));
        assertEq(sumPendingBalance(address(USDC), address(this)), amounts[1] - manager.getWithdrawFee(address(USDC)));
        assertLe(sumPendingBalance(address(WETH), address(this)), amounts[2] - manager.getWithdrawFee(address(WETH)));

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(BTC), router, amounts[0]);
        deal(address(USDC), router, amounts[1]);
        deal(address(WETH), router, amounts[2]);

        // Claim tokens for user and owner.
        manager.claim(address(this), perpTokens, 2);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);
        assertEq(BTC.balanceOf(address(this)), amounts[0] - manager.getWithdrawFee(address(BTC)));
        assertEq(USDC.balanceOf(address(this)), amounts[1] - manager.getWithdrawFee(address(USDC)));
        assertLe(WETH.balanceOf(address(this)), amounts[2] - manager.getWithdrawFee(address(WETH)));
        assertEq(BTC.balanceOf(owner), manager.getWithdrawFee(address(BTC)));
    }

    /// @notice Unit test for a double deposit and withdraw flow in a perp pool.
    function testPerpDouble(uint144 amountBTC, uint160 amountUSDC, uint256 amountWETH) public {
        // Amounts to deposit should be at least the withdraw fee (otherwise not enough to pay fee for withdrawals).
        vm.assume(amountBTC >= manager.getWithdrawFee(address(BTC)) && amountBTC <= type(uint72).max);
        vm.assume(amountUSDC >= manager.getWithdrawFee(address(USDC)) && amountUSDC <= type(uint80).max);
        vm.assume(amountWETH >= manager.getWithdrawFee(address(WETH)) && amountWETH <= type(uint128).max);
        perpDepositSetUp();

        deal(address(BTC), address(this), amountBTC * 2);
        deal(address(USDC), address(this), amountUSDC * 2);
        deal(address(WETH), address(this), amountWETH * 2);

        BTC.approve(address(manager), amountBTC * 2);
        USDC.approve(address(manager), amountUSDC * 2);
        WETH.approve(address(manager), amountWETH * 2);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;
        amounts[2] = amountWETH;

        manager.depositPerp(2, perpTokens, amounts, address(this));

        (address router, uint256 activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, uint256 activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, uint256 activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        uint256 userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        assertEq(userActiveAmountBTC, amounts[0]);
        assertEq(userActiveAmountUSDC, amounts[1]);
        assertEq(activeAmountWETH, amounts[2]);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);
        assertEq(userActiveAmountWETH, activeAmountWETH);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.depositPerp(2, perpTokens, amounts, address(this));

        (, activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        assertEq(userActiveAmountBTC, amounts[0] * 2);
        assertEq(userActiveAmountUSDC, amounts[1] * 2);
        assertEq(activeAmountWETH, amounts[2] * 2);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);
        assertEq(userActiveAmountWETH, activeAmountWETH);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.withdrawPerp(2, perpTokens, amounts);

        processQueue();

        (, activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        assertEq(userActiveAmountBTC, amounts[0]);
        assertEq(userActiveAmountUSDC, amounts[1]);
        assertEq(activeAmountWETH, amounts[2]);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);
        assertEq(userActiveAmountWETH, activeAmountWETH);

        assertEq(sumPendingBalance(address(BTC), address(this)), amounts[0] - manager.getWithdrawFee(address(BTC)));
        assertEq(sumPendingBalance(address(USDC), address(this)), amounts[1] - manager.getWithdrawFee(address(USDC)));
        assertLe(sumPendingBalance(address(WETH), address(this)), amounts[2] - manager.getWithdrawFee(address(WETH)));

        manager.withdrawPerp(2, perpTokens, amounts);

        processQueue();

        (, activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

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
            sumPendingBalance(address(BTC), address(this)), 2 * (amounts[0] - manager.getWithdrawFee(address(BTC)))
        );
        assertEq(
            sumPendingBalance(address(USDC), address(this)), 2 * (amounts[1] - manager.getWithdrawFee(address(USDC)))
        );
        assertLe(
            sumPendingBalance(address(WETH), address(this)), 2 * (amounts[2] - manager.getWithdrawFee(address(WETH)))
        );

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(BTC), router, 2 * amounts[0]);
        deal(address(USDC), router, 2 * amounts[1]);
        deal(address(WETH), router, 2 * amounts[2]);

        // Claim tokens for user and owner.
        manager.claim(address(this), perpTokens, 2);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);
        assertEq(BTC.balanceOf(address(this)), 2 * (amounts[0] - manager.getWithdrawFee(address(BTC))));
        assertEq(USDC.balanceOf(address(this)), 2 * (amounts[1] - manager.getWithdrawFee(address(USDC))));
        assertLe(WETH.balanceOf(address(this)), 2 * (amounts[2] - manager.getWithdrawFee(address(WETH))));
        assertEq(BTC.balanceOf(owner), 2 * manager.getWithdrawFee(address(BTC)));
    }

    /// @notice Unit test for a single deposit and withdraw flow in a perp pool for a different receiver.
    function testPerpOtherReceiver(uint72 amountBTC, uint80 amountUSDC, uint256 amountWETH) public {
        // Amounts to deposit should be at least the withdraw fee (otherwise not enough to pay fee).
        vm.assume(amountBTC >= manager.getWithdrawFee(address(BTC)));
        vm.assume(amountUSDC >= manager.getWithdrawFee(address(USDC)));
        vm.assume(amountWETH >= manager.getWithdrawFee(address(WETH)));

        perpDepositSetUp();

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

        manager.depositPerp(2, perpTokens, amounts, address(0x69));

        (address router, uint256 activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, uint256 activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, uint256 activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        uint256 userActiveAmountCallerBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        uint256 userActiveAmountCallerUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        uint256 userActiveAmountCallerWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        uint256 userActiveAmountReceiverBTC = manager.getUserActiveAmount(2, address(BTC), address(0x69));
        uint256 userActiveAmountReceiverUSDC = manager.getUserActiveAmount(2, address(USDC), address(0x69));
        uint256 userActiveAmountReceiverWETH = manager.getUserActiveAmount(2, address(WETH), address(0x69));

        assertEq(activeAmountBTC, amountBTC);
        assertEq(activeAmountUSDC, amountUSDC);
        assertEq(activeAmountWETH, amountWETH);

        assertEq(userActiveAmountCallerBTC, 0);
        assertEq(userActiveAmountCallerUSDC, 0);
        assertEq(userActiveAmountCallerWETH, 0);

        assertEq(userActiveAmountReceiverBTC, amountBTC);
        assertEq(userActiveAmountReceiverUSDC, amountUSDC);
        assertEq(userActiveAmountReceiverWETH, amountWETH);

        assertEq(activeAmountBTC, userActiveAmountCallerBTC + userActiveAmountReceiverBTC);
        assertEq(activeAmountUSDC, userActiveAmountCallerUSDC + userActiveAmountReceiverUSDC);
        assertEq(activeAmountWETH, userActiveAmountCallerWETH + userActiveAmountReceiverWETH);

        assertEq(sumPendingBalance(address(BTC), address(0x69)), 0);
        assertEq(sumPendingBalance(address(USDC), address(0x69)), 0);
        assertEq(sumPendingBalance(address(WETH), address(0x69)), 0);
        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        vm.prank(address(0x69));
        manager.withdrawPerp(2, perpTokens, amounts);

        (, activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        userActiveAmountCallerBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        userActiveAmountCallerUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        userActiveAmountCallerWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        userActiveAmountReceiverBTC = manager.getUserActiveAmount(2, address(BTC), address(0x69));
        userActiveAmountReceiverUSDC = manager.getUserActiveAmount(2, address(USDC), address(0x69));
        userActiveAmountReceiverWETH = manager.getUserActiveAmount(2, address(WETH), address(0x69));

        assertEq(activeAmountBTC, 0);
        assertEq(activeAmountUSDC, 0);
        assertEq(activeAmountWETH, 0);

        assertEq(userActiveAmountCallerBTC, 0);
        assertEq(userActiveAmountCallerUSDC, 0);
        assertEq(userActiveAmountCallerWETH, 0);

        assertEq(userActiveAmountReceiverBTC, 0);
        assertEq(userActiveAmountReceiverUSDC, 0);
        assertEq(userActiveAmountReceiverWETH, 0);

        assertEq(activeAmountBTC, userActiveAmountCallerBTC + userActiveAmountReceiverBTC);
        assertEq(activeAmountUSDC, userActiveAmountCallerUSDC + userActiveAmountReceiverUSDC);
        assertEq(activeAmountWETH, userActiveAmountCallerWETH + userActiveAmountReceiverWETH);

        assertEq(uint256(manager.queueCount()), perpTokens.length);

        // Process queue.
        processQueue();

        assertEq(sumPendingBalance(address(BTC), address(0x69)), amounts[0] - manager.getWithdrawFee(address(BTC)));
        assertEq(sumPendingBalance(address(USDC), address(0x69)), amounts[1] - manager.getWithdrawFee(address(USDC)));
        assertLe(sumPendingBalance(address(WETH), address(0x69)), amounts[2] - manager.getWithdrawFee(address(WETH)));
        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(BTC), router, amounts[0]);
        deal(address(USDC), router, amounts[1]);
        deal(address(WETH), router, amounts[2]);

        // Claim tokens for user and owner.
        manager.claim(address(0x69), perpTokens, 2);

        assertEq(sumPendingBalance(address(BTC), address(0x69)), 0);
        assertEq(sumPendingBalance(address(USDC), address(0x69)), 0);
        assertEq(sumPendingBalance(address(WETH), address(0x69)), 0);
        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);
        assertEq(BTC.balanceOf(address(0x69)), amounts[0] - manager.getWithdrawFee(address(BTC)));
        assertEq(USDC.balanceOf(address(0x69)), amounts[1] - manager.getWithdrawFee(address(USDC)));
        assertLe(WETH.balanceOf(address(0x69)), amounts[2] - manager.getWithdrawFee(address(WETH)));
        assertEq(BTC.balanceOf(owner), manager.getWithdrawFee(address(BTC)));
    }

    /*//////////////////////////////////////////////////////////////
                 DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for a failed deposit due to not enough approval.
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

        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, address(this));
    }

    /// @notice Unit test for a failed withdraw due to not enough approval.
    function testWithdrawWithNotEnoughBalance(uint248 amountBTC) public {
        vm.assume(amountBTC > 1);
        spotDepositSetUp();

        deal(address(BTC), address(this), type(uint256).max);
        deal(address(USDC), address(this), type(uint256).max);

        BTC.approve(address(manager), type(uint256).max);
        USDC.approve(address(manager), type(uint256).max);

        manager.depositSpot(1, spotTokens, amountBTC / 2, 1, type(uint256).max, address(this));

        processSlowModeTxs();

        vm.expectRevert();
        manager.withdrawSpot(1, spotTokens, amountBTC, 0);
    }

    /// @notice Unit test for a failed deposit due to not enough balance but enough approval.
    function testDepositWithNoBalance(uint240 amountBTC) public {
        vm.assume(amountBTC > 0);
        spotDepositSetUp();

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, address(this));
    }

    /// @notice Unit test for a failed withdraw due to not enough balance but enough approval.
    function testWithdrawWithNoBalance(uint240 amountBTC) public {
        vm.assume(amountBTC > 0);
        spotDepositSetUp();

        vm.expectRevert();
        manager.withdrawSpot(1, spotTokens, amountBTC, 0);
    }

    /// @notice Unit test for a failed deposit due to zero approval.
    function testDepositWithNoApproval(uint240 amountBTC) public {
        vm.assume(amountBTC > 0);
        spotDepositSetUp();

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, address(this));
    }

    /// @notice Unit test for all checks in deposit and withdraw functions for a perp pool.
    function testPerpChecks(uint72 amountBTC, uint80 amountUSDC, uint256 amountWETH) public {
        perpDepositSetUp();

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

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidPool.selector, 69));
        manager.depositPerp(69, perpTokens, amounts, address(this));

        address[] memory emptyTokens = new address[](0);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.EmptyTokens.selector, emptyTokens));
        manager.depositPerp(2, emptyTokens, amounts, address(this));

        address[] memory invalidTokens = new address[](1);
        invalidTokens[0] = address(0x69);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.MismatchInputs.selector, amounts, invalidTokens));
        manager.depositPerp(2, invalidTokens, amounts, address(this));

        vm.expectRevert(abi.encodeWithSelector(VertexManager.ZeroAddress.selector));
        manager.depositPerp(2, perpTokens, amounts, address(0));

        manager.depositPerp(2, perpTokens, amounts, address(this));

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidPool.selector, 69));
        manager.withdrawPerp(69, perpTokens, amounts);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.EmptyTokens.selector, emptyTokens));
        manager.withdrawPerp(2, emptyTokens, amounts);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.MismatchInputs.selector, amounts, invalidTokens));
        manager.withdrawPerp(2, invalidTokens, amounts);

        uint256[] memory amountSingle = new uint256[](1);
        amountSingle[0] = amounts[0] - amounts[0];

        address[] memory tokenSingle = new address[](1);
        tokenSingle[0] = perpTokens[0];

        vm.expectRevert(
            abi.encodeWithSelector(
                VertexManager.AmountTooLow.selector, amountSingle[0], manager.getWithdrawFee(tokenSingle[0])
            )
        );
        manager.withdrawPerp(2, tokenSingle, amountSingle);
    }

    /// @notice Unit test for all checks in deposit and withdraw functions for a spot pool.
    function testSpotChecks(uint72 amountBTC) public {
        vm.assume(amountBTC > 0);
        spotDepositSetUp();

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidPool.selector, 69));
        manager.depositSpot(69, spotTokens, amountBTC, amountUSDC, amountUSDC, address(this));

        address[] memory emptyTokens = new address[](0);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidTokens.selector, emptyTokens));
        manager.depositSpot(1, emptyTokens, amountBTC, amountUSDC, amountUSDC, address(this));

        address[] memory duplicatedTokens = new address[](2);
        duplicatedTokens[0] = address(BTC);
        duplicatedTokens[1] = address(BTC);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.DuplicatedTokens.selector, address(BTC), duplicatedTokens));
        manager.depositSpot(1, duplicatedTokens, amountBTC, amountUSDC, amountUSDC, address(this));

        vm.expectRevert(abi.encodeWithSelector(VertexManager.ZeroAddress.selector));
        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, address(0));

        vm.expectRevert(
            abi.encodeWithSelector(VertexManager.SlippageTooHigh.selector, amountUSDC, amountUSDC * 2, amountUSDC * 4)
        );
        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC * 2, amountUSDC * 4, address(this));

        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, address(this));

        // invalid pool
        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidPool.selector, 69));
        manager.withdrawSpot(69, spotTokens, amountBTC, 0);

        // invalid tokens
        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidTokens.selector, emptyTokens));
        manager.withdrawSpot(1, emptyTokens, amountBTC, 0);

        // duplicated tokens
        vm.expectRevert(abi.encodeWithSelector(VertexManager.DuplicatedTokens.selector, address(BTC), duplicatedTokens));
        manager.withdrawSpot(1, duplicatedTokens, amountBTC, 0);

        // invalid fee index
        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidFeeIndex.selector, 69, spotTokens));
        manager.withdrawSpot(1, spotTokens, amountBTC, 69);
    }

    /// @notice Unit test for all checks in the claim function
    function testClaimChecks(uint72 amountBTC) public {
        // BTC amount to deposit should be at least the withdraw fee (otherwise not enough to pay fee).
        vm.assume(amountBTC >= manager.getWithdrawFee(address(BTC)));
        spotDepositSetUp();

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, address(this));
        manager.withdrawSpot(1, spotTokens, amountBTC, 0);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidPool.selector, 69));
        manager.claim(address(this), spotTokens, 69);

        address[] memory emptyTokens = new address[](0);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.EmptyTokens.selector, emptyTokens));
        manager.claim(address(this), emptyTokens, 1);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.ZeroAddress.selector));
        manager.claim(address(0), spotTokens, 1);
    }

    /// @notice Unit test for unsuported tokens in both deposit and withdraw functions.
    function testUnsupportedToken(uint72 amountBTC) public {
        // BTC amount to deposit should be at least the withdraw fee (otherwise not enough to pay fee).
        vm.assume(amountBTC >= manager.getWithdrawFee(address(BTC)));
        spotDepositSetUp();

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), type(uint256).max);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), type(uint256).max);

        address[] memory tokens = new address[](2);
        tokens[0] = address(WETH);
        tokens[1] = address(USDC);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.UnsupportedToken.selector, address(WETH), 1));
        manager.depositSpot(1, tokens, 1 ether, 0, type(uint256).max, address(this));

        tokens[0] = address(BTC);

        manager.depositSpot(1, tokens, amountBTC, 0, type(uint256).max, address(this));

        tokens[0] = address(WETH);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.UnsupportedToken.selector, address(WETH), 1));
        manager.withdrawSpot(1, tokens, 1 ether, 0);
    }

    /// @notice Unit test for a failed deposit due to exceeding the hardcap.
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
        manager.depositSpot(1, spotTokens, amounts[0], amounts[1], amounts[1], address(this));

        uint256 amountBTC = 1 * 10 ** 8;
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.HardcapReached.selector, address(BTC), 0, 0, amountBTC));
        manager.depositSpot(1, spotTokens, amounts[0], amounts[1], amounts[1], address(this));

        hardcaps[0] = type(uint256).max;
        hardcaps[1] = 0;

        vm.prank(owner);
        manager.updatePoolHardcaps(1, spotTokens, hardcaps);

        deal(address(BTC), address(this), amountBTC);
        BTC.approve(address(manager), amountBTC);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.HardcapReached.selector, address(USDC), 0, 0, amountUSDC));
        manager.depositSpot(1, spotTokens, amounts[0], amounts[1], amounts[1], address(this));

        hardcaps[1] = type(uint256).max;

        vm.prank(owner);
        manager.updatePoolHardcaps(1, spotTokens, hardcaps);

        deal(address(USDC), address(this), amountUSDC);
        USDC.approve(address(manager), amountUSDC);

        manager.depositSpot(1, spotTokens, amounts[0], amounts[1], amounts[1], address(this));
    }

    /// @notice Unit test for a deposit and withdraw flow in a spot pool, paying the fee in USDC.
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

        manager.depositSpot(1, spotTokens, amounts[0], amounts[1], amounts[1], address(this));

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.withdrawSpot(1, spotTokens, amounts[0], 1);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();

        // Claim tokens for user and owner.
        manager.claim(address(this), spotTokens, 1);
    }

    /// @notice Unit test for a failed deposit and withdraw flow in a spot pool due to insufficient funds for fee payment.
    function testInsufficientFee() public {
        perpDepositSetUp();

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        address[] memory tokens = new address[](1);
        tokens[0] = address(BTC);

        manager.depositPerp(2, tokens, amounts, address(this));

        // Try to withdraw and pay fees with USDC, but should revert because there is no USDC, so not enough to pay fees.
        vm.expectRevert(
            abi.encodeWithSelector(VertexManager.AmountTooLow.selector, amounts[0], manager.getWithdrawFee(tokens[0]))
        );
        manager.withdrawPerp(2, tokens, amounts);
    }

    // TODO: Test to skip spot in queue.

    /*//////////////////////////////////////////////////////////////
                            POOL MANAGE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for adding and updating a pool.
    function testAddAndUpdatePool() public {
        vm.startPrank(owner);

        // Create BTC spot pool with BTC and USDC as tokens.
        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        manager.addPool(1, tokens, hardcaps, VertexManager.PoolType.Spot, externalAccount);

        // Get the pool data.
        (address routerBTC, uint256 activeAmountBTC, uint256 hardcapBTC, bool activeBTC) =
            manager.getPoolToken(1, address(BTC));
        (address routerUSDC, uint256 activeAmountUSDC, uint256 hardcapUSDC, bool activeUSDC) =
            manager.getPoolToken(1, address(USDC));

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
        (,, hardcapBTC, activeBTC) = manager.getPoolToken(1, address(BTC));
        (,, hardcapUSDC, activeUSDC) = manager.getPoolToken(1, address(USDC));

        assertEq(hardcapBTC, hardcaps[0]);
        assertEq(hardcapUSDC, hardcaps[1]);
        assertTrue(activeBTC);
        assertTrue(activeUSDC);
    }

    /// @notice Unit test for adding and updating a pool with a new token.
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

    /*//////////////////////////////////////////////////////////////
                      POOL MANAGE SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for unauthorized add and update a pool.
    function testUnauthorizedAddAndUpdate() public {
        address[] memory tokens = new address[](0);
        uint256[] memory hardcaps = new uint256[](0);

        vm.expectRevert("Ownable: caller is not the owner");
        manager.updatePoolHardcaps(1, tokens, hardcaps);

        vm.expectRevert("Ownable: caller is not the owner");
        manager.addPoolTokens(1, tokens, hardcaps);
    }

    /// @notice Unit test for checking pool empty state.
    function testIsPoolAdded() public {
        // Get the pool data.
        (address routerBTC, uint256 activeAmountBTC, uint256 hardcapBTC, bool activeBTC) =
            manager.getPoolToken(1, address(BTC));

        assertEq(routerBTC, address(0));
        assertEq(activeAmountBTC, 0);
        assertEq(hardcapBTC, 0);
        assertFalse(activeBTC);
    }

    /// @notice Unit test for checking pool empty state.
    function testPoolAdd() public {
        vm.startPrank(owner);

        // Remove tokens from owner to simulate not having funds to pay for the LinkedSigner fee.
        paymentToken.transfer(address(0x69), type(uint256).max);

        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        // Expect revert when trying to create a pool as owner doesn't have funds to cover LinkedSigner fee.
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        manager.addPool(1, tokens, hardcaps, VertexManager.PoolType.Spot, externalAccount);

        vm.stopPrank();
        vm.prank(address(0x69));

        // Transfer tokens back to owner.
        paymentToken.transfer(address(owner), type(uint256).max);

        vm.startPrank(owner);

        // Remove allowance.
        paymentToken.approve(address(manager), 0);

        // Expect revert when trying to create a pool as owner didn't give allowance for LinkedSigner fee.
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        manager.addPool(1, tokens, hardcaps, VertexManager.PoolType.Spot, externalAccount);

        // Approve the manager to move USDC for fee payments.
        paymentToken.approve(address(manager), type(uint256).max);

        manager.addPool(1, tokens, hardcaps, VertexManager.PoolType.Spot, externalAccount);
    }

    /// @notice Unit test for checks when adding pools.
    function testPoolChecks() public {
        spotDepositSetUp();

        vm.startPrank(owner);

        address[] memory tokens = new address[](2);
        tokens[0] = address(WETH);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidPool.selector, 1));
        manager.addPool(1, tokens, hardcaps, VertexManager.PoolType.Spot, externalAccount);

        tokens[0] = address(WETH);
        tokens[1] = address(WETH);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.AlreadySupported.selector, address(WETH), 2));
        manager.addPool(2, tokens, hardcaps, VertexManager.PoolType.Spot, externalAccount);
    }

    /// @notice Unit test for failing to add a pool token with more than 18 decimals.
    function testAddInvalidPoolToken() public {
        spotDepositSetUp();

        MockTokenDecimals invalidToken = new MockTokenDecimals(19);

        vm.startPrank(owner);

        address[] memory tokens = new address[](1);
        tokens[0] = address(invalidToken);

        uint256[] memory hardcaps = new uint256[](1);
        hardcaps[0] = type(uint256).max;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidToken.selector, address(invalidToken)));
        manager.addPoolTokens(1, tokens, hardcaps);
    }

    /// @notice Unit test for tokens in a pool with less than 18 decimals.
    function testTokenDecimals(uint8 decimals1, uint8 decimals2, uint80 amount) public {
        vm.assume(decimals1 > 0 && decimals1 < 19);
        vm.assume(decimals2 > 0 && decimals2 < 19);

        vm.startPrank(owner);

        address token1 = address(new MockTokenDecimals(decimals1));
        address token2 = address(new MockTokenDecimals(decimals2));

        address[] memory tokens = new address[](2);
        tokens[0] = token1;
        tokens[1] = token2;

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        manager.addPool(1, tokens, hardcaps, VertexManager.PoolType.Spot, externalAccount);

        manager.getBalancedAmount(token1, token2, amount);
    }

    /// @notice Unit test for failing to update hardcaps due to mismatched lengths of arrays.
    function testInvalidHardcaps() public {
        vm.startPrank(owner);

        address[] memory tokens = new address[](0);

        uint256[] memory hardcaps = new uint256[](1);
        hardcaps[0] = type(uint256).max;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.MismatchInputs.selector, hardcaps, tokens));
        manager.updatePoolHardcaps(1, tokens, hardcaps);
    }

    /*//////////////////////////////////////////////////////////////
                             PAUSED TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for paused deposits.
    function testDepositsPaused() public {
        vm.prank(owner);
        manager.pause(true, false, false);

        uint256[] memory amounts = new uint256[](2);
        address[] memory tokens = new address[](2);

        vm.expectRevert(VertexManager.DepositsPaused.selector);
        manager.depositSpot(1, tokens, amounts[0], amounts[1], amounts[1], address(this));
    }

    /// @notice Unit test for paused withdrawals.
    function testWithdrawalsPaused() public {
        vm.prank(owner);
        manager.pause(false, true, false);

        address[] memory tokens = new address[](2);

        vm.expectRevert(VertexManager.WithdrawalsPaused.selector);
        manager.withdrawSpot(1, tokens, 0, 0);
    }

    /// @notice Unit test for paused claims.
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

    /// @notice Unit test for updating a token.
    function testUpdateToken() public {
        vm.startPrank(owner);

        assertEq(manager.tokenToProduct(address(BTC)), 0);

        manager.updateToken(address(BTC), 1);

        assertEq(manager.tokenToProduct(address(BTC)), 1);

        manager.updateToken(address(BTC), 2);

        assertEq(manager.tokenToProduct(address(BTC)), 2);
    }

    /// @notice Unit test for failing to update a token.
    function testFailUpdateToken() public {
        manager.updateToken(address(BTC), 69);
    }

    /*//////////////////////////////////////////////////////////////
                              PROXY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for initializing the proxy.
    function testInitialize() public {
        // Deploy and initialize the proxy contract.
        new ERC1967Proxy(address(vertexManagerImplementation), abi.encodeWithSignature("initialize(address,uint256)", address(endpoint), 1000000));
    }

    /// @notice Unit test for failing to initialize the proxy twice.
    function testFailDoubleInitiliaze() public {
        manager.initialize(address(0), 0);
    }

    /// @notice Unit test for upgrading the proxy and running a spot single unit test.
    function testUpgradeProxy() public {
        vm.startPrank(owner);

        // Deploy another implementation and upgrade proxy to it.
        manager.upgradeTo(address(new VertexManager()));

        testSpotSingle(100 * 10 ** 8);
    }

    /// @notice Unit test for failing to upgrade the proxy.
    function testFailUnauthorizedUpgrade() public {
        manager.upgradeTo(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                              OTHER TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for getting the withdraw fee of an invalid token.
    function testFailGetWithdrawFee() public view {
        manager.getWithdrawFee(address(0xdead));
    }

    /// @notice Unit test for getting the withdraw fee.
    function testUpdateSlowModeFee() public {
        vm.expectRevert("Ownable: caller is not the owner");
        manager.updateSlowModeFee(69);

        vm.prank(owner);
        manager.updateSlowModeFee(69);
    }

    /// @notice Unit test for failing to update the withdraw fee as it's too high.
    function testUpdateSlowModeFeeTooHigh() public {
        vm.prank(owner);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.FeeTooHigh.selector, 100000001));
        manager.updateSlowModeFee(100000001);
    }

    /// @notice Unit test for getting the token price.
    function testPrice() public {
        spotDepositSetUp();

        // Revert for non existant Vertex product.
        vm.expectRevert();
        manager.getPrice(69);

        manager.getPrice(1);
    }

    /// @notice Unit test for getting a withdraw amount.
    function testGetWithdraw() public {
        uint256 output = manager.getWithdrawAmount(1, 1, 1);
        assertEq(output, 1);
    }

    /// @notice Unit test for reversed spot deposits.
    function testReversedSpot(uint72 amountBTC) public {
        // BTC amount to deposit should be at least the withdraw fee (otherwise not enough to pay fee).
        vm.assume(amountBTC >= manager.getWithdrawFee(address(BTC)));
        spotDepositSetUp();

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, address(this));

        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(BTC);

        manager.withdrawSpot(1, tokens, amountUSDC, 1);
    }

    /// @notice Unit test for balanced amount calculation.
    function testBalancedAmount(uint240 amountBTC) public {
        vm.assume(amountBTC > 0);
        spotDepositSetUp();

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);
        assertLe(manager.getBalancedAmount(address(USDC), address(BTC), amountUSDC), amountBTC);
    }

    /// @notice Unit test for a cross product deposit, withdraw, and claim flow.
    function testCrossProduct() public {
        perpDepositSetUp();
        spotDepositSetUp();

        uint72 amountBTC = 1 * 10 ** 8; // 1 BTC
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC * 2);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC * 2);

        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, address(this));

        processSlowModeTxs();

        manager.withdrawSpot(1, spotTokens, amountBTC, 0);

        address[] memory singleUSDC = new address[](1);
        singleUSDC[0] = address(USDC);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amountUSDC;

        processSlowModeTxs();

        manager.depositPerp(2, singleUSDC, amounts, address(this));

        processSlowModeTxs();

        manager.withdrawPerp(2, singleUSDC, amounts);

        processQueue();

        assertEq(
            sumPendingBalance(address(USDC), address(this)),
            (amountUSDC * 2)
                - (
                    manager.getUserFee(2, address(USDC), address(this))
                        + manager.getUserFee(1, address(USDC), address(this))
                )
        );

        processSlowModeTxs();

        (address router1,,,) = manager.getPoolToken(1, address(0));
        (address router2,,,) = manager.getPoolToken(2, address(0));

        assertEq(BTC.balanceOf(router1) + BTC.balanceOf(router2), amountBTC);
        assertEq(USDC.balanceOf(router1) + USDC.balanceOf(router2), amountUSDC * 2);

        // used to fail because the pending balance is greater than than the USDC balance of the router1 as the pending balances are grouped by token, not by router or product.
        manager.claim(address(this), spotTokens, 1);

        assertEq(BTC.balanceOf(router1) + BTC.balanceOf(router2), 0);
        assertEq(USDC.balanceOf(router1) + USDC.balanceOf(router2), amountUSDC);

        manager.claim(address(this), singleUSDC, 2);

        assertEq(BTC.balanceOf(router1) + BTC.balanceOf(router2), 0);
        assertEq(USDC.balanceOf(router1) + USDC.balanceOf(router2), 0);
    }

    /// @notice Unit test for a different fee used for withdraws.
    function testFeesPerPool() public {
        perpDepositSetUp();

        uint256 amountBTC = 10 * 10 ** 8; // 10 BTC
        uint256 amountUSDC = 100 * 10 ** 6; // 100 USDC

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        // Deposit 10 BTC and 100 USDC.
        manager.depositPerp(2, perpTokens, amounts, address(this));

        address[] memory singleBTC = new address[](1);
        singleBTC[0] = address(BTC);

        uint256[] memory amountBTCList = new uint256[](1);
        amountBTCList[0] = amountBTC;

        // Withdraw 10 BTC paying fee in BTC.
        manager.withdrawPerp(2, singleBTC, amountBTCList);

        address[] memory singleUSDC = new address[](1);
        singleUSDC[0] = address(USDC);

        uint256[] memory amountUSDCList = new uint256[](1);
        amountUSDCList[0] = amountUSDC;

        // Withdraw 100 USDC paying fee in USDC.
        manager.withdrawPerp(2, singleUSDC, amountUSDCList);

        processQueue();

        // Check that the fees are stored well (are more than 0).
        assertGe(manager.getUserFee(2, address(BTC), address(this)), 0);
        assertGe(manager.getUserFee(2, address(USDC), address(this)), 0);

        processSlowModeTxs();

        uint256 beforeClaimUSDC = USDC.balanceOf(owner);
        uint256 beforeClaimBTC = BTC.balanceOf(owner);

        // Claim and check that the fees and tokens were distributed.
        manager.claim(address(this), perpTokens, 2);

        uint256 afterClaimUSDC = USDC.balanceOf(owner);
        uint256 afterClaimBTC = BTC.balanceOf(owner);

        assertEq(afterClaimBTC - beforeClaimBTC, manager.getWithdrawFee(address(BTC)));
        assertEq(afterClaimUSDC - beforeClaimUSDC, manager.getWithdrawFee(address(USDC)));
        assertEq(BTC.balanceOf(address(this)), amountBTC - (afterClaimBTC - beforeClaimBTC));
        assertEq(USDC.balanceOf(address(this)), amountUSDC - (afterClaimUSDC - beforeClaimUSDC));
    }
}
