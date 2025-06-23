import { ConnectButton } from '@rainbow-me/rainbowkit'

export default function Header() {
  return (
    <header className="flex items-center justify-end px-6 py-4 border-b bg-background/80 backdrop-blur-sm relative z-10">
      <div className="flex items-center space-x-4">
        <div className="hidden md:flex items-center space-x-2 text-sm text-muted-foreground">
          <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
          <span>Live Market Data</span>
        </div>
        <ConnectButton />
      </div>
    </header>
  )
}
