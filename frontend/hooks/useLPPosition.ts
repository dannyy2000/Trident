'use client'

import { useAccount, useReadContract, useReadContracts } from 'wagmi'
import { encodeAbiParameters, keccak256 } from 'viem'
import { POSITION_TRACKER_ABI, IL_RESERVE_VAULT_ABI } from '@/lib/abis'
import { CONTRACTS } from '@/lib/contracts'

export type LPPosition = {
  exists: boolean
  lp: string
  tickLower: number
  tickUpper: number
  entryTick: number
  liquidity: bigint
  entryBlock: bigint
  outOfRange: boolean
  estimatedPayout: bigint
  positionId: `0x${string}`
  isLoading: boolean
}

// currentTick must come from the pool (e.g. PoolManager.getSlot0).
// For now we accept it as a prop; the parent reads it once and passes it down.
export function useLPPosition(params: {
  tickLower: number
  tickUpper: number
  salt?: `0x${string}`
  currentTick: number
}): LPPosition {
  const { address } = useAccount()
  const salt = params.salt ?? ('0x' + '0'.repeat(64) as `0x${string}`)

  const positionId = address
    ? keccak256(encodeAbiParameters(
        [
          { name: 'lp',        type: 'address' },
          { name: 'tickLower', type: 'int24' },
          { name: 'tickUpper', type: 'int24' },
          { name: 'salt',      type: 'bytes32' },
        ],
        [address, params.tickLower, params.tickUpper, salt]
      ))
    : ('0x' + '0'.repeat(64) as `0x${string}`)

  const enabled = !!address

  const { data: positionData, isLoading: posLoading } = useReadContract({
    address: CONTRACTS.tracker,
    abi: POSITION_TRACKER_ABI,
    functionName: 'getPosition',
    args: [positionId],
    query: { enabled },
  })

  const { data: estimatedPayout, isLoading: payoutLoading } = useReadContract({
    address: CONTRACTS.vault,
    abi: IL_RESERVE_VAULT_ABI,
    functionName: 'previewPayout',
    args: [positionId, params.currentTick],
    query: { enabled },
  })

  const pos = positionData as {
    exists: boolean; lp: string; tickLower: number; tickUpper: number
    entryTick: number; liquidity: bigint; entryBlock: bigint; outOfRange: boolean
  } | undefined

  return {
    exists:           pos?.exists ?? false,
    lp:               pos?.lp ?? '',
    tickLower:        pos?.tickLower ?? 0,
    tickUpper:        pos?.tickUpper ?? 0,
    entryTick:        pos?.entryTick ?? 0,
    liquidity:        pos?.liquidity ?? BigInt(0),
    entryBlock:       pos?.entryBlock ?? BigInt(0),
    outOfRange:       pos?.outOfRange ?? false,
    estimatedPayout:  estimatedPayout ?? BigInt(0),
    positionId,
    isLoading:        posLoading || payoutLoading,
  }
}
