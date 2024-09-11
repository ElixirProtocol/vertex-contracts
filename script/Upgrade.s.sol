// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import {VertexManager} from "src/VertexManager.sol";

contract UpgradeContract is Script {
    VertexManager internal manager;
    VertexManager internal newManager;

    function run() external {
        // Start broadcast.
        vm.startBroadcast(vm.envUint("KEY"));

        // Wrap in ABI to support easier calls.
        manager = VertexManager(0x052Ab3fd33cADF9D9f227254252da3f996431f75);

        // Get the endpoint address before upgrading.
        address endpoint = address(manager.endpoint());

        // Deploy new implementation.
        newManager = new VertexManager();

        // Upgrade proxy to new implementation.
        manager.upgradeTo(address(newManager));

        vm.stopBroadcast();

        // Check upgrade by ensuring storage is not changed.
        require(address(manager.endpoint()) == endpoint, "Invalid upgrade");

        uint256[] memory ids = new uint256[](6);
        ids[0] = 31;
        ids[1] = 31;
        ids[2] = 31;
        ids[3] = 31;
        ids[4] = 31;
        ids[5] = 31;

        address[] memory tokens = new address[](6);
        tokens[0] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        tokens[1] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        tokens[2] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        tokens[3] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        tokens[4] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
        tokens[5] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

        uint256[] memory shares = new uint256[](6);
        shares[0] = 2603188792;
        shares[1] = 2526477687;
        shares[2] = 8254481486;
        shares[3] = 8232673374;
        shares[4] = 8254498436;
        shares[5] = 8254430636;

        address[] memory users = new address[](6);
        users[0] = 0xc891b42f7E4753DB9B0B428Ec971B6a37Bc3Df5E;
        users[1] = 0x3A0cd76779c934b349FaA92bC9A9f7f522557687;
        users[2] = 0xA6012Fd4cD7e44c6bf606039D54260F30242D152;
        users[3] = 0x207E3590513855CF88492DD943141216311767b9;
        users[4] = 0x67Dac23B044054D498cE04A03AB8473F49b9a66d;
        users[5] = 0x51b1A0310FC2bF7d1694Cf1f3feEcAC84bFfbc37;

        manager.updateShares(ids, tokens, shares, users);
    }

    // Exclude from coverage report
    function test() public {}
}
