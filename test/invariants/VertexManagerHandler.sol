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
    IERC20Metadata public BTC;
    IERC20Metadata public USDC;
    IERC20Metadata public WETH;

    // Ghost balances
    mapping(address => uint256) public ghost_deposits;
    mapping(address => uint256) public ghost_withdraws;
    mapping(address => uint256) public ghost_fees;
    mapping(address => uint256) public ghost_claims;

    // Current actor
    address public currentActor;

    // Actors
    AddressSet internal _actors;

    // Spot tokens
    address[] public spotTokens;

    // Perp tokens
    address[] public perpTokens;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(msg.sender);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(VertexManager _manager, address[] memory _spotTokens, address[] memory _perpTokens) {
        manager = _manager;
        BTC = IERC20Metadata(_perpTokens[0]);
        USDC = IERC20Metadata(_perpTokens[1]);
        WETH = IERC20Metadata(_perpTokens[2]);

        spotTokens = _spotTokens;
        perpTokens = _perpTokens;
    }

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function depositPerp(uint256 amountBTC, uint256 amountUSDC, uint256 amountWETH) public createActor {
        amountBTC = bound(amountBTC, 0, BTC.balanceOf(address(this)));
        amountUSDC = bound(amountUSDC, 0, USDC.balanceOf(address(this)));
        amountWETH = bound(amountWETH, 0, WETH.balanceOf(address(this)));

        _pay(currentActor, BTC, amountBTC);
        _pay(currentActor, USDC, amountUSDC);
        _pay(currentActor, WETH, amountWETH);

        vm.startPrank(currentActor);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);
        WETH.approve(address(manager), amountWETH);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;
        amounts[2] = amountWETH;

        manager.depositPerp(2, perpTokens, amounts, currentActor);

        vm.stopPrank();

        ghost_deposits[address(BTC)] += amountBTC;
        ghost_deposits[address(USDC)] += amountUSDC;
        ghost_deposits[address(WETH)] += amountWETH;
    }

    function depositSpot(uint256 amountBTC) public createActor {
        amountBTC = bound(amountBTC, 0, BTC.balanceOf(address(this)));

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);
        if (amountUSDC > USDC.balanceOf(address(this))) return;

        _pay(currentActor, BTC, amountBTC);
        _pay(currentActor, USDC, amountUSDC);

        vm.startPrank(currentActor);

        BTC.approve(address(manager), amountBTC);
        USDC.approve(address(manager), amountUSDC);

        manager.depositSpot(1, spotTokens, amountBTC, amountUSDC, amountUSDC, currentActor);

        vm.stopPrank();

        ghost_deposits[address(BTC)] += amountBTC;
        ghost_deposits[address(USDC)] += amountUSDC;
    }

    function withdrawPerp(
        uint256 actorSeed,
        uint256 amountBTC,
        uint256 amountUSDC,
        uint256 amountWETH,
        uint256 feeIndex
    ) public useActor(actorSeed) {
        feeIndex = bound(feeIndex, 0, 2);

        uint256 fee;
        uint256 userActiveAmountBTC = manager.getUserActiveAmount(2, address(BTC), currentActor);
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(2, address(USDC), currentActor);
        uint256 userActiveAmountWETH = manager.getUserActiveAmount(2, address(WETH), currentActor);

        amountBTC = bound(amountBTC, 0, userActiveAmountBTC);
        amountUSDC = bound(amountUSDC, 0, userActiveAmountUSDC);
        amountWETH = bound(amountWETH, 0, userActiveAmountWETH);

        if (feeIndex == 0) {
            fee = manager.getWithdrawFee(address(BTC));

            if (amountBTC < fee) {
                return;
            }

            ghost_fees[address(BTC)] += fee;
        } else if (feeIndex == 1) {
            fee = manager.getWithdrawFee(address(USDC));

            if (amountUSDC < fee) {
                return;
            }

            ghost_fees[address(USDC)] += fee;
        } else {
            fee = manager.getWithdrawFee(address(WETH));

            if (amountWETH < fee) {
                return;
            }

            ghost_fees[address(WETH)] += fee;
        }

        vm.startPrank(currentActor);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountBTC;
        amounts[1] = amountUSDC;
        amounts[2] = amountWETH;

        manager.withdrawPerp(2, perpTokens, amounts);

        vm.stopPrank();

        ghost_withdraws[address(BTC)] += amountBTC;
        ghost_withdraws[address(USDC)] += amountUSDC;
        ghost_withdraws[address(WETH)] += amountWETH;
    }

    function withdrawSpot(uint256 actorSeed, uint256 amountBTC, uint256 feeIndex) public useActor(actorSeed) {
        feeIndex = bound(feeIndex, 0, 1);

        uint256 fee;
        uint256 userActiveAmountBTC = manager.getUserActiveAmount(1, address(BTC), currentActor);
        uint256 userActiveAmountUSDC = manager.getUserActiveAmount(1, address(USDC), currentActor);

        amountBTC = bound(amountBTC, 0, userActiveAmountBTC);

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);
        if (amountUSDC > userActiveAmountUSDC) return;

        if (feeIndex == 0) {
            fee = manager.getWithdrawFee(address(BTC));

            if (amountBTC < fee) {
                return;
            }

            ghost_fees[address(BTC)] += fee;
        } else {
            fee = manager.getWithdrawFee(address(USDC));

            if (amountUSDC < fee) {
                return;
            }

            ghost_fees[address(USDC)] += fee;
        }

        vm.startPrank(currentActor);

        manager.withdrawSpot(1, spotTokens, amountBTC, feeIndex);

        vm.stopPrank();

        ghost_withdraws[address(BTC)] += amountBTC;
        ghost_withdraws[address(USDC)] += amountUSDC;
    }

    function claimPerp(uint256 actorSeed) public useActor(actorSeed) {
        if (currentActor == address(0)) return;
        vm.startPrank(currentActor);

        simulate(2, perpTokens, currentActor);

        uint256 beforeBTC = BTC.balanceOf(currentActor);
        uint256 beforeUSDC = USDC.balanceOf(currentActor);
        uint256 beforeWETH = WETH.balanceOf(currentActor);

        manager.claim(currentActor, perpTokens, 2);

        uint256 receivedBTC = BTC.balanceOf(currentActor) - beforeBTC;
        uint256 receivedUSDC = USDC.balanceOf(currentActor) - beforeUSDC;
        uint256 receivedWETH = WETH.balanceOf(currentActor) - beforeWETH;

        _pay(address(this), BTC, receivedBTC);
        _pay(address(this), USDC, receivedUSDC);
        _pay(address(this), WETH, receivedWETH);

        vm.stopPrank();

        ghost_claims[address(BTC)] += receivedBTC;
        ghost_claims[address(USDC)] += receivedUSDC;
        ghost_claims[address(WETH)] += receivedWETH;
    }

    function claimSpot(uint256 actorSeed) public useActor(actorSeed) {
        if (currentActor == address(0)) return;
        vm.startPrank(currentActor);

        simulate(1, spotTokens, currentActor);

        uint256 beforeBTC = BTC.balanceOf(currentActor);
        uint256 beforeUSDC = USDC.balanceOf(currentActor);

        manager.claim(currentActor, spotTokens, 1);

        uint256 receivedBTC = BTC.balanceOf(currentActor) - beforeBTC;
        uint256 receivedUSDC = USDC.balanceOf(currentActor) - beforeUSDC;

        _pay(address(this), BTC, receivedBTC);
        _pay(address(this), USDC, receivedUSDC);

        vm.stopPrank();

        ghost_claims[address(BTC)] += receivedBTC;
        ghost_claims[address(USDC)] += receivedUSDC;
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _pay(address to, IERC20Metadata token, uint256 amount) internal {
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

    function simulate(uint256 id, address[] memory tokens, address user) public {
        (address router,,,) = manager.getPoolToken(id, address(0));

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];

            deal(token, router, manager.getUserPendingAmount(id, token, user) + manager.getUserFee(id, token, user));
        }
    }

    // Exclude from coverage report
    function test() public {}
}
