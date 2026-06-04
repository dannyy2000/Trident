'use client'

import { useState } from 'react'
import { useAccount } from 'wagmi'
import { useLPPosition } from '@/hooks/useLPPosition'
import { useVaultState, formatTokenAmount } from '@/hooks/useVaultState'

export function LPPosition({ currentTick }: { currentTick: number }) {
  const { isConnected } = useAccount()
  const { tokenSymbol, tokenDecimals } = useVaultState()

  const [tickLower, setTickLower] = useState(-6000)
  const [tickUpper, setTickUpper] = useState(6000)

  const position = useLPPosition({ tickLower, tickUpper, currentTick })

  if (!isConnected) {
    return (
      <div id="position" className="bg-gray-900 border border-gray-800 rounded-xl p-5">
        <h2 className="font-semibold text-white mb-3">My LP Position</h2>
        <p className="text-gray-500 text-sm">Connect your wallet to view your position and projected IL payout.</p>
      </div>
    )
  }

  return (
    <div id="position" className="bg-gray-900 border border-gray-800 rounded-xl p-5 space-y-4">
      <h2 className="font-semibold text-white">My LP Position</h2>

      {/* Range inputs */}
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="text-xs text-gray-500 block mb-1">Tick lower</label>
          <input
            type="number"
            value={tickLower}
            onChange={e => setTickLower(Number(e.target.value))}
            className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm font-mono text-gray-200 focus:outline-none focus:border-indigo-500"
          />
        </div>
        <div>
          <label className="text-xs text-gray-500 block mb-1">Tick upper</label>
          <input
            type="number"
            value={tickUpper}
            onChange={e => setTickUpper(Number(e.target.value))}
            className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm font-mono text-gray-200 focus:outline-none focus:border-indigo-500"
          />
        </div>
      </div>

      {position.isLoading ? (
        <div className="animate-pulse space-y-2">
          {[1,2,3].map(i => <div key={i} className="h-10 bg-gray-800 rounded-lg" />)}
        </div>
      ) : !position.exists ? (
        <div className="text-sm text-gray-500 bg-gray-800/50 rounded-lg p-4 text-center">
          No Trident position found for this range.
          <br />
          <span className="text-xs text-gray-600">Add liquidity through the Uniswap v4 pool with TridentHook attached.</span>
        </div>
      ) : (
        <div className="space-y-3">
          {position.outOfRange && (
            <div className="bg-red-900/30 border border-red-800 rounded-lg p-3 text-sm text-red-300">
              Position is out of range — earning 0 fees, accumulating IL.
            </div>
          )}

          <div className="grid grid-cols-2 gap-2 text-sm">
            <div className="bg-gray-800/50 rounded-lg p-3">
              <p className="text-xs text-gray-500 mb-1">Entry tick</p>
              <p className="font-mono font-bold">{position.entryTick}</p>
            </div>
            <div className="bg-gray-800/50 rounded-lg p-3">
              <p className="text-xs text-gray-500 mb-1">Current tick</p>
              <p className="font-mono font-bold">{currentTick}</p>
            </div>
            <div className="bg-gray-800/50 rounded-lg p-3">
              <p className="text-xs text-gray-500 mb-1">Tick movement</p>
              <p className="font-mono font-bold text-amber-400">
                {Math.abs(currentTick - position.entryTick)} ticks
              </p>
            </div>
            <div className="bg-gray-800/50 rounded-lg p-3">
              <p className="text-xs text-gray-500 mb-1">Entry block</p>
              <p className="font-mono font-bold text-xs">{position.entryBlock.toString()}</p>
            </div>
          </div>

          {/* Projected vault payout */}
          <div className="bg-indigo-900/30 border border-indigo-800 rounded-lg p-4">
            <p className="text-xs text-indigo-300 mb-1">Projected vault payout</p>
            <p className="text-2xl font-bold font-mono text-indigo-300">
              {formatTokenAmount(position.estimatedPayout, tokenDecimals, 6)} {tokenSymbol}
            </p>
            <p className="text-xs text-gray-500 mt-1">
              IL × loyalty × health — calculated live from vault state.
              Actual payout occurs when you remove liquidity.
            </p>
          </div>

          <div className="text-xs text-gray-600 font-mono break-all">
            Position ID: {position.positionId}
          </div>
        </div>
      )}
    </div>
  )
}
