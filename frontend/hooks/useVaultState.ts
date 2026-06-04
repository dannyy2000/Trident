'use client'

import { useReadContracts } from 'wagmi'
import { IL_RESERVE_VAULT_ABI, ERC20_ABI } from '@/lib/abis'
import { CONTRACTS } from '@/lib/contracts'

export type VaultState = {
  totalReserveBalance: bigint
  totalLiability: bigint
  healthRatio: bigint        // 1e18 = 100%
  captureRateBps: bigint
  tokenSymbol: string
  tokenDecimals: number
  healthLabel: 'healthy' | 'low' | 'emergency'
  captureRateLabel: string
  isLoading: boolean
}

export function useVaultState(): VaultState {
  const { data, isLoading } = useReadContracts({
    contracts: [
      { address: CONTRACTS.vault,      abi: IL_RESERVE_VAULT_ABI, functionName: 'totalReserveBalance' },
      { address: CONTRACTS.vault,      abi: IL_RESERVE_VAULT_ABI, functionName: 'totalLiability' },
      { address: CONTRACTS.vault,      abi: IL_RESERVE_VAULT_ABI, functionName: 'vaultHealthRatio' },
      { address: CONTRACTS.vault,      abi: IL_RESERVE_VAULT_ABI, functionName: 'captureRateBps' },
      { address: CONTRACTS.payoutToken, abi: ERC20_ABI,            functionName: 'symbol' },
      { address: CONTRACTS.payoutToken, abi: ERC20_ABI,            functionName: 'decimals' },
    ],
  })

  const reserve       = (data?.[0]?.result as bigint | undefined) ?? BigInt(0)
  const liability     = (data?.[1]?.result as bigint | undefined) ?? BigInt(0)
  const health        = (data?.[2]?.result as bigint | undefined) ?? BigInt(1000000000000000000n)
  const captureRate   = (data?.[3]?.result as bigint | undefined) ?? BigInt(1000)
  const symbol        = (data?.[4]?.result as string | undefined) ?? '?'
  const decimals      = (data?.[5]?.result as number | undefined) ?? 18

  // 0.8e18 = HEALTH_LOW, 0.3e18 = HEALTH_EMERGENCY
  const HEALTH_LOW       = BigInt('800000000000000000')
  const HEALTH_EMERGENCY = BigInt('300000000000000000')

  const healthLabel: VaultState['healthLabel'] =
    health < HEALTH_EMERGENCY ? 'emergency' :
    health < HEALTH_LOW       ? 'low'       :
    'healthy'

  const captureRateLabel = `${Number(captureRate) / 100}%`

  return {
    totalReserveBalance: reserve,
    totalLiability:      liability,
    healthRatio:         health,
    captureRateBps:      captureRate,
    tokenSymbol:         symbol,
    tokenDecimals:       decimals,
    healthLabel,
    captureRateLabel,
    isLoading,
  }
}

/** Formats a raw token amount to a human-readable string with the given decimals. */
export function formatTokenAmount(amount: bigint, decimals: number, precision = 4): string {
  if (amount === BigInt(0)) return '0'
  const divisor = BigInt(10 ** decimals)
  const whole   = amount / divisor
  const frac    = amount % divisor
  const fracStr = frac.toString().padStart(decimals, '0').slice(0, precision)
  return `${whole}.${fracStr}`
}
