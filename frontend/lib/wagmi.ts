'use client'

import { createConfig, http } from 'wagmi'
import { injected } from 'wagmi/connectors'
import { defineChain } from 'viem'

export const unichainSepolia = defineChain({
  id: 1301,
  name: 'Unichain Sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://sepolia.unichain.org'] },
  },
  blockExplorers: {
    default: { name: 'Uniscan', url: 'https://sepolia.uniscan.xyz' },
  },
  testnet: true,
})

export const wagmiConfig = createConfig({
  chains: [unichainSepolia],
  connectors: [injected()],
  transports: {
    [unichainSepolia.id]: http('https://sepolia.unichain.org'),
  },
  ssr: true,
})
