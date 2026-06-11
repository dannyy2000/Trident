'use client'

import { useReadContract } from 'wagmi'
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
import { CONTRACTS }      from '@/lib/contracts'
import { POOL_MANAGER_ABI } from '@/lib/abis'

const POOL_ID = '0x5e1589e36bf91d1b848851741701815f43d2b750dd64b05135b771f340b1d4e6' as `0x${string}`

export default function Home() {
  const { data: slot0 } = useReadContract({
    address: CONTRACTS.poolManager,
    abi: POOL_MANAGER_ABI,
    functionName: 'getSlot0',
    args: [POOL_ID],
    query: { refetchInterval: 10000 },
  })
  const currentTick = slot0 ? Number((slot0 as any)[1]) : 0

  return (
    <div className="min-h-screen bg-gray-950">
      <Header />

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">

        {/* Hero */}
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-2xl font-bold text-white">TridentHook</h1>
            <p className="text-gray-500 text-sm mt-0.5">
              Three-layer IL protection — Arb detection · Gamma-aware fees · IL reserve vault
            </p>
          </div>
          <div className="hidden sm:flex flex-col items-end gap-1 text-xs text-gray-500 mt-0.5">
            <div className="flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />
              <span className="text-green-400 font-medium">Live — Unichain Sepolia</span>
            </div>
            {currentTick !== 0 && (
              <span className="font-mono text-gray-600">pool tick {currentTick}</span>
            )}
          </div>
        </div>

        {/* Demo oracle controls */}
        <DemoControls />

        {/* Faucet — get tokens before anything else */}
        <TokenFaucet />

        {/* Core actions */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <SwapPanel />
          <LiquidityPanel />
        </div>

        {/* Live monitoring — right after actions so fee changes are visible immediately */}
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          <FeeBreakdown />
          <VaultHealth />
          <ReactiveStatus />
        </div>

        {/* Live swap activity */}
        <ActivityFeed />

        {/* LP Position viewer */}
        <LPPosition currentTick={currentTick} />

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
