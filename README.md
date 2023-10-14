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
<td><code>0xdA89782a6e3A15d4041F750414BB337a8724A325</code></td>
<td><code>0x2c61C7C6D608033b084B60A78A08216d73730545</code></td>
<td><code>0xcfd5D7AdF20ccfB45BCf15b88E29DA1Fc47FD9Cb</code></td>
<td><code>0xfAE95d8e678e266249a30fA120D44B883c9E6b2e</code></td>
<td><code>0xd393aA9A5985ce9000c4909489B6685698970705</code></td>
<td><code>0x89dE9Db43b888beBbE75ABd8FEa174D9FB90069E</code></td>
<td><code>0x2d277639850B0C0daf728f8B10eD1d507e1aA100</code></td>
<td><code>0x5F7B340373Dfa8a00C831b8c3745Cd284E8fA085</code></td>
<td><code>0x768EC6Eaf7D4305aAdde0c040458e4b5B74E7C1C</code></td>
<td><code>0x22132A8fB1a42eE0d380Deb7164a69471DfF6179</code></td>
<td><code>0x8b42Fa9D303F2a37DFB59FEEC27221f4629bb0cA</code></td>
<td><code>0xbe41c8B096a744F0A855FBb543b1bEc7267A8Edc</code></td>
<td><code>0xC67e88C8df11a082a91710059F5E863d7bB3BBE6</code></td>
<td><code>0x7385B3d528973F2BcE8afbe01f7c6839393D8076</code></td>
<td><code>0x3f202338Bd2fbB9E21AB29E72815Bc0cAbA0c25b</code></td>
<td><code>0xa258BaCC1d7fae87430A9ec6b601cb27d3dbb5Fb</code></td>
<td><code>0x54B57eB42C50Fb5170F0183fC8B18dd3C2D01220</code></td>
<td><code>0x9cBC189b11136eaccbF3a12b614E024C37BFF229</code></td>
<td><code>0x76Cc0CDde8726dA745aE4e8567426668f5162657</code></td>
<td><code>0x52bafC36eb0ea761CC1dD683933F691D1A82a7F7</code></td>
<td><code>0xCdfa723849ad49AdfabaA7a54145Dfb3F85fB0Cd</code></td>
<td><code>0xEED1EE3A0f3c8DeC8e292e5987b10e9Fabe201a4</code></td>
</tr>
<tr>
<td>Arbitrum Goerli</td>
<td><code>0xdA89782a6e3A15d4041F750414BB337a8724A325</code></td>
<td><code>0x2c61C7C6D608033b084B60A78A08216d73730545</code></td>
<td><code>0xcfd5D7AdF20ccfB45BCf15b88E29DA1Fc47FD9Cb</code></td>
<td><code>0xfAE95d8e678e266249a30fA120D44B883c9E6b2e</code></td>
<td><code>0xd393aA9A5985ce9000c4909489B6685698970705</code></td>
<td><code>0x89dE9Db43b888beBbE75ABd8FEa174D9FB90069E</code></td>
<td><code>0x2d277639850B0C0daf728f8B10eD1d507e1aA100</code></td>
<td><code>0x5F7B340373Dfa8a00C831b8c3745Cd284E8fA085</code></td>
<td><code>0x768EC6Eaf7D4305aAdde0c040458e4b5B74E7C1C</code></td>
<td><code>0x22132A8fB1a42eE0d380Deb7164a69471DfF6179</code></td>
<td><code>0x8b42Fa9D303F2a37DFB59FEEC27221f4629bb0cA</code></td>
<td><code>0xbe41c8B096a744F0A855FBb543b1bEc7267A8Edc</code></td>
<td><code>0xC67e88C8df11a082a91710059F5E863d7bB3BBE6</code></td>
<td><code>0x7385B3d528973F2BcE8afbe01f7c6839393D8076</code></td>
<td><code>0x3f202338Bd2fbB9E21AB29E72815Bc0cAbA0c25b</code></td>
<td><code>0xa258BaCC1d7fae87430A9ec6b601cb27d3dbb5Fb</code></td>
<td><code>0x54B57eB42C50Fb5170F0183fC8B18dd3C2D01220</code></td>
<td><code>0x9cBC189b11136eaccbF3a12b614E024C37BFF229</code></td>
<td><code>0x76Cc0CDde8726dA745aE4e8567426668f5162657</code></td>
<td><code>0x52bafC36eb0ea761CC1dD683933F691D1A82a7F7</code></td>
<td><code>0xCdfa723849ad49AdfabaA7a54145Dfb3F85fB0Cd</code></td>
<td><code>0xEED1EE3A0f3c8DeC8e292e5987b10e9Fabe201a4</code></td>
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
