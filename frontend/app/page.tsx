'use client'

import { Header }         from '@/components/Header'
import { FeeBreakdown }   from '@/components/FeeBreakdown'
import { VaultHealth }    from '@/components/VaultHealth'
import { ReactiveStatus } from '@/components/ReactiveStatus'
import { LPPosition }     from '@/components/LPPosition'
import { ActivityFeed }   from '@/components/ActivityFeed'
import { SwapPanel }      from '@/components/SwapPanel'
import { LiquidityPanel } from '@/components/LiquidityPanel'
import { DemoControls }   from '@/components/DemoControls'
import { TokenFaucet }    from '@/components/TokenFaucet'

export default function Home() {
  // currentTick read from PoolManager.getSlot0 in a future hook;
  // LP position form lets users override their range inputs for now.
  const currentTick = 0

  return (
    <div className="min-h-screen bg-gray-950">
      <Header />

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">

        {/* Hero */}
        <div>
          <h1 className="text-2xl font-bold text-white">Trident</h1>
          <p className="text-gray-500 text-sm mt-1">
            Three-layer IL protection — Arb detection · Gamma-aware fees · IL reserve vault · Powered by Reactive Network
          </p>
        </div>

        {/* Demo oracle controls (only visible when NEXT_PUBLIC_MOCK_FEED is set) */}
        <DemoControls />

        {/* Faucet — get tokens before anything else */}
        <TokenFaucet />

        {/* Actions row: the core demo flow */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <SwapPanel />
          <LiquidityPanel />
        </div>

        {/* LP Position viewer */}
        <LPPosition currentTick={currentTick} />

        {/* Live swap activity */}
        <ActivityFeed />

        {/* Monitoring — fee breakdown, vault health, reactive status */}
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          <FeeBreakdown />
          <VaultHealth />
          <ReactiveStatus />
        </div>

        {/* Architecture reminder */}
        <div className="border border-gray-800 rounded-xl p-5 bg-gray-900/50 grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
          <div className="space-y-1">
            <p className="text-indigo-400 font-semibold">Layer 1 — Arb Detector</p>
            <p className="text-gray-500 text-xs">
              Reads Chainlink oracle deviation vs pool sqrtPriceX96.
              Arb bots pay elevated fees proportional to the value they extract.
            </p>
          </div>
          <div className="space-y-1">
            <p className="text-purple-400 font-semibold">Layer 2 — Range Guardian</p>
            <p className="text-gray-500 text-xs">
              Gamma score = 1/(tickSpacingsAway + 1).
              LPs are compensated more when price is nearest their boundary.
            </p>
          </div>
          <div className="space-y-1">
            <p className="text-green-400 font-semibold">Layer 3 — IL Reserve Vault</p>
            <p className="text-gray-500 text-xs">
              10–20% of elevated fees accrue here. Long-term LPs claim at withdrawal.
              JIT LPs (same-block in/out) receive zero.
            </p>
          </div>
        </div>

      </main>
    </div>
  )
}
