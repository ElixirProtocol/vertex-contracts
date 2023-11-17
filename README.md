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
<th>Router MATIC-PERP (ID 14)</th>
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
<th>Router DYDX-PERP (ID 38)</th>
<th>Router CRV-PERP (ID 40)</th>
</tr>
<tr>
<td>Arbitrum Mainnet</td>
<td><code>0x052Ab3fd33cADF9D9f227254252da3f996431f75</code></td>
<td><code>0x5E5E03AaE77C667664bA47556528a947af0A4716</code></td>
<td><code>0xA760E3dF6026a462A81EEe0227921D156d94C888</code></td>
<td><code>0x86612c5C2bdAe1e8534778B6C9C5535f635Fd04e</code></td>
<td><code>0x5328277109AdE587C69B90e2D6BDD004A97E1bB9</code></td>
<td><code>0x8294Ea1bdAac220B6b840B6F9d294aDf6cD069aD</code></td>
<td><code>0xE2F852E5877fD6901481c6f5bb2ecD94919ba026</code></td>
<td><code>0xCE30817dB0106b0362f3310ABD43fD0623Be83D7</code></td>
<td><code>0x8e7C90103e86Ba0171c3c37F84cCdB19B93b2C62</code></td>
<td><code>0x2DCa8aB151811D7425446931Cb138072bD815DCD</code></td>
<td><code>0x16e1c7beCdD3bD7171AceD6f0774e076a1a3Ccd6</code></td>
<td><code>0xF967Db12dc3eAA2bFd5958b33D3F4c787cD01394</code></td>
<td><code>0x3DfE28737C7fD444111cA30d521B75f9b0C803E7</code></td>
<td><code>0x3421bb71E71919A2a2809D1Ec3A2DFcFd8eEd890</code></td>
<td><code>0xFfF7a80Fcb3ade0379bd09B50f8dda9adcA3e17d</code></td>
<td><code>0x7805db7765a61Ec70D94A262ca7F46ce2A0Cf85F</code></td>
<td><code>0xA5205f83dE3D66674635Ac9642464ee6b169E5ff</code></td>
<td><code>0xeAc3A369FBe6C44a137ff6Fb5dE771c1891a201E</code></td>
<td><code>0xC61f8e36E763a645BbA417A3d88c1A2DDe62faa0</code></td>
<td><code>0xEe7DFBe0CE3ad8044eB36C38bDb59f56e0f86088</code></td>
<td><code>0x4662Ed14d509791A5a1Fe0376415a2A8438bd53a</code></td>
<td><code>0x5B4F6c8527237038d922a9f9cC7726bE65E7f27a</code></td>
<td><code>0xf06d2fd349Fc5B4BEA2F4Ac2997A8F21C1b5d025</code></td>
<td><code>0xaA19B0EC4a0E97d202B04713Ac76853Abd3dd2dA</code></td>
</tr>
<tr>
<td>Arbitrum Goerli</td>
<td><code>0x052Ab3fd33cADF9D9f227254252da3f996431f75</code></td>
<td><code>0x5E5E03AaE77C667664bA47556528a947af0A4716</code></td>
<td><code>0xA760E3dF6026a462A81EEe0227921D156d94C888</code></td>
<td><code>0x86612c5C2bdAe1e8534778B6C9C5535f635Fd04e</code></td>
<td><code>0x5328277109AdE587C69B90e2D6BDD004A97E1bB9</code></td>
<td><code>0x8294Ea1bdAac220B6b840B6F9d294aDf6cD069aD</code></td>
<td><code>0xE2F852E5877fD6901481c6f5bb2ecD94919ba026</code></td>
<td><code>0xCE30817dB0106b0362f3310ABD43fD0623Be83D7</code></td>
<td><code>0x8e7C90103e86Ba0171c3c37F84cCdB19B93b2C62</code></td>
<td><code>0x2DCa8aB151811D7425446931Cb138072bD815DCD</code></td>
<td><code>0x16e1c7beCdD3bD7171AceD6f0774e076a1a3Ccd6</code></td>
<td><code>0xF967Db12dc3eAA2bFd5958b33D3F4c787cD01394</code></td>
<td><code>0x3DfE28737C7fD444111cA30d521B75f9b0C803E7</code></td>
<td><code>0x3421bb71E71919A2a2809D1Ec3A2DFcFd8eEd890</code></td>
<td><code>0xFfF7a80Fcb3ade0379bd09B50f8dda9adcA3e17d</code></td>
<td><code>0x7805db7765a61Ec70D94A262ca7F46ce2A0Cf85F</code></td>
<td><code>0xA5205f83dE3D66674635Ac9642464ee6b169E5ff</code></td>
<td><code>0xeAc3A369FBe6C44a137ff6Fb5dE771c1891a201E</code></td>
<td><code>0xC61f8e36E763a645BbA417A3d88c1A2DDe62faa0</code></td>
<td><code>0xEe7DFBe0CE3ad8044eB36C38bDb59f56e0f86088</code></td>
<td><code>0x4662Ed14d509791A5a1Fe0376415a2A8438bd53a</code></td>
<td><code>0x5B4F6c8527237038d922a9f9cC7726bE65E7f27a</code></td>
<td><code>0xf06d2fd349Fc5B4BEA2F4Ac2997A8F21C1b5d025</code></td>
<td><code>0xaA19B0EC4a0E97d202B04713Ac76853Abd3dd2dA</code></td>
</tr>
<tr>
<td>Arbitrum Sepolia</td>
<td><code>0x052Ab3fd33cADF9D9f227254252da3f996431f75</code></td>
<td><code>0x5E5E03AaE77C667664bA47556528a947af0A4716</code></td>
<td><code>0xA760E3dF6026a462A81EEe0227921D156d94C888</code></td>
<td><code>0x86612c5C2bdAe1e8534778B6C9C5535f635Fd04e</code></td>
<td><code>0x5328277109AdE587C69B90e2D6BDD004A97E1bB9</code></td>
<td><code>0x8294Ea1bdAac220B6b840B6F9d294aDf6cD069aD</code></td>
<td><code>0xE2F852E5877fD6901481c6f5bb2ecD94919ba026</code></td>
<td><code>0xCE30817dB0106b0362f3310ABD43fD0623Be83D7</code></td>
<td><code>0x8e7C90103e86Ba0171c3c37F84cCdB19B93b2C62</code></td>
<td><code>0x2DCa8aB151811D7425446931Cb138072bD815DCD</code></td>
<td><code>0x16e1c7beCdD3bD7171AceD6f0774e076a1a3Ccd6</code></td>
<td><code>0xF967Db12dc3eAA2bFd5958b33D3F4c787cD01394</code></td>
<td><code>0x3DfE28737C7fD444111cA30d521B75f9b0C803E7</code></td>
<td><code>0x3421bb71E71919A2a2809D1Ec3A2DFcFd8eEd890</code></td>
<td><code>0xFfF7a80Fcb3ade0379bd09B50f8dda9adcA3e17d</code></td>
<td><code>0x7805db7765a61Ec70D94A262ca7F46ce2A0Cf85F</code></td>
<td><code>0xA5205f83dE3D66674635Ac9642464ee6b169E5ff</code></td>
<td><code>0xeAc3A369FBe6C44a137ff6Fb5dE771c1891a201E</code></td>
<td><code>0xC61f8e36E763a645BbA417A3d88c1A2DDe62faa0</code></td>
<td><code>0xEe7DFBe0CE3ad8044eB36C38bDb59f56e0f86088</code></td>
<td><code>0x4662Ed14d509791A5a1Fe0376415a2A8438bd53a</code></td>
<td><code>0x5B4F6c8527237038d922a9f9cC7726bE65E7f27a</code></td>
<td><code>0xf06d2fd349Fc5B4BEA2F4Ac2997A8F21C1b5d025</code></td>
<td><code>0xaA19B0EC4a0E97d202B04713Ac76853Abd3dd2dA</code></td>
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
