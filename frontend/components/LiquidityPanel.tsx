'use client'

import { useState } from 'react'
import {
  useConnection, useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt,
} from 'wagmi'
import { CONTRACTS, POOL_KEY, DYNAMIC_FEE_FLAG } from '@/lib/contracts'
import { LIQUIDITY_HELPER_ABI, ERC20_ABI, POOL_MANAGER_ABI } from '@/lib/abis'
type Mode = 'add' | 'remove'

// PoolId = keccak256(abi.encode(poolKey)) — precomputed from InitPool output
const POOL_ID = '0x198c039d15a9e83af81d10cc37c7962537d26cf4ea137c0c8ad4724d7cc0d077' as `0x${string}`

// Compute liquidity from token0 amount + sqrtPrice + tick bounds.
// Mirrors LiquidityAmounts.getLiquidityForAmount0 from Uniswap v3/v4 math.
function sqrtX96(tick: number): bigint {
  // Approximate: sqrtPriceX96 = 2^96 * 1.0001^(tick/2)
  return BigInt(Math.floor(Math.pow(1.0001, tick / 2) * 2 ** 96))
}

function getLiquidityForAmounts(
  sqrtPrice: bigint,
  tickLower: number,
  tickUpper: number,
  amount0: bigint,
  amount1: bigint,
): bigint {
  const sqrtA = sqrtX96(tickLower)
  const sqrtB = sqrtX96(tickUpper)
  const Q96 = 2n ** 96n

  if (sqrtPrice <= sqrtA) {
    // Only token0 needed
    if (amount0 === 0n || sqrtB <= sqrtA) return 0n
    return (amount0 * sqrtA * sqrtB / Q96) / (sqrtB - sqrtA)
  } else if (sqrtPrice < sqrtB) {
    // Both tokens
    const liq0 = sqrtPrice > 0n
      ? (amount0 * sqrtPrice * sqrtB / Q96) / (sqrtB - sqrtPrice)
      : 0n
    const liq1 = (amount1 * Q96) / (sqrtPrice - sqrtA)
    return liq0 < liq1 ? liq0 : liq1
  } else {
    // Only token1 needed
    if (amount1 === 0n || sqrtB <= sqrtA) return 0n
    return (amount1 * Q96) / (sqrtB - sqrtA)
  }
}

const POOL_KEY_TUPLE = {
  currency0:   POOL_KEY.token0,
  currency1:   POOL_KEY.token1,
  fee:         DYNAMIC_FEE_FLAG,
  tickSpacing: POOL_KEY.tickSpacing,
  hooks:       CONTRACTS.hook,
} as const

export function LiquidityPanel() {
  const { address, isConnected } = useConnection()
  const [mode,      setMode]      = useState<Mode>('add')
  const [tickLower, setTickLower] = useState(-6000)
  const [tickUpper, setTickUpper] = useState(6000)
  const [amount0In, setAmount0In] = useState('')  // token0 human amount
  const [amount1In, setAmount1In] = useState('')  // token1 human amount
  const [txHash,    setTxHash]    = useState<`0x${string}` | undefined>()

  // Read current pool price + token metadata
  const { data: slot0 } = useReadContract({
    address: CONTRACTS.poolManager,
    abi: POOL_MANAGER_ABI,
    functionName: 'getSlot0',
    args: [POOL_ID],
    query: { refetchInterval: 8000 },
  })

  const { data: meta, refetch: refetchMeta } = useReadContracts({
    contracts: [
      { address: POOL_KEY.token0, abi: ERC20_ABI, functionName: 'decimals' },
      { address: POOL_KEY.token1, abi: ERC20_ABI, functionName: 'decimals' },
      { address: POOL_KEY.token0, abi: ERC20_ABI, functionName: 'symbol'   },
      { address: POOL_KEY.token1, abi: ERC20_ABI, functionName: 'symbol'   },
      { address: POOL_KEY.token0, abi: ERC20_ABI, functionName: 'allowance',
        args: address ? [address, CONTRACTS.liquidityHelper] : undefined },
      { address: POOL_KEY.token1, abi: ERC20_ABI, functionName: 'allowance',
        args: address ? [address, CONTRACTS.liquidityHelper] : undefined },
    ],
    query: { enabled: !!address },
  })

  const dec0  = Number((meta?.[0].result as bigint | undefined) ?? 18n)
  const dec1  = Number((meta?.[1].result as bigint | undefined) ?? 6n)
  const sym0  = (meta?.[2].result as string | undefined) ?? 'token0'
  const sym1  = (meta?.[3].result as string | undefined) ?? 'token1'
  const all0  = (meta?.[4].result as bigint | undefined) ?? 0n
  const all1  = (meta?.[5].result as bigint | undefined) ?? 0n

  const sqrtPrice = (slot0 as any)?.[0] as bigint | undefined

  // Parse human amounts to base units
  const raw0 = amount0In
    ? BigInt(Math.floor(parseFloat(amount0In) * 10 ** dec0))
    : 0n
  const raw1 = amount1In
    ? BigInt(Math.floor(parseFloat(amount1In) * 10 ** dec1))
    : 0n

  // Compute liquidityDelta from token amounts
  const liquidityDelta: bigint = (() => {
    if (mode === 'remove') return -(raw0 || raw1 || 0n)
    if (!sqrtPrice || (raw0 === 0n && raw1 === 0n)) return 0n
    return getLiquidityForAmounts(sqrtPrice, tickLower, tickUpper, raw0, raw1)
  })()

  const MAX_UINT256 = 2n ** 256n - 1n
  const needsApprove0 = mode === 'add' && raw0 > 0n && all0 < raw0
  const needsApprove1 = mode === 'add' && raw1 > 0n && all1 < raw1

  const { mutate: writeContract, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })
  if (isSuccess) { refetchMeta(); setTxHash(undefined) }

  function approve(which: 0 | 1) {
    const tokenAddr = which === 0 ? POOL_KEY.token0 : POOL_KEY.token1
    writeContract(
      { address: tokenAddr, abi: ERC20_ABI, functionName: 'approve',
        args: [CONTRACTS.liquidityHelper, MAX_UINT256] },
      { onSuccess: (hash) => setTxHash(hash) }
    )
  }

  function modify() {
    if (liquidityDelta === 0n) return
    writeContract(
      {
        address: CONTRACTS.liquidityHelper,
        abi: LIQUIDITY_HELPER_ABI,
        functionName: 'modifyLiquidity',
        args: [
          POOL_KEY_TUPLE,
          liquidityDelta,
          tickLower,
          tickUpper,
          ('0x' + '0'.repeat(64)) as `0x${string}`,
        ],
      },
      {
        onSuccess: (hash) => {
          setTxHash(hash)
          setAmount0In('')
          setAmount1In('')
        },
      }
    )
  }

  const canModify = liquidityDelta !== 0n && !needsApprove0 && !needsApprove1

  if (!isConnected) {
    return (
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-5">
        <h2 className="font-semibold text-white mb-2">Liquidity</h2>
        <p className="text-sm text-gray-500">Connect your wallet to add or remove liquidity.</p>
      </div>
    )
  }

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl p-5 space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="font-semibold text-white">Liquidity</h2>
        <div className="flex rounded-lg overflow-hidden border border-gray-700 text-xs">
          {(['add', 'remove'] as Mode[]).map(m => (
            <button
              key={m}
              onClick={() => setMode(m)}
              className={`px-3 py-1.5 capitalize transition-colors ${
                mode === m ? 'bg-indigo-600 text-white' : 'text-gray-400 hover:text-white'
              }`}
            >
              {m}
            </button>
          ))}
        </div>
      </div>

      {/* Tick range */}
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

      {/* Token amounts */}
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="text-xs text-gray-500 block mb-1">
            {sym0} amount {mode === 'remove' ? '(liquidity units)' : ''}
          </label>
          <input
            type="number"
            placeholder={mode === 'add' ? '0.0' : 'raw liquidity to remove'}
            value={amount0In}
            onChange={e => setAmount0In(e.target.value)}
            className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm font-mono text-gray-200 focus:outline-none focus:border-indigo-500"
          />
        </div>
        {mode === 'add' && (
          <div>
            <label className="text-xs text-gray-500 block mb-1">{sym1} amount</label>
            <input
              type="number"
              placeholder="0.0"
              value={amount1In}
              onChange={e => setAmount1In(e.target.value)}
              className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm font-mono text-gray-200 focus:outline-none focus:border-indigo-500"
            />
          </div>
        )}
      </div>

      {liquidityDelta !== 0n && (
        <p className="text-xs text-gray-600 font-mono">
          liquidityDelta = {liquidityDelta.toString()}
        </p>
      )}

      {/* Approve buttons */}
      {mode === 'add' && (
        <div className="flex gap-2">
          {needsApprove0 && (
            <button
              onClick={() => approve(0)}
              disabled={isPending || isConfirming}
              className="flex-1 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 disabled:opacity-40 text-xs font-semibold text-gray-200 transition-colors"
            >
              {isPending ? 'Approving…' : `Approve ${sym0}`}
            </button>
          )}
          {needsApprove1 && (
            <button
              onClick={() => approve(1)}
              disabled={isPending || isConfirming}
              className="flex-1 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 disabled:opacity-40 text-xs font-semibold text-gray-200 transition-colors"
            >
              {isPending ? 'Approving…' : `Approve ${sym1}`}
            </button>
          )}
        </div>
      )}

      <button
        onClick={modify}
        disabled={!canModify || isPending || isConfirming}
        className={`w-full py-2.5 rounded-lg text-sm font-semibold transition-colors disabled:opacity-40 disabled:cursor-not-allowed ${
          mode === 'add'
            ? 'bg-indigo-600 hover:bg-indigo-500 text-white'
            : 'bg-red-800 hover:bg-red-700 text-white'
        }`}
      >
        {isPending || isConfirming
          ? (mode === 'add' ? 'Adding…' : 'Removing…')
          : (mode === 'add' ? 'Add Liquidity' : 'Remove Liquidity')}
      </button>

      {isSuccess && (
        <p className="text-xs text-green-400">
          {mode === 'add' ? 'Liquidity added.' : 'Liquidity removed — check vault payout in My LP Position.'}
        </p>
      )}
    </div>
  )
}
