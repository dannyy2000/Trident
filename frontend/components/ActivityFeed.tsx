'use client'

import { useSwapEvents } from '@/hooks/useSwapEvents'
import { bpsToPct } from '@/hooks/useFeeBreakdown'
import { formatTokenAmount } from '@/hooks/useVaultState'
import { useVaultState } from '@/hooks/useVaultState'

function FeeTag({ value, color }: { value: number; color: string }) {
  return (
    <span className={`font-mono text-xs px-1.5 py-0.5 rounded ${color}`}>
      {bpsToPct(value)}
    </span>
  )
}

export function ActivityFeed() {
  const events = useSwapEvents()
  const { tokenDecimals, tokenSymbol } = useVaultState()

  return (
    <div id="activity" className="bg-gray-900 border border-gray-800 rounded-xl p-5 space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="font-semibold text-white">Swap Activity</h2>
        <span className="text-xs text-gray-500">{events.length} recent swaps</span>
      </div>

      {events.length === 0 ? (
        <p className="text-sm text-gray-600 py-4 text-center">
          No swaps captured yet — watching for SwapFeeBreakdown events...
        </p>
      ) : (
        <div className="space-y-2">
          {events.map((e, i) => (
            <div
              key={`${e.txHash}-${i}`}
              className="bg-gray-800/40 rounded-lg p-3 flex flex-col gap-1.5 hover:bg-gray-800 transition-colors"
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-1.5 flex-wrap">
                  <span className="text-xs text-gray-600">base</span>
                  <FeeTag value={e.baseFee}           color="bg-gray-700 text-gray-300" />
                  {e.arbPremiumBps > 0 && (
                    <>
                      <span className="text-xs text-amber-700">+ arb</span>
                      <FeeTag value={e.arbPremiumBps}   color="bg-amber-900/60 text-amber-300" />
                    </>
                  )}
                  {e.boundaryPremiumBps > 0 && (
                    <>
                      <span className="text-xs text-purple-700">+ boundary</span>
                      <FeeTag value={e.boundaryPremiumBps} color="bg-purple-900/60 text-purple-300" />
                    </>
                  )}
                  <span className="text-gray-600 text-xs">=</span>
                  <FeeTag value={e.totalFee}          color="bg-indigo-900/60 text-indigo-300 font-bold" />
                </div>
                <span className="text-xs text-gray-600 font-mono">
                  #{e.blockNumber.toString()}
                </span>
              </div>

              <div className="flex items-center justify-between text-xs text-gray-600">
                <a
                  href={`https://sepolia.uniscan.xyz/tx/${e.txHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-mono hover:text-indigo-400 transition-colors"
                >
                  {e.txHash.slice(0, 12)}…
                </a>
                {e.vaultCapture > BigInt(0) && (
                  <span className="text-green-600">
                    +{formatTokenAmount(e.vaultCapture, tokenDecimals, 6)} {tokenSymbol} → vault
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      <p className="text-xs text-gray-700">
        Arb premium = oracle divergence fee charged to arb bots (Layer 1) ·{' '}
        Boundary = gamma score near LP range edge (Layer 2)
      </p>
    </div>
  )
}
