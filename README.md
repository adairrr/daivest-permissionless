# Daivest

A proof-of-concept portfolio management platform using Account Abstraction (ERC-7579) and automated smart contract modules.

## Concept

This hackathon project demonstrates:
- Modular smart accounts for portfolio management
- Target allocation-based rebalancing
- Trade execution through PancakeSwap 
- Portfolio protection using Forte Rules Engine
- Integration with Supra oracles for price feeds
- Built on BNB Chain testnet

## Project Structure

```
packages/
├── smart-contracts/          # Smart contracts
│   ├── src/
│   │   ├── PortfolioManagerExecutor.sol    # Main portfolio manager
│   │   ├── RulesEngineClientCustom.sol     # Forte rules integration
│   │   └── ...
│   ├── script/               # Deploy scripts
│   ├── test/                 # Tests
│   └── policy.json          # Forte rules policy
└── frontend/                 # React app
    ├── src/App.tsx          # Portfolio creation UI
    └── ...
```

## Key Contracts

### [PortfolioManagerExecutor.sol](./packages/smart-contracts/src/PortfolioManagerExecutor.sol)
ERC-7579 executor module with:
- Portfolio configuration and target allocations
- Drift-based rebalancing logic
- **Supra Oracle** integration for price feeds (also intended for automation triggers)
- PancakeSwap V2/V3 routing
- **Forte Rules Engine** integration for portfolio protection

### [RulesEngineClientCustom.sol](./packages/smart-contracts/src/RulesEngineClientCustom.sol)
**Forte Rules Engine** modifiers generated from [policy.json](./packages/smart-contracts/policy.json):
- Portfolio value protection during rebalancing
- Rebalancing frequency limits
- Drift threshold enforcement

## Deployed Contracts

**BNB Chain Testnet:**
| Contract | Address |
|----------|---------|
| PortfolioManagerExecutor | `0x216F8088DF93940e6117561d5b293F5151c6329c` |
| Safe Account (Example) | `0x3fE9d4BE344fD83AEFB818af23F35c61c0003FF5` |

## Setup

```bash
# Install dependencies
pnpm install
```

## Commands

**Smart Contracts:**
```bash
cd packages/smart-contracts

# Compile and test
forge build
forge test

# Deploy to BSC testnet
forge script script/DeployModule.s.sol --rpc-url $BSC_TESTNET_RPC --broadcast
```

**Frontend:**
```bash
cd packages/frontend

# Run the app
pnpm dev
```

## Implementation Status

✅ **Smart Contracts**: Successfully deployed to **BNB Chain** testnet
- PortfolioManagerExecutor with **Supra Oracle** integration
- **Forte Rules Engine** policy generation and integration
- Safe account creation scripts

❌ **Frontend Integration**: Encountered bundler issues with Account Abstraction on testnets
- Smart account creation UI implemented
- Bundler/paymaster integration attempted but failed due to testnet infrastructure limitations
- Contracts are deployed but frontend cannot interact with AA infrastructure

## Intended Flow

1. Create Safe smart account with portfolio module
2. Set target allocations (e.g., 50% BNB, 30% CAKE, 20% USDT)
3. **Supra Oracle** provides price feeds and automation triggers
4. Contract rebalances when portfolio drifts from targets
5. **Forte Rules Engine** protects portfolio value during trades
6. All on **BNB Chain** with gasless transactions

## Tech Stack

- **Blockchain**: BNB Chain testnet
- **Oracles**: Supra (price feeds + intended automation)
- **Risk Management**: Forte Rules Engine
- **Smart Contracts**: Solidity, Foundry, ERC-7579
- **Frontend**: React, TypeScript, Wagmi
- **Account Abstraction**: Safe, Rhinestone (deployment issues on testnet)

**Hackathon Project - Permissionless IV**