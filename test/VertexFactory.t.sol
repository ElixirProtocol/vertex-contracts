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
                                  MISC
    //////////////////////////////////////////////////////////////*/

    // Off-chain validator account that makes request on behalf of the vaults.
    address internal EXTERNAL_ACCOUNT;

    /*//////////////////////////////////////////////////////////////
                                  TESTS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        utils = new Utils();
        address payable[] memory users = utils.createUsers(3);

        USER1 = users[0];
        vm.label(USER1, "User");

        FACTORY_OWNER = users[1];
        vm.label(FACTORY_OWNER, "Factory Owner");

        EXTERNAL_ACCOUNT = users[2];
        vm.label(EXTERNAL_ACCOUNT, "External Account");

        baseToken = new MockToken();
        quoteToken = new MockToken();

        // TODO: Create Vertex contracts mocking clearinghouse and endpoint.

        vertexFactory = new VertexFactory();
        vertexFactory.initialize(clearingHouse, endpoint, EXTERNAL_ACCOUNT, FACTORY_OWNER);
    }

    function testDeployVault() public {
        vm.prank(FACTORY_OWNER);
        VertexStable vertexStable = VertexStable(vertexFactory.deployVault(0, baseToken, quoteToken));

        assertEq(vertexFactory.getVaultByProduct(0), address(vertexStable));
        assertEq(address(vertexStable.baseToken()), address(baseToken));
        assertEq(address(vertexStable.quoteToken()), address(quoteToken));
    }

    function testFailNoDuplicateVaults() public {
        vm.startPrank(FACTORY_OWNER);
        vertexFactory.deployVault(0, baseToken, quoteToken);
        vertexFactory.deployVault(0, baseToken, quoteToken);
    }

    function testIsVaultDeployed() public {
        assertFalse(vertexFactory.getVaultByProduct(1) != address(0));
    }
}
