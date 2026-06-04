'use client'

import { Header } from '@/components/Header'
import { FeeBreakdown } from '@/components/FeeBreakdown'
import { VaultHealth } from '@/components/VaultHealth'
import { ReactiveStatus } from '@/components/ReactiveStatus'
import { LPPosition } from '@/components/LPPosition'
import { ActivityFeed } from '@/components/ActivityFeed'

export default function Home() {
  // In production: read currentTick from PoolManager.getSlot0 via a hook.
  // For now, using 0 as a safe default — the LP position form lets users override their range inputs.
  const currentTick = 0

  return (
    <div className="min-h-screen bg-gray-950">
      <Header />

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">

        {/* Hero */}
        <div id="dashboard">
          <h1 className="text-2xl font-bold text-white">
            Trident Dashboard
          </h1>
          <p className="text-gray-500 text-sm mt-1">
            Three-layer IL protection — Arb detection · Gamma-aware fees · IL reserve vault · Powered by Reactive Network
          </p>
        </div>

        {/* Top row: Fee + Vault + Reactive */}
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          <FeeBreakdown />
          <VaultHealth />
          <ReactiveStatus />
        </div>

        {/* LP Position */}
        <LPPosition currentTick={currentTick} />

        {/* Activity feed */}
        <ActivityFeed />

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
              Gamma score = 1/( tickSpacingsAway + 1 ).
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
