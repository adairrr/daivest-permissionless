// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import { IERC7579Account } from "modulekit/Accounts.sol";
import { ModeLib } from "modulekit/accounts/common/lib/ModeLib.sol";

/**
 * @title ISupraPriceFeed
 * @dev Interface for Supra price feed oracle contract
 */
interface ISupraPriceFeed {
    /**
     * @dev Get price data for a specific pair
     * @param pairId The pair ID to get price for
     * @return price The price value
     * @return decimals The number of decimals
     * @return timestamp The timestamp of the price update
     * @return round The round number
     */
    function getSvalue(uint256 pairId) external view returns (
        bytes32 price,
        uint256 decimals,
        uint256 timestamp,
        uint256 round
    );
    
    /**
     * @dev Get multiple price values at once
     * @param pairIds Array of pair IDs
     * @return prices Array of price data
     */
    function getSvalues(uint256[] calldata pairIds) external view returns (
        bytes32[] memory prices,
        uint256[] memory decimals,
        uint256[] memory timestamps,
        uint256[] memory rounds
    );
}

/**
 * @title PortfolioManagerExecutor
 * @dev ERC-7579 compliant executor module for automated portfolio management
 * @notice Manages multi-asset portfolios with automatic rebalancing capabilities
 * @author SimplifAI Team
 */
contract PortfolioManagerExecutor is ERC7579ExecutorBase {
    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANTS & STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Maximum number of assets in a portfolio
    uint256 public constant MAX_ASSETS = 10;
    
    /// @dev Minimum rebalancing threshold (0.1%)
    uint256 public constant MIN_THRESHOLD = 10; // 0.1% in basis points
    
    /// @dev Maximum rebalancing threshold (50%)
    uint256 public constant MAX_THRESHOLD = 5000; // 50% in basis points
    
    /// @dev Basis points denominator (100%)
    uint256 public constant BASIS_POINTS = 10000;
    
    /// @dev Minimum time between rebalancing operations (1 hour)
    uint256 public constant MIN_REBALANCE_INTERVAL = 1 hours;
    
    /// @dev Maximum price staleness (30 minutes)
    uint256 public constant MAX_PRICE_STALENESS = 30 minutes;
    
    /// @dev Default Supra oracle contract address
    address public constant DEFAULT_SUPRA_ORACLE = 0x004d42225631F6bec6503a281Ed4c233810CBC29;
    
    /// @dev BNB/USDC pair ID on Supra
    uint256 public constant BNB_USDC_PAIR_ID = 370;
    
    /// @dev CAKE/USDT pair ID on Supra
    uint256 public constant CAKE_USDT_PAIR_ID = 125;

    /*//////////////////////////////////////////////////////////////////////////
                                    STRUCTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Portfolio configuration for a smart account
     * @param assets Array of asset token addresses
     * @param targetAllocations Target allocation percentages in basis points (sum must equal 10000)
     * @param rebalancingThreshold Threshold in basis points that triggers rebalancing
     * @param lastRebalanceTimestamp Timestamp of the last rebalancing operation
     * @param isActive Whether the portfolio configuration is active
     */
    struct Config {
        address[] assets;
        uint256[] targetAllocations;
        uint256 rebalancingThreshold;
        uint256 lastRebalanceTimestamp;
        bool isActive;
    }
    
    /**
     * @dev Price data structure for caching
     * @param price The price value (scaled by decimals)
     * @param decimals Number of decimals for the price
     * @param timestamp When the price was last updated
     * @param isValid Whether the price data is valid and fresh
     */
    struct PriceData {
        uint256 price;
        uint8 decimals;
        uint256 timestamp;
        bool isValid;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Mapping from smart account address to portfolio configuration
    mapping(address => Config) private _portfolioConfigs;
    
    /// @dev Supra oracle contract address (configurable)
    ISupraPriceFeed public supraPriceFeed;
    
    /// @dev Mapping from asset address to Supra pair ID
    mapping(address => uint256) public assetToPairId;
    
    /// @dev Mapping from asset address to cached price data
    mapping(address => PriceData) private _priceCache;

    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Emitted when a portfolio configuration is installed
     * @param smartAccount The smart account address
     * @param assets Array of asset addresses
     * @param targetAllocations Array of target allocations
     * @param rebalancingThreshold The rebalancing threshold
     */
    event PortfolioConfigured(
        address indexed smartAccount,
        address[] assets,
        uint256[] targetAllocations,
        uint256 rebalancingThreshold
    );

    /**
     * @dev Emitted when a portfolio configuration is removed
     * @param smartAccount The smart account address
     */
    event PortfolioRemoved(address indexed smartAccount);

    /**
     * @dev Emitted when a portfolio is rebalanced
     * @param smartAccount The smart account address
     * @param timestamp The timestamp of rebalancing
     */
    event PortfolioRebalanced(address indexed smartAccount, uint256 timestamp);

    /**
     * @dev Emitted when rebalancing is triggered but conditions are not met
     * @param smartAccount The smart account address
     * @param reason The reason rebalancing was skipped
     */
    event RebalancingSkipped(address indexed smartAccount, string reason);
    
    /**
     * @dev Emitted when asset price is updated
     * @param asset The asset address
     * @param price The new price
     * @param timestamp The update timestamp
     */
    event PriceUpdated(address indexed asset, uint256 price, uint256 timestamp);
    
    /**
     * @dev Emitted when portfolio NAV is calculated
     * @param smartAccount The smart account address
     * @param totalValue The calculated portfolio value
     * @param timestamp The calculation timestamp
     */
    event PortfolioValueCalculated(address indexed smartAccount, uint256 totalValue, uint256 timestamp);
    
    /**
     * @dev Emitted when Supra oracle address is updated
     * @param oldOracle The previous oracle address
     * @param newOracle The new oracle address
     */
    event SupraOracleUpdated(address indexed oldOracle, address indexed newOracle);
    
    /**
     * @dev Emitted when asset to pair ID mapping is updated
     * @param asset The asset address
     * @param pairId The Supra pair ID
     */
    event AssetPairMappingUpdated(address indexed asset, uint256 pairId);

    /*//////////////////////////////////////////////////////////////////////////
                                    ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Thrown when arrays have mismatched lengths
    error ArrayLengthMismatch();
    
    /// @dev Thrown when no assets are provided
    error NoAssetsProvided();
    
    /// @dev Thrown when too many assets are provided
    error TooManyAssets();
    
    /// @dev Thrown when target allocations don't sum to 100%
    error InvalidAllocationSum();
    
    /// @dev Thrown when rebalancing threshold is out of bounds
    error InvalidThreshold();
    
    /// @dev Thrown when trying to operate on non-existent configuration
    error ConfigurationNotFound();
    
    /// @dev Thrown when trying to rebalance too frequently
    error RebalancingTooFrequent();
    
    /// @dev Thrown when zero address is provided
    error ZeroAddress();
    
    /// @dev Thrown when price data is stale
    error StalePriceData();
    
    /// @dev Thrown when price is zero or invalid
    error InvalidPrice();
    
    /// @dev Thrown when oracle fails to provide data
    error OracleFailure();
    
    /// @dev Thrown when asset is not supported by price feed
    error UnsupportedAsset();
    
    /// @dev Thrown when price feed is not available
    error PriceFeedUnavailable();

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Constructor to initialize the Supra price feed integration
     * @dev Sets up default oracle address and asset mappings
     */
    constructor() {
        supraPriceFeed = ISupraPriceFeed(DEFAULT_SUPRA_ORACLE);
        
        // Set up default asset mappings (these would need to be actual token addresses)
        // Note: In production, these should be the actual deployed token contract addresses
        // assetToPairId[BNB_TOKEN_ADDRESS] = BNB_USDC_PAIR_ID;
        // assetToPairId[CAKE_TOKEN_ADDRESS] = CAKE_USDT_PAIR_ID;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     CONFIG
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the module with portfolio configuration data
     * @dev Decodes and stores portfolio configuration for the calling smart account
     * @param data ABI-encoded portfolio configuration (assets, targetAllocations, rebalancingThreshold)
     */
    function onInstall(bytes calldata data) external override {
        if (data.length == 0) revert NoAssetsProvided();
        
        (address[] memory assets, uint256[] memory targetAllocations, uint256 rebalancingThreshold) = 
            abi.decode(data, (address[], uint256[], uint256));
        
        _validatePortfolioConfig(assets, targetAllocations, rebalancingThreshold);
        
        Config storage config = _portfolioConfigs[msg.sender];
        config.assets = assets;
        config.targetAllocations = targetAllocations;
        config.rebalancingThreshold = rebalancingThreshold;
        config.lastRebalanceTimestamp = block.timestamp;
        config.isActive = true;
        
        emit PortfolioConfigured(msg.sender, assets, targetAllocations, rebalancingThreshold);
    }

    /**
     * @notice De-initialize the module and cleanup account state
     * @dev Removes portfolio configuration for the calling smart account
     * @param data Not used in this implementation
     */
    function onUninstall(bytes calldata data) external override {
        Config storage config = _portfolioConfigs[msg.sender];
        if (!config.isActive) revert ConfigurationNotFound();
        
        // Clear the configuration
        delete _portfolioConfigs[msg.sender];
        
        emit PortfolioRemoved(msg.sender);
    }

    /**
     * @notice Check if the module is initialized for a smart account
     * @param smartAccount The smart account address to check
     * @return true if the module is initialized, false otherwise
     */
    function isInitialized(address smartAccount) external view returns (bool) {
        return _portfolioConfigs[smartAccount].isActive;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  MODULE LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Execute portfolio rebalancing for the calling smart account
     * @dev Triggers rebalancing if conditions are met (threshold exceeded and sufficient time passed)
     * @param rebalanceData Optional data for rebalancing execution
     */
    function executeRebalancing(bytes calldata rebalanceData) external {
        Config storage config = _portfolioConfigs[msg.sender];
        if (!config.isActive) revert ConfigurationNotFound();
        
        // Check if enough time has passed since last rebalancing
        if (block.timestamp < config.lastRebalanceTimestamp + MIN_REBALANCE_INTERVAL) {
            emit RebalancingSkipped(msg.sender, "Minimum interval not met");
            revert RebalancingTooFrequent();
        }
        
        // Update last rebalancing timestamp
        config.lastRebalanceTimestamp = block.timestamp;
        
        // Execute rebalancing logic through the smart account
        IERC7579Account(msg.sender).executeFromExecutor(
            ModeLib.encodeSimpleSingle(), 
            rebalanceData
        );
        
        emit PortfolioRebalanced(msg.sender, block.timestamp);
    }

    /**
     * @notice Update portfolio configuration for the calling smart account
     * @dev Allows updating target allocations and rebalancing threshold
     * @param newTargetAllocations New target allocation percentages
     * @param newRebalancingThreshold New rebalancing threshold
     */
    function updatePortfolioConfig(
        uint256[] calldata newTargetAllocations,
        uint256 newRebalancingThreshold
    ) external {
        Config storage config = _portfolioConfigs[msg.sender];
        if (!config.isActive) revert ConfigurationNotFound();
        
        _validateAllocations(config.assets, newTargetAllocations);
        _validateThreshold(newRebalancingThreshold);
        
        config.targetAllocations = newTargetAllocations;
        config.rebalancingThreshold = newRebalancingThreshold;
        
        emit PortfolioConfigured(msg.sender, config.assets, newTargetAllocations, newRebalancingThreshold);
    }

    /**
     * @notice Get portfolio configuration for a smart account
     * @param smartAccount The smart account address
     * @return assets Array of asset addresses
     * @return targetAllocations Array of target allocations
     * @return rebalancingThreshold The rebalancing threshold
     * @return lastRebalanceTimestamp Timestamp of last rebalancing
     * @return isActive Whether the configuration is active
     */
    function getPortfolioConfig(address smartAccount) 
        external 
        view 
        returns (
            address[] memory assets,
            uint256[] memory targetAllocations,
            uint256 rebalancingThreshold,
            uint256 lastRebalanceTimestamp,
            bool isActive
        ) 
    {
        Config storage config = _portfolioConfigs[smartAccount];
        return (
            config.assets,
            config.targetAllocations,
            config.rebalancingThreshold,
            config.lastRebalanceTimestamp,
            config.isActive
        );
    }

    /**
     * @notice Check if rebalancing is needed for a smart account
     * @param smartAccount The smart account address
     * @return needed Whether rebalancing is needed
     * @return reason Reason for the decision
     */
    function isRebalancingNeeded(address smartAccount) 
        external 
        view 
        returns (bool needed, string memory reason) 
    {
        Config storage config = _portfolioConfigs[smartAccount];
        
        if (!config.isActive) {
            return (false, "Configuration not active");
        }
        
        if (block.timestamp < config.lastRebalanceTimestamp + MIN_REBALANCE_INTERVAL) {
            return (false, "Minimum interval not met");
        }
        
        // Check if we can get prices for all assets (basic validation)
        for (uint256 i = 0; i < config.assets.length; i++) {
            if (!_hasValidPriceMapping(config.assets[i])) {
                return (false, "Price feed not available for all assets");
            }
        }
        
        // In a real implementation, this would check actual asset balances
        // against target allocations to determine if threshold is exceeded
        return (true, "Conditions met for rebalancing");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 PRICE FEED LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the Supra price feed contract address
     * @dev Only callable by the contract owner/admin (in production, add access control)
     * @param newPriceFeed The new Supra price feed contract address
     */
    function updateSupraPriceFeed(address newPriceFeed) external {
        if (newPriceFeed == address(0)) revert ZeroAddress();
        
        address oldOracle = address(supraPriceFeed);
        supraPriceFeed = ISupraPriceFeed(newPriceFeed);
        
        emit SupraOracleUpdated(oldOracle, newPriceFeed);
    }

    /**
     * @notice Set asset to pair ID mapping
     * @dev Maps asset addresses to their corresponding Supra pair IDs
     * @param asset The asset token address
     * @param pairId The Supra pair ID for the asset
     */
    function setAssetPairMapping(address asset, uint256 pairId) external {
        if (asset == address(0)) revert ZeroAddress();
        
        assetToPairId[asset] = pairId;
        emit AssetPairMappingUpdated(asset, pairId);
    }

    /**
     * @notice Get current price for an asset
     * @dev Retrieves price from Supra oracle with validation
     * @param asset The asset address to get price for
     * @return price The current price (scaled by decimals)
     * @return decimals The number of decimals for the price
     */
    function getAssetPrice(address asset) external view returns (uint256 price, uint8 decimals) {
        return _getValidatedPrice(asset);
    }

    /**
     * @notice Calculate total portfolio value for a smart account
     * @dev Calculates real-time NAV using current asset prices
     * @param smartAccount The smart account address
     * @return totalValue The total portfolio value in USD equivalent
     */
    function calculatePortfolioValue(address smartAccount) external returns (uint256 totalValue) {
        Config storage config = _portfolioConfigs[smartAccount];
        if (!config.isActive) revert ConfigurationNotFound();

        totalValue = 0;
        
        for (uint256 i = 0; i < config.assets.length; i++) {
            address asset = config.assets[i];
            
            // Get asset balance (this would need integration with actual balance checking)
            // For now, we'll use a placeholder - in production this would call the smart account
            // uint256 balance = IERC20(asset).balanceOf(smartAccount);
            
            // Get current price
            (uint256 assetPrice, uint8 priceDecimals) = _getValidatedPrice(asset);
            
            // Calculate asset value (balance * price / 10^decimals)
            // uint256 assetValue = (balance * assetPrice) / (10 ** priceDecimals);
            // totalValue += assetValue;
            
            // For demonstration, we'll just accumulate the prices
            totalValue += assetPrice / (10 ** priceDecimals);
        }
        
        emit PortfolioValueCalculated(smartAccount, totalValue, block.timestamp);
        return totalValue;
    }

    /**
     * @notice Batch update prices for multiple assets
     * @dev Updates price cache for gas efficiency
     * @param assets Array of asset addresses to update prices for
     */
    function updatePrices(address[] calldata assets) external {
        if (address(supraPriceFeed) == address(0)) revert PriceFeedUnavailable();
        
        uint256[] memory pairIds = new uint256[](assets.length);
        
        // Prepare pair IDs array
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 pairId = assetToPairId[assets[i]];
            if (pairId == 0) revert UnsupportedAsset();
            pairIds[i] = pairId;
        }
        
        try supraPriceFeed.getSvalues(pairIds) returns (
            bytes32[] memory prices,
            uint256[] memory decimalsArray,
            uint256[] memory timestamps,
            uint256[] memory rounds
        ) {
            for (uint256 i = 0; i < assets.length; i++) {
                uint256 priceValue = _bytes32ToUint(prices[i]);
                
                // Validate price data
                if (priceValue == 0) revert InvalidPrice();
                if (block.timestamp > timestamps[i] + MAX_PRICE_STALENESS) revert StalePriceData();
                
                // Update cache
                _priceCache[assets[i]] = PriceData({
                    price: priceValue,
                    decimals: uint8(decimalsArray[i]),
                    timestamp: timestamps[i],
                    isValid: true
                });
                
                emit PriceUpdated(assets[i], priceValue, timestamps[i]);
            }
        } catch {
            revert OracleFailure();
        }
    }

    /**
     * @notice Check if price data is fresh for an asset
     * @param asset The asset address to check
     * @return isFresh Whether the price data is within staleness threshold
     */
    function isPriceFresh(address asset) external view returns (bool isFresh) {
        PriceData storage cachedPrice = _priceCache[asset];
        return cachedPrice.isValid && 
               (block.timestamp <= cachedPrice.timestamp + MAX_PRICE_STALENESS);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     INTERNAL
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Validates the complete portfolio configuration
     * @param assets Array of asset addresses
     * @param targetAllocations Array of target allocations
     * @param rebalancingThreshold The rebalancing threshold
     */
    function _validatePortfolioConfig(
        address[] memory assets,
        uint256[] memory targetAllocations,
        uint256 rebalancingThreshold
    ) internal view {
        _validateAllocations(assets, targetAllocations);
        _validateThreshold(rebalancingThreshold);
        _validateAssetPriceMappings(assets);
    }

    /**
     * @dev Validates asset addresses and target allocations
     * @param assets Array of asset addresses
     * @param targetAllocations Array of target allocations
     */
    function _validateAllocations(address[] memory assets, uint256[] memory targetAllocations) internal pure {
        if (assets.length == 0) revert NoAssetsProvided();
        if (assets.length > MAX_ASSETS) revert TooManyAssets();
        if (assets.length != targetAllocations.length) revert ArrayLengthMismatch();
        
        // Check for zero addresses and calculate total allocation
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == address(0)) revert ZeroAddress();
            totalAllocation += targetAllocations[i];
        }
        
        if (totalAllocation != BASIS_POINTS) revert InvalidAllocationSum();
    }

    /**
     * @dev Validates rebalancing threshold
     * @param rebalancingThreshold The rebalancing threshold to validate
     */
    function _validateThreshold(uint256 rebalancingThreshold) internal pure {
        if (rebalancingThreshold < MIN_THRESHOLD || rebalancingThreshold > MAX_THRESHOLD) {
            revert InvalidThreshold();
        }
    }

    /**
     * @dev Get validated price for an asset from Supra oracle
     * @param asset The asset address
     * @return price The validated price
     * @return decimals The price decimals
     */
    function _getValidatedPrice(address asset) internal view returns (uint256 price, uint8 decimals) {
        if (address(supraPriceFeed) == address(0)) revert PriceFeedUnavailable();
        
        uint256 pairId = assetToPairId[asset];
        if (pairId == 0) revert UnsupportedAsset();
        
        // First check cached data
        PriceData storage cachedPrice = _priceCache[asset];
        if (cachedPrice.isValid && block.timestamp <= cachedPrice.timestamp + MAX_PRICE_STALENESS) {
            return (cachedPrice.price, cachedPrice.decimals);
        }
        
        // Fetch fresh data from oracle
        try supraPriceFeed.getSvalue(pairId) returns (
            bytes32 priceBytes,
            uint256 priceDecimals,
            uint256 timestamp,
            uint256 round
        ) {
            uint256 priceValue = _bytes32ToUint(priceBytes);
            
            // Validate price data
            if (priceValue == 0) revert InvalidPrice();
            if (block.timestamp > timestamp + MAX_PRICE_STALENESS) revert StalePriceData();
            
            return (priceValue, uint8(priceDecimals));
        } catch {
            revert OracleFailure();
        }
    }

    /**
     * @dev Convert bytes32 to uint256 for price data
     * @param value The bytes32 value to convert
     * @return The uint256 representation
     */
    function _bytes32ToUint(bytes32 value) internal pure returns (uint256) {
        return uint256(value);
    }

    /**
     * @dev Check if asset has a valid price feed mapping
     * @param asset The asset address to check
     * @return hasMapping Whether the asset has a valid mapping
     */
    function _hasValidPriceMapping(address asset) internal view returns (bool hasMapping) {
        return assetToPairId[asset] != 0;
    }

    /**
     * @dev Validate array of assets have price feed mappings
     * @param assets Array of asset addresses to validate
     */
    function _validateAssetPriceMappings(address[] memory assets) internal view {
        for (uint256 i = 0; i < assets.length; i++) {
            if (!_hasValidPriceMapping(assets[i])) revert UnsupportedAsset();
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     METADATA
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice The name of the module
     * @return name The name of the module
     */
    function name() external pure returns (string memory) {
        return "PortfolioManagerExecutor";
    }

    /**
     * @notice The version of the module
     * @return version The version of the module
     */
    function version() external pure returns (string memory) {
        return "1.1.0";
    }

    /**
     * @notice Check if the module is of a certain type
     * @param typeID The type ID to check
     * @return true if the module is of the given type, false otherwise
     */
    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }
}