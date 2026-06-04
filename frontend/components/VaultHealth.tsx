'use client'

import { useVaultState, formatTokenAmount } from '@/hooks/useVaultState'

const HEALTH_COLORS = {
  healthy:   { bar: '#22c55e', badge: 'bg-green-900/50 text-green-400 border-green-700' },
  low:       { bar: '#f59e0b', badge: 'bg-yellow-900/50 text-yellow-400 border-yellow-700' },
  emergency: { bar: '#ef4444', badge: 'bg-red-900/50 text-red-400 border-red-700' },
}

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="bg-gray-800/50 rounded-lg p-3">
      <p className="text-xs text-gray-500 mb-1">{label}</p>
      <p className="text-base font-bold font-mono text-white">{value}</p>
      {sub && <p className="text-xs text-gray-500 mt-0.5">{sub}</p>}
    </div>
  )
}

export function VaultHealth() {
  const {
    totalReserveBalance,
    totalLiability,
    healthRatio,
    captureRateBps,
    tokenSymbol,
    tokenDecimals,
    healthLabel,
    captureRateLabel,
    isLoading,
  } = useVaultState()

  const colors = HEALTH_COLORS[healthLabel]
  const healthPct = Math.min(Number(healthRatio) / 1e16, 100) // 1e18 = 100%
  const healthDisplay = (Number(healthRatio) / 1e16).toFixed(1) + '%'

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl p-5 space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="font-semibold text-white">IL Reserve Vault</h2>
        <span className={`text-xs border rounded px-2 py-0.5 capitalize ${colors.badge}`}>
          {healthLabel}
        </span>
      </div>

      {isLoading ? (
        <div className="space-y-2 animate-pulse">
          {[1,2,3].map(i => <div key={i} className="h-14 bg-gray-800 rounded-lg" />)}
        </div>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-2">
            <Stat
              label="Reserve balance"
              value={`${formatTokenAmount(totalReserveBalance, tokenDecimals, 4)} ${tokenSymbol}`}
            />
            <Stat
              label="Total liability"
              value={`${formatTokenAmount(totalLiability, tokenDecimals, 4)} ${tokenSymbol}`}
              sub="worst-case claims"
            />
            <Stat
              label="Health ratio"
              value={healthDisplay}
              sub="reserve / liability"
            />
            <Stat
              label="Capture rate"
              value={captureRateLabel}
              sub="of each swap fee"
            />
          </div>

          {/* Health bar */}
          <div>
            <div className="flex justify-between text-xs text-gray-500 mb-1">
              <span>Vault health</span>
              <span>{healthDisplay}</span>
            </div>
            <div className="h-2 bg-gray-800 rounded-full overflow-hidden">
              <div
                className="h-full rounded-full transition-all duration-700"
                style={{ width: `${Math.min(healthPct, 100)}%`, backgroundColor: colors.bar }}
              />
            </div>
            <div className="flex justify-between text-xs text-gray-700 mt-1">
              <span>0%</span>
              <span className="text-red-800">30% emergency</span>
              <span className="text-yellow-800">80% low</span>
              <span>100%+</span>
            </div>
          </div>
        </>
      )}

      <p className="text-xs text-gray-600">
        Capture rate auto-adjusts: 10% (healthy) → 15% (low) → 20% (emergency).
      </p>
    </div>
  )
}
