// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import {IEndpoint, IClearinghouse, VertexFactory} from "../../src/VertexFactory.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract CreateFactory is Script {
    // Deploy addresses.
    VertexFactory internal factory;

    // Assuming base token is WBTC and quote token is USDC for Arbitrum Goerli.
    ERC20 internal baseToken = ERC20(0x5Cc7c91690b2cbAEE19A513473D73403e13fb431);
    ERC20 internal quoteToken = ERC20(0x179522635726710Dd7D2035a81d856de4Aa7836c);

    // Deployer key.
    uint256 internal deployerKey;

    function run() external {
        deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Deploy with key.
        vm.startBroadcast(deployerKey);

        // Wrap in ABI to support easier calls.
        factory = VertexFactory(0xEa9d2D99A623AB7D3c2EE80C65e2eAe4eb6f83d4);

        address(quoteToken).call(abi.encodeWithSignature("mint(address,uint256)", address(factory), 20000000000));

        factory.deployVault(1, baseToken, quoteToken);

        vm.stopBroadcast();
    }
}
