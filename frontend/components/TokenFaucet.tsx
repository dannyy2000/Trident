'use client'

import { useAccount, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { useState } from 'react'
import { POOL_KEY } from '@/lib/contracts'
import { MOCK_ERC20_ABI, ERC20_ABI } from '@/lib/abis'

const WETH_MINT = 10n * 10n ** 18n       // 10 mWETH
const USDC_MINT = 30000n * 10n ** 6n     // 30,000 mUSDC

export function TokenFaucet() {
  const { address, isConnected } = useAccount()
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>()
  const [minting, setMinting] = useState<'weth' | 'usdc' | null>(null)

  const { data: balances, refetch } = useReadContracts({
    contracts: [
      { address: POOL_KEY.token0, abi: ERC20_ABI, functionName: 'balanceOf', args: address ? [address] : undefined },
      { address: POOL_KEY.token1, abi: ERC20_ABI, functionName: 'balanceOf', args: address ? [address] : undefined },
      { address: POOL_KEY.token0, abi: ERC20_ABI, functionName: 'symbol' },
      { address: POOL_KEY.token1, abi: ERC20_ABI, functionName: 'symbol' },
      { address: POOL_KEY.token0, abi: ERC20_ABI, functionName: 'decimals' },
      { address: POOL_KEY.token1, abi: ERC20_ABI, functionName: 'decimals' },
    ],
    query: { enabled: !!address, refetchInterval: 8000 },
  })

  const { mutate: writeContract, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash: txHash })
  if (isSuccess) { refetch(); setTxHash(undefined) }

  function fmt(raw: bigint | undefined, dec: number) {
    if (raw === undefined) return '—'
    return (Number(raw) / 10 ** dec).toLocaleString(undefined, { maximumFractionDigits: 4 })
  }

  const bal0    = balances?.[0].result as bigint | undefined
  const bal1    = balances?.[1].result as bigint | undefined
  const sym0    = (balances?.[2].result as string | undefined) ?? 'token0'
  const sym1    = (balances?.[3].result as string | undefined) ?? 'token1'
  const dec0    = Number((balances?.[4].result as bigint | undefined) ?? 18n)
  const dec1    = Number((balances?.[5].result as bigint | undefined) ?? 6n)

  function mint(token: 'weth' | 'usdc') {
    if (!address) return
    setMinting(token)
    const tokenAddr = token === 'weth' ? POOL_KEY.token0 : POOL_KEY.token1
    const amount    = token === 'weth' ? WETH_MINT : USDC_MINT
    writeContract(
      { address: tokenAddr, abi: MOCK_ERC20_ABI, functionName: 'mint', args: [address, amount] },
      {
        onSuccess: (hash) => { setTxHash(hash); setMinting(null) },
        onError:   ()     => setMinting(null),
      }
    )
  }

  if (!isConnected) return null

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl p-5 space-y-3">
      <div className="flex items-center gap-2">
        <h2 className="font-semibold text-white text-sm">Test Token Faucet</h2>
        <span className="ml-auto text-xs text-gray-600">open mint — testnet only</span>
      </div>

      <div className="grid grid-cols-2 gap-3 text-sm">
        <div className="bg-gray-800/60 rounded-lg p-3 space-y-2">
          <div className="flex justify-between text-xs text-gray-500">
            <span>{sym0}</span>
            <span className="font-mono">{fmt(bal0, dec0)}</span>
          </div>
          <button
            onClick={() => mint('weth')}
            disabled={isPending || isConfirming || minting === 'weth'}
            className="w-full py-1.5 rounded-lg bg-indigo-700 hover:bg-indigo-600 disabled:opacity-40 text-xs font-semibold text-white transition-colors"
          >
            {minting === 'weth' ? 'Minting…' : `Get 10 ${sym0}`}
          </button>
        </div>

        <div className="bg-gray-800/60 rounded-lg p-3 space-y-2">
          <div className="flex justify-between text-xs text-gray-500">
            <span>{sym1}</span>
            <span className="font-mono">{fmt(bal1, dec1)}</span>
          </div>
          <button
            onClick={() => mint('usdc')}
            disabled={isPending || isConfirming || minting === 'usdc'}
            className="w-full py-1.5 rounded-lg bg-indigo-700 hover:bg-indigo-600 disabled:opacity-40 text-xs font-semibold text-white transition-colors"
          >
            {minting === 'usdc' ? 'Minting…' : `Get 30k ${sym1}`}
          </button>
        </div>
      </div>

      {isSuccess && (
        <p className="text-xs text-green-400">Minted — balances updated above.</p>
      )}
    </div>
  )
}
