'use client'

import { useFeeBreakdown } from '@/hooks/useFeeBreakdown'
import { CONTRACTS } from '@/lib/contracts'

function StatusRow({ label, value, badge }: { label: string; value: string; badge?: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between py-2 border-b border-gray-800 last:border-0">
      <span className="text-sm text-gray-400">{label}</span>
      <div className="flex items-center gap-2">
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
  } = useFeeBreakdown()

  const deviationPct   = (Number(primedDeviationBps) / 100).toFixed(2) + '%'
  const gammaNorm      = (Number(primedGammaScore) / 1e16).toFixed(1) + '%'
  const explorerBase   = 'https://sepolia.uniscan.xyz/address/'

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl p-5 space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="font-semibold text-white">Reactive Network Status</h2>
        <span className="flex items-center gap-1.5 text-xs text-green-400">
          <span className="w-1.5 h-1.5 rounded-full bg-green-400 animate-pulse" />
          Live
        </span>
      </div>

      <div>
        <StatusRow
          label="Primed oracle deviation"
          value={deviationPct}
          badge={
            Number(primedDeviationBps) > 200 ? (
              <span className="text-xs bg-amber-900/50 text-amber-400 border border-amber-700 rounded px-1.5 py-0.5">
                arb premium active
              </span>
            ) : undefined
          }
        />
        <StatusRow
          label="Primed gamma score"
          value={gammaNorm}
          badge={
            Number(primedGammaScore) > BigInt('500000000000000000') ? (
              <span className="text-xs bg-purple-900/50 text-purple-400 border border-purple-700 rounded px-1.5 py-0.5">
                near boundary
              </span>
            ) : undefined
          }
        />
        <StatusRow
          label="Nearest boundary tick"
          value={primedBoundaryTick === 0 ? 'none primed' : primedBoundaryTick.toString()}
        />
        <StatusRow
          label="Oracle manipulation guard"
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

      <div className="text-xs text-gray-600 space-y-1">
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
        <p>Reactive updates primed state after every Swap event on Unichain.</p>
      </div>
    </div>
  )
}
