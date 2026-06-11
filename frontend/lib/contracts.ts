export const CONTRACTS = {
  hook:            '0x87Bb5917BA1fa7f4EFD08903a5D305971B4146C0' as `0x${string}`,
  vault:           '0x07b2E842731a16Efc6F3d39bfA468f47b911Bc7f' as `0x${string}`,
  tracker:         '0xe4A49b9Bf9d46aa866397b2a0193DAb2D5D1f424' as `0x${string}`,
  oracleReader:    '0x7de2ceB1316Cc7d9e12668E1771Be88de860FD01' as `0x${string}`,
  reactiveAdapter: '0x7DAd5E3b0A4AfA91414b30AdBf64E33954278b0c' as `0x${string}`,
  payoutToken:     '0x8a777593e7aD6Df9e4b7E104cF3e2B8eF82d0057' as `0x${string}`,
  swapHelper:      '0xa2E9fAF8C2045A5e10842006d064410a6C4aC076' as `0x${string}`,
  liquidityHelper: '0x2F87C8ACBBB399bF77f6a0131284F2a6BC70E78d' as `0x${string}`,
  mockFeed:        '0x467A074ADE6B5D828cd57EB2CeC76Cc396ca6Db6' as `0x${string}`,
  poolManager:     '0x00B036B58a818B1BC34d502D3fE730Db729e62AC' as `0x${string}`,
}

export const POOL_KEY = {
  token0:      '0x8a777593e7aD6Df9e4b7E104cF3e2B8eF82d0057' as `0x${string}`, // mWETH
  token1:      '0xff455ad480806CdC260B7073BAfDa9a191c0ff92' as `0x${string}`, // mUSDC
  tickSpacing: 60,
}

// DYNAMIC_FEE_FLAG — hook sets fee dynamically
export const DYNAMIC_FEE_FLAG = 0x800000
