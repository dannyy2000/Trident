# Trident — Three-Layer Impermanent Loss Protection for Uniswap v4

> *A self-sustaining LP protection system that recaptures arb value, compensates Gamma risk, and builds an on-chain IL insurance reserve — all in one hook. Powered by Reactive Network.*

---

## Table of Contents

1. [The Problem](#the-problem)
2. [The Solution](#the-solution)
3. [Reactive Network Integration](#reactive-network-integration)
4. [The Self-Funding Flywheel](#the-self-funding-flywheel)
5. [Technical Architecture](#technical-architecture)
6. [Tech Stack](#tech-stack)
7. [Team](#team)

---

## The Problem

### What Is Impermanent Loss?

Impermanent Loss (IL) is the difference in value between depositing tokens into a Uniswap pool vs simply holding them. Three structural attacks compound it on every block.

### The Three Structural Attacks on LPs

#### Attack 1: The LVR Tax (Loss-Versus-Rebalancing)

Every time external market price moves, the pool price lags. Arb bots exploit the gap — buying from your pool at stale price, selling at true market price. That profit comes entirely from LP capital.

> *"A Uniswap pool needs to turnover 10% of its total liquidity in volume every single day for LP fees of 30 basis points to fully cover LVR losses."*
> — Milionis et al., 2022

#### Attack 2: The Blind Range Problem (Gamma Exposure)

Uniswap v3/v4 concentrated liquidity means IL spikes at range boundaries. The pool charges the same flat fee at $2,199 (one tick from maximum danger) as at $2,000 (safely in center). The fee structure is completely blind to Gamma.

> *"Impermanent loss is identified as the Gamma component of the associated self-financing trading strategy."*
> — Impermanent Loss in Uniswap v3, arXiv 2111.09192

#### Attack 3: JIT Liquidity and Fee Theft

JIT bots inject massive liquidity right before large swaps, steal ~85% of fees, then exit. Long-term LPs absorb all the IL but receive almost none of the fees on meaningful swaps.

> *"JIT liquidity dilutes regular LP shares by an average of 85%."*

---

## The Solution

### Trident Architecture Overview

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    TRIDENT HOOK SYSTEM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  LAYER 1: ARB DETECTOR
  ┌─────────────────────────────────────────────────────┐
  │  beforeSwap()                                       │
  │  Read oracle (Chainlink) → get real price           │
  │  Compare to pool sqrtPriceX96 → deviation %         │
  │  Large deviation = arb swap → RAISE FEE             │
  │  Zero deviation = retail swap → normal fee          │
  │  (Reactive pre-primes deviation for gas efficiency) │
  └─────────────────────────────────────────────────────┘
                          +
  LAYER 2: RANGE GUARDIAN
  ┌─────────────────────────────────────────────────────┐
  │  beforeSwap()                                       │
  │  Read current tick from slot0                       │
  │  Compute gamma score vs nearest boundary cluster    │
  │  gamma_score = 1e18 / (tickSpacingsAway + 1)        │
  │  High gamma = near boundary → ADD TO FEE            │
  │  (Reactive pre-primes boundary tick between swaps)  │
  └─────────────────────────────────────────────────────┘
                          ↓
  [Swap executes with combined dynamic fee]
                          ↓
  LAYER 3: IL RESERVE VAULT
  ┌─────────────────────────────────────────────────────┐
  │  afterSwap()                                        │
  │  Accrue 10–15% of elevated fee to pendingCapture    │
  │  afterAddLiquidity()                                │
  │  Record LP entry (tick, block, liquidity)           │
  │  beforeRemoveLiquidity()                            │
  │  Settle vault: IL × loyalty × health → payout to LP│
  └─────────────────────────────────────────────────────┘
                          ↓
  BETWEEN SWAPS — REACTIVE NETWORK
  ┌─────────────────────────────────────────────────────┐
  │  Monitors pool Swap events continuously             │
  │  Detects oracle deviation → primeDeviation()        │
  │  Detects boundary drift → primeBoundaryFee()        │
  │  Auto-adjusts vault capture rate via health         │
  │  Marks out-of-range LP positions                    │
  │  Flushes pending capture to vault                   │
  └─────────────────────────────────────────────────────┘

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Layer 1 — The Arb Detector

**Hook point:** `beforeSwap()`

The hook reads the Chainlink oracle price and the pool's current `sqrtPriceX96` from slot0. It converts pool price to a 1e18-normalised value using a per-pool `decimalAdjustment` constant, then calls `OracleReader.getDeviationBps(poolPrice)`.

When Reactive Network has pre-primed the deviation (gas-efficient cache), that value is used directly. Otherwise the hook queries the oracle in the swap path as a fallback.

```
oracle_price  = Chainlink ETH/USDC = $2,100
pool_price    = current sqrtPriceX96 → $2,000
deviation     = 5% = 500 bps

arb_premium   = 500 bps × 0.80 (ARB_AMPLIFIER) = 400 bps
final_fee     = 30 bps (base) + 400 bps = 430 bps
```

### Layer 2 — The Range Guardian

**Hook point:** `beforeSwap()` (additive with Layer 1)

The hook reads the current tick from `PoolManager.getSlot0()` and computes a gamma score against the nearest LP boundary tick primed by Reactive:

```
gamma_score = 1e18 / (tickSpacingsAway + 1)

boundary_premium = gamma_score × MAX_BOUNDARY_PREMIUM_BPS / 1e18
final_fee        = base + arb_premium + boundary_premium
```

### Layer 3 — The IL Reserve Vault

**Hook points:** `afterSwap()`, `afterAddLiquidity()`, `beforeRemoveLiquidity()`

- `afterSwap`: accrues `captureRateBps%` of fee to `_pendingCapture`. Reactive periodically calls `flushToVault()` to transfer to `ILReserveVault`.
- `afterAddLiquidity`: records LP entry state (entryTick, entryBlock, liquidity) in `ILReserveVault` and `PositionTracker`.
- `beforeRemoveLiquidity`: settles position — computes IL factor, applies loyalty factor and health ratio, pays out from vault.

```
payout = liquidity × IL_factor × loyalty_factor × health_ratio
       capped at MAX_SINGLE_CLAIM_PCT (10%) of vault
```

**Loyalty factor eliminates JIT:** A position held for 1 block gets loyalty ≈ 0. A 30-day LP gets loyalty = 1.0.

---

## Reactive Network Integration

Reactive Network is an event-driven execution layer. Reactive Contracts subscribe to on-chain events and execute autonomously in response — no bot, no off-chain server needed.

**What Reactive automates:**

1. **Oracle monitoring**: Reads Chainlink price after each Swap event, calls `primeDeviation(deviationBps)` on hook. Also detects Chainlink vs TWAP divergence → `setOracleManipulated(true)`.

2. **Boundary drift detection**: After each Swap, identifies nearest LP boundary cluster and calls `primeBoundaryFee(tick, gammaScore)`. Pre-computes GammaScorer result off-chain.

3. **Vault health management**: Monitors vault health ratio, calls `updateCaptureRate()` when thresholds are crossed.

4. **Out-of-range tracking**: When price exits an LP's range, calls `markOutOfRange(positionId, lp)` via ReactiveAdapter.

5. **Vault flush**: Calls `TridentHook.flushToVault(token)` periodically to sweep pending capture into the vault.

---

## The Self-Funding Flywheel

```
Arb bot exploits LP pool
        ↓
Trident detects oracle deviation (Layer 1)
        ↓
Arb bot pays elevated fee (arb premium captured)
        ↓
15% of elevated fee → IL Reserve Vault
        ↓
Vault grows during active/volatile periods
        ↓
Long-term LP withdraws → claims from vault
        ↓
LP receives fees + IL offset → better net return
        ↓
Better LP economics → more deep liquidity
        ↓
More volume → more arb → more vault funding
```

**The attack funds the defense.** No external token. No governance. No subsidy.

---

## Technical Architecture

### Smart Contract Structure

```
src/
  TridentHook.sol           — Main hook, all three layers
  ILReserveVault.sol        — Vault: deposit, IL calc, loyalty, payout
  OracleReader.sol          — Chainlink abstraction + TWAP manipulation guard
  GammaScorer.sol           — Tick-to-boundary proximity (gamma score)
  PositionTracker.sol       — LP entry state for Reactive out-of-range tracking
  ReactiveAdapter.sol       — Validates Reactive origin, forwards to hook
  interfaces/
    ITridentHook.sol
    IILReserveVault.sol
    IOracleReader.sol
    IReactiveCallback.sol
reactive/
  TridentReactive.sol       — Reactive smart contract (deployed on Reactive Network)
test/
  unit/                     — Per-contract unit + fuzz tests (132 tests)
  invariant/                — Vault solvency and no-money-printing invariants
  integration/              — Full swap lifecycle with mock PoolManager
script/
  Deploy.s.sol
  DeployReactive.s.sol
```

### Vault Mechanics

```
captureRate auto-adjustment:
  health > 0.8  → 10% (NORMAL)
  health < 0.8  → 15% (LOW)
  health < 0.3  → 20% (EMERGENCY)

IL factor:   min(|exitTick - entryTick| × 5e13, MAX_IL_FACTOR=50%)
Loyalty:     min(blocksHeld / 216000, 1.0)   [30 days = full loyalty]
Health cap:  min(reserve / liability, 1.0)    [overfunding ≠ >100% payout]
Max claim:   min(payout, reserve × 10%)       [no single-LP vault drain]
```

### Oracle Integration

- **Primary:** Chainlink AggregatorV3 — staleness guard, normalised to 1e18
- **Manipulation guard:** If Reactive detects Chainlink vs pool-TWAP divergence > 2%, `oracleManipulated` flag is set and fee is capped at 0.3%
- **Pyth Network:** Used by Reactive off-chain for sub-second price comparison (not called on-chain)

---

## Research Foundation

| Paper | Finding | Layer |
|---|---|---|
| Milionis et al. arXiv 2208.06046 | LVR dominant LP loss, oracle-aware fee implied fix | Layer 1 |
| Fritsch & Canidio arXiv 2404.05803 | Empirical: fees don't cover arb losses in most pools | Layer 1 |
| arXiv 2111.09192 | IL = Gamma component, spikes at range boundaries | Layer 2 |
| arXiv 2407.05146 | IL equivalent to short calls+puts, dynamic Gamma pricing required | Layer 2 |
| arXiv 2410.00854 | IL and LVR: spikes are dominant loss for long-term LPs | Layer 3 |
| arXiv 2502.04097 | Three regimes: smoothing reserve is structurally correct | Layer 3 |
| arXiv 2311.18164 | JIT dilutes regular LP fees 85%, $750B annual volume | Layer 3 Loyalty |
| AFT 2025 Dagstuhl | Time-weighted participation correct JIT counter-mechanism | Layer 3 Loyalty |

---

## Tech Stack

| Component | Technology |
|---|---|
| Smart contract language | Solidity ^0.8.26 |
| Development framework | Foundry |
| Uniswap v4 interface | v4-core, v4-periphery |
| Primary oracle | Chainlink Price Feeds |
| Secondary oracle | Pyth Network (via Reactive) |
| Cross-chain automation | Reactive Network |
| Target deployment | Unichain |
| Testing | Forge unit + fuzz + invariant |

---

## Team

**Daniel Akinsanya** — Builder, Uniswap Hook Incubator Alumni

Previous: PEGKEEPER — cross-chain stablecoin depeg protection hook using Reactive Network.

Contact: akinsanyadaniel665@gmail.com | GitHub: dannyy2000

---

*Built for UHI9 — Uniswap Hook Incubator Cohort 9 Hookathon*
*Theme: Impermanent Loss & Yield Systems | Partner: Reactive Network*
