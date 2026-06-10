'use client'

import { useState } from 'react'
import { useConnection, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '@/lib/contracts'
import { MOCK_FEED_ABI } from '@/lib/abis'

// Convert a raw feed answer to a human ETH/USD price.
// If feedDecimals = 8  (WETH/USDC pool): price = answer / 1e8
// If feedDecimals = 18 (USDC/WETH pool): price = 1e18 / answer  (inverted feed)
function answerToUSD(answer: bigint, decimals: number): number {
  if (answer === 0n) return 0
  if (decimals === 8)  return Number(answer) / 1e8
  if (decimals === 18) return Number(10n ** 18n * 10n ** 3n / answer) / 1e3
  return Number(answer) / 10 ** decimals
}

// Convert a human ETH/USD price back to the raw feed answer.
function usdToAnswer(usdPrice: number, decimals: number): bigint {
  if (usdPrice <= 0) return 0n
  if (decimals === 8)  return BigInt(Math.round(usdPrice * 1e8))
  if (decimals === 18) return BigInt(Math.round(1e18 / usdPrice))
  return BigInt(Math.round(usdPrice * 10 ** decimals))
}

export function DemoControls() {
  const { isConnected } = useConnection()
  const [newPrice, setNewPrice] = useState('')
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>()

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

  const { mutate: writeContract, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  if (isSuccess && txHash) refetchPrice()

  const currentUSD = latestAnswer !== undefined && feedDecimals !== undefined
    ? answerToUSD(latestAnswer as bigint, Number(feedDecimals))
    : null

  function handleSet() {
    const parsed = parseFloat(newPrice)
    if (isNaN(parsed) || parsed <= 0 || feedDecimals === undefined) return
    const scaledAnswer = usdToAnswer(parsed, Number(feedDecimals))
    writeContract(
      {
        address: CONTRACTS.mockFeed,
        abi: MOCK_FEED_ABI,
        functionName: 'setAnswer',
        args: [scaledAnswer],
      },
      { onSuccess: (hash) => setTxHash(hash) }
    )
  }

  if (CONTRACTS.mockFeed === '0x0000000000000000000000000000000000000000') return null

  return (
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
          onClick={handleSet}
          disabled={!isConnected || isPending || isConfirming || !newPrice}
          className="px-4 py-2 rounded-lg bg-amber-600 hover:bg-amber-500 disabled:opacity-40 disabled:cursor-not-allowed text-white text-sm font-semibold transition-colors"
        >
          {isPending || isConfirming ? 'Updating…' : 'Set Price'}
        </button>
      </div>

      {isSuccess && (
        <p className="text-xs text-green-400">
          Price updated — swap now to trigger arb premium in the Fee Breakdown card.
        </p>
      )}

      <p className="text-xs text-amber-900">
        Changing the oracle price creates a divergence between the Chainlink feed and the pool.
        The next swap will include an arb premium proportional to the deviation.
      </p>
    </div>
  )
}
