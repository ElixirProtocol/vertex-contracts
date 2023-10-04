// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {VertexManager} from "../../src/VertexManager.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract DeployMainnet is DeployBase {
    address public constant EXTERNAL_ACCOUNT = 0x28CcdB531854d09D48733261688dc1679fb9A242;

    address public constant BTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant ETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    constructor() DeployBase(0xbbEE07B3e8121227AfCFe1E2B82772246226128e) {}

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

        uint256[] memory spotBTCHardcaps = new uint256[](2);
        spotBTCHardcaps[0] = 1371000000; // 13.71 WBTC
        spotBTCHardcaps[1] = 375000000000; // 375000 USDC

        manager.addPool(1, spotBTC, spotBTCHardcaps, VertexManager.PoolType.Spot, EXTERNAL_ACCOUNT);

        // Perp BTC: USDC
        address[] memory singleUSDC = new address[](1);
        singleUSDC[0] = USDC;

        uint256[] memory perpBTCHardcaps = new uint256[](1);
        perpBTCHardcaps[0] = 375000000000; // 375000 USDC

        manager.addPool(2, singleUSDC, perpBTCHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Spot ETH: ETH and USDC
        address[] memory spotETH = new address[](2);
        spotETH[0] = address(ETH);
        spotETH[1] = address(USDC);

        uint256[] memory spotETHHardcaps = new uint256[](2);
        spotETHHardcaps[0] = 227 ether; // 227 ETH
        spotETHHardcaps[1] = 375000000000; // 375000 USDC

        manager.addPool(3, spotETH, spotETHHardcaps, VertexManager.PoolType.Spot, EXTERNAL_ACCOUNT);

        // Perp ETH: USDC
        uint256[] memory perpETHHardcaps = new uint256[](1);
        perpETHHardcaps[0] = 375000000000; // 375000 USDC

        manager.addPool(4, singleUSDC, perpETHHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Spot ARB: ARB and USDC
        address[] memory spotARB = new address[](2);
        spotARB[0] = address(ARB);
        spotARB[1] = address(USDC);

        uint256[] memory spotARBHardcaps = new uint256[](2);
        spotARBHardcaps[0] = 73500 ether; // 73500 ARB
        spotARBHardcaps[1] = 75000000000; // 75000 USDC

        manager.addPool(5, spotARB, spotARBHardcaps, VertexManager.PoolType.Spot, EXTERNAL_ACCOUNT);

        // Perp ARB: USDC
        uint256[] memory perpHardcaps = new uint256[](1);
        perpHardcaps[0] = 90000000000; // 90000 USDC

        manager.addPool(6, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp BNB: USDC
        manager.addPool(8, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp XRP: USDC
        manager.addPool(10, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp SOL: USDC
        manager.addPool(12, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp MATIC: USDC
        manager.addPool(14, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp SUI: USDC
        manager.addPool(16, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp OP: USDC
        manager.addPool(18, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp APT: USDC
        manager.addPool(20, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp LTC: USDC
        manager.addPool(22, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp BCH: USDC
        manager.addPool(24, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp COMP: USDC
        manager.addPool(26, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp MKR: USDC
        manager.addPool(28, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp mPEPE: USDC
        manager.addPool(30, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Spot USDT: USDT and USDC
        address[] memory spotUSDT = new address[](2);
        spotUSDT[0] = address(USDT);
        spotUSDT[1] = address(USDC);

        uint256[] memory spotUSDTHardcaps = new uint256[](2);
        spotUSDTHardcaps[0] = 45000000000; // 45000 USDT
        spotUSDTHardcaps[1] = 45000000000; // 45000 USDC

        manager.addPool(31, spotUSDT, spotUSDTHardcaps, VertexManager.PoolType.Spot, EXTERNAL_ACCOUNT);

        // Perp DOGE: USDC
        manager.addPool(34, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        // Perp LINK: USDC
        manager.addPool(36, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, EXTERNAL_ACCOUNT);

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public override {}
}
