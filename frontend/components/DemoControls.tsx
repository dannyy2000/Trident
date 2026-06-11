'use client'

import { useState, useEffect } from 'react'
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '@/lib/contracts'
import { MOCK_FEED_ABI, TRIDENT_HOOK_ABI, MOCK_ERC20_ABI } from '@/lib/abis'

function answerToUSD(answer: bigint, decimals: number): number {
  if (answer === 0n) return 0
  if (decimals === 8)  return Number(answer) / 1e8
  if (decimals === 18) return Number(10n ** 18n * 10n ** 3n / answer) / 1e3
  return Number(answer) / 10 ** decimals
}

function usdToAnswer(usdPrice: number, decimals: number): bigint {
  if (usdPrice <= 0) return 0n
  if (decimals === 8)  return BigInt(Math.round(usdPrice * 1e8))
  if (decimals === 18) return BigInt(Math.round(1e18 / usdPrice))
  return BigInt(Math.round(usdPrice * 10 ** decimals))
}

function formatPending(raw: bigint): string {
  // mWETH has 18 decimals — show 8 dp so small captures are visible
  const whole = raw / 10n ** 18n
  const frac  = (raw % 10n ** 18n) * 100_000_000n / 10n ** 18n
  return `${whole}.${frac.toString().padStart(8, '0')}`
}

export function DemoControls() {
  const { isConnected } = useAccount()

  // ── Oracle price ──────────────────────────────────────────────────
  const [newPrice, setNewPrice] = useState('')
  const [oracleTxHash, setOracleTxHash] = useState<`0x${string}` | undefined>()

  const { data: latestAnswer, refetch: refetchPrice } = useReadContract({
    address: CONTRACTS.mockFeed,
    abi: MOCK_FEED_ABI,
    functionName: 'latestAnswer',
  })
  const { data: feedDecimals } = useReadContract({
    address: CONTRACTS.mockFeed,
    abi: MOCK_FEED_ABI,
    functionName: 'decimals',
  })

  const { mutate: writeOracle, isPending: isOraclePending } = useWriteContract()
  const { isLoading: isOracleConfirming, isSuccess: isOracleSuccess } = useWaitForTransactionReceipt({ hash: oracleTxHash })

  if (isOracleSuccess && oracleTxHash) refetchPrice()

  const currentUSD = latestAnswer !== undefined && feedDecimals !== undefined
    ? answerToUSD(latestAnswer as bigint, Number(feedDecimals))
    : null

  function handleSetPrice() {
    const parsed = parseFloat(newPrice)
    if (isNaN(parsed) || parsed <= 0 || feedDecimals === undefined) return
    const scaledAnswer = usdToAnswer(parsed, Number(feedDecimals))
    writeOracle(
      { address: CONTRACTS.mockFeed, abi: MOCK_FEED_ABI, functionName: 'setAnswer', args: [scaledAnswer] },
      { onSuccess: (hash) => setOracleTxHash(hash) }
    )
  }

  // ── SeedVault ─────────────────────────────────────────────────────
  const [mintHash,   setMintHash]   = useState<`0x${string}` | undefined>()
  const [flushHash,  setFlushHash]  = useState<`0x${string}` | undefined>()
  const [flushError, setFlushError] = useState<string | null>(null)

  const { data: pendingRaw, refetch: refetchPending } = useReadContract({
    address: CONTRACTS.hook,
    abi: TRIDENT_HOOK_ABI,
    functionName: 'pendingCapture',
    args: [CONTRACTS.payoutToken],
    query: { refetchInterval: 6000 },
  })
  const pending = (pendingRaw as bigint | undefined) ?? 0n

  const { mutate: writeMint,  isPending: isMintPending  } = useWriteContract()
  const { mutate: writeFlush, isPending: isFlushPending } = useWriteContract()
  const { isLoading: isMintConfirming,  isSuccess: mintDone  } = useWaitForTransactionReceipt({ hash: mintHash  })
  const { isLoading: isFlushConfirming, isSuccess: flushDone } = useWaitForTransactionReceipt({ hash: flushHash })

  // When mint is confirmed → trigger flush automatically
  useEffect(() => {
    if (!mintDone || flushHash !== undefined) return
    setFlushError(null)
    writeFlush(
      {
        address: CONTRACTS.hook,
        abi: TRIDENT_HOOK_ABI,
        functionName: 'flushToVault',
        args: [CONTRACTS.payoutToken],
      },
      {
        onSuccess: (hash) => setFlushHash(hash),
        onError: (err) => setFlushError(err.message ?? 'Flush failed — try clicking Seed Vault again'),
      }
    )
  }, [mintDone])

  // Reset after flush is done so the user can re-seed later
  useEffect(() => {
    if (!flushDone) return
    refetchPending()
  }, [flushDone])

  function handleSeedVault() {
    if (pending === 0n) return
    setMintHash(undefined)
    setFlushHash(undefined)
    setFlushError(null)
    writeMint(
      {
        address: CONTRACTS.payoutToken,
        abi: MOCK_ERC20_ABI,
        functionName: 'mint',
        args: [CONTRACTS.hook, pending],
      },
      {
        onSuccess: (hash) => setMintHash(hash),
      }
    )
  }

  const seedBusy = isMintPending || isMintConfirming || mintDone && !flushHash || isFlushPending || isFlushConfirming
  const seedLabel = (() => {
    if (isMintPending)                   return 'Sending mint…'
    if (isMintConfirming)                return 'Confirming mint…'
    if (mintDone && !flushHash)          return 'Triggering flush…'
    if (isFlushPending || isFlushConfirming) return 'Flushing to vault…'
    if (flushDone)                       return 'Vault seeded!'
    return `Seed Vault (${formatPending(pending)} mWETH)`
  })()

  if (CONTRACTS.mockFeed === '0x0000000000000000000000000000000000000000') return null

  return (
    <div className="space-y-4">
      {/* Oracle price control */}
      <div className="bg-amber-950/30 border border-amber-800/50 rounded-xl p-5 space-y-3">
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-amber-500 animate-pulse" />
          <h2 className="font-semibold text-amber-300 text-sm">Demo — Oracle Price Control</h2>
          <span className="ml-auto text-xs text-amber-700">MockChainlinkFeed</span>
        </div>

        <div className="flex items-center gap-3 text-sm">
          <span className="text-gray-500">Current ETH/USD:</span>
          <span className="font-mono font-bold text-white">
            {currentUSD !== null ? `$${currentUSD.toFixed(2)}` : '—'}
          </span>
          <span className="text-xs text-gray-600">
            (diverge this from pool price → next swap charges arb premium)
          </span>
        </div>

        <div className="flex gap-2">
          <input
            type="number"
            placeholder="New ETH price in USD, e.g. 3500"
            value={newPrice}
            onChange={e => setNewPrice(e.target.value)}
            className="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm font-mono text-gray-200 focus:outline-none focus:border-amber-500"
          />
          <button
            onClick={handleSetPrice}
            disabled={!isConnected || isOraclePending || isOracleConfirming || !newPrice}
            className="px-4 py-2 rounded-lg bg-amber-600 hover:bg-amber-500 disabled:opacity-40 disabled:cursor-not-allowed text-white text-sm font-semibold transition-colors"
          >
            {isOraclePending || isOracleConfirming ? 'Updating…' : 'Set Price'}
          </button>
        </div>

        {isOracleSuccess && (
          <p className="text-xs text-green-400">
            Price updated — swap now to trigger arb premium in the Fee Breakdown card.
          </p>
        )}

        <p className="text-xs text-amber-900">
          Changing the oracle price creates a divergence between the Chainlink feed and the pool.
          The next swap will include an arb premium proportional to the deviation.
        </p>
      </div>

      {/* Seed vault */}
      <div className="bg-indigo-950/30 border border-indigo-800/50 rounded-xl p-5 space-y-3">
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-indigo-400 animate-pulse" />
          <h2 className="font-semibold text-indigo-300 text-sm">Demo — Seed IL Reserve Vault</h2>
        </div>

        <p className="text-xs text-gray-400">
          After doing swaps, accumulated arb-premium fees sit in <span className="font-mono text-indigo-300">pendingCapture</span>.
          Clicking below mints those tokens to the hook and flushes them into the vault so
          LPs receive a payout when they remove liquidity.
        </p>

        <div className="flex items-center gap-3 text-sm">
          <span className="text-gray-500">Pending capture:</span>
          <span className="font-mono font-bold text-white">
            {pending === 0n ? '0 mWETH' : `${formatPending(pending)} mWETH`}
          </span>
        </div>

        {pending === 0n && !flushDone && (
          <p className="text-xs text-gray-600">
            Do at least one swap with an oracle divergence first to accumulate pending capture.
          </p>
        )}

        <button
          onClick={handleSeedVault}
          disabled={!isConnected || pending === 0n || seedBusy}
          className="w-full py-2.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 disabled:cursor-not-allowed text-white text-sm font-semibold transition-colors"
        >
          {seedLabel}
        </button>

        {flushError && (
          <div className="space-y-2">
            <p className="text-xs text-red-400">Flush failed: {flushError.slice(0, 120)}</p>
            <button
              onClick={() => {
                setFlushError(null)
                writeFlush(
                  { address: CONTRACTS.hook, abi: TRIDENT_HOOK_ABI, functionName: 'flushToVault', args: [CONTRACTS.payoutToken] },
                  { onSuccess: (hash) => setFlushHash(hash), onError: (e) => setFlushError(e.message ?? 'Flush failed') }
                )
              }}
              className="w-full py-2 rounded-lg bg-indigo-800 hover:bg-indigo-700 text-white text-xs font-semibold transition-colors"
            >
              Retry Flush
            </button>
          </div>
        )}

        {flushDone && (
          <p className="text-xs text-green-400">
            Vault seeded — remove liquidity now to receive your IL compensation payout.
          </p>
        )}
      </div>
    </div>
  )
}
