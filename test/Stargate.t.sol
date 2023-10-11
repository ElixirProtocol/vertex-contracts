// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {MockTokenDecimals} from "./utils/MockTokenDecimals.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {VertexManager} from "../src/VertexManager.sol";
import {StargateReceiver} from "../src/helpers/Stargate.sol";

interface StargateRouter {
    struct lzTxObj {
        uint256 dstGasForCall;
        uint256 dstNativeAmount;
        bytes dstNativeAddr;
    }

    function swap(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLD,
        uint256 _minAmountLD,
        lzTxObj memory _lzTxParams,
        bytes calldata _to,
        bytes calldata _payload
    ) external payable;
}

contract TestStargate is Test {
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // Elixir contracts
    StargateReceiver public stargateReceiver;
    VertexManager public manager = VertexManager(0x82dF40dea5E618725E7C7fB702b80224A1BB771F);

    // LayerZero contracts
    address public relayer = 0x177d36dBE2271A4DdB2Ad8304d82628eb921d790;

    // Tokens
    IERC20Metadata public BTC = IERC20Metadata(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20Metadata public USDC = IERC20Metadata(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    // RPC URL for Arbitrum fork.
    string public networkRpcUrl = vm.envString("ARBITRUM_RPC_URL");

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.createSelectFork(networkRpcUrl);

        // Deploy StargateReceiver
        stargateReceiver = new StargateReceiver(address(manager), relayer);

        stargateReceiver.approveToken(address(USDC));
        stargateReceiver.approveToken(address(BTC));
    }

    function testReceivePerp() external {
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 * 10 ** 6;

        deal(address(USDC), address(stargateReceiver), amounts[0]);

        vm.prank(relayer);
        (bool success,) = address(stargateReceiver).call(
            abi.encodePacked(
                abi.encodeWithSelector(StargateReceiver.depositPerpOnBehalf.selector, 2, tokens, amounts), address(0x69)
            )
        );

        assertTrue(success);
        assertEq(manager.getUserActiveAmount(2, address(USDC), address(0x69)), amounts[0]);
    }

    function testReceiveSpot() external {
        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        uint256 amountBTC = 1 * 10 ** 8;
        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        deal(address(BTC), address(stargateReceiver), amountBTC);
        deal(address(USDC), address(stargateReceiver), amountUSDC);

        vm.prank(relayer);
        (bool success,) = address(stargateReceiver).call(
            abi.encodePacked(
                abi.encodeWithSelector(
                    StargateReceiver.depositSpotOnBehalf.selector, 1, tokens, amountBTC, amountUSDC, amountUSDC
                ),
                address(0x69)
            )
        );

        assertTrue(success);
        assertEq(manager.getUserActiveAmount(1, address(BTC), address(0x69)), amountBTC);
        assertEq(manager.getUserActiveAmount(1, address(USDC), address(0x69)), amountUSDC);
    }

    function testApprove() external {
        MockTokenDecimals token = new MockTokenDecimals(18);

        assertEq(token.allowance(address(stargateReceiver), address(manager)), 0);

        stargateReceiver.approveToken(address(token));

        assertEq(token.allowance(address(stargateReceiver), address(manager)), type(uint256).max);
    }
}
