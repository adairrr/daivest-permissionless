import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { http } from 'wagmi';
import { bscTestnet } from 'wagmi/chains'


export const config = getDefaultConfig({
  appName: 'Simplifai',
  projectId: import.meta.env.VITE_WC_PROJECT_ID,
  chains: [bscTestnet],
  transports: {
    [bscTestnet.id]: http('https://data-seed-prebsc-1-s1.binance.org:8545/'),
  },
  ssr: false, // Set to true if you use SSR
});

declare module 'wagmi' {
  interface Register {
    config: typeof config;
  }
}
