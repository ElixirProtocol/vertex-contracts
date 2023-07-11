// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {VertexContracts} from "./VertexContracts.sol";
import {VertexStable} from "../src/VertexStable.sol";
import {VertexFactory} from "../src/VertexFactory.sol";

contract TestVertexFactory is Test, VertexContracts {
    /*//////////////////////////////////////////////////////////////
                                  TESTS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Fork network, deploy factory, and prepare contracts
        factorySetUp();
    }

    function testDeployVault() public {
        vm.selectFork(networkFork);
        vm.prank(FACTORY_OWNER);
        VertexStable vertexStable = VertexStable(vertexFactory.deployVault(0, baseToken, quoteToken));

        assertEq(vertexFactory.getVaultByProduct(0), address(vertexStable));
        assertEq(address(vertexStable.baseToken()), address(baseToken));
        assertEq(address(vertexStable.quoteToken()), address(quoteToken));
    }

    function testFailNoDuplicateVaults() public {
        vm.selectFork(networkFork);
        vm.startPrank(FACTORY_OWNER);
        vertexFactory.deployVault(0, baseToken, quoteToken);
        vertexFactory.deployVault(0, baseToken, quoteToken);
    }

    function testIsVaultDeployed() public {
        vm.selectFork(networkFork);
        assertFalse(vertexFactory.getVaultByProduct(1) != address(0));
    }
}
