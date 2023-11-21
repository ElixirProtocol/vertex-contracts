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
    uint256 public privateKey = 0x12345;

    // EIP712 domain hash.
    bytes32 public eip712DomainHash;

    // cast keccak "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    bytes32 public constant TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

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
                TYPEHASH,
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

    function generateSignature(Claim memory claim) public returns (bytes memory signature) {
        bytes32 digest = getTypedDataHash(claim);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        signature = abi.encodePacked(r, s, v);

        assertEq(signature.length, 65);
    }

    /*//////////////////////////////////////////////////////////////
                                  TESTS
    //////////////////////////////////////////////////////////////*/

    function testDoubleClaim(uint128 amount, uint32 epoch) public {
        // Skip zeros.
        vm.assume(amount > 0 && amount <= type(uint128).max && epoch > 0 && epoch <= type(uint32).max - 1);

        // Mint tokens to contract.
        vrtx.mint(address(rewards), amount);

        // Generate message to sign.
        Claim memory claim = Claim({user: address(this), epoch: epoch, amount: amount});

        rewards.claim(epoch, amount, generateSignature(claim));

        // Generate anonthermessage to sign.
        Claim memory claim2 = Claim({user: address(this), epoch: epoch + 1, amount: amount});

        // Mint tokens to contract.
        vrtx.mint(address(rewards), amount);

        rewards.claim(epoch + 1, amount, generateSignature(claim2));
    }

    function testAlreadyClaimed() public {
        vrtx.mint(address(rewards), 100 ether);

        Claim memory claim = Claim({user: address(this), epoch: 1, amount: 100 ether});

        bytes memory signature = generateSignature(claim);

        rewards.claim(1, 100 ether, signature);

        vm.expectRevert(abi.encodeWithSelector(VertexRewards.AlreadyClaimed.selector));
        rewards.claim(1, 100 ether, signature);
    }

    function testInvalid() public {
        vm.expectRevert(abi.encodeWithSelector(VertexRewards.InvalidAmount.selector));
        rewards.claim(1, 0, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(VertexRewards.InvalidEpoch.selector));
        rewards.claim(0, 1, bytes(""));
        
        Claim memory claim = Claim({user: address(this), epoch: 1, amount: 1 ether});

        bytes32 digest = getTypedDataHash(claim);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x123, digest);

        vm.expectRevert(abi.encodeWithSelector(VertexRewards.InvalidSignature.selector));
        rewards.claim(1, 1 ether, abi.encodePacked(r, s, v));
    }

    function testNotUser() public {
        vrtx.mint(address(rewards), 100 ether);

        Claim memory claim = Claim({user: address(0xbeef), epoch: 1, amount: 100 ether});

        bytes memory signature = generateSignature(claim);

        vm.expectRevert(abi.encodeWithSelector(VertexRewards.InvalidSignature.selector));
        rewards.claim(1, 100 ether, signature);
    }

    function testNotEnough() public {
        Claim memory claim = Claim({user: address(this), epoch: 1, amount: 100 ether});

        bytes memory signature = generateSignature(claim);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        rewards.claim(1, 100 ether, signature);
    }
}
