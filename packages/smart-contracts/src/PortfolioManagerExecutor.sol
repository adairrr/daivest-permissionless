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
 * @title IUniversalRouter
 * @dev Interface for PancakeSwap's Infinity Universal Router
 */
interface IUniversalRouter {
    /// @notice Thrown when a required command has failed
    error ExecutionFailed(uint256 commandIndex, bytes message);

    /// @notice Thrown when attempting to send ETH directly to the contract
    error ETHNotAccepted();

    /// @notice Thrown when executing commands with an expired deadline
    error TransactionDeadlinePassed();

    /// @notice Thrown when attempting to execute commands and an incorrect number of inputs are provided
    error LengthMismatch();

    // @notice Thrown when an address that isnt WETH tries to send ETH to the router without calldata
    error InvalidEthSender();

    /// @notice Executes encoded commands along with provided inputs. Reverts if deadline has expired.
    /// @dev Caller is advised to add a sweep command at the end to take any remaining ETH in contract
    /// @param commands A set of concatenated commands, each 1 byte in length
    /// @param inputs An array of byte strings containing abi encoded inputs for each command
    /// @param deadline The deadline by which the transaction must be executed
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

/**
 * @title IPermit2
 * @dev Interface for Permit2 approval system
 */
interface IPermit2 {
    /**
     * @dev Approve tokens through Permit2 system
     * @param token Token address to approve
     * @param spender Address to approve for spending
     * @param amount Amount to approve (use type(uint160).max for infinite)
     * @param expiration Expiration timestamp (use type(uint48).max for no expiration)
     */
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
    
    /**
     * @dev Get the current allowance for a token/owner/spender combination
     * @param owner Token owner address
     * @param token Token address
     * @param spender Spender address
     * @return amount Current allowance amount
     * @return expiration Expiration timestamp
     */
    function allowance(address owner, address token, address spender) 
        external view returns (uint160 amount, uint48 expiration);
        
    /**
     * @dev Transfer tokens using Permit2
     * @param from Source address
     * @param to Destination address
     * @param amount Amount to transfer
     * @param token Token address
     */
    function transferFrom(address from, address to, uint160 amount, address token) external;
}

/**
 * @title IERC20
 * @dev Standard ERC20 interface for token operations
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
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
    
    /// @dev PancakeSwap Infinity Universal Router address
    address public constant PANCAKE_UNIVERSAL_ROUTER = 0x87FD5305E6a40F378da124864B2D479c2028BD86;
    
    /// @dev Permit2 contract address (same across networks)
    address public constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    
    /// @dev Universal Router command constants
    uint8 public constant V3_SWAP_EXACT_IN = 0x00;
    uint8 public constant V3_SWAP_EXACT_OUT = 0x01;
    uint8 public constant PERMIT2_TRANSFER_FROM = 0x02;
    uint8 public constant PERMIT2_PERMIT_BATCH = 0x03;
    uint8 public constant SWEEP = 0x04;
    uint8 public constant TRANSFER = 0x05;
    uint8 public constant PAY_PORTION = 0x06;
    uint8 public constant V2_SWAP_EXACT_IN = 0x08;
    uint8 public constant V2_SWAP_EXACT_OUT = 0x09;
    uint8 public constant PERMIT2_PERMIT = 0x0a;
    
    /// @dev Minimum swap amount (0.001 ETH equivalent in wei)
    uint256 public constant MIN_SWAP_AMOUNT = 1e15;
    
    /// @dev Maximum slippage tolerance (3% in basis points)
    uint256 public constant MAX_SLIPPAGE = 300;
    
    /// @dev Default rebalance deviation threshold (5% in basis points)
    uint256 public constant DEFAULT_REBALANCE_THRESHOLD = 500;
    
    /// @dev WBNB token address on BSC
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    
    /// @dev Infinite approval amount for Permit2
    uint160 public constant INFINITE_APPROVAL = type(uint160).max;
    
    /// @dev Default approval expiration (1 year)
    uint48 public constant DEFAULT_EXPIRATION = type(uint48).max;
    
    /// @dev Maximum number of hops in a swap path
    uint256 public constant MAX_HOPS = 3;
    
    /// @dev V3 fee tiers
    uint24 public constant FEE_LOW = 500;     // 0.05%
    uint24 public constant FEE_MEDIUM = 3000; // 0.30%
    uint24 public constant FEE_HIGH = 10000;  // 1.00%

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
    
    /**
     * @dev Swap parameters for V3 exact input
     * @param recipient Address to receive output tokens
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum amount of output tokens
     * @param path Encoded swap path (token addresses and fees)
     * @param payerIsUser Whether tokens come from user (true) or contract (false)
     */
    struct V3SwapExactInParams {
        address recipient;
        uint256 amountIn;
        uint256 amountOutMin;
        bytes path;
        bool payerIsUser;
    }
    
    /**
     * @dev Swap parameters for V2 exact input
     * @param recipient Address to receive output tokens
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum amount of output tokens
     * @param path Array of token addresses for swap path
     * @param payerIsUser Whether tokens come from user (true) or contract (false)
     */
    struct V2SwapExactInParams {
        address recipient;
        uint256 amountIn;
        uint256 amountOutMin;
        address[] path;
        bool payerIsUser;
    }
    
    /**
     * @dev Rebalancing action structure
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens to swap
     * @param amountOutMin Minimum amount of output tokens expected
     * @param useV3 Whether to use V3 (true) or V2 (false) for this swap
     */
    struct RebalanceAction {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        bool useV3;
    }
    
    /**
     * @dev Swap route structure for optimal path finding
     * @param path Array of token addresses in the swap route
     * @param fees Array of fee tiers for V3 pools (empty for V2)
     * @param expectedOutput Expected output amount for this route
     * @param useV3 Whether this route uses V3 pools
     * @param hops Number of hops in the route
     */
    struct SwapRoute {
        address[] path;
        uint24[] fees;
        uint256 expectedOutput;
        bool useV3;
        uint8 hops;
    }
    
    /**
     * @dev Pool information for liquidity analysis
     * @param token0 First token in the pool
     * @param token1 Second token in the pool
     * @param fee Fee tier (for V3 pools)
     * @param liquidity Available liquidity
     * @param isV3 Whether this is a V3 pool
     */
    struct PoolInfo {
        address token0;
        address token1;
        uint24 fee;
        uint256 liquidity;
        bool isV3;
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
    
    /// @dev Balance cache: smartAccount => token => balance
    mapping(address => mapping(address => uint256)) private _balanceCache;
    
    /// @dev Balance cache timestamps: smartAccount => token => timestamp
    mapping(address => mapping(address => uint256)) private _balanceCacheTimestamp;
    
    /// @dev Permit2 contract instance
    IPermit2 public permit2;
    
    /// @dev Array of intermediate tokens for routing (configurable)
    address[] public intermediateTokens;
    
    /// @dev Mapping to track known intermediate tokens for routing
    mapping(address => bool) public isIntermediateToken;

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
    
    /**
     * @dev Emitted when optimal route is found
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @param expectedOutput Expected output amount
     * @param useV3 Whether V3 was selected
     * @param hops Number of hops in the route
     */
    event OptimalRouteFound(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 expectedOutput,
        bool useV3,
        uint8 hops
    );
    
    /**
     * @dev Emitted when intermediate token is added or removed
     * @param token The token address
     * @param isAdded Whether the token was added (true) or removed (false)
     */
    event IntermediateTokenUpdated(address indexed token, bool isAdded);
    
    /**
     * @dev Emitted when a swap fails with detailed error information
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount attempted to swap
     * @param reason Failure reason
     */
    event SwapFailedWithReason(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        string reason
    );
    
    /**
     * @dev Emitted when path validation fails
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param reason Validation failure reason
     */
    event PathValidationError(
        address indexed tokenIn,
        address indexed tokenOut,
        string reason
    );
    
    /**
     * @dev Emitted when slippage protection is triggered
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param expectedOutput Expected output amount
     * @param actualOutput Actual output amount
     * @param slippagePercent Slippage percentage
     */
    event SlippageWarning(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 expectedOutput,
        uint256 actualOutput,
        uint256 slippagePercent
    );

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
    
    /// @dev Thrown when swap execution fails
    error SwapFailed();
    
    /// @dev Thrown when swap path is invalid
    error InvalidSwapPath();
    
    /// @dev Thrown when slippage tolerance is exceeded
    error SlippageExceeded();
    
    /// @dev Thrown when swap amount is below minimum
    error InsufficientSwapAmount();
    
    /// @dev Thrown when Universal Router is not available
    error RouterUnavailable();
    
    /// @dev Thrown when swap deadline has been exceeded
    error SwapDeadlineExceeded();
    
    /// @dev Thrown when command sequence is invalid
    error InvalidCommandSequence();
    
    /// @dev Thrown when swap execution panics
    error SwapPanic(uint256 errorCode);
    
    /// @dev Thrown when low-level swap execution fails
    error SwapExecutionFailed(bytes data);
    
    /// @dev Thrown when path validation fails
    error PathValidationFailed(string reason);
    
    /// @dev Thrown when no optimal route is found
    error NoRouteFound();
    
    /// @dev Thrown when Permit2 approval fails
    error Permit2ApprovalFailed();
    
    /// @dev Thrown when token balance is insufficient
    error InsufficientBalance();
    
    /// @dev Thrown when balance cache is stale
    error StaleBalanceCache();
    
    /// @dev Thrown when route validation fails
    error InvalidRoute();
    
    /// @dev Thrown when too many hops in route
    error TooManyHops();
    
    /// @dev Thrown when intermediate token operations fail
    error IntermediateTokenError();

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Constructor to initialize the Supra price feed integration
     * @dev Sets up default oracle address and asset mappings
     */
    constructor() {
        supraPriceFeed = ISupraPriceFeed(DEFAULT_SUPRA_ORACLE);
        permit2 = IPermit2(PERMIT2_ADDRESS);
        
        // Initialize common intermediate tokens
        _addIntermediateToken(WBNB);
        // Additional intermediate tokens would be added here:
        // _addIntermediateToken(USDT_ADDRESS);
        // _addIntermediateToken(BUSD_ADDRESS);
        // _addIntermediateToken(USDC_ADDRESS);
        
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
     */
    function onUninstall(bytes calldata /* data */) external override {
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
            
            // Get real asset balance
            uint256 balance = _getRealTokenBalance(smartAccount, asset);
            
            // Update balance cache
            _updateBalanceCache(smartAccount, asset, balance);
            
            // Skip if no balance
            if (balance == 0) continue;
            
            // Get current price
            (uint256 assetPrice, uint8 priceDecimals) = _getValidatedPrice(asset);
            
            // Get token decimals for proper scaling
            uint8 tokenDecimals;
            try IERC20(asset).decimals() returns (uint8 decimals) {
                tokenDecimals = decimals;
            } catch {
                tokenDecimals = 18; // Default to 18 decimals if query fails
            }
            
            // Calculate asset value: (balance * price) / (10^priceDecimals)
            // Scale balance to match price decimals for accurate calculation
            uint256 scaledBalance = balance;
            if (tokenDecimals > priceDecimals) {
                scaledBalance = balance / (10 ** (tokenDecimals - priceDecimals));
            } else if (tokenDecimals < priceDecimals) {
                scaledBalance = balance * (10 ** (priceDecimals - tokenDecimals));
            }
            
            uint256 assetValue = (scaledBalance * assetPrice) / (10 ** priceDecimals);
            totalValue += assetValue;
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
            uint256[] memory /* rounds */
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
            uint256 /* round */
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
                                 SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Ensure Permit2 approval for token spending
     * @param smartAccount Smart account that owns the tokens
     * @param token Token address to approve
     * @param amount Amount to approve for spending
     */
    function _ensurePermit2Approval(address smartAccount, address token, uint256 amount) internal {
        if (token == address(0)) revert PathValidationFailed("Invalid token address");
        
        // Check current allowance
        (uint160 currentAllowance, uint48 expiration) = permit2.allowance(
            smartAccount, 
            token, 
            PANCAKE_UNIVERSAL_ROUTER
        );
        
        // Check if approval is sufficient and not expired
        if (currentAllowance >= amount && expiration > block.timestamp) {
            return; // Sufficient approval exists
        }
        
        // Need to approve tokens through the smart account
        try IERC7579Account(smartAccount).executeFromExecutor(
            ModeLib.encodeSimpleSingle(),
            abi.encodeCall(
                IPermit2.approve,
                (token, PANCAKE_UNIVERSAL_ROUTER, INFINITE_APPROVAL, DEFAULT_EXPIRATION)
            )
        ) {
            // Approval successful
        } catch {
            revert Permit2ApprovalFailed();
        }
    }

    /**
     * @dev Get real token balance for a smart account
     * @param smartAccount Smart account address
     * @param token Token address
     * @return balance Current token balance
     */
    function _getRealTokenBalance(address smartAccount, address token) internal view returns (uint256 balance) {
        if (token == address(0)) revert PathValidationFailed("Invalid token address");
        
        try IERC20(token).balanceOf(smartAccount) returns (uint256 bal) {
            return bal;
        } catch {
            return 0; // Return 0 if balance query fails
        }
    }

    /**
     * @dev Get cached token balance with staleness check
     * @param smartAccount Smart account address
     * @param token Token address
     * @return balance Cached balance (returns 0 if stale)
     */
    function _getCachedBalance(address smartAccount, address token) internal view returns (uint256 balance) {
        uint256 timestamp = _balanceCacheTimestamp[smartAccount][token];
        
        // Check if cache is stale (older than 5 minutes)
        if (block.timestamp > timestamp + 300) {
            return 0; // Cache is stale
        }
        
        return _balanceCache[smartAccount][token];
    }

    /**
     * @dev Update balance cache for a smart account and token
     * @param smartAccount Smart account address
     * @param token Token address
     * @param balance New balance to cache
     */
    function _updateBalanceCache(address smartAccount, address token, uint256 balance) internal {
        _balanceCache[smartAccount][token] = balance;
        _balanceCacheTimestamp[smartAccount][token] = block.timestamp;
    }

    /**
     * @dev Get token balance with caching for gas efficiency
     * @param smartAccount Smart account address
     * @param token Token address
     * @param forceRefresh Whether to force a fresh balance query
     * @return balance Current token balance
     */
    function getTokenBalance(address smartAccount, address token, bool forceRefresh) 
        external 
        view 
        returns (uint256 balance) 
    {
        if (!forceRefresh) {
            balance = _getCachedBalance(smartAccount, token);
            if (balance > 0) {
                return balance;
            }
        }
        
        return _getRealTokenBalance(smartAccount, token);
    }

    /**
     * @dev Refresh and cache balance for a token
     * @param smartAccount Smart account address
     * @param token Token address
     * @return balance Updated balance
     */
    function refreshTokenBalance(address smartAccount, address token) external returns (uint256 balance) {
        balance = _getRealTokenBalance(smartAccount, token);
        _updateBalanceCache(smartAccount, token, balance);
        return balance;
    }

    /**
     * @dev Validate sufficient balance for swap
     * @param smartAccount Smart account address
     * @param token Token address
     * @param requiredAmount Required amount for the swap
     */
    function _validateSufficientBalance(address smartAccount, address token, uint256 requiredAmount) internal {
        uint256 balance = _getRealTokenBalance(smartAccount, token);
        
        if (balance < requiredAmount) {
            revert InsufficientBalance();
        }
        
        // Update cache with fresh balance
        _updateBalanceCache(smartAccount, token, balance);
    }

    /**
     * @dev Validate swap parameters before execution
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount to swap
     * @param amountOutMin Minimum output amount
     */
    function _validateSwapParams(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal pure {
        if (tokenIn == address(0) || tokenOut == address(0)) {
            revert PathValidationFailed("Invalid token addresses");
        }
        if (tokenIn == tokenOut) {
            revert PathValidationFailed("Identical input and output tokens");
        }
        if (amountIn == 0) {
            revert PathValidationFailed("Zero input amount");
        }
        if (amountIn < MIN_SWAP_AMOUNT) {
            revert InsufficientSwapAmount();
        }
        if (amountOutMin == 0) {
            revert PathValidationFailed("Zero minimum output amount");
        }
    }

    /**
     * @dev Validate swap path for V2/V3 routing
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param useV3 Whether to use V3 routing
     */
    function _validateSwapPath(
        address tokenIn,
        address tokenOut,
        bool useV3
    ) internal {
        // Basic token validation
        if (tokenIn == address(0) || tokenOut == address(0)) {
            revert InvalidSwapPath();
        }
        
        // Check if we have price feeds for the tokens (basic liquidity check)
        if (!_hasValidPriceMapping(tokenIn) && tokenIn != WBNB) {
            emit PathValidationError(tokenIn, tokenOut, "No price feed for input token");
            revert PathValidationFailed("No price feed for input token");
        }
        if (!_hasValidPriceMapping(tokenOut) && tokenOut != WBNB) {
            emit PathValidationError(tokenIn, tokenOut, "No price feed for output token");
            revert PathValidationFailed("No price feed for output token");
        }
        
        // Additional V3-specific validations could be added here
        if (useV3) {
            // V3 pools might have different availability
            // This is a placeholder for more sophisticated pool existence checks
        }
    }

    /**
     * @dev Validate execution deadline
     * @param deadline Execution deadline timestamp
     */
    function _validateDeadline(uint256 deadline) internal view {
        if (deadline <= block.timestamp) {
            revert SwapDeadlineExceeded();
        }
        // Ensure deadline is reasonable (not more than 1 hour in the future)
        if (deadline > block.timestamp + 3600) {
            revert PathValidationFailed("Deadline too far in future");
        }
    }

    /**
     * @dev Check for excessive slippage and emit warnings
     * @param expectedOutput Expected output amount
     * @param minOutput Minimum acceptable output amount
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     */
    function _checkSlippageWarning(
        uint256 expectedOutput,
        uint256 minOutput,
        address tokenIn,
        address tokenOut
    ) internal {
        if (expectedOutput > 0 && minOutput > 0) {
            uint256 slippagePercent = ((expectedOutput - minOutput) * BASIS_POINTS) / expectedOutput;
            
            // Warn if slippage is more than 2%
            if (slippagePercent > 200) {
                emit SlippageWarning(
                    tokenIn,
                    tokenOut,
                    expectedOutput,
                    minOutput,
                    slippagePercent
                );
            }
        }
    }

    /**
     * @dev Build command sequence for V3 exact input swap
     * @param params V3 swap parameters
     * @return commands Encoded commands
     * @return inputs Array of encoded inputs
     */
    function _buildV3SwapCommand(V3SwapExactInParams memory params) 
        internal 
        pure 
        returns (bytes memory commands, bytes[] memory inputs) 
    {
        commands = abi.encodePacked(V3_SWAP_EXACT_IN);
        inputs = new bytes[](1);
        inputs[0] = abi.encode(
            params.recipient,
            params.amountIn,
            params.amountOutMin,
            params.path,
            params.payerIsUser
        );
    }

    /**
     * @dev Build command sequence for V2 exact input swap
     * @param params V2 swap parameters
     * @return commands Encoded commands
     * @return inputs Array of encoded inputs
     */
    function _buildV2SwapCommand(V2SwapExactInParams memory params) 
        internal 
        pure 
        returns (bytes memory commands, bytes[] memory inputs) 
    {
        commands = abi.encodePacked(V2_SWAP_EXACT_IN);
        inputs = new bytes[](1);
        inputs[0] = abi.encode(
            params.recipient,
            params.amountIn,
            params.amountOutMin,
            params.path,
            params.payerIsUser
        );
    }

    /**
     * @notice External wrapper for safe swap execution during rebalancing
     * @dev Called internally via try-catch for graceful error handling
     * @param action Rebalancing action to execute
     * @param smartAccount Smart account executing the swap
     */
    function _executeSwapSafe(RebalanceAction memory action, address smartAccount) external {
        require(msg.sender == address(this), "Only internal calls allowed");
        _executeSwap(action, smartAccount);
    }

    /**
     * @dev Execute swap through Universal Router with optimal routing
     * @param action Rebalancing action to execute
     * @param smartAccount Smart account executing the swap
     */
    function _executeSwap(RebalanceAction memory action, address smartAccount) internal {
        if (PANCAKE_UNIVERSAL_ROUTER == address(0)) revert RouterUnavailable();
        
        // Validate swap parameters
        _validateSwapParams(action.tokenIn, action.tokenOut, action.amountIn, action.amountOutMin);
        
        // Validate sufficient balance for the swap
        _validateSufficientBalance(smartAccount, action.tokenIn, action.amountIn);
        
        // Ensure Permit2 approval for input token
        _ensurePermit2Approval(smartAccount, action.tokenIn, action.amountIn);
        
        // Validate swap path
        _validateSwapPath(action.tokenIn, action.tokenOut, action.useV3);
        
        // Validate deadline (5 minutes from now)
        uint256 deadline = block.timestamp + 300;
        _validateDeadline(deadline);

        // Find optimal route
        SwapRoute memory optimalRoute = _findOptimalRoute(
            action.tokenIn,
            action.tokenOut,
            action.amountIn
        );

        // Validate route found
        if (optimalRoute.path.length == 0) revert NoRouteFound();
        
        // Update action with optimal route information
        action.useV3 = optimalRoute.useV3;
        action.amountOutMin = _calculateMinAmountOut(optimalRoute.expectedOutput, MAX_SLIPPAGE);
        
        // Check for excessive slippage and emit warning if necessary
        _checkSlippageWarning(
            optimalRoute.expectedOutput,
            action.amountOutMin,
            action.tokenIn,
            action.tokenOut
        );

        bytes memory commands;
        bytes[] memory inputs;

        if (optimalRoute.useV3) {
            // Build V3 multi-hop path
            bytes memory path = _buildV3MultiHopPath(optimalRoute.path, optimalRoute.fees);

            V3SwapExactInParams memory v3Params = V3SwapExactInParams({
                recipient: smartAccount,
                amountIn: action.amountIn,
                amountOutMin: action.amountOutMin,
                path: path,
                payerIsUser: false
            });

            (commands, inputs) = _buildV3SwapCommand(v3Params);
        } else {
            // Use V2 multi-hop path
            V2SwapExactInParams memory v2Params = V2SwapExactInParams({
                recipient: smartAccount,
                amountIn: action.amountIn,
                amountOutMin: action.amountOutMin,
                path: optimalRoute.path,
                payerIsUser: false
            });

            (commands, inputs) = _buildV2SwapCommand(v2Params);
        }

        // Execute swap through smart account
        try IERC7579Account(smartAccount).executeFromExecutor(
            ModeLib.encodeSimpleSingle(),
            abi.encodeCall(
                IUniversalRouter.execute,
                (commands, inputs, block.timestamp + 300) // 5 minute deadline
            )
        ) {
            // Refresh balance cache for both tokens after successful swap
            _updateBalanceCache(smartAccount, action.tokenIn, _getRealTokenBalance(smartAccount, action.tokenIn));
            _updateBalanceCache(smartAccount, action.tokenOut, _getRealTokenBalance(smartAccount, action.tokenOut));
            
            // Emit optimal route event
            emit OptimalRouteFound(
                action.tokenIn,
                action.tokenOut,
                action.amountIn,
                optimalRoute.expectedOutput,
                optimalRoute.useV3,
                optimalRoute.hops
            );
        } catch Error(string memory reason) {
            // Handle string revert reasons from Universal Router
            if (keccak256(bytes(reason)) == keccak256(bytes("TransactionDeadlinePassed"))) {
                emit SwapFailedWithReason(action.tokenIn, action.tokenOut, action.amountIn, "Deadline exceeded");
                revert SwapDeadlineExceeded();
            } else if (keccak256(bytes(reason)) == keccak256(bytes("LengthMismatch"))) {
                emit SwapFailedWithReason(action.tokenIn, action.tokenOut, action.amountIn, "Invalid command sequence");
                revert InvalidCommandSequence();
            } else {
                emit SwapFailedWithReason(action.tokenIn, action.tokenOut, action.amountIn, reason);
                revert SwapFailed();
            }
        } catch Panic(uint errorCode) {
            // Handle panic errors (overflow, underflow, etc.)
            emit SwapFailedWithReason(action.tokenIn, action.tokenOut, action.amountIn, "Panic error");
            revert SwapPanic(errorCode);
        } catch (bytes memory lowLevelData) {
            // Handle custom errors and low-level failures
            emit SwapFailedWithReason(action.tokenIn, action.tokenOut, action.amountIn, "Low-level execution failed");
            revert SwapExecutionFailed(lowLevelData);
        }
    }

    /**
     * @dev Encode V3 swap path for multi-hop swaps
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param fee Fee tier for the pool
     * @return path Encoded path
     */
    function _encodeV3Path(address tokenA, address tokenB, uint24 fee) 
        internal 
        pure 
        returns (bytes memory path) 
    {
        path = abi.encodePacked(tokenA, fee, tokenB);
    }

    /**
     * @dev Calculate minimum output amount with slippage protection
     * @param amountOut Expected output amount
     * @param slippageBps Slippage tolerance in basis points
     * @return minAmountOut Minimum acceptable output amount
     */
    function _calculateMinAmountOut(uint256 amountOut, uint256 slippageBps) 
        internal 
        pure 
        returns (uint256 minAmountOut) 
    {
        if (slippageBps > MAX_SLIPPAGE) revert SlippageExceeded();
        minAmountOut = (amountOut * (BASIS_POINTS - slippageBps)) / BASIS_POINTS;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            OPTIMAL ROUTING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Find the optimal route for a token swap
     * @dev Compares direct routes and multi-hop routes through intermediate tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @return route Optimal swap route with highest expected output
     */
    function _findOptimalRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (SwapRoute memory route) {
        if (tokenIn == tokenOut) revert InvalidSwapPath();
        
        SwapRoute memory bestRoute;
        uint256 bestOutput = 0;
        
        // 1. Try direct routes (V2 and V3)
        SwapRoute memory directV2Route = _getDirectRoute(tokenIn, tokenOut, amountIn, false);
        SwapRoute memory directV3Route = _getDirectRoute(tokenIn, tokenOut, amountIn, true);
        
        if (directV2Route.expectedOutput > bestOutput) {
            bestRoute = directV2Route;
            bestOutput = directV2Route.expectedOutput;
        }
        
        if (directV3Route.expectedOutput > bestOutput) {
            bestRoute = directV3Route;
            bestOutput = directV3Route.expectedOutput;
        }
        
        // 2. Try indirect routes through intermediate tokens
        for (uint256 i = 0; i < intermediateTokens.length; i++) {
            address intermediate = intermediateTokens[i];
            
            // Skip if intermediate is same as input or output
            if (intermediate == tokenIn || intermediate == tokenOut) continue;
            
            // Try V2 route: tokenIn -> intermediate -> tokenOut
            SwapRoute memory indirectV2Route = _getIndirectRoute(
                tokenIn, tokenOut, intermediate, amountIn, false
            );
            
            if (indirectV2Route.expectedOutput > bestOutput) {
                bestRoute = indirectV2Route;
                bestOutput = indirectV2Route.expectedOutput;
            }
            
            // Try V3 route: tokenIn -> intermediate -> tokenOut
            SwapRoute memory indirectV3Route = _getIndirectRoute(
                tokenIn, tokenOut, intermediate, amountIn, true
            );
            
            if (indirectV3Route.expectedOutput > bestOutput) {
                bestRoute = indirectV3Route;
                bestOutput = indirectV3Route.expectedOutput;
            }
            
            // Try mixed routes (V2->V3 and V3->V2)
            SwapRoute memory mixedRoute1 = _getMixedRoute(
                tokenIn, tokenOut, intermediate, amountIn, false, true
            );
            
            if (mixedRoute1.expectedOutput > bestOutput) {
                bestRoute = mixedRoute1;
                bestOutput = mixedRoute1.expectedOutput;
            }
            
            SwapRoute memory mixedRoute2 = _getMixedRoute(
                tokenIn, tokenOut, intermediate, amountIn, true, false
            );
            
            if (mixedRoute2.expectedOutput > bestOutput) {
                bestRoute = mixedRoute2;
                bestOutput = mixedRoute2.expectedOutput;
            }
        }
        
        return bestRoute;
    }

    /**
     * @dev Get direct route between two tokens
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Input amount
     * @param useV3 Whether to use V3 pools
     * @return route Direct swap route
     */
    function _getDirectRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bool useV3
    ) internal view returns (SwapRoute memory route) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        uint256 expectedOutput = _estimateSwapOutput(path, amountIn, useV3);
        
        if (expectedOutput > 0) {
            route.path = path;
            route.expectedOutput = expectedOutput;
            route.useV3 = useV3;
            route.hops = 1;
            
            if (useV3) {
                route.fees = new uint24[](1);
                route.fees[0] = _getBestV3Fee(tokenIn, tokenOut);
            }
        }
    }

    /**
     * @dev Get indirect route through an intermediate token
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param intermediate Intermediate token
     * @param amountIn Input amount
     * @param useV3 Whether to use V3 pools
     * @return route Indirect swap route
     */
    function _getIndirectRoute(
        address tokenIn,
        address tokenOut,
        address intermediate,
        uint256 amountIn,
        bool useV3
    ) internal view returns (SwapRoute memory route) {
        address[] memory path = new address[](3);
        path[0] = tokenIn;
        path[1] = intermediate;
        path[2] = tokenOut;
        
        uint256 expectedOutput = _estimateSwapOutput(path, amountIn, useV3);
        
        if (expectedOutput > 0) {
            route.path = path;
            route.expectedOutput = expectedOutput;
            route.useV3 = useV3;
            route.hops = 2;
            
            if (useV3) {
                route.fees = new uint24[](2);
                route.fees[0] = _getBestV3Fee(tokenIn, intermediate);
                route.fees[1] = _getBestV3Fee(intermediate, tokenOut);
            }
        }
    }

    /**
     * @dev Get mixed route using different pool versions for each hop
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param intermediate Intermediate token
     * @param amountIn Input amount
     * @param firstHopV3 Whether first hop uses V3
     * @param secondHopV3 Whether second hop uses V3
     * @return route Mixed swap route
     */
    function _getMixedRoute(
        address tokenIn,
        address tokenOut,
        address intermediate,
        uint256 amountIn,
        bool firstHopV3,
        bool secondHopV3
    ) internal view returns (SwapRoute memory route) {
        // Estimate first hop output
        address[] memory firstPath = new address[](2);
        firstPath[0] = tokenIn;
        firstPath[1] = intermediate;
        
        uint256 intermediateAmount = _estimateSwapOutput(firstPath, amountIn, firstHopV3);
        if (intermediateAmount == 0) return route;
        
        // Estimate second hop output
        address[] memory secondPath = new address[](2);
        secondPath[0] = intermediate;
        secondPath[1] = tokenOut;
        
        uint256 finalAmount = _estimateSwapOutput(secondPath, intermediateAmount, secondHopV3);
        if (finalAmount == 0) return route;
        
        // Build full path
        address[] memory fullPath = new address[](3);
        fullPath[0] = tokenIn;
        fullPath[1] = intermediate;
        fullPath[2] = tokenOut;
        
        route.path = fullPath;
        route.expectedOutput = finalAmount;
        route.useV3 = firstHopV3; // Use first hop's version for command building
        route.hops = 2;
        
        if (firstHopV3 || secondHopV3) {
            route.fees = new uint24[](2);
            route.fees[0] = firstHopV3 ? _getBestV3Fee(tokenIn, intermediate) : 0;
            route.fees[1] = secondHopV3 ? _getBestV3Fee(intermediate, tokenOut) : 0;
        }
    }

    /**
     * @dev Estimate swap output for a given path
     * @param path Token path for the swap
     * @param amountIn Input amount
     * @param useV3 Whether to use V3 pools
     * @return expectedOutput Estimated output amount
     */
    function _estimateSwapOutput(
        address[] memory path,
        uint256 amountIn,
        bool useV3
    ) internal view returns (uint256 expectedOutput) {
        if (path.length < 2) return 0;
        
        uint256 currentAmount = amountIn;
        
        for (uint256 i = 0; i < path.length - 1; i++) {
            address tokenA = path[i];
            address tokenB = path[i + 1];
            
            // Get pool liquidity estimate (simplified)
            uint256 poolLiquidity = _getPoolLiquidity(tokenA, tokenB, useV3);
            if (poolLiquidity == 0) return 0; // No liquidity, invalid route
            
            // Simple price estimation using oracle prices
            // In production, this would query actual pool reserves/prices
            (uint256 priceA, ) = _getSafePrice(tokenA);
            (uint256 priceB, ) = _getSafePrice(tokenB);
            
            if (priceA == 0 || priceB == 0) return 0;
            
            // Calculate expected output with simplified formula
            // Real implementation would use more sophisticated AMM math
            uint256 expectedOut = (currentAmount * priceA) / priceB;
            
            // Apply fee (V3: variable, V2: 0.25%)
            uint256 fee = useV3 ? _getBestV3Fee(tokenA, tokenB) : 250; // 0.25% for V2
            expectedOut = (expectedOut * (10000 - (fee / 100))) / 10000;
            
            currentAmount = expectedOut;
        }
        
        return currentAmount;
    }

    /**
     * @dev Get best V3 fee tier for a token pair
     * @param tokenA First token
     * @param tokenB Second token
     * @return fee Best fee tier
     */
    function _getBestV3Fee(address tokenA, address tokenB) internal view returns (uint24 fee) {
        // Simplified fee selection - in production, check actual pool liquidity
        // for different fee tiers and select the one with most liquidity
        
        // For major pairs, use low fee
        if (_isMajorToken(tokenA) && _isMajorToken(tokenB)) {
            return FEE_LOW;
        }
        
        // For one major token, use medium fee
        if (_isMajorToken(tokenA) || _isMajorToken(tokenB)) {
            return FEE_MEDIUM;
        }
        
        // For exotic pairs, use high fee
        return FEE_HIGH;
    }

    /**
     * @dev Check if token is a major trading pair
     * @param token Token address
     * @return isMajor Whether token is major
     */
    function _isMajorToken(address token) internal view returns (bool isMajor) {
        return isIntermediateToken[token];
    }

    /**
     * @dev Get pool liquidity estimate
     * @param tokenA First token
     * @param tokenB Second token
     * @return liquidity Estimated liquidity
     */
    function _getPoolLiquidity(
        address tokenA,
        address tokenB,
        bool /* useV3 */
    ) internal view returns (uint256 liquidity) {
        // Simplified liquidity check
        // In production, this would query actual pool contracts
        
        // Return non-zero for pairs involving intermediate tokens
        if (isIntermediateToken[tokenA] || isIntermediateToken[tokenB]) {
            return 1e18; // Placeholder liquidity value
        }
        
        return 0; // No liquidity assumption for unknown pairs
    }

    /**
     * @dev Get safe price for a token, returns 0 if unavailable
     * @param token Token address
     * @return price Token price
     * @return decimals Price decimals
     */
    function _getSafePrice(address token) internal view returns (uint256 price, uint8 decimals) {
        try this.getAssetPrice(token) returns (uint256 p, uint8 d) {
            return (p, d);
        } catch {
            // For WBNB or if price feed fails, assume 1:1 ratio for routing calculation
            if (token == WBNB) {
                return (1e18, 18);
            }
            return (0, 0);
        }
    }

    /**
     * @dev Build V3 multi-hop path with fees
     * @param path Token path
     * @param fees Fee array
     * @return encodedPath Encoded path for V3 router
     */
    function _buildV3MultiHopPath(
        address[] memory path,
        uint24[] memory fees
    ) internal pure returns (bytes memory encodedPath) {
        if (path.length < 2) revert InvalidRoute();
        if (fees.length != path.length - 1) revert InvalidRoute();
        
        encodedPath = abi.encodePacked(path[0]);
        
        for (uint256 i = 0; i < fees.length; i++) {
            encodedPath = abi.encodePacked(
                encodedPath,
                fees[i],
                path[i + 1]
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                          CORE REBALANCING LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate rebalancing needs for a portfolio
     * @dev Compares current vs target allocations and generates swap actions
     * @param smartAccount The smart account address
     * @return actions Array of RebalanceAction structs for required swaps
     */
    function _calculateRebalanceNeeds(address smartAccount) internal returns (RebalanceAction[] memory actions) {
        Config storage config = _portfolioConfigs[smartAccount];
        if (!config.isActive) revert ConfigurationNotFound();

        uint256 totalPortfolioValue = this.calculatePortfolioValue(smartAccount);
        if (totalPortfolioValue == 0) {
            return new RebalanceAction[](0);
        }

        // Step 1: Calculate current allocations and identify rebalancing needs
        (uint256[] memory currentAllocations, bool[] memory needsRebalancing, uint256 rebalanceCount) = 
            _calculateCurrentAllocations(smartAccount, totalPortfolioValue, config);

        if (rebalanceCount == 0) {
            return new RebalanceAction[](0);
        }

        // Step 2: Generate rebalance actions
        return _generateRebalanceActions(smartAccount, currentAllocations, needsRebalancing, totalPortfolioValue, config);
    }

    /**
     * @dev Calculate current allocations and drift for all assets
     * @param smartAccount The smart account address
     * @param totalPortfolioValue Total portfolio value
     * @param config Portfolio configuration
     * @return currentAllocations Current allocation percentages
     * @return needsRebalancing Boolean array indicating which assets need rebalancing
     * @return rebalanceCount Number of assets that need rebalancing
     */
    function _calculateCurrentAllocations(
        address smartAccount,
        uint256 totalPortfolioValue,
        Config storage config
    ) internal view returns (
        uint256[] memory currentAllocations,
        bool[] memory needsRebalancing,
        uint256 rebalanceCount
    ) {
        uint256 assetsLength = config.assets.length;
        currentAllocations = new uint256[](assetsLength);
        needsRebalancing = new bool[](assetsLength);
        rebalanceCount = 0;

        for (uint256 i = 0; i < assetsLength; i++) {
            address asset = config.assets[i];
            uint256 balance = _getRealTokenBalance(smartAccount, asset);
            
            if (balance == 0) {
                currentAllocations[i] = 0;
            } else {
                currentAllocations[i] = _calculateAssetAllocation(asset, balance, totalPortfolioValue);
            }
            
            // Calculate drift and check threshold
            uint256 targetAllocation = config.targetAllocations[i];
            uint256 drift = currentAllocations[i] > targetAllocation 
                ? currentAllocations[i] - targetAllocation 
                : targetAllocation - currentAllocations[i];
            
            if (drift > config.rebalancingThreshold) {
                needsRebalancing[i] = true;
                rebalanceCount++;
            }
        }
    }

    /**
     * @dev Calculate allocation percentage for a single asset
     * @param asset Asset address
     * @param balance Asset balance
     * @param totalPortfolioValue Total portfolio value
     * @return allocation Allocation percentage in basis points
     */
    function _calculateAssetAllocation(
        address asset,
        uint256 balance,
        uint256 totalPortfolioValue
    ) internal view returns (uint256 allocation) {
        (uint256 assetPrice, uint8 priceDecimals) = _getValidatedPrice(asset);
        uint8 tokenDecimals;
        try IERC20(asset).decimals() returns (uint8 decimals) {
            tokenDecimals = decimals;
        } catch {
            tokenDecimals = 18;
        }
        
        // Scale balance to match price decimals
        uint256 scaledBalance = balance;
        if (tokenDecimals > priceDecimals) {
            scaledBalance = balance / (10 ** (tokenDecimals - priceDecimals));
        } else if (tokenDecimals < priceDecimals) {
            scaledBalance = balance * (10 ** (priceDecimals - tokenDecimals));
        }
        
        uint256 assetValue = (scaledBalance * assetPrice) / (10 ** priceDecimals);
        allocation = (assetValue * BASIS_POINTS) / totalPortfolioValue;
    }

    /**
     * @dev Generate rebalance actions based on allocation analysis
     * @param currentAllocations Current allocation percentages
     * @param needsRebalancing Boolean array indicating rebalancing needs
     * @param totalPortfolioValue Total portfolio value
     * @param config Portfolio configuration
     * @return actions Array of rebalance actions
     */
    function _generateRebalanceActions(
        address /* smartAccount */,
        uint256[] memory currentAllocations,
        bool[] memory needsRebalancing,
        uint256 totalPortfolioValue,
        Config storage config
    ) internal view returns (RebalanceAction[] memory actions) {
        uint256 maxActions = 0;
        uint256 assetsLength = config.assets.length;
        
        // Count potential actions (over-allocated assets)
        for (uint256 i = 0; i < assetsLength; i++) {
            if (needsRebalancing[i] && currentAllocations[i] > config.targetAllocations[i]) {
                maxActions++;
            }
        }
        
        if (maxActions == 0) {
            return new RebalanceAction[](0);
        }
        
        actions = new RebalanceAction[](maxActions);
        uint256 actionIndex = 0;

        // Generate swap actions for over-allocated assets
        for (uint256 i = 0; i < assetsLength; i++) {
            if (!needsRebalancing[i] || currentAllocations[i] <= config.targetAllocations[i]) continue;
            
            address sellAsset = config.assets[i];
            uint256 excessValue = ((currentAllocations[i] - config.targetAllocations[i]) * totalPortfolioValue) / BASIS_POINTS;
            uint256 amountToSell = _calculateSellAmount(sellAsset, excessValue);
            
            if (amountToSell < MIN_SWAP_AMOUNT) continue;
            
            address buyAsset = _findBestBuyAsset(currentAllocations, needsRebalancing, config, i);
            if (buyAsset == address(0)) continue;
            
            SwapRoute memory route = _findOptimalRoute(sellAsset, buyAsset, amountToSell);
            
            actions[actionIndex] = RebalanceAction({
                tokenIn: sellAsset,
                tokenOut: buyAsset,
                amountIn: amountToSell,
                amountOutMin: _calculateMinAmountOut(route.expectedOutput, MAX_SLIPPAGE),
                useV3: route.useV3
            });
            actionIndex++;
        }
        
        // Resize array if needed
        if (actionIndex < maxActions) {
            RebalanceAction[] memory resizedActions = new RebalanceAction[](actionIndex);
            for (uint256 i = 0; i < actionIndex; i++) {
                resizedActions[i] = actions[i];
            }
            return resizedActions;
        }
        
        return actions;
    }

    /**
     * @dev Calculate amount to sell for rebalancing
     * @param asset Asset to sell
     * @param excessValue Excess value to sell
     * @return amountToSell Amount to sell in asset tokens
     */
    function _calculateSellAmount(address asset, uint256 excessValue) internal view returns (uint256 amountToSell) {
        (uint256 assetPrice, uint8 priceDecimals) = _getValidatedPrice(asset);
        uint8 tokenDecimals;
        try IERC20(asset).decimals() returns (uint8 decimals) {
            tokenDecimals = decimals;
        } catch {
            tokenDecimals = 18;
        }
        
        amountToSell = (excessValue * (10 ** priceDecimals)) / assetPrice;
        if (tokenDecimals > priceDecimals) {
            amountToSell = amountToSell * (10 ** (tokenDecimals - priceDecimals));
        } else if (tokenDecimals < priceDecimals) {
            amountToSell = amountToSell / (10 ** (priceDecimals - tokenDecimals));
        }
    }

    /**
     * @dev Find the best asset to buy (most under-allocated)
     * @param currentAllocations Current allocation percentages
     * @param needsRebalancing Boolean array indicating rebalancing needs
     * @param config Portfolio configuration
     * @param excludeIndex Index to exclude from search
     * @return bestBuyAsset Address of best asset to buy
     */
    function _findBestBuyAsset(
        uint256[] memory currentAllocations,
        bool[] memory needsRebalancing,
        Config storage config,
        uint256 excludeIndex
    ) internal view returns (address bestBuyAsset) {
        uint256 largestDeficit = 0;
        
        for (uint256 j = 0; j < config.assets.length; j++) {
            if (j == excludeIndex || !needsRebalancing[j]) continue;
            if (currentAllocations[j] >= config.targetAllocations[j]) continue;
            
            uint256 deficit = config.targetAllocations[j] - currentAllocations[j];
            if (deficit > largestDeficit) {
                largestDeficit = deficit;
                bestBuyAsset = config.assets[j];
            }
        }
    }

    /**
     * @notice Execute rebalancing operations for a portfolio
     * @dev Processes RebalanceAction array with optimal ordering and constraints
     * @param smartAccount The smart account address
     * @param actions Array of rebalance actions to execute
     */
    function _executeRebalance(address smartAccount, RebalanceAction[] memory actions) internal {
        if (actions.length == 0) return;
        
        uint256 successfulSwaps = 0;
        
        // Sort actions by amount (largest first) for optimal execution order
        _sortActionsByAmount(actions);
        
        for (uint256 i = 0; i < actions.length; i++) {
            RebalanceAction memory action = actions[i];
            
            // Validate minimum trade amount
            if (action.amountIn < MIN_SWAP_AMOUNT) {
                emit SwapFailedWithReason(
                    action.tokenIn, 
                    action.tokenOut, 
                    action.amountIn, 
                    "Amount below minimum"
                );
                continue;
            }
            
            // Validate sufficient balance
            uint256 currentBalance = _getRealTokenBalance(smartAccount, action.tokenIn);
            if (currentBalance < action.amountIn) {
                emit SwapFailedWithReason(
                    action.tokenIn, 
                    action.tokenOut, 
                    action.amountIn, 
                    "Insufficient balance"
                );
                continue;
            }
            
            // Execute the swap with graceful error handling
            try this._executeSwapSafe(action, smartAccount) {
                successfulSwaps++;
            } catch Error(string memory reason) {
                emit SwapFailedWithReason(action.tokenIn, action.tokenOut, action.amountIn, reason);
            } catch {
                emit SwapFailedWithReason(action.tokenIn, action.tokenOut, action.amountIn, "Unknown error");
            }
        }
        
        // Refresh balance cache for all portfolio assets after rebalancing
        Config storage config = _portfolioConfigs[smartAccount];
        for (uint256 i = 0; i < config.assets.length; i++) {
            address asset = config.assets[i];
            uint256 newBalance = _getRealTokenBalance(smartAccount, asset);
            _updateBalanceCache(smartAccount, asset, newBalance);
        }
        
        // Emit completion event with success ratio
        if (successfulSwaps > 0) {
            emit PortfolioRebalanced(smartAccount, block.timestamp);
        } else {
            emit RebalancingSkipped(smartAccount, "All swaps failed");
        }
    }

    /**
     * @notice Execute complete portfolio rebalancing
     * @dev End-to-end rebalancing function with validation and execution
     * @param smartAccount The smart account address (optional, defaults to msg.sender)
     */
    function executePortfolioRebalancing(address smartAccount) public {
        if (smartAccount == address(0)) {
            smartAccount = msg.sender;
        }
        
        Config storage config = _portfolioConfigs[smartAccount];
        if (!config.isActive) revert ConfigurationNotFound();
        
        // Check minimum interval
        if (block.timestamp < config.lastRebalanceTimestamp + MIN_REBALANCE_INTERVAL) {
            emit RebalancingSkipped(smartAccount, "Minimum interval not met");
            revert RebalancingTooFrequent();
        }
        
        // Validate that we have price feeds for all assets
        for (uint256 i = 0; i < config.assets.length; i++) {
            if (!_hasValidPriceMapping(config.assets[i])) {
                emit RebalancingSkipped(smartAccount, "Price feed not available for all assets");
                revert UnsupportedAsset();
            }
        }
        
        // Calculate rebalancing needs
        RebalanceAction[] memory actions = _calculateRebalanceNeeds(smartAccount);
        
        if (actions.length == 0) {
            emit RebalancingSkipped(smartAccount, "No rebalancing needed");
            return;
        }
        
        // Execute rebalancing
        _executeRebalance(smartAccount, actions);
        
        // Update last rebalance timestamp
        config.lastRebalanceTimestamp = block.timestamp;
    }

    /**
     * @notice Execute complete portfolio rebalancing (public wrapper)
     * @dev Allows external calls to trigger rebalancing for the caller
     */
    function rebalancePortfolio() external {
        executePortfolioRebalancing(msg.sender);
    }

    /**
     * @dev Sort rebalance actions by amount in descending order for optimal execution
     * @param actions Array of rebalance actions to sort
     */
    function _sortActionsByAmount(RebalanceAction[] memory actions) internal pure {
        if (actions.length <= 1) return;
        
        // Simple bubble sort for small arrays (portfolio rebalancing typically has few actions)
        for (uint256 i = 0; i < actions.length - 1; i++) {
            for (uint256 j = 0; j < actions.length - i - 1; j++) {
                if (actions[j].amountIn < actions[j + 1].amountIn) {
                    // Swap actions
                    RebalanceAction memory temp = actions[j];
                    actions[j] = actions[j + 1];
                    actions[j + 1] = temp;
                }
            }
        }
    }

    /**
     * @notice Check if portfolio needs rebalancing with detailed drift analysis
     * @dev Enhanced version that provides drift information for each asset
     * @param smartAccount The smart account address
     * @return needed Whether rebalancing is needed
     * @return drifts Array of drift percentages for each asset (in basis points)
     * @return reason Human-readable reason for the decision
     */
    function checkRebalancingNeeds(address smartAccount) 
        external 
        returns (bool needed, uint256[] memory drifts, string memory reason) 
    {
        Config storage config = _portfolioConfigs[smartAccount];
        
        if (!config.isActive) {
            drifts = new uint256[](0);
            return (false, drifts, "Configuration not active");
        }
        
        if (block.timestamp < config.lastRebalanceTimestamp + MIN_REBALANCE_INTERVAL) {
            drifts = new uint256[](0);
            return (false, drifts, "Minimum interval not met");
        }
        
        uint256 totalPortfolioValue = this.calculatePortfolioValue(smartAccount);
        if (totalPortfolioValue == 0) {
            drifts = new uint256[](0);
            return (false, drifts, "No portfolio value");
        }
        
        uint256 assetsLength = config.assets.length;
        drifts = new uint256[](assetsLength);
        bool needsRebalancing = false;
        uint256 maxDrift = 0;
        
        for (uint256 i = 0; i < assetsLength; i++) {
            address asset = config.assets[i];
            uint256 balance = _getRealTokenBalance(smartAccount, asset);
            uint256 currentAllocation = 0;
            
            if (balance > 0) {
                (uint256 assetPrice, uint8 priceDecimals) = _getValidatedPrice(asset);
                uint8 tokenDecimals;
                try IERC20(asset).decimals() returns (uint8 decimals) {
                    tokenDecimals = decimals;
                } catch {
                    tokenDecimals = 18;
                }
                
                uint256 scaledBalance = balance;
                if (tokenDecimals > priceDecimals) {
                    scaledBalance = balance / (10 ** (tokenDecimals - priceDecimals));
                } else if (tokenDecimals < priceDecimals) {
                    scaledBalance = balance * (10 ** (priceDecimals - tokenDecimals));
                }
                
                uint256 assetValue = (scaledBalance * assetPrice) / (10 ** priceDecimals);
                currentAllocation = (assetValue * BASIS_POINTS) / totalPortfolioValue;
            }
            
            uint256 targetAllocation = config.targetAllocations[i];
            uint256 drift = currentAllocation > targetAllocation 
                ? currentAllocation - targetAllocation 
                : targetAllocation - currentAllocation;
            
            drifts[i] = drift;
            
            if (drift > maxDrift) {
                maxDrift = drift;
            }
            
            if (drift > config.rebalancingThreshold) {
                needsRebalancing = true;
            }
        }
        
        if (needsRebalancing) {
            return (true, drifts, "Drift threshold exceeded");
        } else {
            return (false, drifts, "Within tolerance");
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                        INTERMEDIATE TOKEN MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Preview optimal route for a token swap
     * @dev Public function to check routing without executing
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @return route Optimal swap route information
     */
    function previewOptimalRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (SwapRoute memory route) {
        return _findOptimalRoute(tokenIn, tokenOut, amountIn);
    }

    /**
     * @notice Add an intermediate token for routing
     * @param token Token address to add
     */
    function addIntermediateToken(address token) external {
        _addIntermediateToken(token);
    }

    /**
     * @notice Remove an intermediate token from routing
     * @param token Token address to remove
     */
    function removeIntermediateToken(address token) external {
        if (!isIntermediateToken[token]) revert IntermediateTokenError();
        
        isIntermediateToken[token] = false;
        
        // Remove from array
        for (uint256 i = 0; i < intermediateTokens.length; i++) {
            if (intermediateTokens[i] == token) {
                intermediateTokens[i] = intermediateTokens[intermediateTokens.length - 1];
                intermediateTokens.pop();
                break;
            }
        }
        
        emit IntermediateTokenUpdated(token, false);
    }

    /**
     * @notice Get all intermediate tokens
     * @return tokens Array of intermediate token addresses
     */
    function getIntermediateTokens() external view returns (address[] memory tokens) {
        return intermediateTokens;
    }

    /**
     * @dev Internal function to add intermediate token
     * @param token Token address to add
     */
    function _addIntermediateToken(address token) private {
        if (token == address(0)) revert ZeroAddress();
        if (isIntermediateToken[token]) return; // Already added
        
        isIntermediateToken[token] = true;
        intermediateTokens.push(token);
        
        emit IntermediateTokenUpdated(token, true);
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