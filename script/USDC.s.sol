// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import {VertexManager, IEndpoint} from "src/VertexManager.sol";
import {VertexProcessor} from "src/VertexProcessor.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

// Scrip to migrate from USDC.e to USDC (Sepolia example).
contract USDC is Script {
    VertexManager internal manager;

    IERC20Metadata USDC = IERC20Metadata(0xD32ea1C76ef1c296F131DD4C5B2A0aac3b22485a);

    function run() external {
        // Start broadcast.
        vm.startBroadcast();

        // Wrap in ABI to support easier calls.
        manager = VertexManager(0x052Ab3fd33cADF9D9f227254252da3f996431f75);

        // Get the endpoint address.
        IEndpoint endpoint = manager.endpoint();

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
        // deal(address(USDC), address(manager.owner()), 10000000 * 10 ** USDC.decimals());

        /*//////////////////////////////////////////////////////////////
                                    STEP 6
        //////////////////////////////////////////////////////////////*/

        // Unpause manager
        manager.pause(false, false, false);
    }

    // Exclude from coverage report
    function test() public {}
}
