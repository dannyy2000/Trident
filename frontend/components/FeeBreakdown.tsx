'use client'

import { useFeeBreakdown, bpsToPct } from '@/hooks/useFeeBreakdown'

type FeeBarProps = { label: string; value: number; color: string; tooltip: string }

function FeeBar({ label, value, color, tooltip }: FeeBarProps) {
  const pct = Math.min((value / 50_000) * 100, 100) // scale against 5% max
  return (
    <div className="group relative">
      <div className="flex justify-between text-xs mb-1">
        <span className="text-gray-400">{label}</span>
        <span className="font-mono text-gray-200">{bpsToPct(value)}</span>
      </div>
      <div className="h-2 bg-gray-800 rounded-full overflow-hidden">
        <div
          className="h-full rounded-full transition-all duration-500"
          style={{ width: `${pct}%`, backgroundColor: color }}
        />
      </div>
      <div className="absolute bottom-full left-0 mb-1 hidden group-hover:block bg-gray-800 text-xs text-gray-300 rounded px-2 py-1 whitespace-nowrap z-10 border border-gray-700">
        {tooltip}
      </div>
    </div>
  )
}

export function FeeBreakdown() {
  const { baseFee, arbPremium, boundaryPremium, totalFee, oracleManipulated, isLoading } = useFeeBreakdown()

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl p-5 space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="font-semibold text-white">Live Fee Breakdown</h2>
        {oracleManipulated && (
          <span className="text-xs bg-yellow-900/50 text-yellow-400 border border-yellow-700 rounded px-2 py-0.5">
            Oracle manipulation guard active
          </span>
        )}
      </div>

      {isLoading ? (
        <div className="space-y-3 animate-pulse">
          {[1,2,3,4].map(i => (
            <div key={i} className="h-8 bg-gray-800 rounded" />
          ))}
        </div>
      ) : (
        <div className="space-y-3">
          <FeeBar
            label="Base fee"
            value={baseFee}
            color="#4b5563"
            tooltip="Configured base fee for this pool"
          />
          <FeeBar
            label="Arb premium (Layer 1)"
            value={arbPremium}
            color="#f59e0b"
            tooltip="Oracle deviation detected — arb bot pays elevated fee"
          />
          <FeeBar
            label="Boundary premium (Layer 2)"
            value={boundaryPremium}
            color="#8b5cf6"
            tooltip="Gamma risk — price near LP range boundary"
          />

          <div className="border-t border-gray-700 pt-3">
            <div className="flex justify-between items-center">
              <span className="text-sm font-medium text-white">Total fee</span>
              <span className="text-xl font-bold font-mono text-indigo-400">
                {bpsToPct(totalFee)}
              </span>
            </div>
            <div className="h-3 bg-gray-800 rounded-full overflow-hidden mt-2">
              <div
                className="h-full rounded-full bg-gradient-to-r from-indigo-600 to-purple-500 transition-all duration-500"
                style={{ width: `${Math.min((totalFee / 50_000) * 100, 100)}%` }}
              />
            </div>
          </div>
        </div>
      )}

      <p className="text-xs text-gray-600">
        Updates every 10s from hook.previewFee() — reflects current primed state.
      </p>
    </div>
  )
}
