// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {VertexRewards} from "../src/VertexRewards.sol";

import {MockToken} from "./utils/MockToken.sol";

contract TestVertexRewards is Test {
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    MockToken public vrtx;
    VertexRewards public rewards;

    /*//////////////////////////////////////////////////////////////
                                  USERS
    //////////////////////////////////////////////////////////////*/

    // Elixir signer
    address public signer;

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    // Random private key of signer.
    uint256 privateKey = 0x12345;

    // EIP712 domain hash.
    bytes32 eip712DomainHash;

    // cast keccak "Claim(address user,uint32 epoch,uint256 amount)"
    bytes32 public constant CLAIM_TYPEHASH = 0x028b7072b3b189699633f26fd98e08a9228c7e458002373bdb8e2f8d8b3b541a;

    struct Claim {
        address user;
        uint32 epoch;
        uint256 amount;
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Set the signer.
        signer = vm.addr(privateKey);

        // Deploy token.
        vrtx = new MockToken();

        // Deploy contract.
        rewards = new VertexRewards("Vertex Rewards", "1", IERC20(vrtx), signer);

        // Set the domain hash.
        eip712DomainHash = keccak256(
            abi.encode(
                CLAIM_TYPEHASH,
                keccak256(bytes("Vertex Rewards")),
                keccak256(bytes("1")),
                block.chainid,
                address(rewards)
            )
        );
    }

    // Computes the hash of a claim.
    function getStructHash(Claim memory _claim) internal pure returns (bytes32) {
        return keccak256(abi.encode(CLAIM_TYPEHASH, _claim.user, _claim.epoch, _claim.amount));
    }

    // Computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(Claim memory _claim) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", eip712DomainHash, getStructHash(_claim)));
    }

    /*//////////////////////////////////////////////////////////////
                                  TESTS
    //////////////////////////////////////////////////////////////*/

    function testVerifySignature(uint256 amount, uint32 epoch) public {
        // Skip zeros.
        vm.assume(amount > 0 && epoch > 0);

        // Generate message to sign.
        Claim memory claim = Claim({user: address(this), epoch: epoch, amount: amount});

        bytes32 digest = getTypedDataHash(claim);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);

        rewards.claim(epoch, amount, signature);
    }
}
