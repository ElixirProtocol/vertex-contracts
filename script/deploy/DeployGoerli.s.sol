// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {VertexManager} from "../../src/VertexManager.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract DeployGoerli is DeployBase {
    // Arbitrum Goerli addresses
    // 1. USDC fee token
    // 2. Endpoint
    // 3. External account

    constructor()
        DeployBase(
            0x179522635726710Dd7D2035a81d856de4Aa7836c,
            0x5956D6f55011678b2CAB217cD21626F7668ba6c5,
            0x28CcdB531854d09D48733261688dc1679fb9A242
        )
    {}

    function run() external {
        setup();

        vm.startBroadcast(deployerKey);

        address BTC = 0x5Cc7c91690b2cbAEE19A513473D73403e13fb431;
        address USDC = 0x179522635726710Dd7D2035a81d856de4Aa7836c;
        address ETH = 0xCC59686e3a32Fb104C8ff84DD895676265eFb8a6;

        // Add token support.
        manager.updateToken(USDC, 0);
        manager.updateToken(BTC, 1);
        manager.updateToken(ETH, 3);

        // Give approval to create pools.
        IERC20(BTC).approve(address(manager), type(uint256).max);
        IERC20(USDC).approve(address(manager), type(uint256).max);
        IERC20(ETH).approve(address(manager), type(uint256).max);

        // Create BTC spot pool with BTC and USDC as tokens.
        address[] memory tokens = new address[](2);
        tokens[0] = address(BTC);
        tokens[1] = address(USDC);

        uint256[] memory hardcaps = new uint256[](2);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;

        manager.addPool(1, tokens, hardcaps, VertexManager.PoolType.Spot, externalAccount);

        // Create BTC perp pool with BTC, USDC and ETH as tokens.
        tokens = new address[](3);
        tokens[0] = BTC;
        tokens[1] = USDC;
        tokens[2] = ETH;

        hardcaps = new uint256[](3);
        hardcaps[0] = type(uint256).max;
        hardcaps[1] = type(uint256).max;
        hardcaps[2] = type(uint256).max;

        manager.addPool(2, tokens, hardcaps, VertexManager.PoolType.Spot, externalAccount);

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public override {}
}
