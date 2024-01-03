# Elixir <> Vertex Documentation

Overview of Elixir's smart contract architecture integrating to Vertex Protocol.

## Table of Contents

- [Background](#background)
- [Overview](#overview)
- [Sequence of Events](#sequence-of-events)
- [Lifecycle](#example-lifecycle-journey)
- [Incident Response & Monitoring](#incident-response--monitoring)
- [Aspects](#aspects)

## Background

Elixir is building the industry's decentralized, algorithmic market-making protocol. The protocol algorithmically deploys supplied liquidity on the order books, utilizing the equivalent of x*y=k curves to build liquidity and tighten the bid/ask spread. The protocol provides crucial decentralized infrastructure, allowing exchanges and protocols to easily bootstrap liquidity to their books. It also enables crypto projects to incentivize liquidity to their centralized exchange pairs via LP tokens.

This repository contains the smart contracts to power the first native integration between Elixir and Vertex, a cross-margined DEX protocol offering spot, perpetuals, and an integrated money market bundled into one vertical application on Arbitrum. Vertex is powered by a hybrid unified central limit order book (CLOB) and integrated automated market maker (AMM). Gas fees and MEV are minimized on Vertex due to the batched transaction and optimistic rollup model of the underlying Arbitrum Layer 2, where Vertex's smart contracts control the risk engine and core products.

This integration aims to unlock retail liquidity for algorithmic market-making on Vertex. Due to the nature of the underlying integration, the Elixir smart contracts have unique features and functions that allow building on top of it. For example, an important aspect of Vertex Protocol is their orderbook, a "sequencer" that operates as an off-chain node layered on top of their smart contracts and contained within the Arbitrum protocol layer.

More information:
- [Elixir Protocol Documentation](https://docs.elixir.finance/)
- [Vertex Protocol Dcoumentation](https://vertex-protocol.gitbook.io/docs/)

## Overview

This integration comprises two Elixir smart contracts a singleton (VertexManager) and a router (VertexRouter). VertexManager allows users to deposit and withdraw liquidity for spot and perpetual (perp) products on Vertex. By depositing liquidity, users earn VRTX rewards from the market-making done by the Elixir validator network off-chain. Rewards, denominated in the VRTX token, are distributed via epochs lasting 28 days and serve as the sustainability of the APRs. These rewards are deposited into the Distributor contract which allows users to claim tokens with signatures from the Elixir validator network. On the VertexManager smart contract, each Vertex product is associated with a pool structure, which contains a type and router (VertexRouter), plus a nested mapping containing the data of supported tokens in that pool. As Vertex contains their own sequencer, the data from their contracts on-chain is lagging. Therefore, the VertexManager contract implements a FIFO queue so that the Elixir sequencer can process deposits and withdrawals using the latest data off-chain. On the other hand, VertexRouter allows to have one linked signer per VertexManager pool — linked signers let the off-chain Elixir network market make on behalf of the pools. Regarding Vertex, the Elixir smart contract interacts mainly with the Endpoint and Clearinghouse smart contracts.

- [VertexManager](src/VertexManager.sol): Elixir smart contract to deposit, withdraw, claim and manage product pools.
- [VertexRouter](src/VertexRouter.sol): Elixir smart contract to route slow-mode transactions to Vertex, on behalf of a VertexManager pool.
- [Distributor](src/Distributor.sol): Elixir smart contract to claim rewards.
- [Endpoint](https://github.com/vertex-protocol/vertex-contracts/blob/main/contracts/Endpoint.sol): Vertex smart contract that serves as the entry point for all actions and interactions with their protocol.
- [Clearinghouse](https://github.com/vertex-protocol/vertex-contracts/blob/main/contracts/Clearinghouse.sol): Vertex smart contract that serves as the clearinghouse for all trades and positions, storing the liquidity (TVL) of their protocol. Only used in VertexManager initialization to fetch the fee token address.

## Sequence of Events

### Deposit Liquidity
Liquidity for spot and perp pools can be deposited into the VertexManager smart contract by calling the `depositSpot` and `depositPerp` functions, respectively. 

Every spot product is composed of two tokens, the base token and the quote token, which is usually USDC. For this reason, liquidity for a spot product has to be deposited in a balanced way, meaning that the amount of base and quote tokens have to be equal in value. To enfore this, deposits are queued and processed by the Elixir. When depositing into spot pools, the user specifies a slippage amount, which is checked when Elixir processes it. If the amount of tokens to deposit calculated by Elixir is outside the slippage range, the deposit is skipped. On the other hand, perp pools don't require balanced liquidity but Elixir processes them to calculate the amount of shares the user should receive. In order to process the queue, Elixir takes a fee in native ETH when depositing or withdrawing.

The `depositSpot` flow is the following:

1. Check that deposits are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool given is a spot one.
4. Check that the tokens given are two and are not duplicated.
5. Check that the receiver is not a zero address (for the good of the user).
6. Get the Elixir processing fee in native ETH
7. Queue the deposit.

And the `depositPerp` flow is the following:

1. Check that deposits are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool given is a perp one.
5. Check that the receiver is not a zero address (for the good of the user).
6. Get the Elixir processing fee in native ETH
7. Queue the deposit.

Afterwards, the Elixir sequencer will call the `unqueue` function which processes the next transaction in the queue. For deposits, the process flow is the following:

1. If the pool is spot, check for slippage.
2. Call the `_deposit` function for every token being deposited (2 for spot, 1 for perp).
3. The `_deposit` function:
   - Checks that the token is supported by the pool.
   - Checks that the token amount to deposit will not exceed the liquidity hardcap of the token in the pool.
   - Transfer the tokens from the depositor to the smart contract.
   - Build and send the deposit transaction to Vertex, redirecting the received tokens to the Elixir account (EOA, established a linked signer) via the VertexRouter smart contract assigned to this pool.
   - Update the pool data and balances with the new amount.
4. Emit the `Deposit` event.
5. Update the queue state to mark this deposit as processed.

> Note: Only tokens with less or equal to 18 decimals are supported by Vertex.

### Withdraw Liquidity
In order to start a withdrawal, the user should call the `withdrawSpot` or `withdrawPerp` functions in order to signal to the Elixir network their intention of withdrawing. These withdraw functions will queue their intent, and the Elixir sequencer will process it by calling the `unqueue` function. To process a withdrawal, the Elixir sequencer burns the user's shares and sends a withdrawal request to Vertex, charging a fee of 1 USDC. When the request is processed by Vertex, the liquidity is transfered to the pool's VertexRouter smart contract. Here, the user needs to "manually" claim the liquidity via the `claim` function on the Elixir VertexManager smart contract, as no Vertex callback is available. Anyone can call this function on behalf of any address, allowing us to monitor pending claims and process them for users. When calling the `claim` function, the VertexManger smart contract will transfer the liquidity from the pool's VertexRouter into the VertexManager smart contract, which is then transferred to the user.

The `withdrawSpot` flow is the following:

1. Check that withdrawals are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool given is a spot one.
5. Check that the tokens are not duplicated.
6. Get the Elixir processing fee in native ETH
7. Queue the withdrawal.

And the `withdrawPerp` flow is the following:

1. Check that withdrawals are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool given is a perp one.
4. Get the Elixir processing fee in native ETH
5. Queue the withdrawal.

Afterwards, the Elixir sequencer will call the `unqueue` function which processes the next transaction in the queue. For withdrawals, the process flow is the following:

1. Call the `_withdraw` function for every token being withdrawn (2 for spot, 1 for perp).
2. The `_withdraw` function:
   - Subtract the amount of tokens given from the user's balance on the pool data. Reverts if the user does not have enough balance.
   - Add fee amount to the balance of Elixir as it will pay the sequencer fee of 1 USDC on behalf of the user. Elixir is automatically reimbursed with user claims, but it can also reimburse itself by calling the `claim` function on behalf of a user.
   - Substract fee amount from the calculated token amount to withdraw and stored as the pending balance for claims afterward.
   - Build and send the withdrawal request to Vertex.
3. Emit the `Withdraw` event.
4. Update the queue state to mark this withdraw as processed.

> Note: It's vital for the VertexManager smart contract to maintain the invariant of: "each pool must have a unique pool" or "two pools cannot share the same router." Otherwise, a pool with a wrong router will lead to loss of funds during withdrawals because of an inflated balance of the pools. By nature of the current logic, it's impossible for the invariant to break, as changing a pool's router is not supported.

### Claim Liquidity
After the Vertex sequencer fulfills a withdrawal request, the funds will be available to claim on the VertexManager smart contract by calling the `claim` function. This function can be called by anyone on behalf of a user, allowing us to monitor the pending claims and process them for users. The flow of the `claim` function is the following:

1. Check that claims are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool is valid (i.e., it exists).
4. Check that the user to claim for is not the zero address.
5. Fetch and store the pending balance of the user for the token.
6. Fetch and store the Elixir reimburse fee amount.
7. Reset the pending balance and fee to 0.
8. Transfer the token amount to the user.
9. Transfer the fee amount to the owner (Elixir).
10. Emit the `Claim` event.

> Note: As pending balances are not stored sequentially, users are able to claim funds in any order as they arrive at the VertexRouter smart contract. This is expected behavior and does not affect the user's funds as the Vertex sequencer will continue to fulfill withdrawal requests, which can also be manually processed after days of inactivity by the Vertex sequencer.

### Reward Distribution
By market-making (creating and filling orders on the Vertex order book), the Elixir validator network earns VRTX rewards. These rewards are distributed to the users who deposited liquidity on the VertexManager smart contract, depending on the amount and time of their liquidity. Rewards are distributed via epochs lasting 28 days and serve as the sustainability of the APRs. These rewards are deposited into the Distributor contract which allows users to claim tokens with signatures from the Elixir validator network.

Learn more about the VRTX reward mechanism [here](https://vertex-protocol.gitbook.io/docs/community-token-and-dao/trading-rewards-detailed-mechanism).

## Example Lifecycle Journey

### Spot Product

- A user approves the VertexManager smart contract to spend their tokens.
- User calls `depositSpot` and passes the following parameters:
   * `id`: The ID of the pool to deposit to.
   * `token0`: The base token to deposit.
   * `token1`: The quote token to deposit.
   * `amount0`: The amount of base tokens to deposit.
   * `amount1Low`: The low limit of the quote amount.
   * `amount1High`: The high limit of the quote amount.
   * `receiver`: The receiver of the virtual LP balance.
- Elixir processes the deposit from the queue. If the calculated amount of quote tokens is out of the given range (`amount1Low` <> `amount1High`), the function reverts due to slippage.
- The `_deposit` redirects liquidity to Vertex and updates the LP balances, giving the shares to the receiver.
- The Elixir network of decentralized validators receives the liquidity and market makes with it, generating VRTX rewards.
- After some time, the user (i.e., receiver) calls the `withdrawSpot` function to initiate a withdrawal, passing the following parameters:
   * `id`: The ID of the pool to withdraw from.
   * `token0`: The base token to withdraw.
   * `token1`: The quote token to withdraw.
   * `amount0`: The amount of base tokens to withdraw.
- Elixir processes the withdrawal from the queue.
- The `_withdraw` function updates the LP balances and sends the withdrawal requests to Vertex.
- After the Vertex sequencer fulfills the withdrawal request, the funds are available to be claimed via the `claim` function.

### Perpetual Product

- A user approves the VertexManager smart contract to spend their tokens.
- User calls `depositPerp` and passes the following parameters:
   * `id`: The ID of the pool to deposit to.
   * `token`: The token to deposit.
   * `amount`: The amount of tokens to deposit.
   * `receiver`: The receiver of the virtual LP balance.
- Elixir processes the deposit from the queue.
- The `_deposit` redirects liquidity to Vertex and updates the LP balances, giving the shares to the receiver.
- The Elixir network of decentralized validators receives the liquidity and market makes with it, generating VRTX rewards.
- After some time, the user (i.e., receiver) calls the `withdrawPerp` function to initiate a withdrawal, passing the following parameters:
   * `id`: The ID of the pool to withdraw from.
   * `token`: The token to withdraw.
   * `amount`: The amount of tokens to withdraw.
- Elixir processes the withdrawal from the queue.
- The `_withdraw` function updates the LP balances and sends the withdrawal requests to Vertex.
- After the Vertex sequencer fulfills the withdrawal request, the funds are available to be claimed via the `claim` function.

## Incident Response & Monitoring

The Elixir team is planning to protect the smart contracts with Chainalysis Incident Response (CIR) in the event of a hack or exploit. The benefits of CIR include:

- CIR helps deter hackers by letting them know a leading global crypto investigative team is on our side.
- With CIR, we can tap into Chainalysis’ expertise for complex blockchain analysis and investigations. The CIR team is ready to respond to cybersecurity breaches, ransomware attacks, recovery of stolen cryptocurrency, and perform other analyses involving blockchain data. The team consists of respected professional investigators, cybersecurity experts, and data engineers.
- Having a proactive solution in place decreases the time to respond and increases the likelihood of asset freezing and recovery or law enforcement should the worst happen.
- The ability to trace funds through various types of complex platforms is a crucial part of the CIR incident response and the ability to recover funds successfully. This applies to identified mixer platforms but also unidentified mixers and new bridging protocols between blockchains.
- Chainalysis has a huge customer base and, with it, a sizable network with personal connections to almost all significant exchanges and services in the crypto space. Also, their strong relationship with Law Enforcement Agencies around the world makes them very efficient in engaging the relevant entities when needed.
- In over 80% of all cases where an incident has occurred, Chainalysis investigators have been able to give our customers valuable information that leads to recovery of more than what their CIR fee was.

## General Aspects

### Vertex Integration

Because Vertex does not offer an updated state of an account when there are transactions affecting them inside the sequencer queue, the protocol works around this by using an off-chain sequencer to calculate values for deposits and withdrawals.

### Authentication / Access Control

Appropiate access controls are in place for all priviliged operations. The only privliged role in the smart contract is the owner, which is the Elixir multisig. As the Vertex protocol is completely upgradeable, the owner role is needed to perform operations and actions in case any aspect needs to be updated. The capabilities of the owner are the following:

- `pause`: Update the pause status of deposits, withdraws, and claims in case of malicious activity or incidents. Allows to pause each operation modularly; for example, pause deposits but allow withdrawals and claims.
- `addPool`: Adds a new pool. This deploys a new router for the pool, which is unique for this pool. The reason is that Vertex only allows one linked signer per smart contract, which goes against the singleton design of the Manager contract.
- `addPoolTokens`: Adds a new token to a pool.
- `updatePoolHardcaps`: Update the hardcaps of a pool. Used to limit and manage market making activity on Vertex for scaling purposes. An alternative to pausing deposits too.
- `updateToken`: Update the Vertex product ID of a token address. Used when new tokens are supported on Vertex products.
