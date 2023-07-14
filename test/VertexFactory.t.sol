// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {VertexContracts} from "./VertexContracts.t.sol";
import {IClearinghouse} from "../src/interfaces/IClearinghouse.sol";
import {IEndpoint} from "../src/interfaces/IEndpoint.sol";
import {VertexStable} from "../src/VertexStable.sol";
import {VertexFactory} from "../src/VertexFactory.sol";

contract TestVertexFactory is Test, VertexContracts {
    /*//////////////////////////////////////////////////////////////
                                  TESTS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Fork network, deploy factory, and prepare contracts
        testSetUp();
    }

    function testDeployVault() public {
        vm.selectFork(networkFork);
        vm.prank(FACTORY_OWNER);
        VertexStable vertexStable = VertexStable(vertexFactory.deployVault(0, baseToken, quoteToken));

        assertEq(vertexFactory.getVaultByProduct(0), address(vertexStable));
        assertEq(address(vertexStable.baseToken()), address(baseToken));
        assertEq(address(vertexStable.quoteToken()), address(quoteToken));
    }

    function testFailUnauthorizedDeploy() public {
        vm.selectFork(networkFork);
        VertexStable(vertexFactory.deployVault(0, baseToken, quoteToken));
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

    function testFailDoubleInitiliaze() public {
        vertexFactory.initialize(
            IClearinghouse(address(0)), IEndpoint(address(0)), address(address(0)), address(address(0))
        );
    }

    function testSameTokens() public {
        vm.selectFork(networkFork);
        vm.startPrank(FACTORY_OWNER);
        vm.expectRevert(VertexFactory.SameTokens.selector);
        vertexFactory.deployVault(0, baseToken, baseToken);
    }

    function testZeroTokens() public {
        vm.selectFork(networkFork);
        vm.startPrank(FACTORY_OWNER);

        vm.expectRevert(VertexFactory.TokenIsZero.selector);
        vertexFactory.deployVault(0, ERC20(address(0)), quoteToken);

        vm.expectRevert(VertexFactory.TokenIsZero.selector);
        vertexFactory.deployVault(0, baseToken, ERC20(address(0)));
    }

    function testInvalidProduct() public {
        vm.selectFork(networkFork);
        vm.startPrank(FACTORY_OWNER);

        vm.expectRevert(VertexFactory.InvalidProduct.selector);
        vertexFactory.deployVault(type(uint32).max, baseToken, quoteToken);
    }

    function testAuthorizedUpgrade() public {
        vm.selectFork(networkFork);
        vm.startPrank(FACTORY_OWNER);

        // Deploy 2nd Factory implementation
        VertexFactory vertexFactory2 = new VertexFactory();

        vertexFactory.upgradeTo(address(vertexFactory2));
    }

    function testFailUnauthorizedUpgrade() public {
        vertexFactory.upgradeTo(address(0));
    }
}
