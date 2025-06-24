# Daivest

An AI-powered decentralized portfolio management platform built on Account Abstraction (ERC-7579) with automated rebalancing and risk protection through the Forte Rules Engine.

## 🌟 Overview

Daivest revolutionizes portfolio management by combining:

- **Account Abstraction (ERC-7579)**: Modular smart accounts for seamless user experience
- **AI-Powered Analytics**: Intelligent portfolio optimization and risk assessment
- **Automated Rebalancing**: Smart contract-based portfolio rebalancing with drift detection
- **Risk Protection**: Forte Rules Engine integration for portfolio NAV protection
- **Multi-DEX Routing**: Optimal swap execution across PancakeSwap V2/V3
- **Gasless Transactions**: Sponsored transactions through Alchemy paymaster

## 🏗️ Architecture

### Monorepo Structure

```
packages/
├── smart-contracts/          # Core smart contract modules
│   ├── src/
│   │   ├── PortfolioManagerExecutor.sol    # Main portfolio management module
│   │   ├── RulesEngineClientCustom.sol     # Generated Forte Rules Engine modifiers
│   │   └── ...
│   ├── script/               # Deployment and utility scripts
│   ├── test/                 # Contract tests
│   └── policy.json          # Forte Rules Engine policy configuration
├── frontend/                 # React.js web application
│   ├── src/
│   │   ├── App.tsx          # Main application with portfolio creation interface
│   │   ├── wagmi.ts         # Web3 configuration
│   │   └── ...
│   └── package.json
└── package.json             # Root workspace configuration
```

## 🚀 Core Components

### Smart Contracts

#### [PortfolioManagerExecutor.sol](./packages/smart-contracts/src/PortfolioManagerExecutor.sol)
The core ERC-7579 executor module that provides:
- **Portfolio Configuration**: Multi-asset portfolio setup with target allocations
- **Automated Rebalancing**: Drift-based rebalancing with configurable thresholds
- **Price Feed Integration**: Supra Oracle integration for real-time asset pricing
- **Optimal Routing**: Multi-hop swap routing across PancakeSwap V2/V3
- **Risk Management**: Integration with Forte Rules Engine for portfolio protection

#### [RulesEngineClientCustom.sol](./packages/smart-contracts/src/RulesEngineClientCustom.sol)
Generated Forte Rules Engine modifiers based on [policy.json](./packages/smart-contracts/policy.json):
- **Portfolio NAV Protection**: Ensures portfolio value changes stay within drift thresholds
- **Rebalancing Frequency Control**: Monitors and adjusts for excessive rebalancing
- **Emergency Protections**: Automatic safeguards against significant value loss

### Frontend Application

- **Portfolio Creation Interface**: User-friendly interface for creating modular smart accounts
- **Real-time Analytics**: Live portfolio performance and drift monitoring
- **Transaction Management**: Gasless transaction execution through account abstraction
- **Multi-chain Support**: Built for BSC testnet with extensible chain configuration

## 🌐 Deployed Contracts

### BSC Testnet

| Contract | Address | Explorer |
|----------|---------|----------|
| PortfolioManagerExecutor | `0x216F8088DF93940e6117561d5b293F5151c6329c` | [View on BSCScan](https://testnet.bscscan.com/address/0x216F8088DF93940e6117561d5b293F5151c6329c) |
| Safe Account (Example) | `0x3fE9d4BE344fD83AEFB818af23F35c61c0003FF5` | [View on BSCScan](https://testnet.bscscan.com/address/0x3fE9d4BE344fD83AEFB818af23F35c61c0003FF5) |

## 🔧 Development

### Prerequisites

- Node.js 18+
- pnpm
- Foundry (for smart contracts)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd simplifai

# Install dependencies
pnpm install
```

### Smart Contracts

```bash
# Navigate to smart contracts package
cd packages/smart-contracts

# Compile contracts
forge build

# Run tests
forge test

# Run tests with verbosity
forge test -vvv

# Deploy to BSC testnet (requires .env configuration)
forge script script/DeployModule.s.sol --rpc-url $BSC_TESTNET_RPC --broadcast --verify

# Create Safe account
forge script script/CreateSafeAccount.s.sol --rpc-url $BSC_TESTNET_RPC --broadcast
```

### Frontend

```bash
# Navigate to frontend package
cd packages/frontend

# Start development server
pnpm dev

# Build for production
pnpm build

# Lint code
pnpm lint
```

### Environment Configuration

Create `.env` files in the appropriate packages:

**packages/smart-contracts/.env:**
```env
PRIVATE_KEY=your_private_key_here
BSC_TESTNET_RPC=https://data-seed-prebsc-1-s1.binance.org:8545
BSCSCAN_API_KEY=your_bscscan_api_key
```

**packages/frontend/.env:**
```env
VITE_ALCHEMY_API_KEY=your_alchemy_api_key
VITE_WALLETCONNECT_PROJECT_ID=your_walletconnect_project_id
```

## 🧪 Testing

### Smart Contract Tests

```bash
cd packages/smart-contracts

# Run all tests
forge test

# Run specific test file
forge test --match-path test/PortfolioManagerExecutor.t.sol

# Run tests with gas reporting
forge test --gas-report

# Run production-ready tests
forge test --match-path test/PortfolioManagerExecutor.Production.t.sol
```

### Frontend Tests

```bash
cd packages/frontend

# Run component tests (when implemented)
pnpm test

# Type checking
pnpm build
```

## 🔐 Security Features

### Forte Rules Engine Integration

The project integrates with Forte Rules Engine for advanced portfolio protection:

- **Drift Monitoring**: Tracks portfolio value changes and enforces maximum drift thresholds
- **Rebalancing Controls**: Prevents excessive rebalancing frequency
- **NAV Protection**: Ensures portfolio value stability during operations
- **Policy-Based Governance**: Rule definitions in [policy.json](./packages/smart-contracts/policy.json)

### Account Abstraction Security

- **Modular Architecture**: ERC-7579 compliant modular smart accounts
- **Multi-signature Support**: Safe integration for enhanced security
- **Gasless Transactions**: Sponsored transactions reduce user friction
- **Upgradeable Modules**: Secure module installation and management

## 📈 Features

### Portfolio Management
- Multi-asset portfolio creation and management
- Automated rebalancing based on drift thresholds
- Real-time portfolio value calculation
- Historical performance tracking

### Trading & Execution
- Optimal routing across PancakeSwap V2/V3
- Slippage protection and MEV resistance
- Gas-optimized swap execution
- Multi-hop routing through intermediate tokens

### Risk Management
- Portfolio NAV protection policies
- Rebalancing frequency controls
- Emergency stop mechanisms
- Drift-based risk assessment

### User Experience
- Gasless transaction execution
- One-click portfolio creation
- Real-time portfolio analytics
- Cross-chain compatibility (extensible)

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- [PancakeSwap](https://pancakeswap.finance/) - DEX integration
- [Safe](https://safe.global/) - Account abstraction infrastructure
- [Forte Rules Engine](https://www.thrackle.io/) - Risk management and governance
- [Supra Oracles](https://supra.com/) - Price feed integration
- [Alchemy](https://www.alchemy.com/) - Infrastructure and paymaster services

## 🏆 Built For

Permissionless IV Hackathon - Redefining decentralized portfolio management through innovative Account Abstraction and AI-powered analytics.