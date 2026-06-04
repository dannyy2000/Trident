'use client'

import { useWatchContractEvent, usePublicClient } from 'wagmi'
import { useState, useEffect } from 'react'
import { TRIDENT_HOOK_ABI } from '@/lib/abis'
import { CONTRACTS } from '@/lib/contracts'

export type SwapEvent = {
  poolId: `0x${string}`
  baseFee: number
  arbPremiumBps: number
  boundaryPremiumBps: number
  totalFee: number
  vaultCapture: bigint
  blockNumber: bigint
  txHash: `0x${string}`
  timestamp: number
}

const MAX_EVENTS = 20

export function useSwapEvents() {
  const [events, setEvents] = useState<SwapEvent[]>([])
  const client = usePublicClient()

  // Fetch recent historical events on mount
  useEffect(() => {
    if (!client) return
    ;(async () => {
      try {
        const block = await client.getBlockNumber()
        const fromBlock = block > BigInt(500) ? block - BigInt(500) : BigInt(0)

        const logs = await client.getLogs({
          address: CONTRACTS.hook,
          event: TRIDENT_HOOK_ABI.find(x => x.type === 'event' && x.name === 'SwapFeeBreakdown') as never,
          fromBlock,
          toBlock: block,
        })

        const parsed: SwapEvent[] = logs.slice(-MAX_EVENTS).map((log: {
          args?: { poolId?: `0x${string}`; baseFee?: number; arbPremiumBps?: number; boundaryPremiumBps?: number; totalFee?: number; vaultCapture?: bigint }
          blockNumber?: bigint
          transactionHash?: `0x${string}`
        }) => ({
          poolId:            log.args?.poolId            ?? ('0x' as `0x${string}`),
          baseFee:           Number(log.args?.baseFee    ?? 0),
          arbPremiumBps:     Number(log.args?.arbPremiumBps ?? 0),
          boundaryPremiumBps:Number(log.args?.boundaryPremiumBps ?? 0),
          totalFee:          Number(log.args?.totalFee   ?? 0),
          vaultCapture:      log.args?.vaultCapture      ?? BigInt(0),
          blockNumber:       log.blockNumber             ?? BigInt(0),
          txHash:            log.transactionHash         ?? ('0x' as `0x${string}`),
          timestamp:         Date.now(),
        }))

        setEvents(parsed.reverse())
      } catch {
        // Silently ignore — node may not have logs enabled yet
      }
    })()
  }, [client])

  // Watch for new events in real time
  useWatchContractEvent({
    address: CONTRACTS.hook,
    abi: TRIDENT_HOOK_ABI,
    eventName: 'SwapFeeBreakdown',
    onLogs(logs) {
      const newEvents: SwapEvent[] = logs.map((log) => ({
        poolId:            (log as { args: { poolId: `0x${string}` } }).args.poolId,
        baseFee:           Number((log as { args: { baseFee: number } }).args.baseFee),
        arbPremiumBps:     Number((log as { args: { arbPremiumBps: number } }).args.arbPremiumBps),
        boundaryPremiumBps:Number((log as { args: { boundaryPremiumBps: number } }).args.boundaryPremiumBps),
        totalFee:          Number((log as { args: { totalFee: number } }).args.totalFee),
        vaultCapture:      (log as { args: { vaultCapture: bigint } }).args.vaultCapture,
        blockNumber:       (log as { blockNumber: bigint }).blockNumber,
        txHash:            (log as { transactionHash: `0x${string}` }).transactionHash,
        timestamp:         Date.now(),
      }))
      setEvents(prev => [...newEvents, ...prev].slice(0, MAX_EVENTS))
    },
  })

  return events
}
