// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { PortfolioManagerExecutor } from "../src/PortfolioManagerExecutor.sol";

/**
 * @title MockSupraPriceFeed
 * @dev Mock implementation of ISupraPriceFeed for testing
 */
contract MockSupraPriceFeed {
    struct PriceData {
        uint256 price;
        uint256 decimals;
        uint256 timestamp;
        uint256 round;
    }

    mapping(uint256 => PriceData) public prices;
    bool public shouldFail;

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function setPrice(uint256 pairId, uint256 price, uint256 decimals) external {
        prices[pairId] = PriceData({
            price: price,
            decimals: decimals,
            timestamp: block.timestamp,
            round: 1
        });
    }

    function getSvalue(uint256 pairId) external view returns (
        bytes32 price,
        uint256 decimals,
        uint256 timestamp,
        uint256 round
    ) {
        require(!shouldFail, "Oracle failure");
        PriceData memory data = prices[pairId];
        return (bytes32(data.price), data.decimals, data.timestamp, data.round);
    }

    function getSvalues(uint256[] calldata pairIds) external view returns (
        bytes32[] memory pricesArray,
        uint256[] memory decimalsArray,
        uint256[] memory timestamps,
        uint256[] memory rounds
    ) {
        require(!shouldFail, "Oracle failure");
        uint256 length = pairIds.length;
        pricesArray = new bytes32[](length);
        decimalsArray = new uint256[](length);
        timestamps = new uint256[](length);
        rounds = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            PriceData memory data = prices[pairIds[i]];
            pricesArray[i] = bytes32(data.price);
            decimalsArray[i] = data.decimals;
            timestamps[i] = data.timestamp;
            rounds[i] = data.round;
        }
    }
}

/**
 * @title MockERC20
 * @dev Simple mock ERC20 for testing
 */
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/**
 * @title MockERC7579Account
 * @dev Mock smart account for testing executor calls
 */
contract MockERC7579Account {
    address public executor;
    bytes public lastExecutionData;
    bytes32 public lastMode;
    bool public shouldFailExecution;

    function setExecutor(address _executor) external {
        executor = _executor;
    }

    function setShouldFailExecution(bool _shouldFail) external {
        shouldFailExecution = _shouldFail;
    }

    function executeFromExecutor(bytes32 mode, bytes calldata executionCalldata) external {
        require(msg.sender == executor, "Only executor");
        require(!shouldFailExecution, "Execution failed");
        lastMode = mode;
        lastExecutionData = executionCalldata;
    }

    // Simulate module installation
    function installModule(uint256 moduleType, address module, bytes calldata initData) external {
        // Call the module's onInstall function
        (bool success,) = module.call(abi.encodeWithSignature("onInstall(bytes)", initData));
        require(success, "Module installation failed");
    }

    // Simulate module uninstallation
    function uninstallModule(uint256 moduleType, address module, bytes calldata deinitData) external {
        // Call the module's onUninstall function
        (bool success,) = module.call(abi.encodeWithSignature("onUninstall(bytes)", deinitData));
        require(success, "Module uninstallation failed");
    }
}

/**
 * @title PortfolioManagerExecutorTest
 * @dev Comprehensive test suite for PortfolioManagerExecutor
 */
contract PortfolioManagerExecutorTest is Test {
    PortfolioManagerExecutor public executor;
    MockSupraPriceFeed public mockOracle;
    MockERC7579Account public mockAccount;
    MockERC20 public cakeToken;
    MockERC20 public bnbToken;
    MockERC20 public usdtToken;

    // Test addresses
    address public user = address(0x1);
    address public admin = address(0x2);

    // Constants from contract
    uint256 constant MAX_ASSETS = 10;
    uint256 constant MIN_THRESHOLD = 10; // 0.1%
    uint256 constant MAX_THRESHOLD = 5000; // 50%
    uint256 constant BASIS_POINTS = 10000;
    uint256 constant MIN_REBALANCE_INTERVAL = 1 hours;
    uint256 constant MAX_PRICE_STALENESS = 30 minutes;
    uint256 constant BNB_USDC_PAIR_ID = 370;
    uint256 constant CAKE_USDT_PAIR_ID = 125;
    uint256 constant TYPE_EXECUTOR = 2;

    // Test data
    address[] assets;
    uint256[] allocations;
    uint256 rebalancingThreshold = 500; // 5%

    event PortfolioConfigured(
        address indexed smartAccount,
        address[] assets,
        uint256[] targetAllocations,
        uint256 rebalancingThreshold
    );

    event PortfolioRemoved(address indexed smartAccount);
    event PortfolioRebalanced(address indexed smartAccount, uint256 timestamp);
    event RebalancingSkipped(address indexed smartAccount, string reason);
    event PriceUpdated(address indexed asset, uint256 price, uint256 timestamp);
    event PortfolioValueCalculated(address indexed smartAccount, uint256 totalValue, uint256 timestamp);
    event SupraOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event AssetPairMappingUpdated(address indexed asset, uint256 pairId);

    function setUp() public {
        // Deploy mocks
        mockOracle = new MockSupraPriceFeed();
        mockAccount = new MockERC7579Account();

        // Deploy tokens
        cakeToken = new MockERC20("PancakeSwap Token", "CAKE", 18);
        bnbToken = new MockERC20("Binance Coin", "BNB", 18);
        usdtToken = new MockERC20("Tether USD", "USDT", 6);

        // Deploy executor
        executor = new PortfolioManagerExecutor();

        // Update oracle to our mock
        executor.updateSupraPriceFeed(address(mockOracle));

        // Set up asset pair mappings
        executor.setAssetPairMapping(address(bnbToken), BNB_USDC_PAIR_ID);
        executor.setAssetPairMapping(address(cakeToken), CAKE_USDT_PAIR_ID);
        executor.setAssetPairMapping(address(usdtToken), 999); // Custom pair ID for USDT

        // Set up mock prices
        mockOracle.setPrice(BNB_USDC_PAIR_ID, 300e8, 8); // $300 BNB
        mockOracle.setPrice(CAKE_USDT_PAIR_ID, 2e8, 8);   // $2 CAKE
        mockOracle.setPrice(999, 1e8, 8);                 // $1 USDT

        // Set up test arrays
        assets = new address[](3);
        assets[0] = address(cakeToken);
        assets[1] = address(bnbToken);
        assets[2] = address(usdtToken);

        allocations = new uint256[](3);
        allocations[0] = 4000; // 40%
        allocations[1] = 3000; // 30%
        allocations[2] = 3000; // 30%

        // Configure mock account
        mockAccount.setExecutor(address(executor));

        // Set caller as mock account for most tests
        vm.startPrank(address(mockAccount));
    }

    function tearDown() public {
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 INSTALLATION TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_OnInstall_Success() public {
        bytes memory installData = abi.encode(assets, allocations, rebalancingThreshold);

        vm.expectEmit(true, false, false, true);
        emit PortfolioConfigured(address(mockAccount), assets, allocations, rebalancingThreshold);

        executor.onInstall(installData);

        // Verify configuration was stored
        (
            address[] memory storedAssets,
            uint256[] memory storedAllocations,
            uint256 storedThreshold,
            uint256 lastRebalance,
            bool isActive
        ) = executor.getPortfolioConfig(address(mockAccount));

        assertEq(storedAssets.length, assets.length);
        assertEq(storedAssets[0], assets[0]);
        assertEq(storedAllocations[0], allocations[0]);
        assertEq(storedThreshold, rebalancingThreshold);
        assertTrue(isActive);
        assertEq(lastRebalance, block.timestamp);
        assertTrue(executor.isInitialized(address(mockAccount)));
    }

    function test_OnInstall_RevertEmptyData() public {
        vm.expectRevert(PortfolioManagerExecutor.NoAssetsProvided.selector);
        executor.onInstall("");
    }

    function test_OnInstall_RevertNoAssets() public {
        address[] memory emptyAssets;
        uint256[] memory emptyAllocations;
        bytes memory installData = abi.encode(emptyAssets, emptyAllocations, rebalancingThreshold);

        vm.expectRevert(PortfolioManagerExecutor.NoAssetsProvided.selector);
        executor.onInstall(installData);
    }

    function test_OnInstall_RevertTooManyAssets() public {
        address[] memory tooManyAssets = new address[](MAX_ASSETS + 1);
        uint256[] memory tooManyAllocations = new uint256[](MAX_ASSETS + 1);

        for (uint256 i = 0; i <= MAX_ASSETS; i++) {
            tooManyAssets[i] = address(uint160(i + 1));
            tooManyAllocations[i] = BASIS_POINTS / (MAX_ASSETS + 1);
        }

        bytes memory installData = abi.encode(tooManyAssets, tooManyAllocations, rebalancingThreshold);

        vm.expectRevert(PortfolioManagerExecutor.TooManyAssets.selector);
        executor.onInstall(installData);
    }

    function test_OnInstall_RevertArrayLengthMismatch() public {
        address[] memory mismatchedAssets = new address[](2);
        uint256[] memory mismatchedAllocations = new uint256[](3);

        bytes memory installData = abi.encode(mismatchedAssets, mismatchedAllocations, rebalancingThreshold);

        vm.expectRevert(PortfolioManagerExecutor.ArrayLengthMismatch.selector);
        executor.onInstall(installData);
    }

    function test_OnInstall_RevertInvalidAllocationSum() public {
        uint256[] memory invalidAllocations = new uint256[](3);
        invalidAllocations[0] = 4000;
        invalidAllocations[1] = 3000;
        invalidAllocations[2] = 2000; // Sum = 9000, not 10000
        bytes memory installData = abi.encode(assets, invalidAllocations, rebalancingThreshold);

        vm.expectRevert(PortfolioManagerExecutor.InvalidAllocationSum.selector);
        executor.onInstall(installData);
    }

    function test_OnInstall_RevertInvalidThreshold() public {
        bytes memory installData = abi.encode(assets, allocations, MIN_THRESHOLD - 1);

        vm.expectRevert(PortfolioManagerExecutor.InvalidThreshold.selector);
        executor.onInstall(installData);

        installData = abi.encode(assets, allocations, MAX_THRESHOLD + 1);

        vm.expectRevert(PortfolioManagerExecutor.InvalidThreshold.selector);
        executor.onInstall(installData);
    }

    function test_OnInstall_RevertZeroAddress() public {
        address[] memory assetsWithZero = new address[](3);
        assetsWithZero[0] = address(0);
        assetsWithZero[1] = address(bnbToken);
        assetsWithZero[2] = address(usdtToken);
        bytes memory installData = abi.encode(assetsWithZero, allocations, rebalancingThreshold);

        vm.expectRevert(PortfolioManagerExecutor.ZeroAddress.selector);
        executor.onInstall(installData);
    }

    /*//////////////////////////////////////////////////////////////////////////
                               UNINSTALLATION TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_OnUninstall_Success() public {
        // First install
        bytes memory installData = abi.encode(assets, allocations, rebalancingThreshold);
        executor.onInstall(installData);

        // Verify it's installed
        assertTrue(executor.isInitialized(address(mockAccount)));

        // Uninstall
        vm.expectEmit(true, false, false, false);
        emit PortfolioRemoved(address(mockAccount));

        executor.onUninstall("");

        // Verify it's uninstalled
        assertFalse(executor.isInitialized(address(mockAccount)));
    }

    function test_OnUninstall_RevertNotConfigured() public {
        vm.expectRevert(PortfolioManagerExecutor.ConfigurationNotFound.selector);
        executor.onUninstall("");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  MODULE TYPE TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_IsModuleType() public {
        assertTrue(executor.isModuleType(TYPE_EXECUTOR));
        assertFalse(executor.isModuleType(1)); // TYPE_VALIDATOR
        assertFalse(executor.isModuleType(3)); // TYPE_FALLBACK
    }

    function test_Metadata() public {
        assertEq(executor.name(), "PortfolioManagerExecutor");
        assertEq(executor.version(), "1.1.0");
    }

    /*//////////////////////////////////////////////////////////////////////////
                              PRICE FEED TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_UpdateSupraPriceFeed() public {
        address newOracle = address(0x123);

        vm.expectEmit(true, true, false, false);
        emit SupraOracleUpdated(address(mockOracle), newOracle);

        executor.updateSupraPriceFeed(newOracle);

        assertEq(address(executor.supraPriceFeed()), newOracle);
    }

    function test_UpdateSupraPriceFeed_RevertZeroAddress() public {
        vm.expectRevert(PortfolioManagerExecutor.ZeroAddress.selector);
        executor.updateSupraPriceFeed(address(0));
    }

    function test_SetAssetPairMapping() public {
        address newAsset = address(0x456);
        uint256 newPairId = 789;

        vm.expectEmit(true, false, false, true);
        emit AssetPairMappingUpdated(newAsset, newPairId);

        executor.setAssetPairMapping(newAsset, newPairId);

        assertEq(executor.assetToPairId(newAsset), newPairId);
    }

    function test_SetAssetPairMapping_RevertZeroAddress() public {
        vm.expectRevert(PortfolioManagerExecutor.ZeroAddress.selector);
        executor.setAssetPairMapping(address(0), 123);
    }

    function test_GetAssetPrice() public {
        (uint256 price, uint8 decimals) = executor.getAssetPrice(address(bnbToken));

        assertEq(price, 300e8);
        assertEq(decimals, 8);
    }

    function test_GetAssetPrice_RevertUnsupportedAsset() public {
        address unsupportedAsset = address(0x999);

        vm.expectRevert(PortfolioManagerExecutor.UnsupportedAsset.selector);
        executor.getAssetPrice(unsupportedAsset);
    }

    function test_GetAssetPrice_RevertOracleFailure() public {
        mockOracle.setShouldFail(true);

        vm.expectRevert(PortfolioManagerExecutor.OracleFailure.selector);
        executor.getAssetPrice(address(bnbToken));
    }

    function test_UpdatePrices() public {
        address[] memory assetsToUpdate = new address[](2);
        assetsToUpdate[0] = address(bnbToken);
        assetsToUpdate[1] = address(cakeToken);

        vm.expectEmit(true, false, false, true);
        emit PriceUpdated(address(bnbToken), 300e8, block.timestamp);

        executor.updatePrices(assetsToUpdate);

        assertTrue(executor.isPriceFresh(address(bnbToken)));
        assertTrue(executor.isPriceFresh(address(cakeToken)));
    }

    function test_IsPriceFresh() public {
        // Initially no cached price
        assertFalse(executor.isPriceFresh(address(bnbToken)));

        // Update price
        address[] memory assetsToUpdate = new address[](1);
        assetsToUpdate[0] = address(bnbToken);
        executor.updatePrices(assetsToUpdate);

        // Should be fresh
        assertTrue(executor.isPriceFresh(address(bnbToken)));

        // Advance time beyond staleness threshold
        vm.warp(block.timestamp + MAX_PRICE_STALENESS + 1);

        // Should no longer be fresh
        assertFalse(executor.isPriceFresh(address(bnbToken)));
    }

    /*//////////////////////////////////////////////////////////////////////////
                             PORTFOLIO LOGIC TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_ExecuteRebalancing() public {
        // Install portfolio
        bytes memory installData = abi.encode(assets, allocations, rebalancingThreshold);
        executor.onInstall(installData);

        // Advance time to meet minimum interval
        vm.warp(block.timestamp + MIN_REBALANCE_INTERVAL);

        bytes memory rebalanceData = "0x1234";

        vm.expectEmit(true, false, false, true);
        emit PortfolioRebalanced(address(mockAccount), block.timestamp);

        executor.executeRebalancing(rebalanceData);

        // Verify execution was called on mock account
        assertEq(mockAccount.lastExecutionData(), rebalanceData);
    }

    function test_ExecuteRebalancing_RevertNotConfigured() public {
        vm.expectRevert(PortfolioManagerExecutor.ConfigurationNotFound.selector);
        executor.executeRebalancing("0x1234");
    }

    function test_ExecuteRebalancing_RevertTooFrequent() public {
        // Install portfolio
        bytes memory installData = abi.encode(assets, allocations, rebalancingThreshold);
        executor.onInstall(installData);

        // Try to rebalance immediately (should fail)
        vm.expectRevert(PortfolioManagerExecutor.RebalancingTooFrequent.selector);
        executor.executeRebalancing("0x1234");
    }

    function test_UpdatePortfolioConfig() public {
        // Install portfolio
        bytes memory installData = abi.encode(assets, allocations, rebalancingThreshold);
        executor.onInstall(installData);

        uint256[] memory newAllocations = new uint256[](3);
        newAllocations[0] = 5000;
        newAllocations[1] = 2500;
        newAllocations[2] = 2500; // 50%, 25%, 25%
        uint256 newThreshold = 1000; // 10%

        vm.expectEmit(true, false, false, true);
        emit PortfolioConfigured(address(mockAccount), assets, newAllocations, newThreshold);

        executor.updatePortfolioConfig(newAllocations, newThreshold);

        // Verify update
        (, uint256[] memory storedAllocations, uint256 storedThreshold,,) =
            executor.getPortfolioConfig(address(mockAccount));

        assertEq(storedAllocations[0], newAllocations[0]);
        assertEq(storedThreshold, newThreshold);
    }

    function test_IsRebalancingNeeded() public {
        // Install portfolio
        bytes memory installData = abi.encode(assets, allocations, rebalancingThreshold);
        executor.onInstall(installData);

        // Should fail due to time constraint
        (bool needed, string memory reason) = executor.isRebalancingNeeded(address(mockAccount));
        assertFalse(needed);
        assertEq(reason, "Minimum interval not met");

        // Advance time
        vm.warp(block.timestamp + MIN_REBALANCE_INTERVAL);

        (needed, reason) = executor.isRebalancingNeeded(address(mockAccount));
        assertTrue(needed);
        assertEq(reason, "Conditions met for rebalancing");
    }

    function test_CalculatePortfolioValue() public {
        // Install portfolio
        bytes memory installData = abi.encode(assets, allocations, rebalancingThreshold);
        executor.onInstall(installData);

        vm.expectEmit(true, false, false, true);
        emit PortfolioValueCalculated(address(mockAccount), 303, block.timestamp);

        uint256 totalValue = executor.calculatePortfolioValue(address(mockAccount));

        // Total should be sum of normalized prices: 300 + 2 + 1 = 303
        assertEq(totalValue, 303);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   FUZZ TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function testFuzz_ValidAllocationSum(uint256[] memory fuzzAllocations) public {
        vm.assume(fuzzAllocations.length >= 1 && fuzzAllocations.length <= MAX_ASSETS);

        // Ensure allocations sum to BASIS_POINTS
        uint256 sum = 0;
        for (uint256 i = 0; i < fuzzAllocations.length - 1; i++) {
            fuzzAllocations[i] = bound(fuzzAllocations[i], 1, BASIS_POINTS - (fuzzAllocations.length - 1));
            sum += fuzzAllocations[i];
        }
        fuzzAllocations[fuzzAllocations.length - 1] = BASIS_POINTS - sum;

        // Create matching assets array
        address[] memory fuzzAssets = new address[](fuzzAllocations.length);
        for (uint256 i = 0; i < fuzzAllocations.length; i++) {
            fuzzAssets[i] = address(uint160(i + 1));
            executor.setAssetPairMapping(fuzzAssets[i], i + 1);
            mockOracle.setPrice(i + 1, 1e8, 8);
        }

        bytes memory installData = abi.encode(fuzzAssets, fuzzAllocations, rebalancingThreshold);

        // Should not revert
        executor.onInstall(installData);
        assertTrue(executor.isInitialized(address(mockAccount)));
    }

    function testFuzz_PriceValidation(uint256 price, uint256 decimals) public {
        price = bound(price, 1, type(uint128).max);
        decimals = bound(decimals, 0, 18);

        mockOracle.setPrice(BNB_USDC_PAIR_ID, price, decimals);

        (uint256 returnedPrice, uint8 returnedDecimals) = executor.getAssetPrice(address(bnbToken));

        assertEq(returnedPrice, price);
        assertEq(returnedDecimals, decimals);
    }

    function testFuzz_ThresholdValidation(uint256 threshold) public {
        if (threshold < MIN_THRESHOLD || threshold > MAX_THRESHOLD) {
            bytes memory installData = abi.encode(assets, allocations, threshold);
            vm.expectRevert(PortfolioManagerExecutor.InvalidThreshold.selector);
            executor.onInstall(installData);
        } else {
            bytes memory installData = abi.encode(assets, allocations, threshold);
            executor.onInstall(installData);
            assertTrue(executor.isInitialized(address(mockAccount)));
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 EDGE CASE TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_StalePrice() public {
        // Set up a stale price
        mockOracle.setPrice(BNB_USDC_PAIR_ID, 300e8, 8);

        // Advance time beyond staleness threshold
        vm.warp(block.timestamp + MAX_PRICE_STALENESS + 1);

        vm.expectRevert(PortfolioManagerExecutor.StalePriceData.selector);
        executor.getAssetPrice(address(bnbToken));
    }

    function test_ZeroPrice() public {
        mockOracle.setPrice(BNB_USDC_PAIR_ID, 0, 8);

        vm.expectRevert(PortfolioManagerExecutor.InvalidPrice.selector);
        executor.getAssetPrice(address(bnbToken));
    }

    function test_PriceFeedUnavailable() public {
        executor.updateSupraPriceFeed(address(0));

        vm.expectRevert(PortfolioManagerExecutor.PriceFeedUnavailable.selector);
        executor.getAssetPrice(address(bnbToken));
    }

    function test_MultipleAccountsIndependence() public {
        MockERC7579Account account2 = new MockERC7579Account();
        account2.setExecutor(address(executor));

        // Install for first account
        bytes memory installData1 = abi.encode(assets, allocations, rebalancingThreshold);
        executor.onInstall(installData1);

        // Install for second account with different config
        uint256[] memory allocations2 = new uint256[](3);
        allocations2[0] = 3000;
        allocations2[1] = 4000;
        allocations2[2] = 3000;
        bytes memory installData2 = abi.encode(assets, allocations2, 1000);

        vm.prank(address(account2));
        executor.onInstall(installData2);

        // Verify independence
        (, uint256[] memory storedAllocations1,,,) = executor.getPortfolioConfig(address(mockAccount));
        (, uint256[] memory storedAllocations2,,,) = executor.getPortfolioConfig(address(account2));

        assertEq(storedAllocations1[0], 4000);
        assertEq(storedAllocations2[0], 3000);
    }
}
