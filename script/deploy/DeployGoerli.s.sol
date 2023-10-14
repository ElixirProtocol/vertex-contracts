// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {VertexManager} from "../../src/VertexManager.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract DeployGoerli is DeployBase {
    address public constant EXTERNAL_ACCOUNT = 0x28CcdB531854d09D48733261688dc1679fb9A242;

    address public constant BTC = 0x5Cc7c91690b2cbAEE19A513473D73403e13fb431;
    address public constant USDC = 0x179522635726710Dd7D2035a81d856de4Aa7836c;
    address public constant ETH = 0xCC59686e3a32Fb104C8ff84DD895676265eFb8a6;
    address public constant ARB = 0x34e9827219aA7B7962eF591714657817e79eBBbb;
    address public constant USDT = 0x067763aA51E4c7C30eA26DfE08cE2FeA5683cc85;

    // Vertex Goerli Endpoint
    constructor() DeployBase(0x5956D6f55011678b2CAB217cD21626F7668ba6c5) {}

    function run() external {
        setup();

        vm.startBroadcast(deployerKey);

        // Add token support.
        manager.updateToken(USDC, 0);
        manager.updateToken(BTC, 1);
        manager.updateToken(ETH, 3);
        manager.updateToken(ARB, 5);
        manager.updateToken(USDT, 31);

        // Give approval to create pools.
        IERC20(USDC).approve(address(manager), type(uint256).max);

        // Spot BTC: WBTC and USDC
        address[] memory spotBTC = new address[](2);
        spotBTC[0] = address(BTC);
        spotBTC[1] = address(USDC);

        uint256[] memory dualHardcaps = new uint256[](2);
        dualHardcaps[0] = type(uint256).max;
        dualHardcaps[1] = type(uint256).max;

        uint256[] memory singleHardcap = new uint256[](1);
        singleHardcap[0] = type(uint256).max;

        manager.addPool(1, spotBTC, dualHardcaps, VertexManager.PoolType.Spot, EXTERNAL_ACCOUNT);

        // Perp BTC: USDC
        address[] memory singleUSDC = new address[](1);
        singleUSDC[0] = USDC;

        manager.addPool(2, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Spot ETH: ETH and USDC
        address[] memory spotETH = new address[](2);
        spotETH[0] = address(ETH);
        spotETH[1] = address(USDC);

        manager.addPool(3, spotETH, dualHardcaps, VertexManager.PoolType.Spot, EXTERNAL_ACCOUNT);

        manager.addPool(4, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Spot ARB: ARB and USDC
        address[] memory spotARB = new address[](2);
        spotARB[0] = address(ARB);
        spotARB[1] = address(USDC);

        manager.addPool(5, spotARB, dualHardcaps, VertexManager.PoolType.Spot, EXTERNAL_ACCOUNT);

        manager.addPool(6, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp BNB: USDC
        manager.addPool(8, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp XRP: USDC
        manager.addPool(10, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp SOL: USDC
        manager.addPool(12, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp MATIC: USDC
        manager.addPool(14, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp SUI: USDC
        manager.addPool(16, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp OP: USDC
        manager.addPool(18, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp APT: USDC
        manager.addPool(20, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp LTC: USDC
        manager.addPool(22, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp BCH: USDC
        manager.addPool(24, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp COMP: USDC
        manager.addPool(26, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp MKR: USDC
        manager.addPool(28, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp mPEPE: USDC
        manager.addPool(30, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Spot USDT: USDT and USDC
        address[] memory spotUSDT = new address[](2);
        spotUSDT[0] = address(USDT);
        spotUSDT[1] = address(USDC);

        manager.addPool(31, spotUSDT, dualHardcaps, VertexManager.PoolType.Spot, EXTERNAL_ACCOUNT);

        // Perp DOGE: USDC
        manager.addPool(34, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp LINK: USDC
        manager.addPool(36, singleUSDC, singleHardcap, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public override {}
}
