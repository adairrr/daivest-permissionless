// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import { RegistryDeployer } from "modulekit/deployment/registry/RegistryDeployer.sol";

// Import modules here
import { PortfolioManagerExecutor } from "src/PortfolioManagerExecutor.sol";

/// @title DeployModuleScript
/// @notice Deploys PortfolioManagerExecutor module to BSC testnet with proper configuration
contract DeployModuleScript is Script, RegistryDeployer {
    // BSC Testnet addresses
    address constant SUPRA_PRICE_FEED = 0x004d42225631F6bec6503a281Ed4c233810CBC29;
    address constant PANCAKE_UNIVERSAL_ROUTER = 0x87FD5305E6a40F378da124864B2D479c2028BD86;
    
    // BSC Testnet token addresses
    address constant WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
    address constant USDC = 0xCA8eB2dec4Fe3a5abbFDc017dE48E461A936623D;
    address constant CAKE = 0x8d008B313C1d6C7fE2982F62d32Da7507cF43551;
    
    // Supra price feed pair IDs
    uint256 constant BNB_USDC_PAIR_ID = 370;
    uint256 constant CAKE_USDT_PAIR_ID = 125;
    uint256 constant USDC_USDT_PAIR_ID = 0; // Using BTC/USDT as proxy for USDC
    
    function run() public {
        // Verify we're on BSC testnet (Chain ID 97)
        require(block.chainid == 97, "Must deploy on BSC testnet");
        
        console.log("=== Deploying PortfolioManagerExecutor to BSC Testnet ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", msg.sender);
        
        // Setup module bytecode, deploy params, and data
        bytes memory bytecode = type(PortfolioManagerExecutor).creationCode;
        bytes memory resolverContext = "";
        bytes memory metadata = abi.encode(
            "PortfolioManagerExecutor",
            "1.1.0", 
            "AI-powered portfolio management executor for ERC-7579 smart accounts"
        );

        // Get private key for deployment
        vm.startBroadcast(vm.envUint("PK"));

        // Deploy module
        address module = deployModule({
            initCode: bytecode,
            resolverContext: resolverContext,
            salt: bytes32(0),
            metadata: metadata
        });

        console.log("PortfolioManagerExecutor deployed at:", module);
        
        // Configure the deployed module
        PortfolioManagerExecutor executor = PortfolioManagerExecutor(module);
        
        // Set up Supra price feed
        console.log("Configuring Supra price feed...");
        executor.updateSupraPriceFeed(SUPRA_PRICE_FEED);
        
        // Set up asset pair mappings
        console.log("Setting up asset pair mappings...");
        executor.setAssetPairMapping(WBNB, BNB_USDC_PAIR_ID);
        executor.setAssetPairMapping(CAKE, CAKE_USDT_PAIR_ID);
        executor.setAssetPairMapping(USDC, USDC_USDT_PAIR_ID);
        
        // Verify deployment and configuration
        console.log("=== Verifying Deployment ===");
        require(keccak256(bytes(executor.name())) == keccak256(bytes("PortfolioManagerExecutor")), "Name verification failed");
        require(keccak256(bytes(executor.version())) == keccak256(bytes("1.1.0")), "Version verification failed");
        require(executor.isModuleType(2), "Module type verification failed"); // TYPE_EXECUTOR = 2
        require(address(executor.supraPriceFeed()) == SUPRA_PRICE_FEED, "Price feed verification failed");
        require(executor.assetToPairId(WBNB) == BNB_USDC_PAIR_ID, "WBNB mapping verification failed");
        require(executor.assetToPairId(CAKE) == CAKE_USDT_PAIR_ID, "CAKE mapping verification failed");
        require(executor.assetToPairId(USDC) == USDC_USDT_PAIR_ID, "USDC mapping verification failed");
        
        console.log("=== Configuration Verified ===");
        console.log("Supra Price Feed:", address(executor.supraPriceFeed()));
        console.log("WBNB Pair ID:", executor.assetToPairId(WBNB));
        console.log("CAKE Pair ID:", executor.assetToPairId(CAKE));
        console.log("USDC Pair ID:", executor.assetToPairId(USDC));
        
        // Test price feed functionality
        console.log("=== Testing Price Feed ===");
        try executor.getAssetPrice(WBNB) returns (uint256 price, uint8 decimals) {
            console.log("WBNB price:", price, "decimals:", decimals);
        } catch Error(string memory reason) {
            console.log("WBNB price fetch failed:", reason);
        } catch {
            console.log("WBNB price fetch failed: Unknown error");
        }
        
        try executor.getAssetPrice(CAKE) returns (uint256 price, uint8 decimals) {
            console.log("CAKE price:", price, "decimals:", decimals);
        } catch Error(string memory reason) {
            console.log("CAKE price fetch failed:", reason);
        } catch {
            console.log("CAKE price fetch failed: Unknown error");
        }

        // Stop broadcast and log success
        vm.stopBroadcast();
        
        console.log("=== Deployment Complete ===");
        console.log("Module Address:", module);
        console.log("Ready for smart account integration");
    }
}
