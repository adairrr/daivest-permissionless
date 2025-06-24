# Safe Account Creation Scripts

## CreateSafeAccount.s.sol

This script demonstrates how to create a Safe account with ERC-7579 module support using a private key as the owner.

### Features

- **Safe Account Creation**: Uses canonical Safe addresses on Sepolia testnet
- **ERC-7579 Module Support**: Ready for module installation (Portfolio Manager Executor)
- **Private Key as Owner**: Uses the deployer's private key to create an owned Safe account
- **Address Prediction**: Can predict Safe addresses before deployment

### Canonical Addresses (BSC Testnet)

- **Safe Proxy Factory**: `0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67`
- **Safe Singleton**: `0x41675C099F32341bf84BFc5382aF534df5C7461a`
- **Safe7579 Launchpad**: `0x7579011aB74c46090561ea277Ba79D510c6C00ff`
- **Safe7579 Module**: `0x7579EE8307284F293B1927136486880611F20002`

### Usage

#### 1. Basic Safe Account Creation

```bash
# Set your private key
export PK=your_private_key_here

# Deploy to BSC testnet
forge script script/CreateSafeAccount.s.sol:CreateSafeAccountScript --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 --broadcast --verify
```

#### 2. Deploy Test Portfolio Manager Executor

```bash
forge script script/CreateSafeAccount.s.sol:CreateSafeAccountScript --sig "deployTestPortfolioManager()" --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 --broadcast
```

#### 3. Demonstrate Safe Creation Flow

```bash
forge script script/CreateSafeAccount.s.sol:CreateSafeAccountScript --sig "demonstrateSafeCreation()" --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

#### 4. Predict Safe Address

```bash
# This will predict the address without deploying
forge script script/CreateSafeAccount.s.sol:CreateSafeAccountScript --sig "predictSafeAddress(address,uint256)" <owner_address> <salt_nonce> --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

### Environment Variables

Make sure to set these environment variables:

```bash
export PK=your_private_key_here                    # Private key for deployment
export BSC_TESTNET_RPC_URL=https://data-seed-prebsc-1-s1.binance.org:8545  # BSC Testnet RPC URL
```

### Script Functions

#### `run()`
Main deployment function that:
1. Creates Safe account configuration with the deployer as owner
2. Deploys the Safe account using Safe7579Launchpad
3. Verifies the Safe account ownership and threshold
4. Logs all relevant information including the Safe account address

#### `createSafeAccountDirect(SafeAccountConfig)`
Internal function for creating Safe accounts using the Safe7579Launchpad. This function:
1. Prepares Safe initialization data with the specified owner
2. Calls the Safe7579Launchpad to create the account
3. Returns the deployed Safe account address

#### `verifySafeAccount(address, address)`
Verifies that the Safe account was deployed correctly by:
1. Checking that the account has deployed code
2. Calling `getOwners()` to verify the expected owner
3. Calling `getThreshold()` to verify the threshold is set to 1

#### `predictSafeAddress(address, uint256)`
Helper function to predict the Safe account address before deployment using CREATE2. This function:
1. Prepares the same Safe initialization data used in creation
2. Calculates the CREATE2 salt used by the Safe7579Launchpad
3. Returns the predicted address based on the bytecode hash

#### `deployTestPortfolioManager()`
Deploys a test instance of the Portfolio Manager Executor on Sepolia for testing.

#### `demonstrateSafeCreation()`
Demonstrates the Safe account creation flow by showing all relevant addresses and generating a unique salt.

### Integration with Frontend

This script is designed to work with the SimpliFi frontend portfolio creation interface. The Safe accounts created here can be used with:

1. **Account Abstraction**: Gasless transactions via Alchemy paymaster
2. **ERC-7579 Modules**: Install Portfolio Manager Executor for AI-powered portfolio management
3. **Modular Architecture**: Add additional modules for enhanced functionality

### Next Steps

1. **Install Safe7579 Dependencies**: Add proper Safe7579 contracts for full implementation
2. **Complete Safe Integration**: Replace test deployment with actual Safe account creation
3. **Module Installation**: Implement automatic Portfolio Manager Executor installation
4. **Frontend Integration**: Connect with React interface for seamless user experience

### Example Output

```
=== Creating Safe Account with ERC-7579 Support on Sepolia ===
Chain ID: 11155111
Owner address: 0x742d35C36532..
Owner balance: 100000000000000000
Creating Safe account with direct contract deployment...
Test executor deployed at: 0x123456789abcdef...
=== Safe Account Created Successfully ===
Safe Account Address: 0x123456789abcdef...
Owner: 0x742d35C36532..
Salt Nonce: 12345678901234567890
=== Verifying Safe Account ===
Safe account has code deployed
=== Verification Complete ===
```