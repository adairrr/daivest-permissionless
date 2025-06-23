import { ConnectButton } from '@rainbow-me/rainbowkit'

export default function Header() {
  return (
    <header className="flex items-center justify-between px-6 py-4 border-b bg-background">
      <div className="text-xl font-bold">Simplifai</div>
      <ConnectButton />
    </header>
  )
}
