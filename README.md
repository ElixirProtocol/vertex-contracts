# Elixir <> Vertex Integration Contracts • [![CI](https://github.com/ElixirProtocol/vertex-contracts/actions/workflows/test.yml/badge.svg)](https://github.com/ElixirProtocol/elixir-contracts/actions/workflows/test.yml)

## Usage

You will need to install [Foundry](https://github.com/foundry-rs/foundry) before proceeding. See the [installation guide](https://github.com/foundry-rs/foundry#installation) for details.

To build the contracts:

```sh
git clone https://github.com/ElixirProtocol/vertex-contracts.git
cd vertex-contracts
forge install
forge build
```

### Run Tests

In order to run all tests, run:

```sh
forge test
```

You can run Slither with the following command:
```sh
slither . --exclude-dependencies --filter-paths "openzeppelin|test|script"
```

### Deploy Contracts

In order to deploy the contracts, set the relevant constants in the respective chain script, and run the following command(s):

```sh
forge script script/deploy/DeployGoerli.s.sol:DeployGoerli -vvvv --fork-url RPC --broadcast --slow
```
