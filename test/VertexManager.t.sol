// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {Utils} from "test/utils/Utils.sol";
import {ProcessQueue} from "test/utils/ProcessQueue.sol";
import {MockTokenDecimals} from "test/utils/MockTokenDecimals.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

import {IClearinghouse} from "src/interfaces/IClearinghouse.sol";
import {IEndpoint} from "src/interfaces/IEndpoint.sol";

import {VertexManager, IVertexManager} from "src/VertexManager.sol";
import {VertexProcessor} from "src/VertexProcessor.sol";
import {VertexRouter} from "src/VertexRouter.sol";

contract TestVertexManager is Test, ProcessQueue {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // Arbitrum mainnet addresses
    IEndpoint public endpoint = IEndpoint(0xbbEE07B3e8121227AfCFe1E2B82772246226128e);
    IERC20Metadata public paymentToken;
    IClearinghouse public clearingHouse;

    // Elixir contracts
    VertexManager public manager;

    // Tokens
    IERC20Metadata public BTC = IERC20Metadata(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20Metadata public USDC = IERC20Metadata(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
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

    // Elixir fee
    uint256 public fee;

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

        networkFork = vm.createFork(networkRpcUrl, 169452334);

        vm.selectFork(networkFork);

        clearingHouse = IClearinghouse(endpoint.clearinghouse());

        paymentToken = IERC20Metadata(clearingHouse.getQuote());

        vm.startPrank(owner);

        // Deploy Processor implementation
        VertexProcessor processorImplementation = new VertexProcessor();

        // Deploy Manager implementation
        VertexManager managerImplementation = new VertexManager();

        // Deploy and initialize the proxy contract.
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(managerImplementation),
            abi.encodeWithSignature(
                "initialize(address,address,uint256)", address(endpoint), address(processorImplementation), 1000000
            )
        );

        // Wrap in ABI to support easier calls
        manager = VertexManager(address(proxy));

        // Approve the manager to move USDC for fee payments.
        paymentToken.approve(address(manager), type(uint256).max);

        // Deal payment token to the owner, which pays for the slow mode transactions of the pools.
        deal(address(paymentToken), owner, type(uint256).max);

        // Create spot pool with BTC and USDC as tokens.
        spotTokens = new address[](2);
        spotTokens[0] = address(BTC);
        spotTokens[1] = address(USDC);

        uint256[] memory spotHardcaps = new uint256[](2);
        spotHardcaps[0] = type(uint256).max;
        spotHardcaps[1] = type(uint256).max;

        // Add spot pool.
        manager.addPool(1, spotTokens, spotHardcaps, IVertexManager.PoolType.Spot, externalAccount);

        // Create perp pool with BTC, USDC, and ETH as tokens.
        perpTokens = new address[](3);
        perpTokens[0] = address(BTC);
        perpTokens[1] = address(USDC);
        perpTokens[2] = address(WETH);

        uint256[] memory perpHardcaps = new uint256[](3);
        perpHardcaps[0] = type(uint256).max;
        perpHardcaps[1] = type(uint256).max;
        perpHardcaps[2] = type(uint256).max;

        // Add perp pool.
        manager.addPool(2, perpTokens, perpHardcaps, IVertexManager.PoolType.Perp, externalAccount);

        // Add token support.
        manager.updateToken(address(USDC), 0);
        manager.updateToken(address(BTC), 1);
        manager.updateToken(address(WETH), 3);

        vm.stopPrank();

        // Clear any external slow-mode txs from the Vertex queue.
        processSlowModeTxsOld(endpoint);

        // Store the Elixir fee for later use.
        fee = manager.slowModeFee().mulDiv(
            10 ** (18 + WETH.decimals() - paymentToken.decimals()), manager.getPrice(3), Math.Rounding.Up
        );
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
        vm.assume(amountBTC >= manager.getTransactionFee(address(BTC)));

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        manager.depositSpot{value: fee}(
            1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
        );
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

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
        processSlowModeTxsOld(endpoint);

        manager.withdrawSpot{value: fee}(1, spotTokens[0], spotTokens[1], amountBTC);
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        (, activeAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(sumPendingBalance(address(BTC), address(this)), amountBTC - manager.getTransactionFee(address(BTC)));
        assertEq(sumPendingBalance(address(USDC), address(this)), amountUSDC - manager.getTransactionFee(address(USDC)));

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxsOld(endpoint);
        deal(address(USDC), address(router), amountUSDC);

        // Claim tokens for user and owner.
        manager.claim(address(this), spotTokens[0], 1);
        manager.claim(address(this), spotTokens[1], 1);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(BTC.balanceOf(address(this)), amountBTC - manager.getTransactionFee(address(BTC)));
        assertEq(USDC.balanceOf(address(this)), amountUSDC - manager.getTransactionFee(address(USDC)));
        assertEq(BTC.balanceOf(owner), manager.getTransactionFee(address(BTC)));
    }

    /// @notice Unit test for a double deposit and withdraw flow in a spot pool.
    function testSpotDouble(uint144 amountBTC) public {
        // BTC amount to deposit should be at least twice the withdraw fee (otherwise not enough to pay fee for two withdrawals)
        // and no more than the maximum value for uint72 to not overflow test asserts.
        vm.assume(amountBTC >= manager.getTransactionFee(address(BTC)) && amountBTC <= type(uint72).max);

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC * 2);
        deal(address(USDC), address(this), amountUSDC * 2);

        BTC.approve(address(manager), amountBTC * 2);
        USDC.approve(address(manager), amountUSDC * 2);

        manager.depositSpot{value: fee}(
            1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
        );
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        processSlowModeTxsOld(endpoint);

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

        manager.depositSpot{value: fee}(
            1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
        );
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        processSlowModeTxsOld(endpoint);

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

        manager.withdrawSpot{value: fee}(1, spotTokens[0], spotTokens[1], amountBTC);
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        processSlowModeTxsOld(endpoint);

        (, activeAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, amountBTC);
        assertEq(userActiveAmountUSDC, amountUSDC);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(sumPendingBalance(address(BTC), address(this)), amountBTC - manager.getTransactionFee(address(BTC)));
        assertEq(sumPendingBalance(address(USDC), address(this)), amountUSDC - manager.getTransactionFee(address(USDC)));

        manager.withdrawSpot{value: fee}(1, spotTokens[0], spotTokens[1], amountBTC);
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        processSlowModeTxsOld(endpoint);

        (, activeAmountBTC,,) = manager.getPoolToken(1, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(1, address(USDC));

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);

        assertEq(
            sumPendingBalance(address(BTC), address(this)), 2 * (amountBTC - manager.getTransactionFee(address(BTC)))
        );
        assertEq(
            sumPendingBalance(address(USDC), address(this)), 2 * (amountUSDC - manager.getTransactionFee(address(USDC)))
        );

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxsOld(endpoint);
        deal(address(USDC), address(router), amountUSDC * 2);

        // Claim tokens for user and owner.
        manager.claim(address(this), spotTokens[0], 1);
        manager.claim(address(this), spotTokens[1], 1);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(BTC.balanceOf(address(this)), 2 * (amountBTC - manager.getTransactionFee(address(BTC))));
        assertEq(USDC.balanceOf(address(this)), 2 * (amountUSDC - manager.getTransactionFee(address(USDC))));
        assertEq(BTC.balanceOf(owner), 2 * manager.getTransactionFee(address(BTC)));
    }

    /// @notice Unit test for a single deposit and withdraw flow in a spot pool for a different receiver.
    function testSpotOtherReceiver(uint72 amountBTC) public {
        // BTC amount to deposit should be at least the withdraw fee (otherwise not enough to pay fee).
        vm.assume(amountBTC >= manager.getTransactionFee(address(BTC)));

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        manager.depositSpot{value: fee}(
            1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(0x69)
        );
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        processSlowModeTxsOld(endpoint);

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

        vm.deal(address(0x69), fee);

        vm.prank(address(0x69));
        manager.withdrawSpot{value: fee}(1, spotTokens[0], spotTokens[1], amountBTC);
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        processSlowModeTxsOld(endpoint);

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

        assertEq(sumPendingBalance(address(BTC), address(0x69)), amountBTC - manager.getTransactionFee(address(BTC)));
        assertEq(sumPendingBalance(address(USDC), address(0x69)), amountUSDC - manager.getTransactionFee(address(USDC)));
        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxsOld(endpoint);
        deal(address(USDC), address(router), amountUSDC);

        // Claim tokens for user and owner.
        manager.claim(address(0x69), spotTokens[0], 1);
        manager.claim(address(0x69), spotTokens[1], 1);

        assertEq(sumPendingBalance(address(BTC), address(0x69)), 0);
        assertEq(sumPendingBalance(address(USDC), address(0x69)), 0);
        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(BTC.balanceOf(address(0x69)), amountBTC - manager.getTransactionFee(address(BTC)));
        assertEq(USDC.balanceOf(address(0x69)), amountUSDC - manager.getTransactionFee(address(USDC)));
        assertEq(BTC.balanceOf(owner), manager.getTransactionFee(address(BTC)));
    }

    /// @notice Unit test for a single deposit and withdraw flor in a perp pool.
    function testPerpSingle(uint72 amountBTC, uint80 amountUSDC, uint256 amountWETH) public {
        // Amounts to deposit should be at least the withdraw fee (otherwise not enough to pay fee).
        vm.assume(amountBTC >= manager.getTransactionFee(address(BTC)));
        vm.assume(amountUSDC >= manager.getTransactionFee(address(USDC)));
        vm.assume(amountWETH >= manager.getTransactionFee(address(WETH)));

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);
        deal(address(WETH), address(this), amountWETH);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);
        WETH.approve(address(manager), amountWETH);

        manager.depositPerp{value: fee}(2, perpTokens[0], amountBTC, address(this));
        manager.depositPerp{value: fee}(2, perpTokens[1], amountUSDC, address(this));
        manager.depositPerp{value: fee}(2, perpTokens[2], amountWETH, address(this));

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        (address router, uint256 activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, uint256 activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, uint256 activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        uint256 userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        assertEq(userActiveAmountBTC, amountBTC);
        assertEq(userActiveAmountUSDC, amountUSDC);
        assertEq(activeAmountWETH, amountWETH);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);
        assertEq(userActiveAmountWETH, activeAmountWETH);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxsOld(endpoint);

        manager.withdrawPerp{value: fee}(2, perpTokens[0], amountBTC);
        manager.withdrawPerp{value: fee}(2, perpTokens[1], amountUSDC);
        manager.withdrawPerp{value: fee}(2, perpTokens[2], amountWETH);

        (, activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        assertEq(manager.getUserActiveAmount(2, address(BTC), address(this)), activeAmountBTC);
        assertEq(manager.getUserActiveAmount(2, address(USDC), address(this)), activeAmountUSDC);
        assertEq(manager.getUserActiveAmount(2, address(WETH), address(this)), activeAmountWETH);

        assertEq(uint256(manager.queueCount()), perpTokens.length * 2);

        // Process queue.
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        assertEq(manager.getUserActiveAmount(2, address(BTC), address(this)), 0);
        assertEq(manager.getUserActiveAmount(2, address(USDC), address(this)), 0);
        assertEq(manager.getUserActiveAmount(2, address(WETH), address(this)), 0);

        assertEq(sumPendingBalance(address(BTC), address(this)), amountBTC - manager.getTransactionFee(address(BTC)));
        assertEq(sumPendingBalance(address(USDC), address(this)), amountUSDC - manager.getTransactionFee(address(USDC)));
        assertLe(sumPendingBalance(address(WETH), address(this)), amountWETH - manager.getTransactionFee(address(WETH)));

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxsOld(endpoint);
        deal(address(BTC), router, amountBTC);
        deal(address(USDC), router, amountUSDC);
        deal(address(WETH), router, amountWETH);

        // Claim tokens for user and owner.
        manager.claim(address(this), perpTokens[0], 2);
        manager.claim(address(this), perpTokens[1], 2);
        manager.claim(address(this), perpTokens[2], 2);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);
        assertEq(BTC.balanceOf(address(this)), amountBTC - manager.getTransactionFee(address(BTC)));
        assertEq(USDC.balanceOf(address(this)), amountUSDC - manager.getTransactionFee(address(USDC)));
        assertLe(WETH.balanceOf(address(this)), amountWETH - manager.getTransactionFee(address(WETH)));
        assertEq(BTC.balanceOf(owner), manager.getTransactionFee(address(BTC)));
    }

    /// @notice Unit test for a double deposit and withdraw flow in a perp pool.
    function testPerpDouble(uint144 amountBTC, uint160 amountUSDC, uint256 amountWETH) public {
        // Amounts to deposit should be at least the withdraw fee (otherwise not enough to pay fee for withdrawals).
        vm.assume(amountBTC >= manager.getTransactionFee(address(BTC)) && amountBTC <= type(uint72).max);
        vm.assume(amountUSDC >= manager.getTransactionFee(address(USDC)) && amountUSDC <= type(uint80).max);
        vm.assume(amountWETH >= manager.getTransactionFee(address(WETH)) && amountWETH <= type(uint128).max);

        deal(address(BTC), address(this), amountBTC * 2);
        deal(address(USDC), address(this), amountUSDC * 2);
        deal(address(WETH), address(this), amountWETH * 2);

        BTC.approve(address(manager), amountBTC * 2);
        USDC.approve(address(manager), amountUSDC * 2);
        WETH.approve(address(manager), amountWETH * 2);

        manager.depositPerp{value: fee}(2, perpTokens[0], amountBTC, address(this));
        manager.depositPerp{value: fee}(2, perpTokens[1], amountUSDC, address(this));
        manager.depositPerp{value: fee}(2, perpTokens[2], amountWETH, address(this));

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        (address router, uint256 activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, uint256 activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, uint256 activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        uint256 userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        assertEq(userActiveAmountBTC, amountBTC);
        assertEq(userActiveAmountUSDC, amountUSDC);
        assertEq(activeAmountWETH, amountWETH);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);
        assertEq(userActiveAmountWETH, activeAmountWETH);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxsOld(endpoint);

        manager.depositPerp{value: fee}(2, perpTokens[0], amountBTC, address(this));
        manager.depositPerp{value: fee}(2, perpTokens[1], amountUSDC, address(this));
        manager.depositPerp{value: fee}(2, perpTokens[2], amountWETH, address(this));

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        (, activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        assertEq(userActiveAmountBTC, amountBTC * 2);
        assertEq(userActiveAmountUSDC, amountUSDC * 2);
        assertEq(activeAmountWETH, amountWETH * 2);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);
        assertEq(userActiveAmountWETH, activeAmountWETH);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxsOld(endpoint);

        manager.withdrawPerp{value: fee}(2, perpTokens[0], amountBTC);
        manager.withdrawPerp{value: fee}(2, perpTokens[1], amountUSDC);
        manager.withdrawPerp{value: fee}(2, perpTokens[2], amountWETH);

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        (, activeAmountBTC,,) = manager.getPoolToken(2, address(BTC));
        (, activeAmountUSDC,,) = manager.getPoolToken(2, address(USDC));
        (, activeAmountWETH,,) = manager.getPoolToken(2, address(WETH));

        userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), address(this));

        assertEq(userActiveAmountBTC, amountBTC);
        assertEq(userActiveAmountUSDC, amountUSDC);
        assertEq(activeAmountWETH, amountWETH);

        assertEq(userActiveAmountBTC, activeAmountBTC);
        assertEq(userActiveAmountUSDC, activeAmountUSDC);
        assertEq(userActiveAmountWETH, activeAmountWETH);

        assertEq(sumPendingBalance(address(BTC), address(this)), amountBTC - manager.getTransactionFee(address(BTC)));
        assertEq(sumPendingBalance(address(USDC), address(this)), amountUSDC - manager.getTransactionFee(address(USDC)));
        assertLe(sumPendingBalance(address(WETH), address(this)), amountWETH - manager.getTransactionFee(address(WETH)));

        manager.withdrawPerp{value: fee}(2, perpTokens[0], amountBTC);
        manager.withdrawPerp{value: fee}(2, perpTokens[1], amountUSDC);
        manager.withdrawPerp{value: fee}(2, perpTokens[2], amountWETH);

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

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
            sumPendingBalance(address(BTC), address(this)), 2 * (amountBTC - manager.getTransactionFee(address(BTC)))
        );
        assertEq(
            sumPendingBalance(address(USDC), address(this)), 2 * (amountUSDC - manager.getTransactionFee(address(USDC)))
        );
        assertLe(
            sumPendingBalance(address(WETH), address(this)), 2 * (amountWETH - manager.getTransactionFee(address(WETH)))
        );

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxsOld(endpoint);
        deal(address(BTC), router, 2 * amountBTC);
        deal(address(USDC), router, 2 * amountUSDC);
        deal(address(WETH), router, 2 * amountWETH);

        // Claim tokens for user and owner.
        manager.claim(address(this), perpTokens[0], 2);
        manager.claim(address(this), perpTokens[1], 2);
        manager.claim(address(this), perpTokens[2], 2);

        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);
        assertEq(BTC.balanceOf(address(this)), 2 * (amountBTC - manager.getTransactionFee(address(BTC))));
        assertEq(USDC.balanceOf(address(this)), 2 * (amountUSDC - manager.getTransactionFee(address(USDC))));
        assertLe(WETH.balanceOf(address(this)), 2 * (amountWETH - manager.getTransactionFee(address(WETH))));
        assertEq(BTC.balanceOf(owner), 2 * manager.getTransactionFee(address(BTC)));
    }

    /// @notice Unit test for a single deposit and withdraw flow in a perp pool for a different receiver.
    function testPerpOtherReceiver(uint72 amountBTC, uint80 amountUSDC, uint256 amountWETH) public {
        // Amounts to deposit should be at least the withdraw fee (otherwise not enough to pay fee).
        vm.assume(amountBTC >= manager.getTransactionFee(address(BTC)));
        vm.assume(amountUSDC >= manager.getTransactionFee(address(USDC)));
        vm.assume(amountWETH >= manager.getTransactionFee(address(WETH)));

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

        manager.depositPerp{value: fee}(2, perpTokens[0], amountBTC, address(0x69));
        manager.depositPerp{value: fee}(2, perpTokens[1], amountUSDC, address(0x69));
        manager.depositPerp{value: fee}(2, perpTokens[2], amountWETH, address(0x69));

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

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
        processSlowModeTxsOld(endpoint);

        vm.deal(address(0x69), fee * 3);

        vm.startPrank(address(0x69));
        manager.withdrawPerp{value: fee}(2, perpTokens[0], amounts[0]);
        manager.withdrawPerp{value: fee}(2, perpTokens[1], amounts[1]);
        manager.withdrawPerp{value: fee}(2, perpTokens[2], amounts[2]);
        vm.stopPrank();

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

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

        assertEq(uint256(manager.queueCount()), perpTokens.length * 2);

        assertEq(sumPendingBalance(address(BTC), address(0x69)), amounts[0] - manager.getTransactionFee(address(BTC)));
        assertEq(sumPendingBalance(address(USDC), address(0x69)), amounts[1] - manager.getTransactionFee(address(USDC)));
        assertLe(sumPendingBalance(address(WETH), address(0x69)), amounts[2] - manager.getTransactionFee(address(WETH)));
        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxsOld(endpoint);
        deal(address(BTC), router, amounts[0]);
        deal(address(USDC), router, amounts[1]);
        deal(address(WETH), router, amounts[2]);

        // Claim tokens for user and owner.
        manager.claim(address(0x69), perpTokens[0], 2);
        manager.claim(address(0x69), perpTokens[1], 2);
        manager.claim(address(0x69), perpTokens[2], 2);

        assertEq(sumPendingBalance(address(BTC), address(0x69)), 0);
        assertEq(sumPendingBalance(address(USDC), address(0x69)), 0);
        assertEq(sumPendingBalance(address(WETH), address(0x69)), 0);
        assertEq(sumPendingBalance(address(BTC), address(this)), 0);
        assertEq(sumPendingBalance(address(USDC), address(this)), 0);
        assertEq(sumPendingBalance(address(WETH), address(this)), 0);
        assertEq(BTC.balanceOf(address(0x69)), amounts[0] - manager.getTransactionFee(address(BTC)));
        assertEq(USDC.balanceOf(address(0x69)), amounts[1] - manager.getTransactionFee(address(USDC)));
        assertLe(WETH.balanceOf(address(0x69)), amounts[2] - manager.getTransactionFee(address(WETH)));
        assertEq(BTC.balanceOf(owner), manager.getTransactionFee(address(BTC)));
    }

    /*//////////////////////////////////////////////////////////////
                 DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for a failed deposit due to not enough balance but enough approval.
    function testDepositWithNoBalance(uint240 amountBTC) public {
        vm.assume(amountBTC > 0);

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        deal(address(USDC), address(this), amountUSDC);
        deal(address(BTC), address(this), amountBTC);

        manager.depositSpot{value: fee}(
            1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
        );

        BTC.transfer(address(0x69), amountBTC);

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);

        // Silently reverts and spot is skipped.
        vm.prank(externalAccount);
        manager.unqueue(
            1,
            abi.encode(
                IVertexManager.DepositSpotResponse({
                    amount1: amountUSDC,
                    token0Shares: amountBTC,
                    token1Shares: amountUSDC
                })
            )
        );

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);

        // Check that the spot was indeed skipped.
        assertEq(manager.queueUpTo(), 1);
    }

    /// @notice Unit test for a failed deposit due to zero approval.
    function testDepositWithNoApproval(uint240 amountBTC) public {
        vm.assume(amountBTC > 0);

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        manager.depositSpot{value: fee}(
            1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
        );

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);

        // Silently reverts and spot is skipped.
        vm.prank(externalAccount);
        manager.unqueue(
            1,
            abi.encode(
                IVertexManager.DepositSpotResponse({
                    amount1: amountUSDC,
                    token0Shares: amountBTC,
                    token1Shares: amountUSDC
                })
            )
        );

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, 0);
        assertEq(userActiveAmountUSDC, 0);

        // Check that the spot was indeed skipped.
        assertEq(manager.queueUpTo(), 1);
    }

    /// @notice Unit test for all checks in deposit and withdraw functions for a perp pool.
    function testPerpChecks() public {
        // Deposit checks
        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidPool.selector, 69));
        manager.depositPerp{value: fee}(69, address(0), 0, address(this));

        vm.expectRevert(abi.encodeWithSelector(VertexManager.ZeroAddress.selector));
        manager.depositPerp{value: fee}(2, address(0), 0, address(0));

        vm.expectRevert(abi.encodeWithSelector(VertexManager.FeeTooLow.selector, fee - 1, fee));
        manager.depositPerp{value: fee - 1}(2, address(0x69), 100000, address(0x69));

        // Withdraw checks
        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidPool.selector, 69));
        manager.withdrawPerp{value: fee}(69, address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(VertexManager.AmountTooLow.selector, 0, manager.getTransactionFee(perpTokens[0]))
        );
        manager.withdrawPerp{value: fee}(2, perpTokens[0], 0);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.FeeTooLow.selector, fee - 1, fee));
        manager.withdrawPerp{value: fee - 1}(2, perpTokens[0], 10000);
    }

    /// @notice Unit test for all checks in deposit and withdraw functions for a spot pool.
    function testSpotChecks(uint72 amountBTC) public {
        vm.assume(amountBTC > 0);

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        // Deposit checks
        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidPool.selector, 69));
        manager.depositSpot{value: fee}(
            69, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
        );

        vm.expectRevert(abi.encodeWithSelector(VertexManager.DuplicatedToken.selector, address(BTC)));
        manager.depositSpot{value: fee}(1, address(BTC), address(BTC), amountBTC, amountUSDC, amountUSDC, address(this));

        vm.expectRevert(abi.encodeWithSelector(VertexManager.ZeroAddress.selector));
        manager.depositSpot{value: fee}(1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(0));

        vm.expectRevert(abi.encodeWithSelector(VertexManager.FeeTooLow.selector, fee - 1, fee));
        manager.depositSpot{value: fee - 1}(
            1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
        );

        // Withdraw checks
        manager.depositSpot{value: fee}(
            1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
        );

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidPool.selector, 69));
        manager.withdrawSpot{value: fee}(69, spotTokens[0], spotTokens[1], amountBTC);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.DuplicatedToken.selector, address(BTC)));
        manager.withdrawSpot{value: fee}(1, address(BTC), address(BTC), amountBTC);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.FeeTooLow.selector, fee - 1, fee));
        manager.withdrawSpot{value: fee - 1}(1, spotTokens[0], spotTokens[1], amountBTC);
    }

    /// @notice Unit test for all checks in the claim function
    function testClaimChecks() public {
        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidPool.selector, 69));
        manager.claim(address(this), address(0), 69);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.ZeroAddress.selector));
        manager.claim(address(0), address(0), 1);
    }

    /// @notice Unit test for a failed deposit due to exceeding the hardcap.
    function testHardcapReached() public {
        uint256 amountBTC = 10 * 10 ** 8; // 10 BTC
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC * 2);
        deal(address(USDC), address(this), amountUSDC * 2);

        BTC.approve(address(manager), amountBTC * 2);
        USDC.approve(address(manager), amountUSDC * 2);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = amountBTC;
        hardcaps[1] = amountUSDC;

        vm.prank(owner);
        manager.updatePoolHardcaps(1, spotTokens, hardcaps);

        // Deposit should succeed because amounts and hardcaps are the same.
        manager.depositSpot{value: fee}(
            1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
        );
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        uint256 userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, amountBTC);
        assertEq(userActiveAmountUSDC, amountUSDC);

        // Deposit request passes but fails silently when processing, so no change is applied.
        manager.depositSpot{value: fee}(
            1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
        );
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));

        assertEq(userActiveAmountBTC, amountBTC);
        assertEq(userActiveAmountUSDC, amountUSDC);

        assertEq(manager.queueUpTo(), 2);
    }

    /// @notice Unit test for a deposit and withdraw flow in a spot pool, paying the fee in USDC.
    function testWithdrawUSDCFee() public {
        uint256 amountBTC = 1 * 10 ** 8 + manager.getTransactionFee(address(BTC));
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        manager.depositSpot{value: fee}(
            1, spotTokens[0], spotTokens[1], amounts[0], amounts[1], amounts[1], address(this)
        );

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        processSlowModeTxsOld(endpoint);

        manager.withdrawSpot{value: fee}(1, spotTokens[0], spotTokens[1], amounts[0]);

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        processSlowModeTxsOld(endpoint);

        // Claim tokens for user and owner.
        manager.claim(address(this), spotTokens[0], 1);
        manager.claim(address(this), spotTokens[1], 1);
    }

    /// @notice Unit test for safety checks on unqueue function.
    function testUnqueue() public {
        uint256 amountBTC = 10 * 10 ** 8; // 10 BTC
        uint256 amountUSDC = 100 * 10 ** 6; // 100 USDC

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        // Get the pool router.
        (address router,,,) = manager.getPoolToken(2, address(BTC));

        // Deposit 10 BTC.
        manager.depositPerp{value: fee}(2, address(BTC), amountBTC, address(this));

        // Withdraw 10 BTC.
        manager.withdrawPerp{value: fee}(2, address(BTC), amountBTC);

        vm.expectRevert(
            abi.encodeWithSelector(VertexManager.NotExternalAccount.selector, router, externalAccount, address(this))
        );
        manager.unqueue(1, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidSpot.selector, 69, 0));
        vm.prank(externalAccount);
        manager.unqueue(69, abi.encode(IVertexManager.WithdrawPerpResponse({amountToReceive: amountBTC})));

        vm.prank(externalAccount);
        manager.unqueue(1, abi.encode(IVertexManager.WithdrawPerpResponse({amountToReceive: amountBTC})));

        assertEq(manager.getUserActiveAmount(2, address(BTC), address(this)), amountBTC);
    }

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

        manager.addPool(999, tokens, hardcaps, IVertexManager.PoolType.Spot, externalAccount);

        // Get the pool data.
        (address routerBTC, uint256 activeAmountBTC, uint256 hardcapBTC, bool activeBTC) =
            manager.getPoolToken(999, address(BTC));
        (address routerUSDC, uint256 activeAmountUSDC, uint256 hardcapUSDC, bool activeUSDC) =
            manager.getPoolToken(999, address(USDC));

        assertEq(routerBTC, routerUSDC);
        assertEq(activeAmountBTC, 0);
        assertEq(activeAmountBTC, activeAmountUSDC);
        assertEq(hardcapBTC, hardcaps[0]);
        assertEq(hardcapUSDC, hardcaps[1]);
        assertTrue(activeBTC);
        assertTrue(activeUSDC);

        hardcaps[0] = 0;
        hardcaps[1] = 0;

        manager.updatePoolHardcaps(999, tokens, hardcaps);

        // Get the pool data.
        (,, hardcapBTC, activeBTC) = manager.getPoolToken(999, address(BTC));
        (,, hardcapUSDC, activeUSDC) = manager.getPoolToken(999, address(USDC));

        assertEq(hardcapBTC, hardcaps[0]);
        assertEq(hardcapUSDC, hardcaps[1]);
        assertTrue(activeBTC);
        assertTrue(activeUSDC);
    }

    /// @notice Unit test for adding and updating a pool with a new token.
    function testAddPoolTokens() public {
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
            manager.getPoolToken(999, address(BTC));

        assertEq(routerBTC, address(0));
        assertEq(activeAmountBTC, 0);
        assertEq(hardcapBTC, 0);
        assertFalse(activeBTC);
    }

    /// @notice Unit test for checking pool empty state.
    function testPoolAdd() public {
        vm.startPrank(owner);

        uint256 balance = paymentToken.balanceOf(owner);

        // Remove tokens from owner to simulate not having funds to pay for the LinkedSigner fee.
        paymentToken.transfer(address(0x69), balance);

        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        // Expect revert when trying to create a pool as owner doesn't have funds to cover LinkedSigner fee.
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        manager.addPool(999, tokens, hardcaps, IVertexManager.PoolType.Spot, externalAccount);

        vm.stopPrank();

        // Transfer tokens back to owner.
        vm.prank(address(0x69));
        paymentToken.transfer(address(owner), balance);

        vm.startPrank(owner);

        // Remove allowance.
        paymentToken.approve(address(manager), 0);

        // Expect revert when trying to create a pool as owner didn't give allowance for LinkedSigner fee.
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        manager.addPool(999, tokens, hardcaps, IVertexManager.PoolType.Spot, externalAccount);

        // Approve the manager to move USDC for fee payments.
        paymentToken.approve(address(manager), type(uint256).max);

        manager.addPool(999, tokens, hardcaps, IVertexManager.PoolType.Spot, externalAccount);
    }

    /// @notice Unit test for checks when adding pools.
    function testPoolAddChecks() public {
        vm.startPrank(owner);

        address[] memory tokens = new address[](2);
        tokens[0] = address(WETH);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidPool.selector, 1));
        manager.addPool(1, tokens, hardcaps, IVertexManager.PoolType.Spot, externalAccount);

        tokens[0] = address(WETH);
        tokens[1] = address(WETH);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.AlreadySupported.selector, address(WETH), 999));
        manager.addPool(999, tokens, hardcaps, IVertexManager.PoolType.Spot, externalAccount);
    }

    /// @notice Unit test for failing to add a pool token with more than 18 decimals.
    function testAddInvalidPoolToken() public {
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

        manager.addPool(999, tokens, hardcaps, IVertexManager.PoolType.Spot, externalAccount);

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

        vm.expectRevert(VertexManager.DepositsPaused.selector);
        manager.depositSpot{value: fee}(1, address(0), address(0), 0, 0, 0, address(this));
    }

    /// @notice Unit test for paused withdrawals.
    function testWithdrawalsPaused() public {
        vm.prank(owner);
        manager.pause(false, true, false);

        vm.expectRevert(VertexManager.WithdrawalsPaused.selector);
        manager.withdrawSpot{value: fee}(1, address(0), address(0), 0);
    }

    /// @notice Unit test for paused claims.
    function testClaimsPaused() public {
        vm.prank(owner);
        manager.pause(false, false, true);

        vm.expectRevert(VertexManager.ClaimsPaused.selector);
        manager.claim(address(this), address(0), 1);
    }

    /*//////////////////////////////////////////////////////////////
                              TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unit test for updating a token.
    function testUpdateToken() public {
        vm.startPrank(owner);

        assertEq(manager.tokenToProduct(address(0x69)), 0);

        manager.updateToken(address(0x69), 1);

        assertEq(manager.tokenToProduct(address(0x69)), 1);

        manager.updateToken(address(0x69), 2);

        assertEq(manager.tokenToProduct(address(0x69)), 2);
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
        // Deploy Processor implementation
        VertexProcessor processorImplementation = new VertexProcessor();

        // Deploy Manager implementation
        VertexManager managerImplementation = new VertexManager();

        // Deploy and initialize the proxy contract.
        new ERC1967Proxy(
            address(managerImplementation),
            abi.encodeWithSignature(
                "initialize(address,address,uint256)", address(endpoint), address(processorImplementation), 1000000
            )
        );
    }

    /// @notice Unit test for failing to initialize the proxy twice.
    function testFailDoubleInitiliaze() public {
        manager.initialize(address(0), address(0), 0);
    }

    /// @notice Unit test for upgrading the proxy and running a spot single unit test.
    function testUpgradeProxy() public {
        // Deploy another implementation and upgrade proxy to it.
        vm.startPrank(owner);
        manager.upgradeTo(address(new VertexManager()));
        vm.stopPrank();

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
    function testFailgetTransactionFee() public view {
        manager.getTransactionFee(address(0xdead));
    }

    /// @notice Unit test for getting the token price.
    function testPrice() public {
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

    /// @notice Unit test for getting the next spot in queue.
    function testGetNextSpot() public {
        uint256 amountBTC = 10 * 10 ** 8; // 10 BTC
        uint256 amountUSDC = 100 * 10 ** 6; // 100 USDC

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        // Deposit 10 BTC and 100 USDC.
        manager.depositPerp{value: fee}(2, address(BTC), amountBTC, address(this));
        manager.depositPerp{value: fee}(2, address(USDC), amountUSDC, address(this));
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        // Withdraw 10 BTC paying fee in BTC.
        manager.withdrawPerp{value: fee}(2, address(BTC), amountBTC);

        IVertexManager.Spot memory spot = manager.nextSpot();
        IVertexManager.WithdrawPerp memory spotTxn = abi.decode(spot.transaction, (IVertexManager.WithdrawPerp));

        assertEq(spot.sender, address(this));
        assertEq(spotTxn.id, 2);
        assertEq(spotTxn.token, address(BTC));
        assertEq(spotTxn.amount, amountBTC);

        // Withdraw 100 USDC paying fee in USDC.
        manager.withdrawPerp{value: fee}(2, address(USDC), amountUSDC);

        spot = manager.nextSpot();
        spotTxn = abi.decode(spot.transaction, (IVertexManager.WithdrawPerp));

        assertEq(spot.sender, address(this));
        assertEq(spotTxn.id, 2);
        assertEq(spotTxn.token, address(BTC));
        assertEq(spotTxn.amount, amountBTC);

        vm.startPrank(externalAccount);
        manager.unqueue(
            manager.queueUpTo() + 1, abi.encode(IVertexManager.WithdrawPerpResponse({amountToReceive: amountBTC}))
        );

        spot = manager.nextSpot();
        spotTxn = abi.decode(spot.transaction, (IVertexManager.WithdrawPerp));

        assertEq(spot.sender, address(this));
        assertEq(spotTxn.id, 2);
        assertEq(spotTxn.token, address(USDC));
        assertEq(spotTxn.amount, amountUSDC);

        manager.unqueue(
            manager.queueUpTo() + 1, abi.encode(IVertexManager.WithdrawPerpResponse({amountToReceive: amountUSDC}))
        );

        spot = manager.nextSpot();

        assertEq(spot.sender, address(0));
        assertEq(spot.router, address(0));
        assertEq(uint8(spot.spotType), uint8(IVertexManager.SpotType.Empty));
        assertEq(spot.transaction, "");

        vm.stopPrank();
    }

    /// @notice Unit test for reversed spot deposits.
    function testReversedSpot(uint72 amountBTC) public {
        // BTC amount to deposit should be at least the withdraw fee (otherwise not enough to pay fee).
        vm.assume(amountBTC >= manager.getTransactionFee(address(BTC)));

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        manager.depositSpot{value: fee}(
            1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
        );

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        manager.withdrawSpot{value: fee}(1, spotTokens[1], spotTokens[0], amountUSDC);
    }

    /// @notice Unit test for balanced amount calculation.
    function testBalancedAmount(uint240 amountBTC) public {
        vm.assume(amountBTC > 0);

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);
        assertLe(manager.getBalancedAmount(address(USDC), address(BTC), amountUSDC), amountBTC);
    }

    /// @notice Unit test for a cross product deposit, withdraw, and claim flow.
    function testCrossProduct() public {
        uint72 amountBTC = 1 * 10 ** 8; // 1 BTC
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC * 2);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC * 2);

        manager.depositSpot{value: fee}(
            1, spotTokens[0], spotTokens[1], amountBTC, amountUSDC, amountUSDC, address(this)
        );
        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        manager.withdrawSpot{value: fee}(1, spotTokens[0], spotTokens[1], amountBTC);
        manager.depositPerp{value: fee}(2, address(USDC), amountUSDC, address(this));

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        manager.withdrawPerp{value: fee}(2, address(USDC), amountUSDC);

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        processSlowModeTxsOld(endpoint);

        assertEq(
            sumPendingBalance(address(USDC), address(this)),
            (amountUSDC * 2)
                - (
                    manager.getUserFee(2, address(USDC), address(this))
                        + manager.getUserFee(1, address(USDC), address(this))
                )
        );

        (address router1,,,) = manager.getPoolToken(1, address(0));
        (address router2,,,) = manager.getPoolToken(2, address(0));

        assertEq(BTC.balanceOf(router1) + BTC.balanceOf(router2), amountBTC);
        assertEq(USDC.balanceOf(router1) + USDC.balanceOf(router2), amountUSDC * 2);

        manager.claim(address(this), spotTokens[0], 1);
        manager.claim(address(this), spotTokens[1], 1);

        assertEq(BTC.balanceOf(router1) + BTC.balanceOf(router2), 0);
        assertEq(USDC.balanceOf(router1) + USDC.balanceOf(router2), amountUSDC);

        manager.claim(address(this), address(USDC), 2);

        assertEq(BTC.balanceOf(router1) + BTC.balanceOf(router2), 0);
        assertEq(USDC.balanceOf(router1) + USDC.balanceOf(router2), 0);
    }

    /// @notice Unit test for a different fee used for withdraws.
    function testFeesPerPool() public {
        uint256 amountBTC = 10 * 10 ** 8; // 10 BTC
        uint256 amountUSDC = 100 * 10 ** 6; // 100 USDC

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        // Deposit 10 BTC and 100 USDC.
        manager.depositPerp{value: fee}(2, address(BTC), amountBTC, address(this));
        manager.depositPerp{value: fee}(2, address(USDC), amountUSDC, address(this));

        // Withdraw 10 BTC paying fee in BTC.
        manager.withdrawPerp{value: fee}(2, address(BTC), amountBTC);

        // Withdraw 100 USDC paying fee in USDC.
        manager.withdrawPerp{value: fee}(2, address(USDC), amountUSDC);

        vm.startPrank(externalAccount);
        processQueue(manager);
        vm.stopPrank();

        // Check that the fees are stored well (are more than 0).
        assertGe(manager.getUserFee(2, address(BTC), address(this)), 0);
        assertGe(manager.getUserFee(2, address(USDC), address(this)), 0);

        processSlowModeTxsOld(endpoint);

        uint256 beforeClaimUSDC = USDC.balanceOf(owner);
        uint256 beforeClaimBTC = BTC.balanceOf(owner);

        // Claim and check that the fees and tokens were distributed.
        manager.claim(address(this), address(BTC), 2);
        manager.claim(address(this), address(USDC), 2);

        uint256 afterClaimUSDC = USDC.balanceOf(owner);
        uint256 afterClaimBTC = BTC.balanceOf(owner);

        assertEq(afterClaimBTC - beforeClaimBTC, manager.getTransactionFee(address(BTC)));
        assertEq(afterClaimUSDC - beforeClaimUSDC, manager.getTransactionFee(address(USDC)));
        assertEq(BTC.balanceOf(address(this)), amountBTC - (afterClaimBTC - beforeClaimBTC));
        assertEq(USDC.balanceOf(address(this)), amountUSDC - (afterClaimUSDC - beforeClaimUSDC));
    }

    /// @notice Unit test for skipping the spot in the queue.
    function testSkipSpot() public {
        uint256 amountBTC = manager.getTransactionFee(address(BTC));
        deal(address(BTC), address(this), amountBTC);

        BTC.approve(address(manager), amountBTC);

        // Deposit BTC and withdraw BTC.
        manager.depositPerp{value: fee}(2, address(BTC), amountBTC, address(this));
        manager.withdrawPerp{value: fee}(2, address(BTC), amountBTC);

        VertexManager.Spot memory spot = manager.nextSpot();
        IVertexManager.DepositPerp memory spotTxn = abi.decode(spot.transaction, (IVertexManager.DepositPerp));

        assertEq(spot.sender, address(this));
        assertEq(spotTxn.id, 2);
        assertEq(spotTxn.token, address(BTC));
        assertEq(spotTxn.amount, amountBTC);
        assertEq(spotTxn.receiver, address(this));

        assertEq(manager.getUserActiveAmount(2, address(BTC), address(this)), 0);

        // Process tx fails silently and spot is skipped. No changes applied.
        vm.startPrank(externalAccount);
        manager.unqueue(1, "");
        manager.unqueue(2, "");

        assertEq(manager.getUserActiveAmount(2, address(BTC), address(this)), 0);
        assertEq(manager.queueUpTo(), 2);
    }

    /// @notice Unit test to check that any remaining fee is transfered back to user.
    function testElixirFee() public {
        uint256 balanceBefore = address(this).balance;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.FeeTooLow.selector, fee - 1, fee));
        manager.depositPerp{value: fee - 1}(2, address(0), 1, address(this));

        assertEq(address(this).balance, balanceBefore);
        assertEq(externalAccount.balance, 0);

        // Deposit BTC to perp pool.
        manager.depositPerp{value: fee + 1}(2, address(0), 1, address(this));

        assertEq(address(this).balance, balanceBefore - (fee + 1));
        assertEq(externalAccount.balance, fee + 1);
    }
}
