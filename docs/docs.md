# Elixir <> Vertex Documentation

Overview of Elixir's smart contract architecture integrating to Vertex Protocol.

## Table of Contents

- [Background](#background)
- [Overview](#overview)
- [Sequence of Events](#sequence-of-events)
- [Lifecycle](#lifecycle)
- [Known Limitations And Workarounds](#known-limitations-and-workarounds)
- [Aspects](#aspects)

## Background

Elixir is building the industry's decentralized, algorithmic market making protocol. The protocol algorithmically deploys supplied liquidity on the orderbooks, utilizing the orderbook equivalent of x*y=k curves to build up liquidity and tighten the bid/ask spread. ​Elixir is fully composable: enabling decentralized exchanges (DEXs) to natively integrate Elixir into their core infrastructure to unlock retail liquidity for algorithmic market making. The protocol serves as crucial decentralized infrastructure allowing for exchanges and protocols to easily bootstrap liquidity to their books. It also enables crypto projects to incentivize liquidity to their centralized exchange pairs via LP tokens.

This set of smart contracts power the first native integration of Elixir into Vertex Protocol, a cross-margined DEX protocol offering spot, perpetuals, and an integrated money market bundled into one vertically integrated application on Arbitrum. Vertex is powered by a hybrid unified central limit order book (CLOB) and integrated automated market maker (AMM), whose liquidity is augmented as positions from pairwise LP markets populate the orderbook. Gas fees and MEV are minimized on Vertex due to the batched transaction and optimistic rollup model of the underlying Arbitrum layer two (L2), where Vertex’s smart contracts control the risk engine and core products.

For this integration, the most important aspect about Vertex Protocol to understand is their orderbook, a centralized “sequencer” that operates as an off-chain node layered on top of their smart contracts and contained within the Arbitrum protocol layer. Due to this nature of the underlying integration, the Elixir smart contracts have a series of unique features and functions that allow to build on top of it.

More information:
- [Elixir Protocol Documentation](https://docs.elixir.finance/)
- [Vertex Protocol Dcoumentation](https://vertex-protocol.gitbook.io/docs/)

## Overview

## Sequence of Events

## Example Lifecycle Journey

## Known Limitations and Workarounds

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

