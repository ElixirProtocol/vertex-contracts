// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {AddressSet, LibAddressSet} from "../utils/AddressSet.sol";
import {MockToken} from "../utils/MockToken.sol";
import {VertexManager} from "../../src/VertexManager.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

uint256 constant BTC_SUPPLY = 100_000 * 10 ** 18;
uint256 constant USDC_SUPPLY = 3_000_000_000 * 10 ** 18;

contract Handler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;

    VertexManager internal manager;

    MockToken internal BTC;
    MockToken internal USDC;
    MockToken internal WETH;

    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;
    uint256 public ghost_forcePushSum;

    AddressSet internal _actors;

    address internal currentActor;

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(msg.sender);
        _;
    }

    function actors() external view returns (address[] memory) {
        return _actors.addrs;
    }

    constructor(VertexManager _manager, MockToken _BTC, MockToken _USDC, MockToken _WETH) {
        manager = _manager;
        BTC = _BTC;
        USDC = _USDC;
        WETH = _WETH;

        BTC.mint(address(this), BTC_SUPPLY);
        USDC.mint(address(this), USDC_SUPPLY);
    }

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

        manager.deposit(1, amounts, currentActor);

        vm.stopPrank();

        ghost_depositSum += amountBTC;
    }

    function withdraw(uint256 amountBTC) public createActor {
        amountBTC = bound(amountBTC, 0, BTC.balanceOf(address(this)));

        uint256 amountUSDC = manager.getBalancedAmount(address(BTC), address(USDC), amountBTC);

        vm.startPrank(currentActor);

        manager.withdrawBalanced(1, amountBTC, 1);

        _pay(address(this), BTC, amountBTC);
        _pay(address(this), USDC, amountUSDC);

        vm.stopPrank();

        ghost_withdrawSum += amountBTC;
    }

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

    // Exclude from coverage report
    function test() public {}
}
