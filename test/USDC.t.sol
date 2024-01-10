// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {ProcessQueue} from "test/utils/ProcessQueue.sol";

import {IVertexManager, IEndpoint} from "src/VertexStorage.sol";
import {VertexProcessor, IClearinghouse} from "src/VertexProcessor.sol";
import {VertexManager, IClearinghouse} from "src/VertexManager.sol";
import {VertexRouter} from "src/VertexRouter.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract TestVertexManagerUSDC is Test, ProcessQueue {
    VertexManager internal manager;
    IEndpoint internal endpoint;

    IERC20Metadata BTC = IERC20Metadata(0xA7Fcb606611358afa388b6bd23b3B2F2c6abEd82);
    IERC20Metadata WETH = IERC20Metadata(0x94B3173E0a23C28b2BA9a52464AC24c2B032791c);
    IERC20Metadata USDC = IERC20Metadata(0xD32ea1C76ef1c296F131DD4C5B2A0aac3b22485a);
    IERC20Metadata USDCE = IERC20Metadata(0xbC47901f4d2C5fc871ae0037Ea05c3F614690781);

    // RPC URL for Arbitrum fork.
    string public networkRpcUrl = vm.envString("SEPOLIA_RPC_URL");

    function setUp() public {
        vm.createSelectFork(networkRpcUrl, 5974654);

        // Wrap in ABI to support easier calls.
        manager = VertexManager(0x052Ab3fd33cADF9D9f227254252da3f996431f75);

        // Get the endpoint address.
        endpoint = manager.endpoint();

        // Empty Vertex queue for accurate testing.
        processSlowModeTxs(endpoint);

        // Continue as owner.
        vm.startPrank(manager.owner());

        /*//////////////////////////////////////////////////////////////
                                    STEP 1
        //////////////////////////////////////////////////////////////*/

        // Pause the manager.
        manager.pause(true, true, true);

        /*//////////////////////////////////////////////////////////////
                                    STEP 2
        //////////////////////////////////////////////////////////////*/

        // Upgrade to new version.

        // Deploy new Processor implementation.
        VertexProcessor newProcessor = new VertexProcessor();

        // Deploy new Manager implementation.
        VertexManager newManager = new VertexManager();

        // Upgrade proxy to new implementation.
        manager.upgradeToAndCall(
            address(newManager), abi.encodeWithSelector(VertexManager.updateProcessor.selector, address(newProcessor))
        );

        // Check upgrade by ensuring storage is not changed.
        require(address(manager.endpoint()) == address(endpoint), "Invalid upgrade");

        /*//////////////////////////////////////////////////////////////
                                    STEP 3
        //////////////////////////////////////////////////////////////*/

        // Add USDC token for pool. Using BTC-PERP and BTC-SPOT as examples here.
        // This is needed so that all of the routers approve this new token to transfer in and out.
        address[] memory token = new address[](1);
        token[0] = address(USDC);

        uint256[] memory hardcap = new uint256[](1);
        hardcap[0] = 0;

        manager.addPoolTokens(1, token, hardcap);
        manager.addPoolTokens(2, token, hardcap);

        /*//////////////////////////////////////////////////////////////
                                    STEP 4
        //////////////////////////////////////////////////////////////*/

        // Update the quote token to use the new USDC token and store the previous one (USDC.e)
        manager.updateQuoteToken(address(USDC));

        /*//////////////////////////////////////////////////////////////
                                    STEP 5
        //////////////////////////////////////////////////////////////*/

        // Owner (multisig in mainnet, EOA in testnet) should approve USDC for slow-mode fee and make sure to have enough (for exmaple, swapping USDC.e to USDC)
        USDC.approve(address(manager), type(uint256).max);
        deal(address(USDC), address(manager.owner()), 10000000 * 10 ** USDC.decimals());

        /*//////////////////////////////////////////////////////////////
                                    STEP 6
        //////////////////////////////////////////////////////////////*/

        // Unpause manager
        manager.pause(false, false, false);

        vm.stopPrank();
    }

    // Check that the pools helpers work with both USDC and USDC.e, returning same values as they should use the same data.
    function testHelpers() external {
        // Get the USDC data.
        (address routerUSDC, uint256 activeAmountUSDC, uint256 hardcapUSDC, bool activeUSDC) =
            manager.getPoolToken(2, address(USDC));

        // Get the USDC.e data.
        (address routerUSDCE, uint256 activeAmountUSDCE, uint256 hardcapUSDCE, bool activeUSDCE) =
            manager.getPoolToken(2, address(USDCE));

        assertEq(routerUSDC, routerUSDCE);
        assertEq(activeAmountUSDC, activeAmountUSDCE);
        assertEq(hardcapUSDC, hardcapUSDCE);
        assertEq(activeUSDC, activeUSDCE);

        // Get a user's active amount with USDC.
        uint256 userActiveAmountUSDC =
            manager.getUserActiveAmount(2, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        // Get a user's active amount with USDC.e.
        uint256 userActiveAmountUSDCE =
            manager.getUserActiveAmount(2, address(USDCE), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        assertEq(userActiveAmountUSDC, userActiveAmountUSDCE);

        // Get a user's pending amount with USDC.
        uint256 userPendingAmountUSDC =
            manager.getUserPendingAmount(2, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        // Get a user's pending amount with USDC.e.
        uint256 userPendingAmountUSDCE =
            manager.getUserPendingAmount(2, address(USDCE), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        assertEq(userPendingAmountUSDC, userPendingAmountUSDCE);

        // Get a user's fee amount with USDC.
        uint256 userFeeAmountUSDC = manager.getUserFee(2, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        // Get a user's fee amount with USDC.e.
        uint256 userFeeAmountUSDCE = manager.getUserFee(2, address(USDCE), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        assertEq(userFeeAmountUSDC, userFeeAmountUSDCE);
    }

    // Check that USDC.e deposits are rejected.
    function testRejectDeposit() external {
        uint256 amountUSDCE = 100 * 10 ** USDCE.decimals();

        deal(address(USDCE), address(this), amountUSDCE);

        USDCE.approve(address(manager), amountUSDCE);

        uint256 fee = manager.getTransactionFee(address(WETH));

        manager.depositPerp{value: fee}(2, address(USDCE), amountUSDCE, address(this));

        // Get the router address
        (address router,,,) = manager.getPoolToken(2, address(USDCE));

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        // Active amounts should be 0 as deposit should be skipped.
        uint256 activeAmount = manager.getUserActiveAmount(2, address(USDCE), address(this));

        assertEq(activeAmount, 0);
        assertEq(USDCE.balanceOf(address(this)), amountUSDCE);
    }

    // Check that the fee is calculated correctly.
    function testCheckFee() external {
        assertEq(manager.getTransactionFee(address(USDC)), manager.getTransactionFee(address(USDCE)));
    }

    // Deposits and withdraws from perp pool with a fresh account
    function testPerpFreshAccount() external {
        // Deposit to pool.
        uint256 amountUSDC = 100 * 10 ** USDC.decimals();

        deal(address(USDC), address(this), amountUSDC);

        USDC.approve(address(manager), amountUSDC);

        uint256 fee = manager.getTransactionFee(address(WETH));

        manager.depositPerp{value: fee}(2, address(USDC), amountUSDC, address(this));

        // Get the router address
        (address router,,,) = manager.getPoolToken(2, address(USDC));

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        uint256 activeAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        uint256 activeAmountUSDCE = manager.getUserActiveAmount(2, address(USDCE), address(this));

        assertEq(activeAmountUSDC, amountUSDC);
        assertEq(activeAmountUSDC, activeAmountUSDCE);

        // Withdraw from pool.
        manager.withdrawPerp{value: fee}(2, address(USDC), amountUSDC);

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        // USDC shares now should be 0 and the USDC pending amount should be the previous shares amount.
        activeAmountUSDC = manager.getUserActiveAmount(2, address(USDC), address(this));
        activeAmountUSDCE = manager.getUserActiveAmount(2, address(USDCE), address(this));

        assertEq(activeAmountUSDC, 0);
        assertEq(activeAmountUSDC, activeAmountUSDCE);

        uint256 userPendingAmountUSDC = manager.getUserPendingAmount(2, address(USDC), address(this));
        uint256 userPendingAmountUSDCE = manager.getUserPendingAmount(2, address(USDCE), address(this));

        assertEq(userPendingAmountUSDC, amountUSDC - manager.getTransactionFee(address(USDC)));
        assertEq(userPendingAmountUSDC, userPendingAmountUSDCE);

        processSlowModeTxs(endpoint);

        // Claim amounts.
        manager.claim(address(this), address(USDC), 2);

        assertEq(USDC.balanceOf(address(this)), amountUSDC - manager.getTransactionFee(address(USDC)));

        userPendingAmountUSDC = manager.getUserPendingAmount(2, address(USDC), address(this));
        userPendingAmountUSDCE = manager.getUserPendingAmount(2, address(USDCE), address(this));

        assertEq(userPendingAmountUSDC, 0);
        assertEq(userPendingAmountUSDC, userPendingAmountUSDCE);
    }

    // Deposits and withdraws from perp pool with an account that has deposited before the migration.
    function testPerpUsedAccount() external {
        vm.startPrank(0x28CcdB531854d09D48733261688dc1679fb9A242);

        manager.claim(0x28CcdB531854d09D48733261688dc1679fb9A242, address(USDCE), 2);

        // Get the initial active and pending amounts and balance.
        uint256 initialActiveAmount =
            manager.getUserActiveAmount(2, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);
        uint256 initialPendingAmount =
            manager.getUserPendingAmount(2, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        // Deposit to pool.
        uint256 amountUSDC = 100 * 10 ** USDC.decimals();

        deal(address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242, amountUSDC);

        USDC.approve(address(manager), amountUSDC);

        uint256 fee = manager.getTransactionFee(address(WETH));

        manager.depositPerp{value: fee}(2, address(USDC), amountUSDC, 0x28CcdB531854d09D48733261688dc1679fb9A242);

        // Get the router address
        (address router,,,) = manager.getPoolToken(2, address(USDC));

        vm.stopPrank();

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        vm.startPrank(0x28CcdB531854d09D48733261688dc1679fb9A242);

        uint256 activeAmountUSDC =
            manager.getUserActiveAmount(2, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);
        uint256 activeAmountUSDCE =
            manager.getUserActiveAmount(2, address(USDCE), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        assertEq(activeAmountUSDC, initialActiveAmount + amountUSDC);
        assertEq(activeAmountUSDC, activeAmountUSDCE);

        // Withdraw from pool.
        manager.withdrawPerp{value: fee}(2, address(USDC), amountUSDC);

        vm.stopPrank();

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        vm.startPrank(0x28CcdB531854d09D48733261688dc1679fb9A242);

        // USDC shares now should be 0 and the USDC pending amount should be the previous shares amount.
        activeAmountUSDC = manager.getUserActiveAmount(2, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);
        activeAmountUSDCE = manager.getUserActiveAmount(2, address(USDCE), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        assertEq(activeAmountUSDC, initialActiveAmount);
        assertEq(activeAmountUSDC, activeAmountUSDCE);

        uint256 userPendingAmountUSDC =
            manager.getUserPendingAmount(2, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);
        uint256 userPendingAmountUSDCE =
            manager.getUserPendingAmount(2, address(USDCE), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        assertEq(userPendingAmountUSDC, initialPendingAmount + amountUSDC - manager.getTransactionFee(address(USDC)));
        assertEq(userPendingAmountUSDC, userPendingAmountUSDCE);

        processSlowModeTxs(endpoint);

        // Claim amounts.
        manager.claim(0x28CcdB531854d09D48733261688dc1679fb9A242, address(USDC), 2);

        assertEq(
            USDC.balanceOf(0x28CcdB531854d09D48733261688dc1679fb9A242),
            amountUSDC - manager.getTransactionFee(address(USDC))
        );

        userPendingAmountUSDC =
            manager.getUserPendingAmount(2, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);
        userPendingAmountUSDCE =
            manager.getUserPendingAmount(2, address(USDCE), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        assertEq(userPendingAmountUSDC, initialPendingAmount);
        assertEq(userPendingAmountUSDC, userPendingAmountUSDCE);
    }

    // Deposits and withdraws from spot pool with a fresh account
    function testSpotFreshAccount() external {
        // Deposit to pool.
        uint256 amountBTC = 1 * 10 ** BTC.decimals();
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(this), amountBTC);
        deal(address(USDC), address(this), amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        uint256 fee = manager.getTransactionFee(address(WETH));

        manager.depositSpot{value: fee}(
            1, address(BTC), address(USDC), amountBTC, amountUSDC, amountUSDC, address(this)
        );

        // Get the router address
        (address router,,,) = manager.getPoolToken(1, address(USDC));

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        uint256 activeAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        uint256 activeAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));
        uint256 activeAmountUSDCE = manager.getUserActiveAmount(1, address(USDCE), address(this));

        assertEq(activeAmountBTC, amountBTC);
        assertEq(activeAmountUSDC, amountUSDC);
        assertEq(activeAmountUSDC, activeAmountUSDCE);

        // Withdraw from pool.
        manager.withdrawSpot{value: fee}(1, address(BTC), address(USDC), amountBTC);

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        // USDC shares now should be 0 and the USDC pending amount should be the previous shares amount.
        activeAmountBTC = manager.getUserActiveAmount(1, address(BTC), address(this));
        activeAmountUSDC = manager.getUserActiveAmount(1, address(USDC), address(this));
        activeAmountUSDCE = manager.getUserActiveAmount(1, address(USDCE), address(this));

        assertEq(activeAmountBTC, 0);
        assertEq(activeAmountUSDC, 0);
        assertEq(activeAmountUSDC, activeAmountUSDCE);

        uint256 userPendingAmountBTC = manager.getUserPendingAmount(1, address(BTC), address(this));
        uint256 userPendingAmountUSDC = manager.getUserPendingAmount(1, address(USDC), address(this));
        uint256 userPendingAmountUSDCE = manager.getUserPendingAmount(1, address(USDCE), address(this));

        assertEq(userPendingAmountBTC, amountBTC - manager.getTransactionFee(address(BTC)));
        assertEq(userPendingAmountUSDC, amountUSDC - manager.getTransactionFee(address(USDC)));
        assertEq(userPendingAmountUSDC, userPendingAmountUSDCE);

        processSlowModeTxs(endpoint);

        // Claim amounts.
        manager.claim(address(this), address(BTC), 1);
        manager.claim(address(this), address(USDC), 1);

        assertEq(BTC.balanceOf(address(this)), amountBTC - manager.getTransactionFee(address(BTC)));
        assertEq(USDC.balanceOf(address(this)), amountUSDC - manager.getTransactionFee(address(USDC)));

        userPendingAmountBTC = manager.getUserPendingAmount(1, address(BTC), address(this));
        userPendingAmountUSDC = manager.getUserPendingAmount(1, address(USDC), address(this));
        userPendingAmountUSDCE = manager.getUserPendingAmount(1, address(USDCE), address(this));

        assertEq(userPendingAmountBTC, 0);
        assertEq(userPendingAmountUSDC, 0);
        assertEq(userPendingAmountUSDC, userPendingAmountUSDCE);
    }

    // Deposits and withdraws from spot pool with an account that has deposited before the migration.
    function testSpotUsedAccount() external {
        vm.startPrank(0x28CcdB531854d09D48733261688dc1679fb9A242);

        manager.claim(0x28CcdB531854d09D48733261688dc1679fb9A242, address(BTC), 1);
        manager.claim(0x28CcdB531854d09D48733261688dc1679fb9A242, address(USDCE), 1);

        // Get the initial active and pending amounts and balance.
        uint256 initialActiveAmountBTC =
            manager.getUserActiveAmount(1, address(BTC), 0x28CcdB531854d09D48733261688dc1679fb9A242);
        uint256 initialPendingAmountBTC =
            manager.getUserPendingAmount(1, address(BTC), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        uint256 initialActiveAmountUSDC =
            manager.getUserActiveAmount(1, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);
        uint256 initialPendingAmountUSDC =
            manager.getUserPendingAmount(1, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        // Deposit to pool.
        uint256 amountBTC = 1 * 10 ** BTC.decimals();
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), 0x28CcdB531854d09D48733261688dc1679fb9A242, amountBTC);
        deal(address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242, amountUSDC);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        uint256 fee = manager.getTransactionFee(address(WETH));

        manager.depositSpot{value: fee}(
            1,
            address(BTC),
            address(USDC),
            amountBTC,
            amountUSDC,
            amountUSDC,
            0x28CcdB531854d09D48733261688dc1679fb9A242
        );

        // Get the router address
        (address router,,,) = manager.getPoolToken(1, address(USDC));

        vm.stopPrank();

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        {
            vm.startPrank(0x28CcdB531854d09D48733261688dc1679fb9A242);

            uint256 activeAmountBTC =
                manager.getUserActiveAmount(1, address(BTC), 0x28CcdB531854d09D48733261688dc1679fb9A242);
            uint256 activeAmountUSDC =
                manager.getUserActiveAmount(1, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);

            assertEq(activeAmountBTC, initialActiveAmountBTC + amountBTC);
            assertEq(activeAmountUSDC, initialActiveAmountUSDC + amountUSDC);

            // Withdraw from pool.
            manager.withdrawSpot{value: fee}(1, address(BTC), address(USDC), amountBTC);

            vm.stopPrank();

            vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
            processQueue(manager);
            vm.stopPrank();

            // USDC shares now should be 0 and the USDC pending amount should be the previous shares amount.
            activeAmountBTC = manager.getUserActiveAmount(1, address(BTC), 0x28CcdB531854d09D48733261688dc1679fb9A242);
            activeAmountUSDC = manager.getUserActiveAmount(1, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);

            assertEq(activeAmountBTC, initialActiveAmountBTC);
            assertEq(activeAmountUSDC, initialActiveAmountUSDC);
        }

        vm.startPrank(0x28CcdB531854d09D48733261688dc1679fb9A242);

        uint256 userPendingAmountBTC =
            manager.getUserPendingAmount(1, address(BTC), 0x28CcdB531854d09D48733261688dc1679fb9A242);
        uint256 userPendingAmountUSDC =
            manager.getUserPendingAmount(1, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        assertEq(userPendingAmountBTC, initialPendingAmountBTC + amountBTC - manager.getTransactionFee(address(BTC)));
        assertEq(
            userPendingAmountUSDC, initialPendingAmountUSDC + amountUSDC - manager.getTransactionFee(address(USDC))
        );

        processSlowModeTxs(endpoint);

        // Claim amounts.
        manager.claim(0x28CcdB531854d09D48733261688dc1679fb9A242, address(BTC), 1);
        manager.claim(0x28CcdB531854d09D48733261688dc1679fb9A242, address(USDC), 1);

        assertEq(
            USDC.balanceOf(0x28CcdB531854d09D48733261688dc1679fb9A242),
            amountUSDC - manager.getTransactionFee(address(USDC))
        );

        userPendingAmountBTC = manager.getUserPendingAmount(1, address(BTC), 0x28CcdB531854d09D48733261688dc1679fb9A242);
        userPendingAmountUSDC =
            manager.getUserPendingAmount(1, address(USDC), 0x28CcdB531854d09D48733261688dc1679fb9A242);

        assertEq(userPendingAmountBTC, initialPendingAmountBTC);
        assertEq(userPendingAmountUSDC, initialPendingAmountUSDC);
    }

    // Check that pools can be added and used.
    function testAddandUsePool() external {
        vm.startPrank(manager.owner());

        address[] memory token = new address[](1);
        token[0] = address(USDC);

        uint256[] memory hardcap = new uint256[](1);
        hardcap[0] = type(uint256).max;

        manager.addPool(999, token, hardcap, IVertexManager.PoolType.Perp, address(0xbeef));

        vm.stopPrank();

        // Get the USDC data.
        (address routerUSDC, uint256 activeAmountUSDC, uint256 hardcapUSDC, bool activeUSDC) =
            manager.getPoolToken(999, address(USDC));

        // Get the USDC.e data.
        (address routerUSDCE, uint256 activeAmountUSDCE, uint256 hardcapUSDCE, bool activeUSDCE) =
            manager.getPoolToken(999, address(USDCE));

        assertEq(routerUSDC, routerUSDCE);
        assertEq(activeAmountUSDC, activeAmountUSDCE);
        assertEq(hardcapUSDC, hardcapUSDCE);
        assertEq(activeUSDC, activeUSDCE);

        // Deposit to pool.
        uint256 amountUSDC = 100 * 10 ** USDC.decimals();

        deal(address(USDC), address(this), amountUSDC);

        USDC.approve(address(manager), amountUSDC);

        uint256 fee = manager.getTransactionFee(address(WETH));

        manager.depositPerp{value: fee}(999, address(USDC), amountUSDC, address(this));

        // Get the router address
        (address router,,,) = manager.getPoolToken(999, address(USDC));

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        activeAmountUSDC = manager.getUserActiveAmount(999, address(USDC), address(this));
        activeAmountUSDCE = manager.getUserActiveAmount(999, address(USDCE), address(this));

        assertEq(activeAmountUSDC, amountUSDC);
        assertEq(activeAmountUSDC, activeAmountUSDCE);

        // Withdraw from pool.
        manager.withdrawPerp{value: fee}(999, address(USDC), amountUSDC);

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        // USDC shares now should be 0 and the USDC pending amount should be the previous shares amount.
        activeAmountUSDC = manager.getUserActiveAmount(999, address(USDC), address(this));
        activeAmountUSDCE = manager.getUserActiveAmount(999, address(USDCE), address(this));

        assertEq(activeAmountUSDC, 0);
        assertEq(activeAmountUSDC, activeAmountUSDCE);

        uint256 userPendingAmountUSDC = manager.getUserPendingAmount(999, address(USDC), address(this));
        uint256 userPendingAmountUSDCE = manager.getUserPendingAmount(999, address(USDCE), address(this));

        assertEq(userPendingAmountUSDC, amountUSDC - manager.getTransactionFee(address(USDC)));
        assertEq(userPendingAmountUSDC, userPendingAmountUSDCE);

        processSlowModeTxs(endpoint);

        // Claim amounts.
        manager.claim(address(this), address(USDC), 999);

        assertEq(USDC.balanceOf(address(this)), amountUSDC - manager.getTransactionFee(address(USDC)));

        userPendingAmountUSDC = manager.getUserPendingAmount(999, address(USDC), address(this));
        userPendingAmountUSDCE = manager.getUserPendingAmount(999, address(USDCE), address(this));

        assertEq(userPendingAmountUSDC, 0);
        assertEq(userPendingAmountUSDC, userPendingAmountUSDCE);
    }

    // Check that the user can claim when the amounts are partitioned.
    function testClaimDivided() external {
        // Deposit to pool.
        uint256 amountUSDC = 10000 * 10 ** USDC.decimals();

        deal(address(USDC), address(this), amountUSDC);

        USDC.approve(address(manager), amountUSDC);

        uint256 fee = manager.getTransactionFee(address(WETH));

        manager.depositPerp{value: fee}(2, address(USDC), amountUSDC, address(this));

        // Get the router address
        (address router,,,) = manager.getPoolToken(2, address(USDC));

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        // Withdraw from pool.
        manager.withdrawPerp{value: fee}(2, address(USDC), amountUSDC);

        vm.startPrank(address(uint160(bytes20(VertexRouter(router).externalSubaccount()))));
        processQueue(manager);
        vm.stopPrank();

        processSlowModeTxs(endpoint);

        // Simulate partitional scenario.
        vm.startPrank(router);
        USDC.transfer(address(0xbeef), 5000 * 10 ** USDC.decimals());
        vm.stopPrank();

        deal(address(USDCE), router, 5000 * 10 ** USDCE.decimals());

        // Claim in separate.
        manager.claim(address(this), address(USDC), 2);
        manager.claim(address(this), address(USDCE), 2);

        assertEq(
            USDC.balanceOf(address(this)) + USDCE.balanceOf(address(this)),
            amountUSDC - manager.getTransactionFee(address(USDC))
        );
    }

    // Exclude from coverage report
    function test() public {}
}
