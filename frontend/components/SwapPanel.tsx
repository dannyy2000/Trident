'use client'

import { useState } from 'react'
import {
  useConnection, useReadContract, useWriteContract, useWaitForTransactionReceipt,
} from 'wagmi'
import { CONTRACTS, POOL_KEY, DYNAMIC_FEE_FLAG } from '@/lib/contracts'
import { SWAP_HELPER_ABI, ERC20_ABI, TRIDENT_HOOK_ABI } from '@/lib/abis'
import { bpsToPct } from '@/hooks/useFeeBreakdown'

// TickMath price limits — stop at MIN/MAX to allow full range
const MIN_SQRT = 4295128740n
const MAX_SQRT = 1461446703485210103287273052203988822378723970341n

const POOL_KEY_TUPLE = {
  currency0:   POOL_KEY.token0,
  currency1:   POOL_KEY.token1,
  fee:         DYNAMIC_FEE_FLAG,
  tickSpacing: POOL_KEY.tickSpacing,
  hooks:       CONTRACTS.hook,
} as const

export function SwapPanel() {
  const { address, isConnected } = useConnection()
  const [zeroForOne, setZeroForOne] = useState(true)
  const [amountIn,   setAmountIn]   = useState('')
  const [isApproving, setIsApproving] = useState(false)
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>()

  const inputToken  = zeroForOne ? POOL_KEY.token0 : POOL_KEY.token1
  const outputToken = zeroForOne ? POOL_KEY.token1 : POOL_KEY.token0

  const { data: inputDecimals }  = useReadContract({ address: inputToken,  abi: ERC20_ABI, functionName: 'decimals' })
  const { data: inputSymbol }    = useReadContract({ address: inputToken,  abi: ERC20_ABI, functionName: 'symbol'   })
  const { data: outputSymbol }   = useReadContract({ address: outputToken, abi: ERC20_ABI, functionName: 'symbol'   })

  // Live fee preview — negative amountSpecified = exact in
  const parsedAmount = amountIn && inputDecimals !== undefined
    ? -(BigInt(Math.floor(parseFloat(amountIn) * 10 ** Number(inputDecimals))))
    : 0n

  const { data: feePreview } = useReadContract({
    address: CONTRACTS.hook,
    abi: TRIDENT_HOOK_ABI,
    functionName: 'previewFee',
    args: [POOL_KEY_TUPLE, parsedAmount],
    query: { enabled: parsedAmount !== 0n },
  })

  // Allowance check
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: inputToken,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, CONTRACTS.swapHelper] : undefined,
    query: { enabled: !!address },
  })

  const { mutate: writeContract, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })

  if (isSuccess) refetchAllowance()

  const swapAmount = parsedAmount !== 0n ? parsedAmount : undefined
  const needsApproval = swapAmount !== undefined && allowance !== undefined && allowance < -parsedAmount

  function handleApprove() {
    setIsApproving(true)
    const MAX_UINT256 = 2n ** 256n - 1n
    writeContract(
      {
        address: inputToken,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [CONTRACTS.swapHelper, MAX_UINT256],
      },
      {
        onSuccess: (hash) => { setTxHash(hash); setIsApproving(false) },
        onError: () => setIsApproving(false),
      }
    )
  }

  function handleSwap() {
    if (!address || !swapAmount) return
    writeContract(
      {
        address: CONTRACTS.swapHelper,
        abi: SWAP_HELPER_ABI,
        functionName: 'swap',
        args: [
          POOL_KEY_TUPLE,
          {
            zeroForOne,
            amountSpecified: parsedAmount,
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT : MAX_SQRT,
          },
          address,
        ],
      },
      { onSuccess: (hash) => setTxHash(hash) }
    )
  }

  if (!isConnected) {
    return (
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-5">
        <h2 className="font-semibold text-white mb-2">Swap</h2>
        <p className="text-sm text-gray-500">Connect your wallet to swap.</p>
      </div>
    )
  }

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl p-5 space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="font-semibold text-white">Swap</h2>
        <button
          onClick={() => setZeroForOne(z => !z)}
          className="text-xs text-indigo-400 hover:text-indigo-300 transition-colors"
        >
          {inputSymbol ?? 'token0'} → {outputSymbol ?? 'token1'} &#8595;&#8593; flip
        </button>
      </div>

      {/* Amount input */}
      <div>
        <label className="text-xs text-gray-500 block mb-1">
          Amount ({inputSymbol ?? (zeroForOne ? 'token0' : 'token1')})
        </label>
        <input
          type="number"
          placeholder="0.0"
          value={amountIn}
          onChange={e => setAmountIn(e.target.value)}
          className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm font-mono text-gray-200 focus:outline-none focus:border-indigo-500"
        />
      </div>

      {/* Live fee preview */}
      {feePreview && (
        <div className="bg-gray-800/50 rounded-lg p-3 space-y-1 text-xs">
          <p className="text-gray-400 font-medium">Estimated fee breakdown</p>
          <div className="flex flex-wrap gap-2 mt-1">
            <span className="bg-gray-700 text-gray-300 px-1.5 py-0.5 rounded font-mono">
              base {bpsToPct(Number(feePreview[0]))}
            </span>
            {feePreview[1] > 0 && (
              <span className="bg-amber-900/60 text-amber-300 px-1.5 py-0.5 rounded font-mono">
                +arb {bpsToPct(Number(feePreview[1]))}
              </span>
            )}
            {feePreview[2] > 0 && (
              <span className="bg-purple-900/60 text-purple-300 px-1.5 py-0.5 rounded font-mono">
                +boundary {bpsToPct(Number(feePreview[2]))}
              </span>
            )}
            <span className="bg-indigo-900/60 text-indigo-300 px-1.5 py-0.5 rounded font-mono font-bold">
              = {bpsToPct(Number(feePreview[3]))} total
            </span>
          </div>
        </div>
      )}

      {/* Approve if needed */}
      {needsApproval ? (
        <button
          onClick={handleApprove}
          disabled={isApproving || isPending || isConfirming}
          className="w-full py-2.5 rounded-lg bg-gray-700 hover:bg-gray-600 disabled:opacity-40 text-sm font-semibold text-gray-200 transition-colors"
        >
          {isApproving ? 'Approving…' : `Approve ${inputSymbol ?? 'input token'}`}
        </button>
      ) : (
        <button
          onClick={handleSwap}
          disabled={!swapAmount || isPending || isConfirming}
          className="w-full py-2.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 disabled:cursor-not-allowed text-white text-sm font-semibold transition-colors"
        >
          {isPending || isConfirming ? 'Swapping…' : 'Swap'}
        </button>
      )}

      {isSuccess && (
        <p className="text-xs text-green-400">
          Swap confirmed — check the Activity Feed for the fee breakdown.
        </p>
      )}
    </div>
  )
}
