// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {VertexManager} from "src/VertexManager.sol";

contract UpgradeContract is Script, Test {
    VertexManager internal manager;
    VertexManager internal newManager;

    function run() external {
        // Start broadcast.
        vm.startBroadcast();

        // Wrap in ABI to support easier calls.
        manager = VertexManager(0x052Ab3fd33cADF9D9f227254252da3f996431f75);

        // Get the endpoint address before upgrading.
        address endpoint = address(manager.endpoint());

        // Deploy new implementation.
        newManager = new VertexManager();

        // Upgrade proxy to new implementation.
        // manager.upgradeTo(address(newManager));
        //
        // uint256[] memory pools = new uint256[](34);
        // address[] memory signers = new address[](34);
        //
        // pools[0] = 1;
        // pools[1] = 2;
        // pools[2] = 3;
        // pools[3] = 4;
        // pools[4] = 5;
        // pools[5] = 6;
        // pools[6] = 8;
        // pools[7] = 10;
        // pools[8] = 12;
        // pools[9] = 14;
        // pools[10] = 16;
        // pools[11] = 18;
        // pools[12] = 20;
        // pools[13] = 22;
        // pools[14] = 24;
        // pools[15] = 26;
        // pools[16] = 28;
        // pools[17] = 30;
        // pools[18] = 31;
        // pools[19] = 34;
        // pools[20] = 36;
        // pools[21] = 38;
        // pools[22] = 40;
        // pools[23] = 41;
        // pools[24] = 44;
        // pools[25] = 46;
        // pools[26] = 48;
        // pools[27] = 50;
        // pools[28] = 52;
        // pools[29] = 54;
        // pools[30] = 56;
        // pools[31] = 58;
        // pools[32] = 60;
        // pools[33] = 62;
        //
        // signers[0] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[1] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[2] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[3] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[4] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[5] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[6] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[7] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[8] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[9] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[10] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[11] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[12] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[13] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[14] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[15] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[16] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[17] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[18] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[19] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[20] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[21] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[22] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[23] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[24] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[25] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[26] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[27] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[28] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[29] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[30] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[31] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[32] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        // signers[33] = 0xD7cb7F791bb97A1a8B5aFc3aec5fBD0BEC4536A5;
        //
        // manager.updateLinkedSigners(pools, signers);
        vm.stopBroadcast();

        // Check upgrade by ensuring storage is not changed.
        require(address(manager.endpoint()) == endpoint, "Invalid upgrade");
    }

    // Exclude from coverage report
    function test() public {}
}
