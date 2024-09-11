// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import {VertexManager} from "src/VertexManager.sol";
import {IEndpoint} from "src/interfaces/IEndpoint.sol";
import {VertexRouter} from "src/VertexRouter.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract DepositVertex is Script {
    VertexManager internal manager;
    IEndpoint internal endpoint;

    function run() external {
        // Sender must hold the tokens.
        vm.startBroadcast(vm.envUint("KEY"));

        // Wrap in ABI to support easier calls.
        manager = VertexManager(0x052Ab3fd33cADF9D9f227254252da3f996431f75);
        endpoint = IEndpoint(address(manager.endpoint()));

        address[] memory routers = new address[](1);
        routers[0] = 0xe3e3A6cF662a6d7b2B8A60E8aE44636C7E014476;

        address[] memory tokens = new address[](1);
        tokens[0] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 1e6;

        // iterate
        for (uint256 i = 0; i < routers.length; i++) {
            IERC20Metadata(tokens[i]).transfer(routers[i], amounts[i]);
            endpoint.depositCollateralWithReferral(
                bytes12(VertexRouter(routers[i]).contractSubaccount() << 160),
                manager.tokenToProduct(tokens[i]),
                amounts[i],
                "9O7rUEUljP"
            );
        }

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public {}
}
