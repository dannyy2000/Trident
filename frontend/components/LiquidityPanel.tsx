'use client'

import { useState, useEffect } from 'react'
import { keccak256, encodeAbiParameters } from 'viem'
import {
  useAccount, useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt,
} from 'wagmi'
import { CONTRACTS, POOL_KEY, DYNAMIC_FEE_FLAG } from '@/lib/contracts'
import { LIQUIDITY_HELPER_ABI, ERC20_ABI, POOL_MANAGER_ABI, POSITION_TRACKER_ABI } from '@/lib/abis'

type Mode = 'add' | 'remove'

const POOL_ID = '0x5e1589e36bf91d1b848851741701815f43d2b750dd64b05135b771f340b1d4e6' as `0x${string}`

function sqrtX96(tick: number): bigint {
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
    if (amount0 === 0n || sqrtB <= sqrtA) return 0n
    return (amount0 * sqrtA * sqrtB / Q96) / (sqrtB - sqrtA)
  } else if (sqrtPrice < sqrtB) {
    const liq0 = sqrtPrice > 0n
      ? (amount0 * sqrtPrice * sqrtB / Q96) / (sqrtB - sqrtPrice)
      : 0n
    const liq1 = (amount1 * Q96) / (sqrtPrice - sqrtA)
    return liq0 < liq1 ? liq0 : liq1
  } else {
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

const ZERO_BYTES32 = ('0x' + '0'.repeat(64)) as `0x${string}`

export function LiquidityPanel() {
  const { address, isConnected } = useAccount()
  const [mode,      setMode]      = useState<Mode>('add')
  const [tickLower, setTickLower] = useState(-196980)
  const [tickUpper, setTickUpper] = useState(-195600)
  const [amount0In, setAmount0In] = useState('')
  const [amount1In, setAmount1In] = useState('')
  const [txHash,       setTxHash]       = useState<`0x${string}` | undefined>()
  const [approvingIdx, setApprovingIdx] = useState<0 | 1 | null>(null)

  const FALLBACK_SQRT_PRICE = 4339505179874779662909440n

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

  const dec0 = Number((meta?.[0].result as bigint | undefined) ?? 18n)
  const dec1 = Number((meta?.[1].result as bigint | undefined) ?? 6n)
  const sym0 = (meta?.[2].result as string | undefined) ?? 'token0'
  const sym1 = (meta?.[3].result as string | undefined) ?? 'token1'
  const all0 = (meta?.[4].result as bigint | undefined) ?? 0n
  const all1 = (meta?.[5].result as bigint | undefined) ?? 0n

  const sqrtPrice = ((slot0 as any)?.[0] as bigint | undefined) ?? FALLBACK_SQRT_PRICE

  // ── Position fetch for remove mode ───────────────────────────────
  const positionId = keccak256(encodeAbiParameters(
    [
      { name: 'lp',        type: 'address' },
      { name: 'tickLower', type: 'int24'   },
      { name: 'tickUpper', type: 'int24'   },
      { name: 'salt',      type: 'bytes32' },
    ],
    [CONTRACTS.liquidityHelper, tickLower, tickUpper, ZERO_BYTES32]
  ))

  const { data: positionData } = useReadContract({
    address: CONTRACTS.tracker,
    abi: POSITION_TRACKER_ABI,
    functionName: 'getPosition',
    args: [positionId],
    query: { enabled: mode === 'remove', refetchInterval: 5000 },
  })

  const positionLiquidity: bigint = positionData ? (positionData as any).liquidity as bigint : 0n
  const positionExists:  boolean  = positionData ? (positionData as any).exists  as boolean : false

  // Pre-fill remove input when position data arrives
  useEffect(() => {
    if (mode === 'remove' && positionLiquidity > 0n) {
      setAmount0In(positionLiquidity.toString())
    }
  }, [mode, positionLiquidity.toString()])

  // ── Amount parsing ────────────────────────────────────────────────
  const raw0 = amount0In && mode === 'add'
    ? BigInt(Math.floor(parseFloat(amount0In) * 10 ** dec0))
    : 0n
  const raw1 = amount1In && mode === 'add'
    ? BigInt(Math.floor(parseFloat(amount1In) * 10 ** dec1))
    : 0n

  const liquidityDelta: bigint = (() => {
    if (mode === 'remove') {
      try { return -(BigInt(amount0In || '0')) } catch { return 0n }
    }
    if (raw0 === 0n && raw1 === 0n) return 0n
    return getLiquidityForAmounts(sqrtPrice, tickLower, tickUpper, raw0, raw1)
  })()

  const MAX_UINT256 = 2n ** 256n - 1n
  const needsApprove0 = mode === 'add' && raw0 > 0n && all0 < raw0
  const needsApprove1 = mode === 'add' && raw1 > 0n && all1 < raw1

  const { mutate: writeContract, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })
  if (isSuccess) { refetchMeta(); setTxHash(undefined); setApprovingIdx(null) }

  const busy = isPending || isConfirming || approvingIdx !== null

  function approve(which: 0 | 1) {
    if (busy) return
    setApprovingIdx(which)
    const tokenAddr = which === 0 ? POOL_KEY.token0 : POOL_KEY.token1
    writeContract(
      { address: tokenAddr, abi: ERC20_ABI, functionName: 'approve',
        args: [CONTRACTS.liquidityHelper, MAX_UINT256] },
      {
        onSuccess: (hash) => setTxHash(hash),
        onError: () => setApprovingIdx(null),
      }
    )
  }

  function modify() {
    if (liquidityDelta === 0n) return
    writeContract(
      {
        address: CONTRACTS.liquidityHelper,
        abi: LIQUIDITY_HELPER_ABI,
        functionName: 'modifyLiquidity',
        args: [POOL_KEY_TUPLE, liquidityDelta, tickLower, tickUpper, ZERO_BYTES32],
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
              onClick={() => { setMode(m); setAmount0In(''); setAmount1In('') }}
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

      {/* Remove mode: show fetched position info */}
      {mode === 'remove' && (
        <div className="flex items-center justify-between bg-gray-800/60 rounded-lg px-3 py-2">
          <div className="text-xs text-gray-400">
            {positionExists
              ? <>Position liquidity: <span className="font-mono text-white">{positionLiquidity.toString()}</span></>
              : <span className="text-red-400">No active position found for these ticks</span>
            }
          </div>
          {positionExists && positionLiquidity > 0n && (
            <button
              onClick={() => setAmount0In(positionLiquidity.toString())}
              className="text-xs text-indigo-400 hover:text-indigo-300 font-semibold ml-3"
            >
              Use Max
            </button>
          )}
        </div>
      )}

      {/* Token amounts */}
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="text-xs text-gray-500 block mb-1">
            {mode === 'remove' ? 'Liquidity to remove' : `${sym0} amount`}
          </label>
          <input
            type={mode === 'remove' ? 'text' : 'number'}
            placeholder={mode === 'add' ? '0.0' : 'liquidity units'}
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

      {/* Approve buttons */}
      {mode === 'add' && (needsApprove0 || needsApprove1) && (
        <div className="flex gap-2">
          {needsApprove0 && (
            <button
              onClick={() => approve(0)}
              disabled={busy}
              className="flex-1 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 disabled:opacity-40 text-xs font-semibold text-gray-200 transition-colors"
            >
              {approvingIdx === 0 ? 'Approving…' : `Approve ${sym0}`}
            </button>
          )}
          {needsApprove1 && (
            <button
              onClick={() => approve(1)}
              disabled={busy}
              className="flex-1 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 disabled:opacity-40 text-xs font-semibold text-gray-200 transition-colors"
            >
              {approvingIdx === 1 ? 'Approving…' : `Approve ${sym1}`}
            </button>
          )}
        </div>
      )}

      <button
        onClick={modify}
        disabled={!canModify || busy}
        className={`w-full py-2.5 rounded-lg text-sm font-semibold transition-colors disabled:opacity-40 disabled:cursor-not-allowed ${
          mode === 'add'
            ? 'bg-indigo-600 hover:bg-indigo-500 text-white'
            : 'bg-red-800 hover:bg-red-700 text-white'
        }`}
      >
        {busy
          ? (mode === 'add' ? 'Adding…' : 'Removing…')
          : (mode === 'add' ? 'Add Liquidity' : 'Remove Liquidity')}
      </button>

      {isSuccess && (
        <div className="rounded-lg bg-green-950/40 border border-green-800/50 px-3 py-2 text-xs text-green-300 space-y-0.5">
          {mode === 'add' ? (
            <>
              <p className="font-semibold">Liquidity added</p>
              <p className="opacity-80">Your position is now earning fees. Arb bots and boundary-aware premiums will accrue to you while price stays in range.</p>
            </>
          ) : (
            <>
              <p className="font-semibold">Liquidity removed — tokens returned to your wallet</p>
              <p className="opacity-80">Both mWETH and mUSDC have been sent back. If your position was eligible, an IL compensation payout from the vault was included — check <span className="font-mono">My Position</span> above.</p>
            </>
          )}
        </div>
      )}
    </div>
  )
}
