<img align="right" width="150" height="150" top="100" style="border-radius:99%" src="https://i.imgur.com/H5aZQMA.jpg">

# Elixir <> Vertex Contracts • [![CI](https://github.com/ElixirProtocol/vertex-contracts/actions/workflows/test.yml/badge.svg)](https://github.com/ElixirProtocol/elixir-contracts/actions/workflows/test.yml)

## Background

This project contains the smart contracts for the Elixir Protocol integration on top of Vertex Protocol.

See the [documentation](docs/docs.md), the [Elixir Protocol documentation](https://docs.elixir.finance/), and the [Vertex Protocol documentation](https://vertex-protocol.gitbook.io/docs/) for more information.

## Deployments


<table>
<tr>
<th>Network</th>
<th>VertexManager</th>
<th>Router WBTC (ID 1)</th>
<th>Router BTC-PERP (ID 2)</th>
<th>Router WETH (ID 3)</th>
<th>Router ETH-PERP (ID 4)</th>
<th>Router ARB (ID 5)</th>
<th>Router ARB-PERP (ID 6)</th>
<th>Router BNB-PERP (ID 8)</th>
<th>Router XRP-PERP (ID 10)</th>
<th>Router SOL-PERP (ID 12)</th>
<th>Router MATIC-PER (ID 14)P</th>
<th>Router SUI-PERP (ID 16)</th>
<th>Router OP-PERP (ID 18)</th>
<th>Router APT-PERP (ID 20)</th>
<th>Router LTC-PERP (ID 22)</th>
<th>Router BCH-PERP (ID 24)</th>
<th>Router COMP-PERP (ID 26)</th>
<th>Router MKR-PERP (ID 28)</th>
<th>Router MPEPE-PERP (ID 30)</th>
<th>Router USDT (ID 31)</th>
<th>Router DOGE-PERP (ID 34)</th>
<th>Router LINK-PERP (ID 36)</th>
</tr>
<tr>
<td>Arbitrum Mainnet</td>
<td><code>0x82dF40dea5E618725E7C7fB702b80224A1BB771F</code></td>
<td><code>0x393c45709968382Ee52dFf31aafeDeCA3B9654fC</code></td>
<td><code>0x58c66f107A1C129A4865c2f1EDc33eFd38A2f020</code></td>
<td><code>0xf5b2C3A4eb7Fd59F5FBE512EEb1aa98358242FD5</code></td>
<td><code>0xa13a4b97aB259808b10ffA58f08589063eD99943</code></td>
<td><code>0x738163cE85274b7599B91D1dA0E2798cAdc289d1</code></td>
<td><code>0x67B748B2B1c54809140Ebb12766c31480c3DE121</code></td>
<td><code>0x3b4D5D2319dB8d4Ce49eF32241fF447F57EDFb07</code></td>
<td><code>0x56ee545A30FeaC520cf0adCEA289481aB0A94518</code></td>
<td><code>0xD051B4886241feE6E03a32Ce86Ad3DeF77C6fC04</code></td>
<td><code>0x91110A59d41A8b659cb2AA4EFcf2B4C553eDf614</code></td>
<td><code>0x68Fade385055055c4b625E4C0f4e848D97673274</code></td>
<td><code>0x1e4887f4B32A3C758db71375A5c034E445101fBe</code></td>
<td><code>0x782855A9F6678F77Fe4CAbF5FB52C31Bef354535</code></td>
<td><code>0xE11644ac68D93C4E8730fC5Fb94A311211Cb4309</code></td>
<td><code>0x533485094d08399c99b670A241219A5d197C794d</code></td>
<td><code>0xa248740E945c8a6FeE4fB1aA677D2FfD3a8F4162</code></td>
<td><code>0xa15DD3100C9D09aC84310e7A31c7242608F445E7</code></td>
<td><code>0x7dE89198dbC097eb3731F297d18806Dab8e27A72</code></td>
<td><code>0x4B1a9AaC8D05B2f13b8212677aA03bDaa7d8A185</code></td>
<td><code>0x6Ba6435B47a36adCB3cca90189F20AA995e096f7</code></td>
<td><code>0xbf541F7bE0DCE645455698636cf7b354CF4a97d3</code></td>
</tr>
<tr>
<td>Arbitrum Goerli</td>
<td><code>0x82dF40dea5E618725E7C7fB702b80224A1BB771F</code></td>
<td><code>0x393c45709968382Ee52dFf31aafeDeCA3B9654fC</code></td>
<td><code>0x58c66f107A1C129A4865c2f1EDc33eFd38A2f020</code></td>
<td><code>0xf5b2C3A4eb7Fd59F5FBE512EEb1aa98358242FD5</code></td>
<td><code>0xa13a4b97aB259808b10ffA58f08589063eD99943</code></td>
<td><code>0x738163cE85274b7599B91D1dA0E2798cAdc289d1</code></td>
<td><code>0x67B748B2B1c54809140Ebb12766c31480c3DE121</code></td>
<td><code>0x3b4D5D2319dB8d4Ce49eF32241fF447F57EDFb07</code></td>
<td><code>0x56ee545A30FeaC520cf0adCEA289481aB0A94518</code></td>
<td><code>0xD051B4886241feE6E03a32Ce86Ad3DeF77C6fC04</code></td>
<td><code>0x91110A59d41A8b659cb2AA4EFcf2B4C553eDf614</code></td>
<td><code>0x68Fade385055055c4b625E4C0f4e848D97673274</code></td>
<td><code>0x1e4887f4B32A3C758db71375A5c034E445101fBe</code></td>
<td><code>0x782855A9F6678F77Fe4CAbF5FB52C31Bef354535</code></td>
<td><code>0xE11644ac68D93C4E8730fC5Fb94A311211Cb4309</code></td>
<td><code>0x533485094d08399c99b670A241219A5d197C794d</code></td>
<td><code>0xa248740E945c8a6FeE4fB1aA677D2FfD3a8F4162</code></td>
<td><code>0xa15DD3100C9D09aC84310e7A31c7242608F445E7</code></td>
<td><code>0x7dE89198dbC097eb3731F297d18806Dab8e27A72</code></td>
<td><code>0x4B1a9AaC8D05B2f13b8212677aA03bDaa7d8A185</code></td>
<td><code>0x6Ba6435B47a36adCB3cca90189F20AA995e096f7</code></td>
<td><code>0xbf541F7bE0DCE645455698636cf7b354CF4a97d3</code></td>
</tr>
</table>

## Documentation

You can find the technical documentation and references of the smart contracts [here](docs/docs.md). 

## Usage

You will need a copy of [Foundry](https://github.com/foundry-rs/foundry) installed before proceeding. See the [installation guide](https://github.com/foundry-rs/foundry#installation) for details.

To build the contracts:

```sh
git clone https://github.com/ElixirProtocol/vertex-contracts.git
cd vertex-contracts
forge install
forge build
```

### Run Tests

In order to run unit tests, run:

```sh
forge test
```

For longer fuzz campaigns, run:

```sh
FOUNDRY_PROFILE="deep" forge test
```

### Run Slither

After [installing Slither](https://github.com/crytic/slither#how-to-install), run:

```sh
slither src/
```

### Check coverage

To check the test coverage, run:

```sh
forge coverage
```

### Update Gas Snapshots

To update the gas snapshots, run:

```sh
forge snapshot
```

### Deploy Contracts

In order to deploy the contracts, set the relevant constants in the respective chain script, and run the following command(s):

```sh
forge script script/deploy/DeployGoerli.s.sol:DeployGoerli -vvvv --fork-url RPC --broadcast --slow
```
