'use client'

import { useReadContract } from 'wagmi'
import { TRIDENT_HOOK_ABI } from '@/lib/abis'
import { CONTRACTS, POOL_KEY } from '@/lib/contracts'

type FeeBreakdown = {
  baseFee: number
  arbPremium: number
  boundaryPremium: number
  totalFee: number
  primedDeviationBps: bigint
  primedGammaScore: bigint
  primedBoundaryTick: number
  oracleManipulated: boolean
  isLoading: boolean
}

function bpsToPct(bps: number): string {
  return (bps / 10_000).toFixed(4) + '%'
}

export function useFeeBreakdown(): FeeBreakdown {
  const poolKey = {
    currency0: POOL_KEY.token0,
    currency1: POOL_KEY.token1,
    fee: 0x800000 as number, // DYNAMIC_FEE_FLAG = LPFeeLibrary.DYNAMIC_FEE_FLAG
    tickSpacing: POOL_KEY.tickSpacing,
    hooks: CONTRACTS.hook,
  }

  const { data: fees, isLoading: feesLoading } = useReadContract({
    address: CONTRACTS.hook,
    abi: TRIDENT_HOOK_ABI,
    functionName: 'previewFee',
    args: [poolKey, BigInt(0)],
  })

  const { data: deviationBps } = useReadContract({
    address: CONTRACTS.hook,
    abi: TRIDENT_HOOK_ABI,
    functionName: 'primedDeviationBps',
  })

  const { data: gammaScore } = useReadContract({
    address: CONTRACTS.hook,
    abi: TRIDENT_HOOK_ABI,
    functionName: 'primedGammaScore',
  })

  const { data: boundaryTick } = useReadContract({
    address: CONTRACTS.hook,
    abi: TRIDENT_HOOK_ABI,
    functionName: 'primedBoundaryTick',
  })

  const { data: manipulated } = useReadContract({
    address: CONTRACTS.hook,
    abi: TRIDENT_HOOK_ABI,
    functionName: 'oracleManipulated',
  })

  return {
    baseFee:          fees ? Number(fees[0]) : 0,
    arbPremium:       fees ? Number(fees[1]) : 0,
    boundaryPremium:  fees ? Number(fees[2]) : 0,
    totalFee:         fees ? Number(fees[3]) : 0,
    primedDeviationBps: deviationBps ?? BigInt(0),
    primedGammaScore:   gammaScore ?? BigInt(0),
    primedBoundaryTick: boundaryTick ? Number(boundaryTick) : 0,
    oracleManipulated:  manipulated ?? false,
    isLoading:          feesLoading,
  }
}

export { bpsToPct }
