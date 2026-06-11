# Trident — Three-Layer Impermanent Loss Protection for Uniswap v4

> *A self-sustaining LP protection system that recaptures arb value, compensates Gamma risk, and builds an on-chain IL insurance reserve — all in one hook. Powered by Reactive Network.*

![Solidity](https://img.shields.io/badge/Solidity-0.8.26-blue?logo=solidity)
![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange)
![Tests](https://img.shields.io/badge/Tests-146%20passing-brightgreen)
![License](https://img.shields.io/badge/License-MIT-green)
![Uniswap v4](https://img.shields.io/badge/Uniswap-v4%20Hook-pink)
![Reactive Network](https://img.shields.io/badge/Powered%20by-Reactive%20Network-purple)

---

## Table of Contents

1. [The Problem](#the-problem)
   - [What Is a Liquidity Provider?](#what-is-a-liquidity-provider)
   - [What Is Impermanent Loss?](#what-is-impermanent-loss)
   - [The Three Structural Attacks on LPs](#the-three-structural-attacks-on-lps)
   - [Why Uniswap v3 Cannot Fix This](#why-uniswap-v3-cannot-fix-this)
2. [The Solution](#the-solution)
   - [What Is a Uniswap v4 Hook?](#what-is-a-uniswap-v4-hook)
   - [Trident Architecture Overview](#trident-architecture-overview)
   - [Layer 1 — The Arb Detector](#layer-1--the-arb-detector)
   - [Layer 2 — The Range Guardian](#layer-2--the-range-guardian)
   - [Layer 3 — The IL Reserve Vault](#layer-3--the-il-reserve-vault)
3. [Reactive Network Integration](#reactive-network-integration)
4. [The Self-Funding Flywheel](#the-self-funding-flywheel)
5. [Research Foundation](#research-foundation)
6. [Competitive Landscape](#competitive-landscape)
7. [Hookathon Theme Alignment](#hookathon-theme-alignment)
8. [Technical Architecture](#technical-architecture)
9. [Getting Started](#getting-started)
10. [Tech Stack](#tech-stack)
11. [Team](#team)

---

## The Problem

### What Is a Liquidity Provider?

Uniswap is an Automated Market Maker (AMM). Instead of a traditional order book, it uses liquidity pools — smart contracts holding two tokens — and the formula `x * y = k` to set prices automatically. **Liquidity Providers (LPs)** deposit both tokens and earn swap fees. Sounds like passive income. In practice, three structural attacks silently drain LP capital on every block.

---

### What Is Impermanent Loss?

Impermanent Loss (IL) is the difference in value between:
- **Strategy A:** Depositing your tokens into a Uniswap pool
- **Strategy B:** Simply holding those same tokens in your wallet

When price moves, an LP ends up with less total value than if they had just held. The pool's pricing formula automatically sells the appreciating token and buys the depreciating one — the opposite of what a rational holder would do.

**Example:**
- You deposit 1 ETH ($2,000) + 2,000 USDC = $4,000 total
- ETH pumps to $4,000 on Binance/Coinbase
- Your Uniswap pool still prices ETH at $2,000 (stale)
- An arb bot buys your ETH at $2,000, sells it at $4,000 on Binance
- Your pool now holds less ETH and more USDC
- If you withdraw, you receive less total value than if you had just held

That difference is Impermanent Loss. It is not accidental. It is structural. It happens every time the market moves.

---

### The Three Structural Attacks on LPs

#### Attack 1: The LVR Tax (Loss-Versus-Rebalancing)

Every time the external market price moves — on Binance, Coinbase, anywhere — your Uniswap pool price lags behind. Arbitrage bots are watching this gap 24/7. The moment a gap opens, they fire a transaction — buying from your pool at the stale price, selling on the real market at the true price, pocketing the difference. **That profit came entirely from LP capital.**

This is called **Loss-Versus-Rebalancing (LVR)** — formalized in the landmark 2022 paper by Milionis, Moallemi, Roughgarden, and Zhang.

> *"A Uniswap pool needs to turnover 10% of its total liquidity in volume every single day for LP fees of 30 basis points to fully cover LVR losses."*
> — [Milionis et al., 2022](https://arxiv.org/abs/2208.06046)

The 2024 empirical study by Fritsch & Canidio confirmed across the **largest** Uniswap pools:

> *"Fees do not sufficiently compensate for arbitrage losses across many of the largest AMM liquidity pools on Uniswap."*
> — [Fritsch & Canidio, 2024](https://arxiv.org/pdf/2404.05803)

Arb bots have structural advantages LPs can never individually overcome: co-location with validators, private mempools via Flashbots, atomic bundling, flash loan capital, and real-time CEX feeds. **Every single time the market moves, the first transaction in the next block is an arb extracting value from LPs. Not sometimes. Every time. Structurally guaranteed.**

---

#### Attack 2: The Blind Range Problem (Gamma Exposure)

Uniswap v3 and v4 introduced **concentrated liquidity** — LPs choose a price range and only provide liquidity within that range. The hidden cost: **Impermanent Loss is not evenly distributed across the range. It spikes at the boundaries.**

This is a well-established finding from options theory. LP positions are mathematically equivalent to being **short gamma** — selling volatility insurance:

> *"The mechanism behind impermanent loss is similar to being short a portfolio of call and put options — allowing application of financial engineering methods from derivative securities valuation."*
> — [Unified Approach for Hedging Impermanent Loss, arXiv 2407.05146](https://arxiv.org/html/2407.05146v1)

> *"Impermanent loss is identified as the Gamma component of the associated self-financing trading strategy."*
> — [Impermanent Loss in Uniswap v3, arXiv 2111.09192](https://arxiv.org/abs/2111.09192)

**What Gamma means in practice:**
- At the **center of your range** ($2,000 in a $1,800–$2,200 range): Gamma is moderate. Risk is manageable.
- When price approaches the **edge** ($2,199 approaching the $2,200 upper boundary): Gamma is at maximum. The AMM is rapidly converting your position toward 100% of the weaker token.
- When price **crosses the boundary**: You earn zero fees. You hold 100% of the depreciating asset with no income to offset it.

The Uniswap pool charges the **same flat fee** at $2,199 (one tick from maximum danger) as it does at $2,000 (safely centered). The pool has no awareness of where the real risk is concentrated. **LPs are not compensated more when they are in the most danger.**

---

#### Attack 3: JIT Liquidity and Fee Theft

**Just-In-Time (JIT) liquidity** is an MEV strategy where a bot:
1. Watches the public mempool for a large incoming swap
2. Injects massive liquidity into the exact tick range right before the swap
3. The swap executes — the bot's liquidity dilutes fees for all regular LPs
4. The bot removes its liquidity immediately after — held for ~12 seconds
5. The bot took no IL risk whatsoever and extracted the majority of the fee

> *"JIT liquidity dilutes regular LP shares by an average of 85%."*

> *"JIT additions can account for 80–90% of liquidity available in the active tick during a single block."*

> *"JIT liquidity has generated $750 billion in liquidity event volume on Uniswap v3 in a single year."*

> *"The Paradox of Just-in-Time Liquidity: More Providers Can Lead to Less Liquidity — JIT strategy decreases regular LP returns by diluting fees accrued for a block regardless of whether JIT liquidity itself is profitable."*
> — [arXiv 2311.18164](https://arxiv.org/html/2311.18164v2)

Long-term LPs who provide the deep, stable liquidity that makes Uniswap useful are punished the most. They sit through volatile periods absorbing IL while JIT bots steal their fees on every meaningful swap.

---

#### The Compounding Effect

All three attacks compound simultaneously:

```
Regular LP experience today:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Week 1-3:   Earning small fees slowly
            Arb bots draining on every price move (invisible)

Volatile Friday:
            IL spikes in hours
            Arb bots run dozens of extractions
            JIT bots steal fees on the big swaps
            Net result: weeks of fee income wiped out

Withdrawal:
            LP receives less than deposited
            Cannot identify why — no single moment to point to
            Just a slow invisible drain from three directions
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

> *"Three relevant regimes exist: very short times where IL and LVR are identical, intermediate times where they show distinct distribution functions, and long time behavior where both differ significantly — with spikes being the dominant loss mechanism for long-term LPs."*
> — [Impermanent Loss and LVR II, arXiv 2502.04097](https://arxiv.org/pdf/2502.04097)

---

### Why Uniswap v3 Cannot Fix This

In Uniswap v3, every pool has a **fixed fee** set once at creation. The pool is an immutable contract with no programmable logic during swap execution. It cannot:

- Read an oracle to detect arb swaps vs retail swaps
- Know where the current price sits relative to LP range boundaries
- Adjust fees based on any real-time signal
- Route fee revenue to a reserve or insurance mechanism
- Distinguish between a JIT provider and a long-term LP

Every swap is treated identically regardless of who is swapping, why they are swapping, and how much risk that swap is imposing on LPs. **This is a fundamental architectural constraint — not a bug, but the limits of the v3 design.**

---

## The Solution

### What Is a Uniswap v4 Hook?

Uniswap v4 introduced **Hooks** — external smart contracts that attach to pools and execute custom logic at specific moments in the pool lifecycle. The critical capability: in `beforeSwap`, your hook can **override the fee for that specific swap**. The pool pauses, asks your hook "what fee should this swap pay?", your hook runs arbitrary logic to compute the answer, and the swap executes with your custom fee.

This is the architectural change that makes Trident possible. Nothing like this exists in v3.

---

### Trident Architecture Overview

Trident is a three-layer protection system built as a single Uniswap v4 hook, automated end-to-end by Reactive Network.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    TRIDENT HOOK SYSTEM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  LAYER 1: ARB DETECTOR
  ┌─────────────────────────────────────────────────────┐
  │  beforeSwap()                                       │
  │  Read oracle (Chainlink) → get real price           │
  │  Compare to pool sqrtPriceX96 → calculate deviation │
  │  Large deviation = arb swap → RAISE FEE             │
  │  Zero deviation = retail swap → normal fee          │
  │  Reactive pre-primes deviation for gas efficiency   │
  └─────────────────────────────────────────────────────┘
                          +
  LAYER 2: RANGE GUARDIAN
  ┌─────────────────────────────────────────────────────┐
  │  beforeSwap()                                       │
  │  Read current tick from slot0                       │
  │  gamma_score = 1e18 / (tickSpacingsAway + 1)        │
  │  High gamma = near LP boundary → ADD TO FEE         │
  │  Reactive pre-primes boundary tick between swaps    │
  └─────────────────────────────────────────────────────┘
                          ↓
  [Swap executes with combined dynamic fee]
                          ↓
  LAYER 3: IL RESERVE VAULT
  ┌─────────────────────────────────────────────────────┐
  │  afterSwap()  → Accrue 10–15% of fee to capture     │
  │  afterAddLiquidity() → Record LP entry state        │
  │  beforeRemoveLiquidity() → Settle: pay IL offset    │
  │  payout = liquidity × IL × loyalty × health         │
  └─────────────────────────────────────────────────────┘
                          ↓
  BETWEEN SWAPS — REACTIVE NETWORK
  ┌─────────────────────────────────────────────────────┐
  │  Monitors pool Swap events continuously             │
  │  Reads Chainlink → primeDeviation() on hook         │
  │  Detects boundary drift → primeBoundaryFee()        │
  │  Monitors vault health → adjusts capture rate       │
  │  Tracks out-of-range LP positions                   │
  │  Flushes pending capture → vault                    │
  └─────────────────────────────────────────────────────┘
                          ↓
  WHEN LP WITHDRAWS
  ┌─────────────────────────────────────────────────────┐
  │  beforeRemoveLiquidity()                            │
  │  Calculate IL suffered (entry tick vs exit tick)    │
  │  Apply loyalty factor (time held / 30 days)         │
  │  Apply vault health ratio                           │
  │  Cap at 10% of vault (no single-LP drain)           │
  │  LP receives: accrued fees + IL offset from vault   │
  └─────────────────────────────────────────────────────┘

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### Layer 1 — The Arb Detector

**Hook point:** `beforeSwap()`

The hook reads the pool's `sqrtPriceX96` from `PoolManager.getSlot0()`, converts it to a 1e18-normalised price using a per-pool `decimalAdjustment` constant (e.g. `1e30` for WETH/USDC), then calls `OracleReader.getDeviationBps(poolPrice)`.

When Reactive Network has pre-primed the deviation value (gas-efficient cache), it is used directly. Otherwise the hook queries the oracle in the swap path as a fallback.

```
oracle_price  = Chainlink ETH/USDC = $2,100
pool_price    = current sqrtPriceX96 → $2,000
deviation     = |2100 - 2000| / 2000 = 5% = 500 bps

arb_premium   = 500 bps × ARB_AMPLIFIER (0.8) = 400 bps
final_fee     = 30 bps (base) + 400 bps = 430 bps
```

The arb bot still executes — price correction is necessary for market efficiency. But now LPs are compensated for the value being extracted from their position. **The arb premium is funded entirely by the arb profit that previously left the pool for free.**

**What this kills:** LVR Tax.

---

### Layer 2 — The Range Guardian

**Hook point:** `beforeSwap()` (additive with Layer 1)

The hook reads the current tick from `slot0` and computes a **gamma score** — a measure of how close the current price is to the nearest LP range boundary:

```
gamma_score = 1e18 / (tickSpacingsAway + 1)

At boundary (0 spacings away) → 1e18  (100% — maximum danger)
1 spacing away                 → 5e17  (50%)
10 spacings away               → ~9%
Far from boundary              → ~0
```

Normalising by `tickSpacing` ensures the score is comparable across all fee tiers (0.05% pool vs 0.30% pool vs 1% pool).

```
boundary_premium = gamma_score × MAX_BOUNDARY_PREMIUM_BPS / 1e18
final_fee        = base + arb_premium + boundary_premium
```

**What this kills:** The Blind Range Problem. For the first time, the pool is not blind to where LP risk is concentrated.

---

### Layer 3 — The IL Reserve Vault

**Hook points:** `afterSwap()`, `afterAddLiquidity()`, `beforeRemoveLiquidity()`

**Building the reserve:**
After every swap, the hook accrues `captureRateBps%` (10–20%) of the fee to `_pendingCapture`. Reactive periodically calls `flushToVault(token)` to sweep this into `ILReserveVault`. The vault accumulates across every swap — fastest during volatile periods when arb premiums are highest and LPs need protection most.

**Tracking LP positions:**
When liquidity is added, the hook records: entry tick, entry block number, liquidity amount.

**Paying out at withdrawal:**
```
1. IL factor     = min(|exitTick - entryTick| × 5e13,  50%)
2. Loyalty       = min(blocksHeld / 216000,             1.0)   [30 days target]
3. Health ratio  = min(reserve / totalLiability,        1.0)
4. Raw claim     = liquidity × IL_factor × loyalty × health
5. Final payout  = min(raw_claim, vault_balance × 10%)
```

**Loyalty factor eliminates JIT:** A position held for 1 block gets loyalty ≈ 0. A 30-day LP gets loyalty = 1.0. JIT providers who held for 12 seconds receive zero vault payout.

**Vault health auto-adjusts capture rate:**
```
health > 0.8  → 10% capture rate  (healthy)
health < 0.8  → 15% capture rate  (rebuilding)
health < 0.3  → 20% capture rate  (emergency rebuild)
```

**What this kills:** The timing mismatch between fee trickle and IL spikes. JIT fee theft.

---

## Reactive Network Integration

Reactive Network is an **event-driven execution layer**. Reactive Contracts subscribe to on-chain events across any blockchain and execute autonomously in response — no user, no bot, no off-chain server needed.

### Why Reactive Is Essential Here

The Trident hook fires **during swaps**. But LP protection requires intelligence and actions **between swaps** as well:

- What if price is drifting toward range boundaries but no swap is happening?
- What if the vault has accumulated enough to flush but no LP has withdrawn?
- What if an LP's position just crossed the boundary into zero-fee territory at 3am?
- What if vault health is dropping and the capture rate needs adjustment?

The hook is passive between swaps. **Reactive Network is the always-on monitoring and automation layer that makes Trident a complete system.**

### What Reactive Automates

| Action | Trigger | Hook Callback |
|---|---|---|
| Oracle deviation update | After every Swap event | `primeDeviation(deviationBps)` |
| Boundary fee prime | Price nears LP cluster | `primeBoundaryFee(tick, gammaScore)` |
| Oracle manipulation guard | Chainlink vs TWAP divergence > 2% | `setOracleManipulated(true/false)` |
| Out-of-range LP tracking | Price exits LP's range | `markOutOfRange(positionId, lp)` |
| Vault capture rate | Vault health threshold crossed | `updateCaptureRate(newRate)` |
| Vault flush | Sufficient pending capture accumulated | `flushToVault(token)` |

All Reactive callbacks pass through `ReactiveAdapter.sol` — an on-chain trust boundary that validates the Reactive Network origin before forwarding to the hook.

---

## The Self-Funding Flywheel

This is Trident's core innovation. Every other IL protection mechanism requires external funding — token emissions, protocol-owned liquidity, governance allocation, or user-purchased insurance. **Trident funds itself from value the pool was already losing.**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

THE TRIDENT FLYWHEEL

  Arb bot exploits LP pool
          ↓
  Trident detects oracle deviation (Layer 1)
          ↓
  Arb bot pays elevated fee (arb premium captured)
          ↓
  10–20% of elevated fee → IL Reserve Vault
          ↓
  Vault grows during active/volatile periods
          ↓
  Long-term LP withdraws → claims from vault
          ↓
  LP receives fees + IL offset → better net return
          ↓
  Better LP economics → more LPs willing to provide deep liquidity
          ↓
  Deeper liquidity → better prices for traders
          ↓
  Better prices → more trading volume
          ↓
  More volume → more arb → more vault funding

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

The arb bot that was extracting value from LPs is now funding their insurance. **The attack funds the defense.** No external token. No governance. No subsidy. The system is economically self-sustaining from day one.

---

## Research Foundation

Trident is built backwards from academic findings — every mechanism is the direct implementation of what the research identifies as the correct solution.

| Research Paper | Key Finding | Trident Layer |
|---|---|---|
| [Automated Market Making and Loss-Versus-Rebalancing — Milionis et al., arXiv 2208.06046](https://arxiv.org/abs/2208.06046) | LVR is the dominant LP loss. Pools need 10% daily turnover at 30bps to break even. Oracle-aware fee adjustment is the implied structural fix. | Layer 1 — Arb Detector |
| [Measuring Arbitrage Losses and Profitability — Fritsch & Canidio, arXiv 2404.05803](https://arxiv.org/pdf/2404.05803) | Empirical study of largest Uniswap pools: fees do not cover arb losses in most. | Layer 1 — Arb Detector |
| [Impermanent Loss in Uniswap v3 — arXiv 2111.09192](https://arxiv.org/abs/2111.09192) | IL = Gamma component of self-financing strategy. LP positions are short gamma — risk spikes at range boundaries. | Layer 2 — Range Guardian |
| [Unified Approach for Hedging Impermanent Loss — arXiv 2407.05146](https://arxiv.org/html/2407.05146v1) | IL equivalent to being short a portfolio of calls and puts. Hedging requires dynamic pricing of Gamma exposure. | Layer 2 — Range Guardian |
| [Impermanent Loss and LVR I — arXiv 2410.00854](https://arxiv.org/html/2410.00854v2) | IL and LVR have same expectation but vastly different distributions. Spikes are the dominant loss source for long-term LPs. | Layer 3 — Reserve Vault |
| [Impermanent Loss and LVR II — arXiv 2502.04097](https://arxiv.org/pdf/2502.04097) | Three regimes. A smoothing reserve is the structurally correct response. | Layer 3 — Reserve Vault |
| [The Paradox of JIT Liquidity — arXiv 2311.18164](https://arxiv.org/html/2311.18164v2) | JIT bots dilute regular LP fees by average 85%. $750B in JIT volume per year. Long-term LPs structurally disadvantaged. | Layer 3 — Loyalty Factor |
| [Strategic Analysis of JIT Liquidity — AFT 2025, Dagstuhl](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.AFT.2025.8) | Game-theoretic formalization of JIT extraction. Time-weighted participation is the correct counter-mechanism. | Layer 3 — Loyalty Factor |

---

## Competitive Landscape

### What Exists Today and Why It Is Not Enough

| Protocol / Hook | What It Does | Gap |
|---|---|---|
| **FlexFee** | Dynamic fees based on volatility index and swap size | Volatility ≠ arb detection. No range awareness. No reserve. |
| **Autopilot Hook** | ML-based fee adjustment on market volatility | Does not distinguish arb from retail. No reserve. |
| **LVR Minimization Hook** | Oracle-aware fee adjustment (POC only) | Research only. Never shipped. No range protection. No reserve. No Reactive. |
| **Brokkr Dynamic Fee** | Fee adjustment based on trading volume | Volume is not a proxy for arb activity. No oracle. No reserve. |
| **Diamond Protocol (Arrakis)** | Forces arb to pay collateral for block-level access | Infrastructure-level. Not standalone. Requires validator coordination. |
| **Angstrom** | Protects LPs from CEX-DEX arb via hook | Protocol-level. Not standalone. No range awareness. No reserve. |
| **Cork Protocol** | Depeg insurance marketplace | Requires users to actively purchase insurance. Lost $11M to exploit in May 2025. |

### Trident's Position

| Capability | FlexFee | Autopilot | LVR Hook POC | Trident |
|---|---|---|---|---|
| Oracle-aware arb detection | Partial | No | Yes (POC) | **Yes** |
| Range boundary Gamma awareness | No | No | No | **Yes** |
| On-chain IL reserve vault | No | No | No | **Yes** |
| Self-funded from recaptured arb | No | No | No | **Yes** |
| JIT LP loyalty protection | No | No | No | **Yes** |
| Reactive Network automation | No | No | No | **Yes** |
| Invariant-tested vault solvency | No | No | No | **Yes** |

**No existing hook combines all three layers. No existing hook has a self-sustaining reserve. No existing IL hook uses Reactive Network.**

---

## Hookathon Theme Alignment

**UHI9 Theme: "Impermanent Loss & Yield Systems — yield-protected liquidity systems that shield LPs from impermanent loss while unlocking sustainable, predictable on-chain returns."**

| Theme Phrase | How Trident Answers It |
|---|---|
| **"yield-protected"** | The reserve vault pays out on exit. LPs receive fees earned PLUS an IL offset from the vault. That is yield protection — not just reduced loss. |
| **"liquidity systems"** | Trident is a complete system (three hook layers + Reactive automation + vault) not a single mechanism. |
| **"shield LPs from impermanent loss"** | Three shields simultaneously: arb tax (Layer 1), Gamma fee (Layer 2), vault payout (Layer 3). No single existing hook shields from more than one attack vector. |
| **"sustainable"** | The reserve is funded entirely by recaptured arb value. No token emissions. No external subsidy. No governance required. Sustains itself from the pool's own activity. |
| **"predictable on-chain returns"** | Long-term LPs can model their expected payout: `IL_factor × loyalty × health = calculable vault claim`. Predictability is built into the design. |

Trident answers every phrase of the theme. Most submissions answer one or two.

---

## Technical Architecture

### Smart Contract Structure

```
trident-hook/
├── src/
│   ├── TridentHook.sol           # Main hook — all three layers
│   ├── ILReserveVault.sol        # Vault: deposit, IL calc, loyalty, health, payout
│   ├── OracleReader.sol          # Chainlink abstraction + TWAP manipulation guard
│   ├── GammaScorer.sol           # Tick-to-boundary proximity (gamma score math)
│   ├── PositionTracker.sol       # LP entry state + Reactive out-of-range tracking
│   ├── ReactiveAdapter.sol       # Trust boundary — validates Reactive origin
│   ├── demo/
│   │   ├── MockChainlinkFeed.sol # AggregatorV3-compatible mock; setAnswer() for demo
│   │   ├── MockERC20.sol         # Open mint() — testnet faucet token
│   │   ├── SwapHelper.sol        # Minimal v4 swap router (unlock callback pattern)
│   │   └── LiquidityHelper.sol   # Minimal v4 liquidity router
│   └── interfaces/
│       ├── ITridentHook.sol      # Public fee preview + config views
│       ├── IILReserveVault.sol   # Vault external API
│       ├── IOracleReader.sol     # Oracle abstraction
│       └── IReactiveCallback.sol # What Reactive calls back into
├── reactive/
│   └── TridentReactive.sol       # Reactive smart contract (Reactive Network)
├── test/
│   ├── unit/                     # 132 unit + fuzz tests
│   │   ├── OracleReader.t.sol    # 25 tests: price, deviation, manipulation guard
│   │   ├── GammaScorer.t.sol     # 17 tests: tick math, monotonicity, symmetry
│   │   ├── PositionTracker.t.sol # 25 tests: record, delete, access control
│   │   ├── ILReserveVault.t.sol  # 37 tests: deposit, settle, health, loyalty
│   │   └── TridentHook.t.sol     # 28 tests: fee computation, reactive callbacks
│   ├── invariant/
│   │   └── TridentInvariant.t.sol # 7 invariants: vault solvency, no money printing
│   └── integration/
│       └── FullFlow.t.sol        # 7 end-to-end tests: deposit → swaps → withdraw + payout
├── script/
│   ├── Deploy.s.sol              # Core contracts: hook, vault, tracker, oracle, adapter
│   ├── DeployTokens.s.sol        # MockUSDC — establishes token1 address pre-deployment
│   ├── DeployDemo.s.sol          # MockChainlinkFeed, MockWETH, SwapHelper, LiquidityHelper
│   ├── InitPool.s.sol            # PoolManager.initialize at sqrtPriceX96 = $3000
│   ├── SetOraclePrice.s.sol      # MockChainlinkFeed.setAnswer() for demo price changes
│   └── DeployReactive.s.sol      # TridentReactive on Reactive Network (kopli)
├── frontend/                     # Next.js demo UI
│   ├── app/page.tsx              # Main page: faucet → swap → liquidity → LP position
│   ├── components/
│   │   ├── DemoControls.tsx      # Oracle price slider (amber panel)
│   │   ├── SwapPanel.tsx         # Token swap with live fee preview
│   │   ├── LiquidityPanel.tsx    # Add/remove liquidity
│   │   ├── TokenFaucet.tsx       # Mint mWETH / mUSDC for testing
│   │   ├── LPPosition.tsx        # Per-LP vault payout estimate
│   │   ├── ActivityFeed.tsx      # Live SwapFeeBreakdown events
│   │   ├── FeeBreakdown.tsx      # Current fee state from hook
│   │   ├── VaultHealth.tsx       # Reserve vault health ratio
│   │   └── ReactiveStatus.tsx    # Reactive Network connection status
│   └── lib/
│       ├── abis.ts               # Minimal ABIs for all contracts
│       └── contracts.ts          # Contract addresses from .env.local
└── foundry.toml
```

### Hook Lifecycle

```solidity
// 1. Swap arrives
beforeSwap(sender, poolKey, swapParams, hookData)
  → getSlot0()              // read current sqrtPriceX96 + tick
  → if (primedDeviation > 0) use cached value     // Reactive fast path
    else OracleReader.getDeviationBps(poolPrice)  // direct oracle fallback
  → if (primedGamma > 0) use cached value         // Reactive fast path
    else GammaScorer.computeGammaScore(tick, boundary, spacing) // fallback
  → compute: base + arb_premium + boundary_premium
  → cap at MAX_FEE_BPS (5%), apply manipulation guard if set
  → return (fee_override)   // pool executes with this fee

// 2. Swap executes (pool internal math)

// 3. After swap
afterSwap(sender, poolKey, swapParams, delta, hookData)
  → estimate fee from delta
  → accrue captureRateBps% to _pendingCapture
  → emit SwapFeeBreakdown (for Reactive + frontend)

// 4. LP adds liquidity
afterAddLiquidity(sender, poolKey, params, delta, feesAccrued, hookData)
  → ILReserveVault.recordPosition(positionId, lp, entryTick, liquidity)
  → PositionTracker.recordEntry(positionId, lp, tickLower, tickUpper, entryTick, liquidity)

// 5. LP withdraws
beforeRemoveLiquidity(sender, poolKey, params, hookData)
  → if vault.positionExists(positionId):
      getSlot0() → currentTick
      ILReserveVault.settlePosition(positionId, currentTick, lp) → payout
      PositionTracker.deletePosition(positionId)
```

### Vault Mechanics

```
Vault state:
  totalReserveBalance     // ERC-20 tokens held (accounting-tracked, not balanceOf)
  totalLiability          // sum of worst-case claims for all open positions
  captureRateBps          // current fee capture rate (1000–3000 bps)

Per-LP position record:
  lp                      // address of liquidity provider
  entryTick               // pool tick at deposit time
  entryBlock              // block number of deposit (for loyalty calculation)
  liquidity               // liquidity amount added

Claim formula:
  IL_factor        = min(|exitTick - entryTick| × 5e13, MAX_IL_FACTOR)
  loyalty_factor   = min(blocksHeld / LOYALTY_TARGET_BLOCKS, 1e18)
  health_ratio     = min(totalReserveBalance × 1e18 / totalLiability, 1e18)
  raw_claim        = liquidity × IL_factor × loyalty_factor × health_ratio / 1e54
  final_payout     = min(raw_claim, totalReserveBalance × 10%)

Vault health auto-adjustment (fires on every deposit AND position record):
  health > 0.8  → captureRate = 10%   (NORMAL)
  health < 0.8  → captureRate = 15%   (LOW)
  health < 0.3  → captureRate = 20%   (EMERGENCY)
```

### Oracle Integration

- **Primary (on-chain):** Chainlink AggregatorV3 — 1-hour staleness guard, normalised to 1e18 via `_scaleFactor` computed at construction from feed decimals
- **Manipulation guard (via Reactive):** When Reactive detects Chainlink vs pool-TWAP divergence > configured threshold, `setOracleManipulated(true)` caps the fee at `MANIPULATION_FEE_CAP_BPS` (0.3%)
- **Pyth Network:** Used by Reactive off-chain for sub-second price comparison (not called on-chain in this version)

---

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+ (for frontend)
- Git

### Clone and Build

```bash
git clone --recurse-submodules https://github.com/dannyy2000/Trident.git
cd Trident
forge build
```

### Run the Frontend Locally

```bash
cd frontend
npm install
# Copy the example env and fill in your WalletConnect project ID
cp .env.local.example .env.local
npm run dev
# → http://localhost:3000
```

**MetaMask setup for demo:**
1. Add Unichain Sepolia: Chain ID `1301`, RPC `https://sepolia.unichain.org`, Explorer `https://sepolia.uniscan.xyz`
2. Get testnet ETH from `https://faucet.unichain.org`
3. Open `http://localhost:3000`, connect wallet
4. Click "Get 10 mWETH" + "Get 30k mUSDC" in the Token Faucet
5. Add Liquidity (tick range −6000/6000), then Swap, then set a new oracle price via Demo Controls and swap again to see the arb premium kick in

### Run Tests

```bash
# All tests (unit + fuzz + invariant)
forge test

# Unit and fuzz tests only
forge test --match-path "test/unit/*"

# Invariant tests only (takes ~60s — 131,072 calls per invariant)
forge test --match-path "test/invariant/*"

# With gas reporting
forge test --gas-report

# CI profile (50k fuzz runs, 1024 invariant runs)
FOUNDRY_PROFILE=ci forge test
```

### Test Coverage

| Test Suite | Tests | Type |
|---|---|---|
| OracleReader | 25 | Unit + Fuzz |
| GammaScorer | 17 | Unit + Fuzz |
| PositionTracker | 25 | Unit + Fuzz |
| ILReserveVault | 37 | Unit + Fuzz |
| TridentHook | 28 | Unit + Fuzz |
| TridentInvariant | 7 | Invariant (131k calls each) |
| FullFlow | 7 | Integration (end-to-end) |
| **Total** | **146** | |

### Key Invariants Proven

1. **Vault accounting matches ERC-20 balance** — no phantom credits
2. **Total payouts ≤ total deposits** — no money printing
3. **Reserve = deposited − paid out** — no value leakage
4. **Capture rate always in `[NORMAL, MAX]`** — auto-adjustment bounded
5. **Health ratio never reverts** — always computable regardless of state
6. **Reserve never negative** — documented by design
7. **Liability = 0 when no open positions** — no orphaned accounting

### Deployed Contracts — Unichain Sepolia (Chain ID 1301)

> **Current deployment** — redeployed via `FullRedeploy.s.sol`. All addresses below are live.

| Contract | Address |
|---|---|
| TridentHook | `0x87Bb5917BA1fa7f4EFD08903a5D305971B4146C0` |
| ILReserveVault | `0x07b2E842731a16Efc6F3d39bfA468f47b911Bc7f` |
| PositionTracker | `0xe4A49b9Bf9d46aa866397b2a0193DAb2D5D1f424` |
| OracleReader | `0x7de2ceB1316Cc7d9e12668E1771Be88de860FD01` |
| ReactiveAdapter | `0x7DAd5E3b0A4AfA91414b30AdBf64E33954278b0c` |
| MockChainlinkFeed | `0x467A074ADE6B5D828cd57EB2CeC76Cc396ca6Db6` |
| MockWETH / mWETH (token0, 18 dec) | `0x8a777593e7aD6Df9e4b7E104cF3e2B8eF82d0057` |
| MockUSDC / mUSDC (token1, 6 dec) | `0xff455ad480806CdC260B7073BAfDa9a191c0ff92` |
| SwapHelper | `0xa2E9fAF8C2045A5e10842006d064410a6C4aC076` |
| LiquidityHelper | `0x2F87C8ACBBB399bF77f6a0131284F2a6BC70E78d` |
| PoolManager | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |

Pool ID: `0x5e1589e36bf91d1b848851741701815f43d2b750dd64b05135b771f340b1d4e6`
Initial pool price: $3,000 (sqrtPriceX96 = 4339505179874779662909440)
Tick range (default): tickLower = -196980, tickUpper = -195600

### Deployed Contracts — Reactive Network Lasna Testnet (Chain ID 5318007)

| Contract | Address |
|---|---|
| TridentReactive | `0x693eE35A0c3D04b65D58AC075A18941dc212c90b` |

RPC: `https://lasna-rpc.rnk.dev/`
Deploy tx: `0x99034e1588dcc1ecbf54dd767b2a6a122051840ddec80602338d1e742a297dd5`
Subscribed to: Swap + ModifyLiquidity (PoolManager) + AnswerUpdated (MockChainlinkFeed) on chain 1301 ✓
Callback proxy (`reactiveOrigin` in ReactiveAdapter): `0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4` ✓

### Deploy Scripts

```bash
# 1. Deploy MockUSDC first (fixes token sort order — USDC must be token1)
forge script script/DeployTokens.s.sol --rpc-url https://sepolia.unichain.org --broadcast

# 2. Deploy core contracts (hook, vault, tracker, oracle, adapter)
forge script script/Deploy.s.sol --rpc-url https://sepolia.unichain.org --broadcast

# 3. Deploy demo contracts (MockChainlinkFeed, MockWETH, SwapHelper, LiquidityHelper)
forge script script/DeployDemo.s.sol --rpc-url https://sepolia.unichain.org --broadcast

# 4. Initialize the pool at $3000
forge script script/InitPool.s.sol --rpc-url https://sepolia.unichain.org --broadcast

# 5. Deploy TridentReactive to Reactive Network (Lasna testnet)
forge create reactive/TridentReactive.sol:TridentReactive \
  --rpc-url https://lasna-rpc.rnk.dev/ \
  --private-key $PRIVATE_KEY \
  --value 0.1ether \
  --broadcast --legacy \
  --constructor-args 1301 $POOL_MANAGER $CHAINLINK_FEED $REACTIVE_ADAPTER \
    $POOL_ID 60 10000000000 200 300000000000

# 6. Deploy a fresh ReactiveAdapter pointing at the new TridentReactive, then wire the hook
forge create src/ReactiveAdapter.sol:ReactiveAdapter \
  --rpc-url https://sepolia.unichain.org \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --constructor-args $TRIDENT_HOOK $TRIDENT_REACTIVE

cast send $TRIDENT_HOOK "setReactiveContract(address)" $NEW_ADAPTER \
  --rpc-url https://sepolia.unichain.org \
  --private-key $PRIVATE_KEY --legacy
```

---

## Tech Stack

| Component | Technology |
|---|---|
| Smart contract language | Solidity ^0.8.26 |
| Development framework | Foundry |
| Uniswap v4 interface | v4-core, v4-periphery |
| Primary oracle | Chainlink Price Feeds |
| Secondary oracle | Pyth Network (via Reactive) |
| Cross-chain automation | Reactive Network (Reactive Smart Contracts) |
| Target deployment | Unichain Sepolia (Chain ID 1301) |
| Testing | Forge unit + fuzz + invariant + integration (146 tests) |
| CI | GitHub Actions |
| Libraries | OpenZeppelin (ReentrancyGuard, SafeERC20) |
| Frontend framework | Next.js 15 (App Router) |
| Wallet integration | wagmi v3 + RainbowKit |
| Frontend language | TypeScript |

---

## Team

**Daniel Akinsanya** — Builder, Uniswap Hook Incubator Alumni

Previous hookathon project: **PEGKEEPER** — cross-chain stablecoin depeg protection hook using Reactive Network for cross-chain price intelligence. Built during UHI8.

Contact: akinsanyadaniel665@gmail.com | GitHub: [dannyy2000](https://github.com/dannyy2000)

---

*Built for UHI9 — Uniswap Hook Incubator Cohort 9 Hookathon*

*Theme: Impermanent Loss & Yield Systems | Partner: Reactive Network*
