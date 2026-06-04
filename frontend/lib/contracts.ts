// Deployed contract addresses — fill these in after running script/Deploy.s.sol
// All values read from NEXT_PUBLIC_ env vars so they can be set per environment.

export const CONTRACTS = {
  hook:           (process.env.NEXT_PUBLIC_TRIDENT_HOOK           ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
  vault:          (process.env.NEXT_PUBLIC_IL_RESERVE_VAULT       ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
  tracker:        (process.env.NEXT_PUBLIC_POSITION_TRACKER       ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
  oracleReader:   (process.env.NEXT_PUBLIC_ORACLE_READER          ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
  reactiveAdapter:(process.env.NEXT_PUBLIC_REACTIVE_ADAPTER       ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
  payoutToken:    (process.env.NEXT_PUBLIC_PAYOUT_TOKEN           ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
}

// PoolKey parameters — must match how the pool was initialised
export const POOL_KEY = {
  token0:       (process.env.NEXT_PUBLIC_TOKEN0        ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
  token1:       (process.env.NEXT_PUBLIC_TOKEN1        ?? '0x0000000000000000000000000000000000000000') as `0x${string}`,
  tickSpacing:  Number(process.env.NEXT_PUBLIC_TICK_SPACING ?? '60'),
}
