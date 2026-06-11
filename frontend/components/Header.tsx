'use client'

import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { injected } from 'wagmi/connectors'

export function Header() {
  const { address, isConnected } = useAccount()
  const { connect } = useConnect()
  const { disconnect } = useDisconnect()

  return (
    <header className="border-b border-gray-800 bg-gray-950/80 backdrop-blur sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
              <rect x="4"  y="8" width="4" height="16" rx="2" fill="#6366f1" />
              <rect x="12" y="4" width="4" height="20" rx="2" fill="#818cf8" />
              <rect x="20" y="8" width="4" height="16" rx="2" fill="#6366f1" />
            </svg>
            <span className="text-lg font-bold tracking-tight text-white">Trident</span>
          </div>
          <span className="hidden sm:block text-xs text-gray-500 border border-gray-700 rounded px-2 py-0.5">
            Unichain Sepolia
          </span>
        </div>

        <nav className="hidden md:flex items-center gap-6 text-sm text-gray-400">
          <a href="#dashboard" className="hover:text-white transition-colors">Dashboard</a>
          <a href="#position"  className="hover:text-white transition-colors">My Position</a>
          <a href="#activity"  className="hover:text-white transition-colors">Activity</a>
        </nav>

        {isConnected ? (
          <div className="flex items-center gap-3">
            <span className="text-xs font-mono text-gray-400 hidden sm:block">
              {address?.slice(0, 6)}...{address?.slice(-4)}
            </span>
            <button
              onClick={() => disconnect()}
              className="text-xs px-3 py-1.5 rounded-lg border border-gray-700 text-gray-400 hover:text-white hover:border-gray-500 transition-colors"
            >
              Disconnect
            </button>
          </div>
        ) : (
          <button
            onClick={() => connect({ connector: injected() })}
            className="px-4 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold transition-colors"
          >
            Connect Wallet
          </button>
        )}
      </div>
    </header>
  )
}
