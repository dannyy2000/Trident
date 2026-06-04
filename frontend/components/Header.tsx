'use client'

import { ConnectButton } from '@rainbow-me/rainbowkit'

export function Header() {
  return (
    <header className="border-b border-gray-800 bg-gray-950/80 backdrop-blur sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            {/* Trident logo — three bars */}
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

        <ConnectButton
          accountStatus="address"
          chainStatus="icon"
          showBalance={false}
        />
      </div>
    </header>
  )
}
