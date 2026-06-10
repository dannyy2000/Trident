// Minimal ABIs — only functions and events used by the frontend.

export const TRIDENT_HOOK_ABI = [
  // Fee preview
  {
    name: 'previewFee',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      {
        name: 'key',
        type: 'tuple',
        components: [
          { name: 'currency0', type: 'address' },
          { name: 'currency1', type: 'address' },
          { name: 'fee', type: 'uint24' },
          { name: 'tickSpacing', type: 'int24' },
          { name: 'hooks', type: 'address' },
        ],
      },
      { name: 'swapAmount', type: 'int256' },
    ],
    outputs: [
      { name: 'baseFee', type: 'uint24' },
      { name: 'arbPremium', type: 'uint24' },
      { name: 'boundaryPremium', type: 'uint24' },
      { name: 'totalFee', type: 'uint24' },
    ],
  },
  // Reactive-primed state
  { name: 'primedDeviationBps', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'primedGammaScore',   type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'primedBoundaryTick', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'int24' }] },
  { name: 'oracleManipulated',  type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'bool' }] },
  { name: 'pendingCapture',     type: 'function', stateMutability: 'view', inputs: [{ name: 'token', type: 'address' }], outputs: [{ type: 'uint256' }] },
  // Constants
  { name: 'baseFee',                   type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint24' }] },
  { name: 'MAX_FEE_BPS',               type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint24' }] },
  { name: 'MAX_BOUNDARY_PREMIUM_BPS',  type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint24' }] },
  { name: 'vault',                     type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'address' }] },
  // SwapFeeBreakdown event
  {
    name: 'SwapFeeBreakdown',
    type: 'event',
    inputs: [
      { name: 'poolId',            type: 'bytes32', indexed: true },
      { name: 'baseFee',           type: 'uint24',  indexed: false },
      { name: 'arbPremiumBps',     type: 'uint24',  indexed: false },
      { name: 'boundaryPremiumBps',type: 'uint24',  indexed: false },
      { name: 'totalFee',          type: 'uint24',  indexed: false },
      { name: 'vaultCapture',      type: 'uint256', indexed: false },
    ],
  },
  // VaultCaptureAccrued event
  {
    name: 'VaultCaptureAccrued',
    type: 'event',
    inputs: [
      { name: 'token',        type: 'address', indexed: true },
      { name: 'amount',       type: 'uint256', indexed: false },
      { name: 'totalPending', type: 'uint256', indexed: false },
    ],
  },
] as const

export const IL_RESERVE_VAULT_ABI = [
  { name: 'totalReserveBalance', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'totalLiability',      type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'vaultHealthRatio',    type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'captureRateBps',      type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { name: 'positionExists',      type: 'function', stateMutability: 'view', inputs: [{ name: 'positionId', type: 'bytes32' }], outputs: [{ type: 'bool' }] },
  {
    name: 'previewPayout',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'positionId', type: 'bytes32' },
      { name: 'currentTick', type: 'int24' },
    ],
    outputs: [{ type: 'uint256' }],
  },
  // Events
  {
    name: 'VaultDeposit',
    type: 'event',
    inputs: [
      { name: 'token',      type: 'address', indexed: true },
      { name: 'amount',     type: 'uint256', indexed: false },
      { name: 'newBalance', type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'VaultPayout',
    type: 'event',
    inputs: [
      { name: 'lp',            type: 'address', indexed: true },
      { name: 'ilAmount',      type: 'uint256', indexed: false },
      { name: 'loyaltyFactor', type: 'uint256', indexed: false },
      { name: 'payout',        type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'CaptureRateUpdated',
    type: 'event',
    inputs: [
      { name: 'oldRate', type: 'uint256', indexed: false },
      { name: 'newRate', type: 'uint256', indexed: false },
    ],
  },
] as const

export const POSITION_TRACKER_ABI = [
  { name: 'positionExists',   type: 'function', stateMutability: 'view', inputs: [{ name: 'positionId', type: 'bytes32' }], outputs: [{ type: 'bool' }] },
  {
    name: 'getPosition',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'positionId', type: 'bytes32' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'exists',      type: 'bool' },
          { name: 'lp',         type: 'address' },
          { name: 'tickLower',   type: 'int24' },
          { name: 'tickUpper',   type: 'int24' },
          { name: 'entryTick',   type: 'int24' },
          { name: 'liquidity',   type: 'uint128' },
          { name: 'entryBlock',  type: 'uint256' },
          { name: 'outOfRange',  type: 'bool' },
        ],
      },
    ],
  },
  {
    name: 'derivePositionId',
    type: 'function',
    stateMutability: 'pure',
    inputs: [
      { name: 'lp',        type: 'address' },
      { name: 'tickLower', type: 'int24' },
      { name: 'tickUpper', type: 'int24' },
      { name: 'salt',      type: 'bytes32' },
    ],
    outputs: [{ type: 'bytes32' }],
  },
] as const

export const ERC20_ABI = [
  { name: 'decimals',  type: 'function', stateMutability: 'view',        inputs: [], outputs: [{ type: 'uint8' }] },
  { name: 'symbol',    type: 'function', stateMutability: 'view',        inputs: [], outputs: [{ type: 'string' }] },
  { name: 'balanceOf', type: 'function', stateMutability: 'view',        inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'allowance', type: 'function', stateMutability: 'view',        inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'approve',   type: 'function', stateMutability: 'nonpayable',  inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
] as const

// MockERC20 — adds open mint() for testnet faucet
export const MOCK_ERC20_ABI = [
  ...ERC20_ABI,
  { name: 'mint', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [] },
] as const

// PoolManager — getSlot0 to read current sqrtPriceX96
export const POOL_MANAGER_ABI = [
  {
    name: 'getSlot0',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'id', type: 'bytes32' }],
    outputs: [
      { name: 'sqrtPriceX96',       type: 'uint160' },
      { name: 'tick',               type: 'int24'   },
      { name: 'protocolFee',        type: 'uint24'  },
      { name: 'lpFee',              type: 'uint24'  },
    ],
  },
] as const

// POOL_KEY tuple type used in SwapHelper / LiquidityHelper
const POOL_KEY_TUPLE = {
  name: 'key',
  type: 'tuple',
  components: [
    { name: 'currency0',   type: 'address' },
    { name: 'currency1',   type: 'address' },
    { name: 'fee',         type: 'uint24'  },
    { name: 'tickSpacing', type: 'int24'   },
    { name: 'hooks',       type: 'address' },
  ],
} as const

export const SWAP_HELPER_ABI = [
  {
    name: 'swap',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      POOL_KEY_TUPLE,
      {
        name: 'params',
        type: 'tuple',
        components: [
          { name: 'zeroForOne',       type: 'bool'    },
          { name: 'amountSpecified',  type: 'int256'  },
          { name: 'sqrtPriceLimitX96',type: 'uint160' },
        ],
      },
      { name: 'recipient', type: 'address' },
    ],
    outputs: [{ name: 'delta', type: 'int256' }],
  },
] as const

export const LIQUIDITY_HELPER_ABI = [
  {
    name: 'modifyLiquidity',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      POOL_KEY_TUPLE,
      { name: 'liquidityDelta', type: 'int256'   },
      { name: 'tickLower',      type: 'int24'    },
      { name: 'tickUpper',      type: 'int24'    },
      { name: 'salt',           type: 'bytes32'  },
    ],
    outputs: [{ name: 'delta', type: 'int256' }],
  },
] as const

export const MOCK_FEED_ABI = [
  { name: 'latestAnswer', type: 'function', stateMutability: 'view',       inputs: [], outputs: [{ type: 'int256' }] },
  { name: 'decimals',     type: 'function', stateMutability: 'view',       inputs: [], outputs: [{ type: 'uint8'  }] },
  { name: 'setAnswer',    type: 'function', stateMutability: 'nonpayable', inputs: [{ name: '_answer', type: 'int256' }], outputs: [] },
  {
    name: 'AnswerUpdated',
    type: 'event',
    inputs: [
      { name: 'current',   type: 'int256',  indexed: true  },
      { name: 'roundId',   type: 'uint256', indexed: true  },
      { name: 'updatedAt', type: 'uint256', indexed: false },
    ],
  },
] as const
