// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {MockTokenDecimals} from "../../utils/MockTokenDecimals.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {IEndpoint} from "../../../src/interfaces/IEndpoint.sol";
import {VertexManager} from "../../../src/VertexManager.sol";
import {FixVertexManager2} from "./FixVertexManager.sol";

contract TestDebugger2 is Test {
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // Elixir contracts
    VertexManager public manager = VertexManager(0x82dF40dea5E618725E7C7fB702b80224A1BB771F);

    // Tokens
    IERC20Metadata public BTC = IERC20Metadata(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20Metadata public USDC = IERC20Metadata(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    // Agents
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

    function testPatch2() external {
        // 1. deploy new implementation with patches
        FixVertexManager2 fixedManager = new FixVertexManager2();

        // 2. upgrade contract as multisig
        vm.prank(multisig);

        manager.upgradeTo(address(fixedManager));

        FixVertexManager2 fixedProxy = FixVertexManager2(address(manager));

        // 3. Execute patch as multisig and check that routers are empty
        vm.prank(multisig);
        fixedProxy.patch();

        // BTC spot, ID 1
        assertEq(BTC.balanceOf(0x393c45709968382Ee52dFf31aafeDeCA3B9654fC), 0);
        assertEq(USDC.balanceOf(0x393c45709968382Ee52dFf31aafeDeCA3B9654fC), 0);

        // BTC perp, ID 2
        assertEq(USDC.balanceOf(0x58c66f107A1C129A4865c2f1EDc33eFd38A2f020), 0);

        // 4. Active funds are withdrawn through Vertex using linked signer!
    }
}
