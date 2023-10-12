// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {MockTokenDecimals} from "../../utils/MockTokenDecimals.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {IEndpoint} from "../../../src/interfaces/IEndpoint.sol";
import {VertexManager} from "../../../src/VertexManager.sol";
import {FixVertexManager1} from "./FixVertexManager.sol";

contract TestDebugger1 is Test {
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // Elixir contracts
    VertexManager public manager = VertexManager(0x82dF40dea5E618725E7C7fB702b80224A1BB771F);
    IEndpoint public endpoint = IEndpoint(0xbbEE07B3e8121227AfCFe1E2B82772246226128e);

    // Tokens
    IERC20Metadata public BTC = IERC20Metadata(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20Metadata public USDC = IERC20Metadata(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20Metadata public ETH = IERC20Metadata(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20Metadata public ARB = IERC20Metadata(0x912CE59144191C1204E64559FE8253a0e49E6548);
    IERC20Metadata public USDT = IERC20Metadata(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    // Agents
    address public user = 0xA0d43822175Af83d9B1833eeEC918F02833ce2B5;
    address public multisig = 0xdc91701CD5d5a3Adb34d9afD1756f63d3b2201Ac;

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    // RPC URL for Arbitrum fork.
    string public networkRpcUrl = vm.envString("ARBITRUM_RPC_URL");

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.createSelectFork(networkRpcUrl, 140064532);
    }

    /// @notice Processes any transactions in the Vertex queue.
    function processSlowModeTxs() public {
        // Clear any external slow-mode txs from the Vertex queue.
        vm.warp(block.timestamp + 259200);
        IEndpoint.SlowModeConfig memory queue = endpoint.slowModeConfig();
        endpoint.executeSlowModeTransactions(uint32(queue.txCount - queue.txUpTo));
    }

    function testPatch1() external {
        address[] memory spotTokens = new address[](2);
        spotTokens[1] = address(USDC);

        address[] memory perpTokens = new address[](1);
        perpTokens[0] = address(USDC);

        uint256[] memory amounts = new uint256[](1);

        // IMPORTANT: multisig needs more usdc to pay for withdrawals
        deal(address(USDC), multisig, 20 * 10 ** 6);

        // 1. deploy new implementation with patches
        FixVertexManager1 fixedManager = new FixVertexManager1();

        // 2. upgrade contract as multisig
        vm.prank(multisig);

        manager.upgradeTo(address(fixedManager));

        FixVertexManager1 fixedProxy = FixVertexManager1(address(manager));

        // 3. User withdraws everything
        vm.startPrank(user);

        // btc spot, ID 1
        spotTokens[0] = address(BTC);
        fixedProxy.withdrawSpot(1, spotTokens, fixedProxy.getUserActiveAmount(1, spotTokens[0], user), 0);

        // btc perp, ID 2
        amounts[0] = fixedProxy.getUserActiveAmount(2, perpTokens[0], user);
        fixedProxy.withdrawPerp(2, perpTokens, amounts, 0);

        // eth spot, ID 3
        spotTokens[0] = address(ETH);
        fixedProxy.withdrawSpot(3, spotTokens, fixedProxy.getUserActiveAmount(3, spotTokens[0], user), 0);

        // eth perp, ID 4
        amounts[0] = fixedProxy.getUserActiveAmount(4, perpTokens[0], user);
        fixedProxy.withdrawPerp(4, perpTokens, amounts, 0);

        // arb spot, ID 5
        spotTokens[0] = address(ARB);
        fixedProxy.withdrawSpot(5, spotTokens, fixedProxy.getUserActiveAmount(5, spotTokens[0], user), 0);

        // usdt spot, ID 31
        spotTokens[0] = address(USDT);
        fixedProxy.withdrawSpot(31, spotTokens, fixedProxy.getUserActiveAmount(31, spotTokens[0], user), 0);

        processSlowModeTxs();

        vm.stopPrank();

        // 4. Execute patch as multisig
        vm.prank(multisig);
        fixedProxy.patch();

        // 5. Check that the routers don't hold any tokens and that the active amount is 0.
        // BTC spot, ID 1
        assertEq(BTC.balanceOf(0x393c45709968382Ee52dFf31aafeDeCA3B9654fC), 0);
        assertEq(USDC.balanceOf(0x393c45709968382Ee52dFf31aafeDeCA3B9654fC), 0);
        assertEq(fixedProxy.getUserActiveAmount(1, address(BTC), user), 0);
        assertEq(fixedProxy.getUserActiveAmount(1, address(USDC), user), 12477203);

        // BTC perp, ID 2
        assertEq(USDC.balanceOf(0x58c66f107A1C129A4865c2f1EDc33eFd38A2f020), 0);
        assertEq(fixedProxy.getUserActiveAmount(2, address(USDC), user), 0);

        // ETH spot, ID 3
        assertEq(ETH.balanceOf(0xf5b2C3A4eb7Fd59F5FBE512EEb1aa98358242FD5), 0);
        assertEq(USDC.balanceOf(0xf5b2C3A4eb7Fd59F5FBE512EEb1aa98358242FD5), 0);
        assertEq(fixedProxy.getUserActiveAmount(3, address(ETH), user), 0);
        assertEq(fixedProxy.getUserActiveAmount(3, address(USDC), user), 18325181);

        // ETH perp, ID 4
        assertEq(USDC.balanceOf(0xa13a4b97aB259808b10ffA58f08589063eD99943), 0);
        assertEq(fixedProxy.getUserActiveAmount(4, address(USDC), user), 0);

        // ARB spot, ID 5
        assertEq(ARB.balanceOf(0x738163cE85274b7599B91D1dA0E2798cAdc289d1), 0);
        assertEq(USDC.balanceOf(0x738163cE85274b7599B91D1dA0E2798cAdc289d1), 0);
        assertEq(fixedProxy.getUserActiveAmount(5, address(ARB), user), 0);
        assertEq(fixedProxy.getUserActiveAmount(5, address(USDC), user), 6270072);

        // USDT spot, ID 31
        assertEq(USDT.balanceOf(0x4B1a9AaC8D05B2f13b8212677aA03bDaa7d8A185), 0);
        assertEq(USDC.balanceOf(0x4B1a9AaC8D05B2f13b8212677aA03bDaa7d8A185), 0);
        assertEq(fixedProxy.getUserActiveAmount(31, address(USDT), user), 0);
        assertEq(fixedProxy.getUserActiveAmount(31, address(USDC), user), 338863);
    }
}
