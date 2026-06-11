'use client'

import { useFeeBreakdown } from '@/hooks/useFeeBreakdown'
import { useSwapEvents } from '@/hooks/useSwapEvents'
import { CONTRACTS } from '@/lib/contracts'

function StatusRow({ label, value, sub, badge }: { label: string; value: string; sub?: string; badge?: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between py-2.5 border-b border-gray-800 last:border-0 gap-3">
      <div>
        <p className="text-sm text-gray-400">{label}</p>
        {sub && <p className="text-xs text-gray-600 mt-0.5">{sub}</p>}
      </div>
      <div className="flex items-center gap-2 shrink-0">
        {badge}
        <span className="font-mono text-sm text-gray-200">{value}</span>
      </div>
    </div>
  )
}

export function ReactiveStatus() {
  const {
    primedDeviationBps,
    primedGammaScore,
    primedBoundaryTick,
    oracleManipulated,
    arbPremium,
  } = useFeeBreakdown()
  const events = useSwapEvents()
  const latestEvent = events[0]

  const isPrimed       = Number(primedDeviationBps) > 0
  const deviationPct   = (Number(primedDeviationBps) / 100).toFixed(2) + '%'
  const gammaNorm      = (Number(primedGammaScore) / 1e16).toFixed(1) + '%'
  const explorerBase   = 'https://sepolia.uniscan.xyz/address/'

  // Use last swap event arb premium when previewFee shows 0 (no primed state yet)
  const effectiveArb = arbPremium > 0 ? arbPremium : (latestEvent?.arbPremiumBps ?? 0)
  const arbPct = effectiveArb > 0
    ? (effectiveArb / 10_000 * 100).toFixed(4) + '%'
    : null

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl p-5 space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="font-semibold text-white">Reactive Network Status</h2>
        <span className="flex items-center gap-1.5 text-xs text-green-400">
          <span className="w-1.5 h-1.5 rounded-full bg-green-400 animate-pulse" />
          Live
        </span>
      </div>

      {/* Arb detection banner */}
      {arbPct && !isPrimed && (
        <div className="rounded-lg bg-amber-950/40 border border-amber-800/50 px-3 py-2 text-xs text-amber-300">
          <span className="font-semibold">Arb premium firing ({arbPct})</span>
          {' '}— Reactive Network detected this swap event and is queuing a pre-cache for the next one.
        </div>
      )}
      {isPrimed && (
        <div className="rounded-lg bg-green-950/40 border border-green-800/50 px-3 py-2 text-xs text-green-300">
          <span className="font-semibold">Reactive callback received</span>
          {' '}— hook pre-loaded with oracle deviation. Next swap uses cached value.
        </div>
      )}

      <div>
        <StatusRow
          label="Primed oracle deviation"
          sub="Pre-computed by Reactive Network between swaps"
          value={isPrimed ? deviationPct : '0.00%'}
          badge={
            isPrimed ? (
              <span className="text-xs bg-amber-900/50 text-amber-400 border border-amber-700 rounded px-1.5 py-0.5">
                cached
              </span>
            ) : (
              <span className="text-xs bg-indigo-900/50 text-indigo-400 border border-indigo-700 rounded px-1.5 py-0.5">
                monitoring
              </span>
            )
          }
        />
        <StatusRow
          label="Primed gamma score"
          sub="Boundary proximity — set from ModifyLiquidity events"
          value={gammaNorm}
          badge={
            primedGammaScore > 500000000000000000n ? (
              <span className="text-xs bg-purple-900/50 text-purple-400 border border-purple-700 rounded px-1.5 py-0.5">
                near boundary
              </span>
            ) : undefined
          }
        />
        <StatusRow
          label="Nearest LP boundary tick"
          sub="Closest range edge across all active positions"
          value={primedBoundaryTick === 0 ? 'none primed' : primedBoundaryTick.toString()}
        />
        <StatusRow
          label="Oracle manipulation guard"
          sub="Caps fee at base rate if oracle looks manipulated"
          value={oracleManipulated ? 'ACTIVE — fee capped at 0.3%' : 'Inactive'}
          badge={
            oracleManipulated ? (
              <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
            ) : (
              <span className="w-2 h-2 rounded-full bg-green-500" />
            )
          }
        />
      </div>

      <div className="text-xs text-gray-600 space-y-1 pt-1">
        <p>
          Hook:{' '}
          <a
            href={`${explorerBase}${CONTRACTS.hook}`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-indigo-500 hover:text-indigo-400 font-mono"
          >
            {CONTRACTS.hook.slice(0, 10)}…{CONTRACTS.hook.slice(-6)}
          </a>
        </p>
        <p>TridentReactive on Lasna subscribes to Swap and AnswerUpdated events. Each event triggers react() in ReactVM, which queues a callback to pre-load TridentHook's state before the next swap.</p>
      </div>
    </div>
  )
}
