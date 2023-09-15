// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {AddressSet, LibAddressSet} from "../utils/AddressSet.sol";
import {MockToken} from "../utils/MockToken.sol";
import {VertexManager} from "../../src/VertexManager.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract Handler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    /*//////////////////////////////////////////////////////////////
                                VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Elixir contracts
    VertexManager public manager;

    // Tokens
    MockToken public BTC;
    MockToken public USDC;
    MockToken public WETH;

    // Ghost balances
    mapping(address => uint256) public ghost_deposits;
    mapping(address => uint256) public ghost_withdraws;
    mapping(address => uint256) public ghost_claims;

    // Current actor
    address public currentActor;

    // Actors
    AddressSet internal _actors;

    // Spot tokens
    address[] public spotTokens;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(VertexManager _manager, MockToken _BTC, MockToken _USDC, MockToken _WETH) {
        manager = _manager;
        BTC = _BTC;
        USDC = _USDC;
        WETH = _WETH;

        spotTokens = new address[](2);
        spotTokens[0] = address(BTC);
        spotTokens[1] = address(USDC);
    }

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 amountBTC) public createActor {
        amountBTC = bound(amountBTC, 0, BTC.balanceOf(address(this)));

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        _pay(currentActor, BTC, amountBTC);
        _pay(currentActor, USDC, amountUSDC);

        vm.startPrank(currentActor);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;

        manager.deposit(1, spotTokens, amounts, currentActor);

        vm.stopPrank();

        ghost_deposits[address(BTC)] += amountBTC;
        ghost_deposits[address(USDC)] += amountUSDC;
    }

    function withdrawFeeBTC(uint256 amountBTC) public createActor {
        amountBTC = bound(amountBTC, 0, BTC.balanceOf(address(this)));

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        vm.startPrank(currentActor);

        manager.withdrawBalanced(1, spotTokens, amountBTC, 1);

        vm.stopPrank();

        ghost_withdraws[address(BTC)] += amountBTC;
        ghost_withdraws[address(USDC)] += amountUSDC;
    }

    function withdrawFeeUSDC(uint256 amountBTC) public createActor {
        amountBTC = bound(amountBTC, 0, BTC.balanceOf(address(this)));

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        vm.startPrank(currentActor);

        manager.withdrawBalanced(1, spotTokens, amountBTC, 0);

        vm.stopPrank();

        ghost_withdraws[address(BTC)] += amountBTC;
        ghost_withdraws[address(USDC)] += amountUSDC;
    }

    function claim() public createActor {
        vm.startPrank(currentActor);

        manager.claim(currentActor, spotTokens, 1);

        uint256 receivedBTC = BTC.balanceOf(currentActor);
        uint256 receivedUSDC = USDC.balanceOf(currentActor);

        _pay(address(this), BTC, receivedBTC);
        _pay(address(this), USDC, receivedUSDC);

        vm.stopPrank();

        ghost_claims[address(BTC)] += receivedBTC;
        ghost_claims[address(USDC)] += receivedUSDC;
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _pay(address to, MockToken token, uint256 amount) internal {
        token.transfer(to, amount);
    }

    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
    }

    function reduceActors(uint256 acc, function(uint256,address) external returns (uint256) func)
        public
        returns (uint256)
    {
        return _actors.reduce(acc, func);
    }

    function actors() external view returns (address[] memory) {
        return _actors.addrs;
    }

    // Exclude from coverage report
    function test() public {}
}
