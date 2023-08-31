# Elixir <> Vertex Documentation

Overview of Elixir's smart contract architecture integrating to Vertex Protocol.

## Table of Contents

- [Background](#background)
- [Overview](#overview)
- [Sequence of Events](#sequence-of-events)
- [Lifecycle](#example-lifecycle-journey)
- [Expected Behaviour](#expected-behaviour)
- [Aspects](#aspects)

## Background

Elixir is building the industry's decentralized, algorithmic market-making protocol. The protocol algorithmically deploys supplied liquidity on the order books, utilizing the equivalent of x*y=k curves to build liquidity and tighten the bid/ask spread. The protocol provides crucial decentralized infrastructure, allowing exchanges and protocols to easily bootstrap liquidity to their books. It also enables crypto projects to incentivize liquidity to their centralized exchange pairs via LP tokens.

This repository contains the smart contracts to power the first native integration between Elixir and Vertex, a cross-margined DEX protocol offering spot, perpetuals, and an integrated money market bundled into one vertical application on Arbitrum. Vertex is powered by a hybrid unified central limit order book (CLOB) and integrated automated market maker (AMM). Gas fees and MEV are minimized on Vertex due to the batched transaction and optimistic rollup model of the underlying Arbitrum Layer 2, where Vertex's smart contracts control the risk engine and core products.

This integration aims to unlock retail liquidity for algorithmic market-making on Vertex. Due to the nature of the underlying integration, the Elixir smart contracts have unique features and functions that allow building on top of it. For example, an important aspect of Vertex Protocol is their orderbook, a "sequencer" that operates as an off-chain node layered on top of their smart contracts and contained within the Arbitrum protocol layer.

More information:
- [Elixir Protocol Documentation](https://docs.elixir.finance/)
- [Vertex Protocol Dcoumentation](https://vertex-protocol.gitbook.io/docs/)

## Overview

This integration comprises one Elixir smart contract, called Vertex Manager, that allows users to deposit and withdraw liquidity for spot and perpetual (perp) products on Vertex. By depositing liquidity, users earn VRTX rewards from the market-making done by the Elixir validator network off-chain. Rewards, denominated in the VRTX token, are distributed via epochs lasting 28 days and serve as the sustainability of the APRs. On the Vertex Smart contract, each product is associated with a pool structure, which contains data like active amounts, balances, and more. Regarding Vertex, the Elixir smart contract interacts mainly with the Endpoint smart contract.

- [VertexManager](src/VertexManager.sol): Elixir smart contract to deposit, withdraw, claim and manage product pools.
- [Endpoint](https://github.com/vertex-protocol/vertex-contracts/blob/main/contracts/Endpoint.sol): Vertex smart contract that serves as the entry point for all actions and interactions with their protocol.
- [Clearinghouse](https://github.com/vertex-protocol/vertex-contracts/blob/main/contracts/Clearinghouse.sol): Vertex smart contract that serves as the clearinghouse for all trades and positions, storing the liquidity (TVL) of their protocol. Only used in Vertex Manager initialization to fetch the fee token address.

## Sequence of Events

### Deposit Liquidity
Liquidity can be deposited into the Vertex Manager smart contract by calling the `deposit` or `depositBalanced` functions. Every spot product is composed of two tokens, the base token and the quote token, which is usually USDC. For this reason, liquidity for a spot product has to be deposited in a balanced way, meaning that the amount of base and quote tokens have to be equal in value. To check this, product prices are fetched from the Vertex Endpoint smart contract by calling its `getPriceX18` function, which provides the price in 18 decimals for a given product. Therefore, the Vertex Manager smart contract provides the `depositBalanced` function, which takes in a fixed base token amount and a range of quote token amounts to deposit. The function will then calculate the amount of quote tokens needed to perform a balanced deposit given the amount of base tokens. If this calculated amount of quote tokens is out of the given range, the function will revert due to slippage. The `deposit` function can still be used to deposit liquidity for a spot product, but there's a small probability that the transaction reverts if the price of the product changes between the time the price is fetched and the time the transaction is confirmed. For perp products, liquidity can be deposited in an unbalanced way, meaning that the amount of tokens deposited can be different. In any case, the flow of the deposit functions is the following:

1. Check that deposits are not paused.
2. Check that the reentrancy guard is not active.
3. Fetch the pool data using the given product ID.
4. Verify that the length of amounts given match the length of supported tokens in the pool.
5. Check if the length of amounts given is 2, meaning a spot product.
   - If so, check that the amount of base tokens is equal in value to the amount of quote tokens.
6. Loop over the amounts given to fetch the respective tokens and redirect liquidity to Vertex.
   - Fetch the token address by using the index of the amount in the amounts array and the array of supported tokens in the pool.
   - Check if the token amount to deposit will exceed the liquidity hardcap in this pool.
   - Transfer the tokens from the caller to itself.
   - Build and send the deposit transaction to Vertex, redirecting the received tokens to the Elixir account (EOA, established a linked signer).
    * The Elixir linked signer allows the off-chain decentralized validator network to create market making requests on behalf of the Elixir smart contract.
   - Update the pool data with the new amount.
7. Emit the `Deposit` event.

> Note: Before calling the `deposit` function, the `depositBalanced` function checks that the deposit belongs to a spot product and that the amount of base tokens is equal in value to the amount of quote tokens. If this is not the case, the transaction will revert.

### Withdraw Liquidity
Due to the nature of Vertex, withdrawing funds requires a two-step process. First, the liquidity has to be withdrawn from Vertex to the Elixir smart contract, which has to be approved by the Vertex sequencer, charging a fee of 1 USDC. Second, the liquidity has to "manually" be claimed via the `claim` function on the Elixir smart contract, as no Vertex callback is available. Anyone can call this function on behalf of any address, allowing us to monitor pending claims and process them for users. Similarly to deposits, withdrawals on a spot product have to be balanced. Therefore, the Elixir smart contract provides a helper function called `withdrawBalanced` that facilitates the process. In any case, the flow of the `withdraw` function is the following:

1. Check that withdraws are not paused.
2. Check that the reentrancy guard is not active.
3. Fetch the pool data using the given product ID.
4. Verify that the length of amounts given match the length of supported tokens in the pool.
5. Check if the length of amounts given is 2, meaning a spot product.
   - If so, check that the amount of base tokens is equal in value to the amount of quote tokens.
6. Loop over the amounts given to create and send the respective withdraw requests to Vertex.
   - Fetch the token address by using the index of the amount in the amounts array and the array of supported tokens in the pool.
   - Substract the amount of tokens from the user's balance on the pool data. Reverts if the user does not have enough balance.
   - Check if the loop iteration number matches the fee index, which represents what token to use to pay the Vertex sequencer fee.
    * If they match, the smart contract calculates the token amount equivalent to 1 USDC. 
    * This amount is added to the fee balance of Elixir as it will pay the sequencer fee of 1 USDC on behalf of the user. Elixir can reimburse itself via the `claimFees` function.
    * The fee amount is then substracted from the original token amount to withdraw, and stored as the pending balance for claims afterwads.
   - Build and send the withdraw request to Vertex.
7. Emit the `Withdraw` event.

> Note: Before calling the `withdraw` function, the `withdrawBalanced` function checks that the withdraw belongs to a spot product and that the amount of base tokens is equal in value to the amount of quote tokens. If this is not the case, the transaction will revert.

### Claim Liquidity
After the Vertex sequencer fulfills a withdrawal request, the funds will be available to claim on the Elixir smart contract by calling the `claim` function. This function can be called by anyone on behalf of a user, allowing us to monitor the pending claims and process them for users. The flow of the `claim` function is the following:

1. Check that claims are not paused.
1. Check that the reentrancy guard is not active.
2. Loop over the list of tokens given.
   - Fetch and store the pending balance of the user for the token in the iteration.
   - Reset the pending balance to 0.
   - Transfer the token amount to the user.
3. Emit the `Claim` event.

> Note: As pending balances are not stored sequentially, users are able to claim funds in any order as they arrive to the Elixir smart contract. This is expected behaviour and does not affect the user's funds as the Vertex sequencer will continue to fulfill withdraw requests, which can also be manually processed after days of inactivity by the Vertex sequencer. Read more in the expected behaviour section.

### Reward Distribution (Pending)
By market-making (creating and filling orders on the Vertex order book), the Elixir validator network earns VRTX rewards. These rewards would be distributed to the users who deposited liquidity on the Vertex Manager smart contract, depending on the amount and time of their liquidity. Vertex hasn't implemented the functionality to claim rewards yet, but the Elixir smart contract is ready to support it thanks to its upgradeability. Until then, reward balances are stored off-chain and will be synchronized and distributed to users when the Vertex functionality to claim is available.

Learn more about the VRTX reward mechanism [here](https://vertex-protocol.gitbook.io/docs/community-token-and-dao/trading-rewards-detailed-mechanism).

## Example Lifecycle Journey

### Spot Product

- A user approves the Vertex Manager smart contract to spend their tokens.
- User calls `depositBalanced` and passes the following parameters:
   * `id`: The ID of the pool to deposit to.
   * `amount0`: The amount of base tokens to deposit.
   * `amount1Low`: The low limit of the quote amount.
   * `amount1High`: The high limit of the quote amount.
   * `receiver`: The address to receive the virtual balance of deposited tokens.
- `depositBalanced` calculates the balanced amount of quote tokens (`amount1`) needed for the deposit given the amount of base tokens (`amount0`). If the calculated amount of quote tokens is out of the given range (`amount1Low` <> `amount1High`), the function reverts due to slippage.
- The `depositBalanced` function builds the parameters and calls the `deposit` function.
- The `deposit` function performs a series of check and redirects liquidity to Vertex.
- The Elixir network of decentralized of validators receive the liquidity and start to market make using it, generating VRTX rewards for the user.
- After some time, the user (i.e. receiver) calls the `withdrawBalanced` function to withdraw liquidity and passes the following parameters:
   * `id`: The ID of the pool to withdraw from.
   * `amount0`: The amount of base tokens to withdraw.
   * `feeIndex`: As explained in the withdraw section, this represents what token to use to pay the Vertex sequencer fee, reimbursing Elixir.
- This function performs the same balance calculation as in the `depositBalanced` function and call the `withdraw` function.
- The `withdraw` function performs a series of check and sends the withdraw requests to Vertex.
- After the Vertex sequencer fulfills some withdraw requests and funds are available on the Vertex Manager contract, the user can call the `claim` function to claim their funds. Note that this step will most likely be performed by us (or any other third-party) on behalf of the user.

### Perpetual Product

- A user approves the Vertex Manager smart contract to spend their tokens.
- User calls `deposit` and passes the following parameters:
   * `id`: The ID of the pool to deposit to.
   * `amounts`: The amount of tokens to deposit as an array. Each amount has to be in the same order as the supported tokens in the pool.
   * `receiver`: The address to receive the virtual balance of deposited tokens.
- The `deposit` function performs a series of check and redirects liquidity to Vertex.
- The Elixir network of decentralized of validators receive the liquidity and start to market make using it, generating VRTX rewards for the user.
- After some time, the user (i.e. receiver) calls the `withdraw` function to withdraw liquidity and passes the following parameters:
   * `id`: The ID of the pool to withdraw from.
   * `amounts`: The amount of tokens to withdraw as an array. Each amount has to be in the same order as the supported tokens in the pool.
   * `feeIndex`: As explained in the withdraw section, this represents what token to use to pay the Vertex sequencer fee, reimbursing Elixir.
- The `withdraw` function performs a series of check and sends the withdraw requests to Vertex.
- After the Vertex sequencer fulfills some withdraw requests and funds are available on the Vertex Manager contract, the user can call the `claim` function to claim their funds. Note that this step will most likely be performed by us (or any other third-party) on behalf of the user.

## Expected Behaviour

## Aspects

### Arithmetic

### Auditing

### Authentication / Access Control

### Complexity Management

### Decentralization

### Documentation

### Front-running Resistance

### Low-level manipulation

### Testing and Verification

