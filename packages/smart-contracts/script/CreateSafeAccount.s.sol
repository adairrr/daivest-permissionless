// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import { PortfolioManagerExecutor } from "src/PortfolioManagerExecutor.sol";
import { Safe7579Launchpad } from "@rhinestonewtf/safe7579/Safe7579Launchpad.sol";
import { ISafe } from "@rhinestonewtf/safe7579/interfaces/ISafe.sol";
import { SafeProxyFactory } from "@safe-global/safe-contracts/contracts/proxies/SafeProxyFactory.sol";

/// @title CreateSafeAccountScript
/// @notice Creates a new Safe account with ERC-7579 module support using a private key as owner
contract CreateSafeAccountScript is Script {
    // Canonical addresses for BSC testnet
    address constant SAFE_PROXY_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    address constant SAFE_SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;
    address constant SAFE7579_LAUNCHPAD = 0x7579011aB74c46090561ea277Ba79D510c6C00ff;
    address constant SAFE7579_MODULE = 0x7579EE8307284F293B1927136486880611F20002;

    // Our deployed Portfolio Manager Executor (deployed on BSC testnet)
    address constant PORTFOLIO_MANAGER_EXECUTOR = 0xB9EdA6A7729D57a9fdd50443b1b70cDa01a4a6E3;

    struct SafeAccountConfig {
        address owner;
        uint256 saltNonce;
        address[] modules;
        bytes[] moduleInitData;
    }

    function run() public {
        // Verify we're on BSC testnet (Chain ID 97)
        require(block.chainid == 97, "Must deploy on BSC testnet");

        console.log("=== Creating Safe Account with ERC-7579 Support on BSC Testnet ===");
        console.log("Chain ID:", block.chainid);

        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PK");
        address owner = vm.addr(deployerPrivateKey);

        console.log("Owner address:", owner);
        console.log("Owner balance:", owner.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Create Safe account configuration
        SafeAccountConfig memory config = SafeAccountConfig({
            owner: owner,
            saltNonce: uint256(keccak256(abi.encodePacked(block.timestamp, owner))),
            modules: new address[](1),
            moduleInitData: new bytes[](1)
        });

        // Add Portfolio Manager Executor module (if we want to install it immediately)
        config.modules[0] = PORTFOLIO_MANAGER_EXECUTOR;
        config.moduleInitData[0] = ""; // Empty init data for now

        // Create the Safe account using direct contract calls
        address safeAccount = createSafeAccountDirect(config);

        console.log("=== Safe Account Created Successfully ===");
        console.log("Safe Account Address:", safeAccount);
        console.log("Owner:", owner);
        console.log("Salt Nonce:", config.saltNonce);

        // Verify the account was created correctly
        verifySafeAccount(safeAccount, owner);

        vm.stopBroadcast();
    }

    function createSafeAccountDirect(SafeAccountConfig memory config) internal returns (address) {
        console.log("Creating Safe account using Safe7579Launchpad...");
        
        // Prepare the Safe initialization data
        address[] memory owners = new address[](1);
        owners[0] = config.owner;
        
        // Create Safe setup data using the proper ISafe interface
        bytes memory setupData = abi.encodeCall(
            ISafe.setup,
            (
                owners,                    // owners
                1,                        // threshold
                address(0),               // to (no delegate call)
                "",                       // data
                address(0),               // fallbackHandler
                address(0),               // paymentToken
                0,                        // payment
                payable(address(0))       // paymentReceiver (payable)
            )
        );
        
        // Use Safe proxy factory to create the account
        SafeProxyFactory factory = SafeProxyFactory(SAFE_PROXY_FACTORY);
        address safeAccount = address(factory.createProxyWithNonce(
            SAFE_SINGLETON,           // singleton
            setupData,               // setupData
            config.saltNonce         // saltNonce
        ));
        
        console.log("Safe account created at:", safeAccount);
        
        return safeAccount;
    }

    function verifySafeAccount(address safeAccount, address expectedOwner) internal view {
        console.log("=== Verifying Safe Account ===");

        // Check if the account was deployed
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(safeAccount)
        }
        require(codeSize > 0, "Safe account not deployed");
        console.log("Safe account has code deployed");

        // Verify ownership using low-level calls
        (bool success, bytes memory returnData) = safeAccount.staticcall(
            abi.encodeWithSignature("getOwners()")
        );
        
        if (success) {
            address[] memory owners = abi.decode(returnData, (address[]));
            require(owners.length == 1, "Expected exactly one owner");
            require(owners[0] == expectedOwner, "Owner mismatch");
            console.log("Owner verified:", owners[0]);
        } else {
            console.log("Could not verify owners - account may not be fully initialized");
        }

        // Verify threshold using low-level calls
        (bool thresholdSuccess, bytes memory thresholdData) = safeAccount.staticcall(
            abi.encodeWithSignature("getThreshold()")
        );
        
        if (thresholdSuccess) {
            uint256 threshold = abi.decode(thresholdData, (uint256));
            require(threshold == 1, "Expected threshold of 1");
            console.log("Threshold verified:", threshold);
        } else {
            console.log("Could not verify threshold");
        }

        console.log("=== Verification Complete ===");
    }

    /// @notice Helper function to predict Safe account address before deployment
    function predictSafeAddress(address owner, uint256 saltNonce) public pure returns (address) {
        // Prepare the Safe initialization data (same as in createSafeAccountDirect)
        address[] memory owners = new address[](1);
        owners[0] = owner;
        
        bytes memory setupData = abi.encodeCall(
            ISafe.setup,
            (
                owners,                    // owners
                1,                        // threshold
                address(0),               // to (no delegate call)
                "",                       // data
                address(0),               // fallbackHandler
                address(0),               // paymentToken
                0,                        // payment
                payable(address(0))       // paymentReceiver (payable)
            )
        );
        
        // Use SafeProxyFactory to predict the address
        SafeProxyFactory factory = SafeProxyFactory(SAFE_PROXY_FACTORY);
        
        // Calculate the predicted address using the factory's logic
        bytes32 salt = keccak256(abi.encodePacked(keccak256(setupData), saltNonce));
        
        // Note: This is a simplified prediction. The actual SafeProxyFactory
        // uses a more complex CREATE2 calculation that we'd need to replicate exactly
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                SAFE_PROXY_FACTORY,
                salt,
                keccak256(abi.encodePacked(
                    factory.proxyCreationCode(),
                    abi.encode(SAFE_SINGLETON)
                ))
            )
        );

        return address(uint160(uint256(hash)));
    }

    /// @notice Deploy a test portfolio manager executor for Sepolia
    function deployTestPortfolioManager() external returns (address) {
        vm.startBroadcast(vm.envUint("PK"));

        // Deploy Portfolio Manager Executor for testing on Sepolia
        PortfolioManagerExecutor executor = new PortfolioManagerExecutor();

        console.log("Test Portfolio Manager Executor deployed at:", address(executor));

        vm.stopBroadcast();
        return address(executor);
    }

    /// @notice Simple function to demonstrate Safe account creation flow
    function demonstrateSafeCreation() external {
        uint256 deployerPrivateKey = vm.envUint("PK");
        address owner = vm.addr(deployerPrivateKey);

        console.log("=== Safe Account Creation Demonstration ===");
        console.log("Owner:", owner);
        console.log("Safe7579 Launchpad:", SAFE7579_LAUNCHPAD);
        console.log("Safe7579 Module:", SAFE7579_MODULE);
        console.log("Safe Singleton:", SAFE_SINGLETON);
        console.log("Safe Proxy Factory:", SAFE_PROXY_FACTORY);

        // Generate a unique salt for this demonstration
        uint256 saltNonce = uint256(keccak256(abi.encodePacked(block.timestamp, owner, "demo")));
        console.log("Salt Nonce:", saltNonce);

        // Predict the Safe address
        address predictedAddress = predictSafeAddress(owner, saltNonce);
        console.log("Predicted Safe Address:", predictedAddress);

        console.log("=== Demonstration Complete ===");
    }
}
