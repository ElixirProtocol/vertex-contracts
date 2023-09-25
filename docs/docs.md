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
Liquidity for spot and perp pools can be deposited into the VertexManager smart contract by calling the `depositSpot` and `depositPerp` functions respectively. 

Every spot product is composed of two tokens, the base token and the quote token, which is usually USDC. For this reason, liquidity for a spot product has to be deposited in a balanced way, meaning that the amount of base and quote tokens have to be equal in value. To check this, product prices are fetched from the Vertex Clearinghouse smart contract by calling its `getPriceX18` function, which provides the price in 18 decimals for a given product. Therefore, users must call the `depositSpot` function passing a fixed base token amount and a range of quote token amounts to deposit. The function will then calculate the amount of quote tokens needed to perform a balanced deposit given the amount of base tokens. If this calculated amount of quote tokens is out of the given range, the function will revert due to slippage. On the other hand, the `depositPerp` function must be used to deposit liquidity into perp pools, which doesn't require balanced liquidity.

The only difference between the `depositSpot` and `depositPerp` functions are mainly the input parameters and the security checks, as they execute the same deposit logic by calling the `_deposit` private function.

The `depositSpot` flow is the following:

1. Check that deposits are not paused.
2. Check that the reentrancy guard is not active.
3. Check that the pool given is a spot one.
4. Check that the tokens given are two and that they are not duplicated.
5. Check that the receiver is not a zero address (for the good of the user).
6. Calculate amount of quote tokens and check for slippage.
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
   - Check if the token is supported for this pool.
   - Check if the token amount to deposit will exceed the liquidity hardcap of the token in this pool.
   - Transfer the tokens from the caller to the smart contract.
   - Build and send the deposit transaction to Vertex, redirecting the received tokens to the Elixir account (EOA, established a linked signer) via the VertexRouter smart contract assigned to this pool.
    * The Elixir linked signer allows the off-chain decentralized validator network to create market making requests on behalf of the Elixir smart contract.
   - Update the pool data and balances with the new amount.
2. Emit the `Deposit` event.

> Note: Only tokens with less or equal to 18 decimals are supported due to the nature of the Vertex smart contracts.

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

> Note: As pending balances are not stored sequentially, users are able to claim funds in any order as they arrive to the Elixir smart contract. This is expected behaviour and does not affect the user's funds as the Vertex sequencer will continue to fulfill withdraw requests, which can also be manually processed after days of inactivity by the Vertex sequencer.

### Reward Distribution (Pending)
By market-making (creating and filling orders on the Vertex order book), the Elixir validator network earns VRTX rewards. These rewards would be distributed to the users who deposited liquidity on the VertexManager smart contract, depending on the amount and time of their liquidity. Vertex hasn't implemented the functionality to claim rewards yet, but the Elixir smart contract is ready to support it thanks to its upgradeability. Until then, reward balances are stored off-chain and will be synchronized and distributed to users when the Vertex functionality to claim is available.

Learn more about the VRTX reward mechanism [here](https://vertex-protocol.gitbook.io/docs/community-token-and-dao/trading-rewards-detailed-mechanism).

## Example Lifecycle Journey

### Spot Product

- A user approves the VertexManager smart contract to spend their tokens.
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
- After the Vertex sequencer fulfills some withdraw requests and funds are available on the VertexManager contract, the user can call the `claim` function to claim their funds. Note that this step will most likely be performed by us (or any other third-party) on behalf of the user.

### Perpetual Product

- A user approves the VertexManager smart contract to spend their tokens.
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
- After the Vertex sequencer fulfills some withdraw requests and funds are available on the VertexManager contract, the user can call the `claim` function to claim their funds. Note that this step will most likely be performed by us (or any other third-party) on behalf of the user.

## Incident Response & Monitoring

The Elixir team is planning to protect the smart contracts with Chainalysis Incident Response (CIR) in the event of a hack or exploit. The benefits of CIR include:

- CIR helps deter hackers by letting them know a leading global crypto investigative team is on our side.
- With CIR, we can tap into Chainalysis’ expertise for complex blockchain analysis and investigations. The CIR team is ready to respond to cybersecurity breaches, ransomware attacks, recovery of stolen cryptocurrency, and perform other analyses involving blockchain data. The team consists of respected professional investigators, cybersecurity experts, and data engineers.
- Having a proactive solution in place decreases the time to respond and increases the likelihood of asset freezing and recovery or law enforcement should the worst happen.
- The ability to trace funds through various types of complex platforms is a crucial part of the CIR incident response and the ability to recover funds successfully. This applies to identified mixer platforms but also unidentified mixers and new bridging protocols between blockchains.
- Chainalysis has a huge customer base and, with it, a sizable network with personal connections to almost all significant exchanges and services in the crypto space. Also, their strong relationship with Law Enforcement Agencies around the world makes them very efficient in engaging the relevant entities when needed.
- In over 80% of all cases where an incident has occurred, Chainalysis investigators have been able to give our customers valuable information that leads to recovery of more than what their CIR fee was.

## Aspects

### Arithmetic

The codebase does not rely on complex arithmetic. Most of the arithmetic-related complexity is located in the `getBalancedAmount` and `getWithdrawFee` functions. However, fuzzing and invariant tests are applied to check for expected results and increase confidence in the arithmetic operations.

### Auditing

Throughout the codebase, events are emitted to maximize transparency and allow us or third-parties to monitor the smart contract. All state-modifying functions emit events with the necessary data. Additionally, the incident response and monitoring section explains how we monitor the smart contract and respond to incidents.

### Authentication / Access Control

Appropiate access controls are in place for all priviliged operations. The only privliged role in the smart contract is the owner, which is the Elixir 4/5 Multisig. As the Vertex protocol is completely upgradeable, the owner role is needed to perform operations and actions in case any aspect needs to be updated. The capabilities of the owner are the following:

- `pause`: Update the pause status of deposits, withdraws, and claims in case of malicious activity or incidents. Allows to pause each operation modularly; for example, pause deposits but allow withdrawals and claims.
- `addPool`: Adds a new pool. This deploys a new router for the pool, which is unique for this pool. The reason is that Vertex only allows one linked signer per smart contract, which goes against the singleton design of the Manager contract.
- `addPoolTokens`: Adds a new token to a pool.
- `updatePoolHardcaps`: Update the hardcaps of a pool. Used to limit and manage market making activity on Vertex for scaling purposes. An alternative to pausing deposits too.
- `updateToken`: Update the Vertex product ID of a token address. Used when new tokens are supported on Vertex products.
- `updateSlowModeFee`: Update the slow mode fee in case the Vertex sequencer fee changes. Denominated on the `paymentToken`.

### Complexity Management

The codebase is broken down into appropriate components, and the logic is straightforward to understand relative to what the code does. The code is overall well documented through NatSpec comments and in-line comments. The codebase also contains a single, smart contract with a singleton architecture approach, minimizing complexity compared to a factory-based approach.

### Decentralization

Privileged operations go through a 4/5 multi-signature wallet composed of active core members of the Elixir team. Due to this, emergencies and operations can be addressed quickly and safely. There are plans to decentralize the owner role by building a smart contract on top of the VertexManager to support different roles for each type of operation and task, which can be further improved with a DAO governance structure -- in this case, the owner role would be transferred from the multi-sig to this role-based smart contract.

### Documentation

Thorough user and developer documentation can be found in this document and throughout the codebase. Information like diagrams, formulas, system parameters, privileged roles, and more can also be found here.

### Front-running Resistance

The Arbitrum network provides strong MEV and front-running protection, yet the smart contract is equipped with a series of protective measures against such types of attacks. The initialization of the smart contract is executed in robust deployment scripts that protect against front-running. Additionally, as explained in previous sections, the smart contract provides a completely flexible approach to pending balances, allowing users to claim their funds in any order as they arrive at the smart contract. For balanced deposits, slippage protection is also in place.

### Low-level manipulation

The codebase does not include any in-line assembly or dangerous low-level calls. Moreover, supported tokens must be ERC20-compliant.

### Testing and Verification

The protocol benefits from in-depth Foundry-based testing of arithmetic operations and functions through fuzzing, and invariant testing. Real-world end-to-end testing was also conducted in the Arbitrum Goerli testnet over several weeks. Tools like OpenZeppelin Code App, Slither, and Echidna were used to analyze and test the codebase.
