// Deployed contract addresses — fill these in after running script/Deploy.s.sol
// All values read from NEXT_PUBLIC_ env vars so they can be set per environment.

const ZERO = '0x0000000000000000000000000000000000000000' as `0x${string}`
const addr = (key: string) => (process.env[key] ?? ZERO) as `0x${string}`

export const CONTRACTS = {
  hook:             addr('NEXT_PUBLIC_TRIDENT_HOOK'),
  vault:            addr('NEXT_PUBLIC_IL_RESERVE_VAULT'),
  tracker:          addr('NEXT_PUBLIC_POSITION_TRACKER'),
  oracleReader:     addr('NEXT_PUBLIC_ORACLE_READER'),
  reactiveAdapter:  addr('NEXT_PUBLIC_REACTIVE_ADAPTER'),
  payoutToken:      addr('NEXT_PUBLIC_PAYOUT_TOKEN'),
  swapHelper:       addr('NEXT_PUBLIC_SWAP_HELPER'),
  liquidityHelper:  addr('NEXT_PUBLIC_LIQUIDITY_HELPER'),
  mockFeed:         addr('NEXT_PUBLIC_MOCK_FEED'),
  poolManager:      addr('NEXT_PUBLIC_POOL_MANAGER'),
}

// PoolKey parameters — must match how the pool was initialised
export const POOL_KEY = {
  token0:       addr('NEXT_PUBLIC_TOKEN0'),
  token1:       addr('NEXT_PUBLIC_TOKEN1'),
  tickSpacing:  Number(process.env.NEXT_PUBLIC_TICK_SPACING ?? '60'),
}

// DYNAMIC_FEE_FLAG — hook sets fee dynamically
export const DYNAMIC_FEE_FLAG = 0x800000
