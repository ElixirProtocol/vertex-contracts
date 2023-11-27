// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import {VertexManager, IVertexManager} from "../../src/VertexManager.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract AddPool is Script {
    // Environment specific variables.
    IERC20Metadata public base;
    VertexManager public manager;
    address public externalAccount;
    uint32 public productId;
    address public token;
    address[] public tokens;
    uint256[] public hardcaps;
    bool public spot;

    // Deployer key.
    uint256 internal deployerKey;

    // TODO: Replace productId with automatic fetch from Vertex contracts through manager.
    constructor(
        address _base,
        address _manager,
        address _externalAccount,
        uint32 _productId,
        address _token,
        bool _spot
    ) {
        base = IERC20Metadata(_base);
        manager = VertexManager(_manager);
        externalAccount = _externalAccount;
        productId = _productId;
        token = _token;
        spot = _spot;
    }

    function setup() internal {
        deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Get the token decimals.
        uint256 decimals = IERC20Metadata(token).decimals();

        // Deploy with key.
        vm.startBroadcast(0xdc91701CD5d5a3Adb34d9afD1756f63d3b2201Ac);

        // Add token support.
        manager.updateToken(token, productId);

        // Check if allowance is needed.
        if (base.allowance(vm.addr(deployerKey), address(manager)) < type(uint256).max) {
            base.approve(address(manager), type(uint256).max);
        }

        if (spot) {
            tokens = new address[](2);
            tokens[0] = token;
            tokens[1] = address(base);

            hardcaps = new uint256[](2);
            hardcaps[0] = 0;
            hardcaps[1] = 0;

            manager.addPool(productId, tokens, hardcaps, IVertexManager.PoolType.Spot, externalAccount);
        } else {
            tokens = new address[](1);
            tokens[0] = address(base);

            hardcaps = new uint256[](1);
            hardcaps[0] = 0;

            manager.addPool(productId, tokens, hardcaps, IVertexManager.PoolType.Perp, externalAccount);
        }

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public virtual {}
}
