// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {Utils} from "./utils/Utils.sol";
import {MockToken} from "./utils/MockToken.sol";

import {VertexContracts} from "./VertexContracts.sol";
import {VertexStable} from "../src/VertexStable.sol";
import {VertexFactory} from "../src/VertexFactory.sol";

contract TestVertexFactory is Test, VertexContracts {
    Utils internal utils;

    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    VertexFactory internal vertexFactory;
    MockToken internal baseToken;
    MockToken internal quoteToken;

    /*//////////////////////////////////////////////////////////////
                                  USERS
    //////////////////////////////////////////////////////////////*/

    // Neutral users
    address internal USER1;

    // Elixir users
    address internal FACTORY_OWNER;

    /*//////////////////////////////////////////////////////////////
                                  TESTS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        baseToken = new MockToken();
        quoteToken = new MockToken();

        // TODO: Create Vertex contracts mocking clearinghouse and endpoint.

        vertexFactory = new VertexFactory();
        vertexFactory.initialize(address(clearingHouse), address(endpoint), address(externalAccount), FACTORY_OWNER);
    }

    function testDeployVault() public {
        VertexStable vertexStable = vertexFactory.deployVault(underlying);

        assertTrue(vertexFactory.isVaultDeployed(vertexStable));
        assertEq(address(vertexFactory.getStableVaultByTokens(baseToken, quoteToken)), address(vertexStable));
        assertEq(address(vertexStable.baseToken()), address(baseToken));
        assertEq(address(vertexStable.quoteToken()), address(quoteToken));
    }

    function testFailNoDuplicateVaults() public {
        vertexFactory.deployVault(0, baseToken, quoteToken);
        vertexFactory.deployVault(0, baseToken, quoteToken);
    }

    function testIsVaultDeployed() public {
        assertFalse(vertexFactory.isVaultDeployed(Vault(payable(address(0xBEEF)))));
    }
}
