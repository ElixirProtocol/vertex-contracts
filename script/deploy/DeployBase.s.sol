// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import {IEndpoint, VertexManager} from "../../src/VertexManager.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract DeployBase is Script {
    // Environment specific variables.
    IEndpoint public endpoint;
    address public externalAccount;
    address public btc;
    address public usdc;
    address public eth;
    address public arb;
    address public usdt;

    // Deploy addresses.
    VertexManager internal managerImplementation;
    ERC1967Proxy internal proxy;
    VertexManager internal manager;

    // Deployer key.
    uint256 internal deployerKey;

    constructor(
        address _endpoint,
        address _externalAccount,
        address _btc,
        address _usdc,
        address _eth,
        address _arb,
        address _usdt
    ) {
        endpoint = IEndpoint(_endpoint);
        externalAccount = _externalAccount;
        btc = _btc;
        usdc = _usdc;
        eth = _eth;
        arb = _arb;
        usdt = _usdt;
    }

    function setup() internal {
        deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Get the token decimals.
        uint256 btcDecimals = IERC20Metadata(btc).decimals();
        uint256 usdcDecimals = IERC20Metadata(usdc).decimals();
        uint256 ethDecimals = IERC20Metadata(eth).decimals();
        uint256 arbDecimals = IERC20Metadata(arb).decimals();
        uint256 usdtDecimals = IERC20Metadata(usdt).decimals();

        // Deploy with key.
        vm.startBroadcast(deployerKey);

        // Deploy Factory implementation.
        managerImplementation = new VertexManager();

        // Deploy and initialize the proxy contract.
        proxy =
        new ERC1967Proxy(address(managerImplementation), abi.encodeWithSignature("initialize(address,uint256)", address(endpoint), 1000000));

        // Wrap in ABI to support easier calls.
        manager = VertexManager(address(proxy));

        // Add token support.
        manager.updateToken(usdc, 0);
        manager.updateToken(btc, 1);
        manager.updateToken(eth, 3);
        manager.updateToken(arb, 5);
        manager.updateToken(usdt, 31);

        // Give approval to create pools.
        IERC20Metadata(usdc).approve(address(manager), type(uint256).max);

        // Spot BTC: WBTC and USDC
        address[] memory spotBTC = new address[](2);
        spotBTC[0] = btc;
        spotBTC[1] = usdc;

        uint256[] memory spotBTCHardcaps = new uint256[](2);
        spotBTCHardcaps[0] = 1371 * 10 ** btcDecimals - 2; // 13.71 WBTC
        spotBTCHardcaps[1] = 375000 * 10 ** usdcDecimals; // 375000 USDC

        manager.addPool(1, spotBTC, spotBTCHardcaps, VertexManager.PoolType.Spot, externalAccount);

        // Perp BTC: USDC
        address[] memory singleUSDC = new address[](1);
        singleUSDC[0] = usdc;

        uint256[] memory perpBTCHardcaps = new uint256[](1);
        perpBTCHardcaps[0] = 375000 * 10 ** usdcDecimals; // 375000 USDC

        manager.addPool(2, singleUSDC, perpBTCHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Spot ETH: ETH and USDC
        address[] memory spotETH = new address[](2);
        spotETH[0] = eth;
        spotETH[1] = usdc;

        uint256[] memory spotETHHardcaps = new uint256[](2);
        spotETHHardcaps[0] = 227 * 10 ** ethDecimals; // 227 ETH
        spotETHHardcaps[1] = 375000 * 10 ** usdcDecimals; // 375000 USDC

        manager.addPool(3, spotETH, spotETHHardcaps, VertexManager.PoolType.Spot, externalAccount);

        // Perp ETH: USDC
        manager.addPool(4, singleUSDC, perpBTCHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Spot ARB: ARB and USDC
        address[] memory spotARB = new address[](2);
        spotARB[0] = arb;
        spotARB[1] = usdc;

        uint256[] memory spotARBHardcaps = new uint256[](2);
        spotARBHardcaps[0] = 73500 * 10 ** arbDecimals; // 73500 ARB
        spotARBHardcaps[1] = 75000 * 10 ** usdcDecimals; // 75000 USDC

        manager.addPool(5, spotARB, spotARBHardcaps, VertexManager.PoolType.Spot, externalAccount);

        // Perp ARB: USDC
        uint256[] memory perpHardcaps = new uint256[](1);
        perpHardcaps[0] = 90000 * 10 ** usdcDecimals; // 90000 USDC

        manager.addPool(6, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp BNB: USDC
        manager.addPool(8, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp XRP: USDC
        manager.addPool(10, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp SOL: USDC
        manager.addPool(12, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp MATIC: USDC
        manager.addPool(14, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp SUI: USDC
        manager.addPool(16, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp OP: USDC
        manager.addPool(18, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp APT: USDC
        manager.addPool(20, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp LTC: USDC
        manager.addPool(22, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp BCH: USDC
        manager.addPool(24, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp COMP: USDC
        manager.addPool(26, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp MKR: USDC
        manager.addPool(28, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp mPEPE: USDC
        manager.addPool(30, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Spot USDT: USDT and USDC
        address[] memory spotUSDT = new address[](2);
        spotUSDT[0] = usdt;
        spotUSDT[1] = usdc;

        uint256[] memory spotUSDTHardcaps = new uint256[](2);
        spotUSDTHardcaps[0] = 45000 * 10 ** usdtDecimals; // 45000 USDT
        spotUSDTHardcaps[1] = 45000 * 10 ** usdcDecimals; // 45000 USDC

        manager.addPool(31, spotUSDT, spotUSDTHardcaps, VertexManager.PoolType.Spot, externalAccount);

        // Perp DOGE: USDC
        manager.addPool(34, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        // Perp LINK: USDC
        manager.addPool(36, singleUSDC, perpHardcaps, VertexManager.PoolType.Perp, externalAccount);

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public virtual {}
}
