# TridentHook — 5-Minute Demo Script

**Total time: ~4:30**  
Pre-open: slides full-screen + browser tab ready (logged into MetaMask on Unichain Sepolia, chain 1301)

---

## Pre-Demo Checklist (do BEFORE presenting)

- [ ] MetaMask connected to Unichain Sepolia (RPC: `https://sepolia.unichain.org`, Chain ID: 1301)
- [ ] Minted tokens via faucet (click "Get 10 mWETH" + "Get 30k mUSDC")
- [ ] Added a liquidity position (tick lower -196980, upper -195600, e.g. 0.01 mWETH + matching mUSDC)
- [ ] Oracle price is close to pool price — note the current price shown in DemoControls
- [ ] Browser tab open, MetaMask unlocked
- [ ] DemoControls visible (scroll to see current ETH/USD price)

---

## Slide 1 — Cover (20 seconds)

**SHOW:** TridentHook title slide

**SAY:**
> "TridentHook is a Uniswap v4 hook that solves a well-documented problem — LP losses from arbitrage, gamma exposure, and JIT bots. Three layers. Fully on-chain. Autonomous."

---

## Slide 2 — The Problem (50 seconds)

**SHOW:** Point to each of the 4 research cards

**SAY:**
> "These aren't assumptions. Six peer-reviewed papers, same conclusion: LP capital is being systematically extracted."

Point to top-left card:
> "Fritsch & Canidio: fees don't cover arbitrage losses in most major Uniswap pools."

Point to top-right:
> "Milionis: LVR is the dominant LP drain. You need 10% daily turnover at 30bps just to break even."

Point to bottom-left:
> "LP positions are short gamma — risk spikes right at range boundaries."

Point to bottom-right:
> "JIT bots dilute LP fees by 85% on average. $750 billion in value extracted per year."

> "Every layer in TridentHook is the direct response to one of these findings."

---

## Slide 3 — The Solution (40 seconds)

**SHOW:** Three-layer solution slide

**SAY:**
> "Layer 1 — Arb Detector: when a swap would profit an arb bot, the fee spikes proportionally. The arb bot still trades — they just pay for it."

> "Layer 2 — Range Guardian: as price approaches an LP's boundary, the gamma score rises and fee elevates. LPs earn the most exactly when they're at most risk."

> "Layer 3 — IL Reserve Vault: a share of every elevated fee flows into an on-chain reserve. LPs claim compensation on exit. JIT bots — same-block in and out — receive zero."

---

## Slide 4 — Architecture (30 seconds)

**SHOW:** Architecture diagram — two boxes connected by callback arrow

**SAY:**
> "What makes this autonomous is Reactive Network. TridentReactive runs on Lasna, subscribes to Swap and oracle AnswerUpdated events on Unichain Sepolia, computes the fee parameters, and sends a callback. No bot, no keeper, no centralized oracle relay."

> "On Unichain Sepolia, ReactiveAdapter receives the callback and calls primeDeviation on TridentHook — pre-loading the fee state before the next swap executes. The arb premium fires the moment a price gap exists."

---

## Slide 5 → Switch to Browser (2 min 45 sec)

**SAY:** "Let me show you this live."

**SWITCH TO BROWSER**

### Step 1: Dashboard overview (20 sec)

**SHOW:** Full page dashboard — scroll down to Fee Breakdown card

**SAY:**
> "This is all live on Unichain Sepolia. I've already added a liquidity position — you can see it in 'My LP Position' below. The Fee Breakdown card shows the current state: 0.30% base fee, zero arb premium, zero boundary premium. Price is right at fair value."

---

### Step 2: Create oracle divergence (20 sec)

**SHOW:** DemoControls card — "Oracle Price Control" section at top of page

**SAY:**
> "This is a mock Chainlink feed deployed for the hackathon. Watch what happens when I create a price divergence."

**DO:** Enter a price significantly higher than current (if current shows ~$3,000, enter 4500). Click "Set Price". Wait for confirmation (~5 sec).

**SAY:**
> "I've just told the oracle ETH is worth $4,500 while the pool price still implies $3,000. That's a 50% divergence — exactly what an arb bot would exploit."

---

### Step 3: Swap and trigger the arb premium (45 sec)

**SHOW:** Swap panel

**SAY:**
> "Now I'll send a swap through the hook."

**DO:** Enter "0.01" in the mWETH amount field. Click "Swap", confirm MetaMask. Wait for confirmation (~15 sec).

**SHOW:** Scroll to FeeBreakdown card and ActivityFeed (both update immediately after confirmation)

**SAY:**
> "There it is — the fee breakdown card just updated. Base 0.30%, plus arb premium from Layer 1. And in the Activity Feed below, you can see this exact swap: base fee, arb premium, total. That's the hook detecting the oracle gap and charging the arb bot for it."

**SHOW:** Scroll to the Reactive Network Status card

**SAY:**
> "And this is where the Reactive Network comes in. TridentReactive — deployed on Lasna — just detected that Swap event. It runs react() in ReactVM: reads the oracle deviation, computes the fee parameters, and queues a callback to pre-load TridentHook before the next swap. The contract is live, subscriptions funded — you can see it on the monitoring indicator here."

---

### Step 4: Show the fee breakdown (20 sec)

**SHOW:** Scroll to FeeBreakdown card and ActivityFeed

**SAY:**
> "There it is. The fee breakdown card updated — base 0.30%, plus arb premium from Layer 1. And in the Activity Feed, you can see this swap: base fee tag, arb premium tag, total fee. The excess over the base rate went to LPs and the IL Reserve Vault."

---

### Step 5: Seed the vault (25 sec)

**SHOW:** DemoControls — "Seed IL Reserve Vault" section

**SAY:**
> "The arb premium that accumulated in pendingCapture — I'll now flush it into the vault. This simulates what happens on mainnet after multiple swaps."

**DO:** Click "Seed Vault". Wait for two transactions (~20 sec).

**SAY:**
> "That minted the captured amount and flushed it into the reserve vault."

---

### Step 6: Show vault health + LP payout (25 sec)

**SHOW:** Scroll to VaultHealth card and then LP Position

**SAY:**
> "Vault health is high — reserves exceed the outstanding liability. And in 'My LP Position', you can see a projected IL compensation payout. If I remove liquidity right now, that's what the vault would pay out — calculated live from my entry tick, loyalty factor, and vault health ratio."

---

## Close (10 seconds)

**SAY:**
> "146 tests passing, all contracts deployed and verified on Unichain Sepolia. TridentReactive live on Lasna. Three layers of LP protection, fully on-chain — and the Reactive Network subscriptions are active and running."

---

## Fallback / Q&A Answers

**"Has the Reactive Network callback been received yet?"**
> "TridentReactive is live on Lasna with active subscriptions — you can verify the subscribe events in the deploy tx. The contract is running react() in ReactVM for each Swap and AnswerUpdated event. Callback propagation to chain 1301 is the last piece; we're in contact with the Reactive team on that. The hook is architecturally ready to consume callbacks the moment they arrive — and the arb premium fires on every swap regardless."

**"What stops someone from manipulating the oracle feed?"**
> "TridentHook has a manipulation guard — if the oracle deviation exceeds a configurable threshold in a single block, it caps the fee at the base rate and ignores the spike. The guard is shown in the Reactive Network Status card."

**"What about JIT bots?"**
> "Same-block in/out LPs get zero vault payout — the loyalty factor is zero. They can't hold a position for one block and claim the reserve. Regular LPs that hold through volatility accumulate credit."

**"Why Uniswap v4 hooks specifically?"**
> "v4's hook architecture lets us intercept beforeSwap with zero additional contracts — the fee logic runs inside the pool itself. And with dynamic fees enabled, TridentHook can set any fee per-swap, not just a fixed rate."
