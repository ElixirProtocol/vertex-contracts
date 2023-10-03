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

This integration comprises two Elixir smart contracts a singleton (VertexManager) and a router (VertexRouter). VertexManager allows users to deposit and withdraw liquidity for spot and perpetual (perp) products on Vertex. By depositing liquidity, users earn VRTX rewards from the market-making done by the Elixir validator network off-chain. Rewards, denominated in the VRTX token, are distributed via epochs lasting 28 days and serve as the sustainability of the APRs. On the VertexManager smart contract, each Vertex product is associated with a pool structure, which contains a type and router (VertexRouter), plus a nested mapping containing the data of supported tokens in that pool. On the other hand, VertexRouter allows to have one linked signer per VertexManager pool — linked signers allow the off-chain Elixir network to market make across different product and balances on behalf of the pool. Regarding Vertex, the Elixir smart contract interacts mainly with the Endpoint and Clearinghouse smart contracts.

- [VertexManager](src/VertexManager.sol): Elixir smart contract to deposit, withdraw, claim and manage product pools.
- [VertexRouter](src/VertexRouter.sol): Elixir smart contract to route slow-mode transactions to Vertex, on behalf of a VertexManager pool.
- [Endpoint](https://github.com/vertex-protocol/vertex-contracts/blob/main/contracts/Endpoint.sol): Vertex smart contract that serves as the entry point for all actions and interactions with their protocol.
- [Clearinghouse](https://github.com/vertex-protocol/vertex-contracts/blob/main/contracts/Clearinghouse.sol): Vertex smart contract that serves as the clearinghouse for all trades and positions, storing the liquidity (TVL) of their protocol. Only used in VertexManager initialization to fetch the fee token address.

## Sequence of Events

### Deposit Liquidity
Liquidity for spot and perp pools can be deposited into the VertexManager smart contract by calling the `depositSpot` and `depositPerp` functions, respectively. 

Every spot product is composed of two tokens, the base token and the quote token, which is usually USDC. For this reason, liquidity for a spot product has to be deposited in a balanced way, meaning that the amount of base and quote tokens have to be equal in value. To check this, product prices are fetched from the Vertex Clearinghouse smart contract by calling its `getPriceX18` function, which provides the price in 18 decimals for a given product. Therefore, users must call the `depositSpot` function, passing a fixed base token amount and a range of quote token amounts to deposit. The function will then calculate the amount of quote tokens needed to perform a balanced deposit given the base token amount. If this calculated quote token amount is out of the given range, the function will revert due to slippage. On the other hand, the `depositPerp` function must be used to deposit liquidity into perp pools, which doesn't require balanced liquidity.

The only difference between the `depositSpot` and `depositPerp` functions are the input parameters and the security checks, as they execute the same deposit logic by calling the `_deposit` private function.

The `depositSpot` flow is the following:

1. Check that deposits are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool given is a spot one.
4. Check that the tokens given are two and are not duplicated.
5. Check that the receiver is not a zero address (for the good of the user).
6. Calculate the amount of quote tokens and check for slippage.
7. Execute the deposit logic.

And the `depositPerp` flow is the following:

1. Check that deposits are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool given is a perp one.
4. Check that the tokens given are not empty and that the amounts given match the amount of tokens.
5. Check that the receiver is not a zero address (for the good of the user).
7. Execute the deposit logic.

In any case, the flow of the deposit logic is the following:

1. Loop over the amounts given to fetch the respective tokens and redirect liquidity to Vertex.
   - Skip zero amounts.
   - Fetch the token address by using the index of the amount in the amounts array and get the data of the token in the pool.
   - Check that the token is supported for this pool.
   - Check that the token amount to deposit will exceed the liquidity hardcap of the token in this pool.
   - Transfer the tokens from the caller to the smart contract.
   - Build and send the deposit transaction to Vertex, redirecting the received tokens to the Elixir account (EOA, established a linked signer) via the VertexRouter smart contract assigned to this pool.
    * The Elixir linked signer allows the off-chain decentralized validator network to create market making requests on behalf of the Elixir smart contract.
   - Update the pool data and balances with the new amount.
2. Emit the `Deposit` event.

> Note: Only tokens with less or equal to 18 decimals are supported due to the nature of the Vertex smart contracts.

### Withdraw Liquidity
Due to the nature of Vertex, withdrawing funds requires a two-step process. First, the liquidity has to be withdrawn from Vertex to the pool's VertexRouter smart contract, which has to be approved by the Vertex sequencer, charging a fee of 1 USDC. Second, the liquidity has to "manually" be claimed via the `claim` function on the Elixir VertexManager smart contract, as no Vertex callback is available. Anyone can call this function on behalf of any address, allowing us to monitor pending claims and process them for users. When calling the `claim` function, the VertexManger smart contract will transfer the liquidity from the pool's VertexRouter into the VertexManager smart contract, which is then transferred to the user.

Similarly to deposits, withdrawals on a spot product have to be balanced. The VertexManager smart contract provides the `withdrawSpot` function for spot pools and the `withdrawPerp` function for perp pools. 

The `withdrawSpot` flow is the following:

1. Check that withdrawals are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool given is a spot one.
4. Check that the fee index is not bigger than the length of the token array.
5. Check that the tokens given are two and that they are not duplicated.
6. Get the amount of quote tokens to withdraw.
7. Execute the withdraw logic.

And the `withdrawPerp` flow is the following:

1. Check that withdrawals are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool given is a perp one.
4. Check that the tokens given are not empty and that the amounts given match the amount of tokens.
5. Check that the fee index is not bigger than the length of the token array.
6. Execute the withdraw logic.

In any case, the flow of the `withdraw` function is the following:

1. Get the balance of the pool in Vertex.
2. Loop over the amounts given to create and send the respective withdrawal requests to Vertex.
   - Skip zero amounts if not the token for fee payment.
   - Fetch the token address by using the index of the amount in the amounts array and the array of supported tokens in the pool.
   - Check that the token is supported for this pool.
   - Calculate how much of the Vertex balance the user should receive based on the given input amount to withdraw (similar to share-based logic).
   - Subtract the amount of tokens given from the user's balance on the pool data. Reverts if the user does not have enough balance.
   - Check if the loop iteration number matches the fee index, which represents what token to use to pay the Vertex sequencer fee.
    * If they match, the smart contract calculates the token amount equivalent to 1 USDC. 
    * This amount is added to the fee balance of Elixir as it will pay the sequencer fee of 1 USDC on behalf of the user. Elixir is automatically reimbursed with user claims, but it can also reimburse itself by calling the `claim` function on behalf of a user.
    * The fee amount is then subtracted from the calculated token amount to withdraw and stored as the pending balance for claims afterward.
   - Build and send the withdrawal request to Vertex.
3. Emit the `Withdraw` event.

> Note: It's vital for the VertexManager smart contract to maintain the invariant of: "each pool must have a unique pool" or "two pools cannot share the same router." Otherwise, a pool with a wrong router will lead to loss of funds during withdrawals because of an inflated balance of the pools. By nature of the current logic, it's impossible for the invariant to break, as changing a pool's router is not supported.

### Claim Liquidity
After the Vertex sequencer fulfills a withdrawal request, the funds will be available to claim on the VertexManager smart contract by calling the `claim` function. This function can be called by anyone on behalf of a user, allowing us to monitor the pending claims and process them for users. The flow of the `claim` function is the following:

1. Check that claims are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool is valid (i.e., it exists).
4. Check that the tokens given to claim are not empty.
5. Check that the user given to claim for is not the zero address.
6. Loop over the list of tokens given.
   - Fetch and store the pending balance of the user for the token in the iteration.
   - Fetch and store the Elixir reimburse fee of the user and the token in the iteration.
   - Reset the pending balance and fee to 0.
   - Transfer the token amount to the user.
   - Transfer the fee amount to the owner (Elixir).
7. Emit the `Claim` event.

> Note: As pending balances are not stored sequentially, users are able to claim funds in any order as they arrive at the VertexRouter smart contract. This is expected behavior and does not affect the user's funds as the Vertex sequencer will continue to fulfill withdrawal requests, which can also be manually processed after days of inactivity by the Vertex sequencer.

### Reward Distribution (Pending)
By market-making (creating and filling orders on the Vertex order book), the Elixir validator network earns VRTX rewards. These rewards would be distributed to the users who deposited liquidity on the VertexManager smart contract, depending on the amount and time of their liquidity. Vertex hasn't implemented the functionality to claim rewards yet, but the Elixir smart contract is ready to support it thanks to its upgradeability. Until then, reward balances are stored off-chain and will be synchronized and distributed to users when the Vertex functionality to claim is available.

Learn more about the VRTX reward mechanism [here](https://vertex-protocol.gitbook.io/docs/community-token-and-dao/trading-rewards-detailed-mechanism).

## Example Lifecycle Journey

### Spot Product

- A user approves the VertexManager smart contract to spend their tokens.
- User calls `depositSpot` and passes the following parameters:
   * `id`: The ID of the pool to deposit to.
   * `tokens`: The list of tokens to deposit.
   * `amount0`: The amount of base tokens.
   * `amount1Low`: The low limit of the quote amount.
   * `amount1High`: The high limit of the quote amount.
   * `receiver`: The receiver of the virtual LP balance.
- Calculates the balanced amount of quote tokens (`amount1`) needed for the deposit given the amount of base tokens (`amount0`). If the calculated amount of quote tokens is out of the given range (`amount1Low` <> `amount1High`), the function reverts due to slippage.
- The function builds the amounts array and executes the deposit logic by calling the `_deposit` function.
- The `_deposit` redirects liquidity to Vertex and updates the balances.
- The Elixir network of decentralized validators receives the liquidity and starts to market make using it, generating VRTX rewards for the user.
- After some time, the user (i.e., receiver) calls the `withdrawSpot` function to withdraw liquidity and passes the following parameters:
   * `id`: The ID of the pool to withdraw from.
   * `tokens`: The list of tokens to withdraw.
   * `amount0`: The amount of base tokens to withdraw.
   * `feeIndex`: As explained in the withdraw section, this represents what token to use to pay the Vertex sequencer fee, reimbursing Elixir.
- This function performs checks and calls the `_withdraw` function to execute the withdraw logic.
- The `_withdraw` sends the withdrawal requests to Vertex.
- After the Vertex sequencer fulfills some withdrawal requests and funds are available on the VertexManager contract, the user can call the `claim` function to claim their funds. Note that this step will most likely be performed by us (or any other third party) on behalf of the user.

### Perpetual Product

- A user approves the VertexManager smart contract to spend their tokens.
- User calls `depositPerp` and passes the following parameters:
   * `id`: The ID of the pool to deposit to.
   * `tokens`: The list of tokens to deposit.
   * `amounts`: The list of token amounts to deposit.
   * `receiver`: The receiver of the virtual LP balance.
- The `depositPerp` function performs a series of checks and executes the deposit logic by calling the `_deposit` function.
- The `_deposit` redirects liquidity to Vertex and updates the balances.
- The Elixir network of decentralized validators receives the liquidity and starts to market make using it, generating VRTX rewards for the user.
- After some time, the user (i.e., receiver) calls the `withdrawPerp` function to withdraw liquidity and passes the following parameters:
   * `id`: The ID of the pool to withdraw from.
   * `tokens`: The list of tokens to withdraw.
   * `amounts`: The list of token amounts to withdraw.
   * `feeIndex`: As explained in the withdraw section, this represents what token to use to pay the Vertex sequencer fee, reimbursing Elixir.
- This function performs checks and calls the `_withdraw` function to execute the withdraw logic.
- The `_withdraw` sends the withdrawal requests to Vertex.
- After the Vertex sequencer fulfills some withdrawal requests and funds are available on the VertexManager contract, the user can call the `claim` function to claim their funds. Note that this step will most likely be performed by us (or any other third party) on behalf of the user.

## Incident Response & Monitoring

The Elixir team is planning to protect the smart contracts with Chainalysis Incident Response (CIR) in the event of a hack or exploit. The benefits of CIR include:

- CIR helps deter hackers by letting them know a leading global crypto investigative team is on our side.
- With CIR, we can tap into Chainalysis’ expertise for complex blockchain analysis and investigations. The CIR team is ready to respond to cybersecurity breaches, ransomware attacks, recovery of stolen cryptocurrency, and perform other analyses involving blockchain data. The team consists of respected professional investigators, cybersecurity experts, and data engineers.
- Having a proactive solution in place decreases the time to respond and increases the likelihood of asset freezing and recovery or law enforcement should the worst happen.
- The ability to trace funds through various types of complex platforms is a crucial part of the CIR incident response and the ability to recover funds successfully. This applies to identified mixer platforms but also unidentified mixers and new bridging protocols between blockchains.
- Chainalysis has a huge customer base and, with it, a sizable network with personal connections to almost all significant exchanges and services in the crypto space. Also, their strong relationship with Law Enforcement Agencies around the world makes them very efficient in engaging the relevant entities when needed.
- In over 80% of all cases where an incident has occurred, Chainalysis investigators have been able to give our customers valuable information that leads to recovery of more than what their CIR fee was.

## General Aspects

### Oracle

The VertexManager smart contract relies on Vertex as an oracle to get the price of assets to perform certain calculations such as fee calculations or amount of assets in balanced deposits. The prices are not used for any critical aspect of the protocol functionality.

### Vertex Integration

The `getVertexBalance` function is a key function for the operation of the Elixir pools. It is responsible for accurately calculating the pool's current balance in Vertex so that users' withdrawals are performed correctly. If there are any rare trading losses when market making, this function allows to adjust the withdrawal amounts by using the balances as shares of the Vertex balance. Because Vertex does not offer an updated state of an account when there are transactions affecting them inside the sequencer queue, the protocol works around this by querying the Vertex queue and calculating the updated balance itself. Specifically, it only checks for deposit and withdrawal transactions from the given VertexRouter, the only type of transaction that changes the Vertex balance and can be executed by the VertexManager.

### Authentication / Access Control

Appropiate access controls are in place for all priviliged operations. The only privliged role in the smart contract is the owner, which is the Elixir 4/5 Multisig. As the Vertex protocol is completely upgradeable, the owner role is needed to perform operations and actions in case any aspect needs to be updated. The capabilities of the owner are the following:

- `pause`: Update the pause status of deposits, withdraws, and claims in case of malicious activity or incidents. Allows to pause each operation modularly; for example, pause deposits but allow withdrawals and claims.
- `addPool`: Adds a new pool. This deploys a new router for the pool, which is unique for this pool. The reason is that Vertex only allows one linked signer per smart contract, which goes against the singleton design of the Manager contract.
- `addPoolTokens`: Adds a new token to a pool.
- `updatePoolHardcaps`: Update the hardcaps of a pool. Used to limit and manage market making activity on Vertex for scaling purposes. An alternative to pausing deposits too.
- `updateToken`: Update the Vertex product ID of a token address. Used when new tokens are supported on Vertex products.
- `updateSlowModeFee`: Update the slow mode fee in case the Vertex sequencer fee changes. Denominated on the `paymentToken`. It's capped to a maximum fee of 100 USDC.
