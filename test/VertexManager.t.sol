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
        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        // Add spot pool.
        manager.addPool(1, externalAccount, tokens, hardcaps);

        // Add token support.
        manager.updateToken(address(USDC), 0);
        manager.updateToken(address(BTC), 1);

        vm.stopPrank();
    }

    function perpDepositSetUp() public {
        vm.startPrank(owner);

        // Create BTC PERP pool with BTC, USDC, and ETH as tokens.
        address[] memory tokens = new address[](3);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);
        tokens[2] = address(WETH);

        uint256[] memory hardcaps = new uint256[](3);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;
        hardcaps[2] = type(uint256).max;

        // Add perp pool.
        manager.addPool(2, externalAccount, tokens, hardcaps);

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

        manager.deposit(1, amounts, address(this));

        (address router,,, uint256[] memory activeAmounts) = manager.getPool(1);
        uint256[] memory userActiveAmounts = manager.getUserActiveAmounts(1, address(this));

        assertEq(userActiveAmounts, amounts);
        assertEq(activeAmounts, userActiveAmounts);
        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.withdraw(1, amounts, 0);

        uint256[] memory amountsEmpty = new uint256[](2);
        amountsEmpty[0] = 0;
        amountsEmpty[1] = 0;

        (,,, activeAmounts) = manager.getPool(1);
        userActiveAmounts = manager.getUserActiveAmounts(1, address(this));

        assertEq(userActiveAmounts, amountsEmpty);
        assertEq(activeAmounts, userActiveAmounts);
        assertEq(manager.pendingBalances(address(this), address(BTC)), 1 * 10 ** 8);
        assertEq(manager.pendingBalances(address(this), address(USDC)), amounts[1]);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), router, amountUSDC);

        // Claim tokens for user and owner.
        manager.claim(address(this), 1);

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

        manager.deposit(1, amounts, address(this));

        (address router,,, uint256[] memory activeAmounts) = manager.getPool(1);
        uint256[] memory userActiveAmounts = manager.getUserActiveAmounts(1, address(this));

        assertEq(userActiveAmounts, amounts);
        assertEq(activeAmounts, userActiveAmounts);
        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.deposit(1, amounts, address(this));

        (,,, activeAmounts) = manager.getPool(1);
        userActiveAmounts = manager.getUserActiveAmounts(1, address(this));

        uint256[] memory amountsDoubled = new uint256[](2);
        amountsDoubled[0] = amountBTC * 2;
        amountsDoubled[1] = amountUSDC * 2;

        assertEq(userActiveAmounts, amountsDoubled);
        assertEq(activeAmounts, userActiveAmounts);
        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        amountBTC = 1 * 10 ** 8;
        amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        manager.withdraw(1, amounts, 0);

        (,,, activeAmounts) = manager.getPool(1);
        userActiveAmounts = manager.getUserActiveAmounts(1, address(this));

        assertEq(userActiveAmounts, amounts);
        assertEq(activeAmounts, userActiveAmounts);
        assertEq(
            manager.pendingBalances(address(this), address(BTC)), 1 * 10 ** 8 - manager.getWithdrawFee(address(BTC))
        );
        assertEq(manager.pendingBalances(address(this), address(USDC)), amountUSDC);

        manager.withdraw(1, amounts, 0);

        (,,, activeAmounts) = manager.getPool(1);
        userActiveAmounts = manager.getUserActiveAmounts(1, address(this));

        uint256[] memory amountsEmpty = new uint256[](2);
        amountsEmpty[0] = 0;
        amountsEmpty[1] = 0;

        assertEq(userActiveAmounts, amountsEmpty);
        assertEq(activeAmounts, userActiveAmounts);
        assertEq(
            manager.pendingBalances(address(this), address(BTC)),
            2 * (1 * 10 ** 8 - manager.getWithdrawFee(address(BTC)))
        );
        assertEq(manager.pendingBalances(address(this), address(USDC)), 2 * amountUSDC);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), address(router), amountUSDC * 2);

        // Claim tokens for user and owner.
        manager.claim(address(this), 1);

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

        manager.depositBalanced(1, amountBTC, 0, type(uint256).max, address(this));

        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = amountBTC;
        expectedAmounts[1] = amountUSDC;

        (address router,,, uint256[] memory activeAmounts) = manager.getPool(1);
        uint256[] memory userActiveAmounts = manager.getUserActiveAmounts(1, address(this));

        assertEq(userActiveAmounts, expectedAmounts);
        assertEq(activeAmounts, userActiveAmounts);
        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        expectedAmounts[0] = 0;
        expectedAmounts[1] = 0;

        manager.withdrawBalanced(1, amountBTC, 0);

        (,,, activeAmounts) = manager.getPool(1);
        userActiveAmounts = manager.getUserActiveAmounts(1, address(this));

        assertEq(userActiveAmounts, expectedAmounts);
        assertEq(activeAmounts, userActiveAmounts);
        assertEq(manager.pendingBalances(address(this), address(BTC)), 1 * 10 ** 8);
        assertEq(manager.pendingBalances(address(this), address(USDC)), amountUSDC);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), router, amountUSDC);

        // Claim tokens for user and owner.
        manager.claim(address(this), 1);

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

        manager.deposit(2, amounts, address(this));

        (,,, uint256[] memory activeAmounts) = manager.getPool(2);
        uint256[] memory userActiveAmounts = manager.getUserActiveAmounts(2, address(this));

        assertEq(userActiveAmounts, amounts);
        assertEq(activeAmounts, userActiveAmounts);
        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);
        assertEq(manager.pendingBalances(address(this), address(WETH)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.withdraw(2, amounts, 0);

        (,,, activeAmounts) = manager.getPool(2);
        userActiveAmounts = manager.getUserActiveAmounts(2, address(this));

        uint256[] memory amountsEmpty = new uint256[](3);
        amountsEmpty[0] = 0;
        amountsEmpty[1] = 0;
        amountsEmpty[2] = 0;

        assertEq(userActiveAmounts, amountsEmpty);
        assertEq(activeAmounts, userActiveAmounts);
        assertEq(
            manager.pendingBalances(address(this), address(BTC)), amounts[0] - manager.getWithdrawFee(address(BTC))
        );
        assertEq(manager.pendingBalances(address(this), address(USDC)), amounts[1]);
        assertEq(manager.pendingBalances(address(this), address(WETH)), amounts[2]);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();

        // Claim tokens for user and owner.
        manager.claim(address(this), 2);

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

        manager.depositBalanced(1, amountBTC, 0, type(uint256).max, address(0x69));

        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = amountBTC;
        expectedAmounts[1] = amountUSDC;

        (address router,,, uint256[] memory activeAmounts) = manager.getPool(1);
        uint256[] memory userActiveAmountsCaller = manager.getUserActiveAmounts(1, address(this));
        uint256[] memory userActiveAmountsReceiver = manager.getUserActiveAmounts(1, address(0x69));
        uint256[] memory amountsVoid = new uint256[](0);

        assertEq(userActiveAmountsCaller, amountsVoid);
        assertEq(userActiveAmountsReceiver, expectedAmounts);
        assertEq(activeAmounts, userActiveAmountsReceiver);
        assertEq(manager.pendingBalances(address(0x69), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(0x69), address(USDC)), 0);
        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        expectedAmounts[0] = 0;
        expectedAmounts[1] = 0;

        vm.prank(address(0x69));
        manager.withdrawBalanced(1, amountBTC, 0);

        (,,, activeAmounts) = manager.getPool(1);
        userActiveAmountsCaller = manager.getUserActiveAmounts(1, address(this));
        userActiveAmountsReceiver = manager.getUserActiveAmounts(1, address(0x69));

        uint256[] memory amountsEmpty = new uint256[](2);
        amountsEmpty[0] = 0;
        amountsEmpty[1] = 0;

        assertEq(userActiveAmountsCaller, amountsVoid);
        assertEq(userActiveAmountsReceiver, amountsEmpty);
        assertEq(activeAmounts, userActiveAmountsReceiver);
        assertEq(manager.pendingBalances(address(0x69), address(BTC)), 1 * 10 ** 8);
        assertEq(manager.pendingBalances(address(0x69), address(USDC)), amountUSDC);
        assertEq(manager.pendingBalances(address(this), address(BTC)), 0);
        assertEq(manager.pendingBalances(address(this), address(USDC)), 0);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), router, amountUSDC);

        // Claim tokens for user and owner.
        manager.claim(address(0x69), 1);

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
        manager.deposit(1, amounts, address(this));
    }

    function testWithdrawWithNotEnoughBalance(uint248 amountBTC) public {
        vm.assume(amountBTC > 1);
        spotDepositSetUp();

        deal(address(BTC), address(this), type(uint256).max);
        deal(address(USDC), address(this), type(uint256).max);

        BTC.approve(address(manager), type(uint256).max);
        USDC.approve(address(manager), type(uint256).max);

        manager.depositBalanced(1, amountBTC / 2, 1, type(uint256).max, address(this));

        processSlowModeTxs();

        vm.expectRevert();
        manager.withdrawBalanced(1, amountBTC, 0);
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
        manager.deposit(1, amounts, address(this));
    }

    function testWithdrawWithNoBalance(uint240 amountBTC) public {
        vm.assume(amountBTC > 0);
        spotDepositSetUp();

        vm.expectRevert();
        manager.withdrawBalanced(1, amountBTC, 0);
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
        manager.deposit(1, amounts, address(this));
    }

    function testDepositInvalidInputs() public {
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidLength.selector, amounts, 0));

        manager.deposit(0, amounts, address(this));

        amounts = new uint256[](2);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidLength.selector, amounts, 0));
        manager.deposit(0, amounts, address(this));
    }

    function testUnbalancedDeposit() public {
        spotDepositSetUp();

        uint256[] memory amounts = new uint256[](2);
        // 1 BTC
        amounts[0] = 1 ether;
        // 1 USDC
        amounts[1] = 1;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.UnbalancedAmounts.selector, 1, amounts));
        manager.deposit(1, amounts, address(this));
    }

    function testUnbalancedWithdraw() public {
        spotDepositSetUp();

        uint256[] memory amounts = new uint256[](2);
        // 1 BTC
        amounts[0] = 1 ether;
        // 1 USDC
        amounts[1] = 1;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.UnbalancedAmounts.selector, 1, amounts));
        manager.withdraw(1, amounts, 0);
    }

    function testWithdrawInvalidFee() public {
        spotDepositSetUp();

        uint256 amountBTC = 1 * 10 ** 8;
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.InvalidLength.selector, amounts, 1));
        manager.withdraw(1, amounts, 69);
    }

    function testHardcapReached() public {
        spotDepositSetUp();

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = 0;
        hardcaps[1] = 0;

        vm.prank(owner);
        manager.updatePoolHardcaps(1, hardcaps);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        // Deposit should succeed because amounts are 0 and hardcap is 0 too.
        manager.deposit(1, amounts, address(this));

        uint256 amountBTC = 1 * 10 ** 8;
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        vm.expectRevert(abi.encodeWithSelector(VertexManager.HardcapReached.selector, address(BTC), 0, 0, amountBTC));
        manager.deposit(1, amounts, address(this));

        hardcaps[0] = type(uint256).max;
        hardcaps[1] = 0;

        vm.prank(owner);
        manager.updatePoolHardcaps(1, hardcaps);

        deal(address(BTC), address(this), amountBTC);
        BTC.approve(address(manager), amountBTC);

        vm.expectRevert(abi.encodeWithSelector(VertexManager.HardcapReached.selector, address(USDC), 0, 0, amountUSDC));
        manager.deposit(1, amounts, address(this));

        hardcaps[1] = type(uint256).max;

        vm.prank(owner);
        manager.updatePoolHardcaps(1, hardcaps);

        deal(address(USDC), address(this), amountUSDC);
        USDC.approve(address(manager), amountUSDC);

        manager.deposit(1, amounts, address(this));
    }

    function testNotSpotPool() public {
        perpDepositSetUp();

        vm.expectRevert(abi.encodeWithSelector(VertexManager.NotSpotPool.selector, 2));
        manager.depositBalanced(2, 69, 0, type(uint256).max, address(this));

        vm.expectRevert(abi.encodeWithSelector(VertexManager.NotSpotPool.selector, 2));
        manager.withdrawBalanced(2, 69, 0);
    }

    function testSingleDepositBalancedSlippage() public {
        spotDepositSetUp();

        uint256 amountBTC = 1 * 10 ** 8 + manager.getWithdrawFee(address(BTC));
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        vm.expectRevert(
            abi.encodeWithSelector(VertexManager.SlippageTooHigh.selector, amountUSDC, amountUSDC * 2, amountUSDC * 4)
        );
        manager.depositBalanced(1, amountBTC, amountUSDC * 2, amountUSDC * 4, address(this));
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

        manager.deposit(1, amounts, address(this));

        // Advance time for deposit slow-mode tx.
        processSlowModeTxs();

        manager.withdraw(1, amounts, 1);

        // Get the router address.
        (address router,,,) = manager.getPool(1);

        // Advance time for withdraw slow-mode tx.
        processSlowModeTxs();
        deal(address(USDC), router, amountUSDC);

        // Claim tokens for user and owner.
        manager.claim(address(this), 1);
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

        manager.deposit(2, amounts, address(this));

        // Try to withdraw and pay fees with USDC, but should revert because there is no USDC, so not enough to pay fees.
        vm.expectRevert();
        manager.withdraw(2, amounts, 1);
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
        (, address[] memory tokens_, uint256[] memory hardcaps_,) = manager.getPool(1);

        assertEq(tokens_, tokens);
        assertEq(hardcaps_, hardcaps);

        hardcaps[0] = 0;
        hardcaps[1] = 0;

        manager.updatePoolHardcaps(1, hardcaps);

        // Get the pool data.
        (, tokens_, hardcaps_,) = manager.getPool(1);

        assertEq(tokens_, tokens);
        assertEq(hardcaps_, hardcaps);
    }

    function testUnauthorizedAddAndUpdate() public {
        address[] memory tokens = new address[](0);
        uint256[] memory hardcaps = new uint256[](0);

        vm.expectRevert();
        manager.updatePoolHardcaps(1, hardcaps);

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
        (, address[] memory tokens_, uint256[] memory hardcaps_,) = manager.getPool(2);

        assertTrue(tokens_.length == 0);
        assertTrue(hardcaps_.length == 0);
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

        vm.expectRevert(VertexManager.DepositsPaused.selector);
        manager.deposit(1, amounts, address(this));
    }

    function testWithdrawalsPaused() public {
        vm.prank(owner);
        manager.pause(false, true, false);

        uint256[] memory amounts = new uint256[](2);

        vm.expectRevert(VertexManager.WithdrawalsPaused.selector);
        manager.withdraw(1, amounts, 0);
    }

    function testClaimsPaused() public {
        vm.prank(owner);
        manager.pause(false, false, true);

        vm.expectRevert(VertexManager.ClaimsPaused.selector);
        manager.claim(address(this), 1);
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

        manager.getVertexBalance(1, address(BTC));

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountBTC;
        amounts[1] = 0;
        amounts[2] = 0;

        manager.deposit(2, amounts, address(this));

        manager.getVertexBalance(1, address(BTC));
    }
}
