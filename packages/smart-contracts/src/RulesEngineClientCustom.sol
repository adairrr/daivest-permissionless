import "@thrackle-io/forte-rules-engine/src/client/RulesEngineClient.sol";

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;
import { RebalanceAction } from "./PortfolioManagerExecutor.sol";

/**
 * @title Template Contract for Testing the Rules Engine
 * @author @mpetersoCode55, @ShaneDuncan602, @TJ-Everett, @VoR0220
 * @dev This file serves as a template for dynamically injecting custom Solidity modifiers into smart contracts.
 *              It defines an abstract contract that extends the `RulesEngineClient` contract, providing a placeholder
 *              for modifiers that are generated and injected programmatically.
 */
abstract contract RulesEngineClientCustom is RulesEngineClient {
    modifier checkRulesBeforeexecutePortfolioRebalancing(address smartAccount) {
		bytes memory encoded = abi.encodeWithSelector(msg.sig,smartAccount);
		_invokeRulesEngine(encoded);
		_;
	}

	modifier checkRulesAfterexecutePortfolioRebalancing(address smartAccount) {
		bytes memory encoded = abi.encodeWithSelector(msg.sig,smartAccount);
		_;
		_invokeRulesEngine(encoded);
	}

	modifier checkRulesBefore_executeRebalance(address smartAccount, RebalanceAction[] memory actions, uint256 portfolioValueAfter) {
		bytes memory encoded = abi.encodeWithSelector(msg.sig,smartAccount, actions, portfolioValueAfter);
		_invokeRulesEngine(encoded);
		_;
	}

	modifier checkRulesAfter_executeRebalance(address smartAccount, RebalanceAction[] memory actions, uint256 portfolioValueAfter) {
		bytes memory encoded = abi.encodeWithSelector(msg.sig,smartAccount, actions, portfolioValueAfter);
		_;
		_invokeRulesEngine(encoded);
	}

	modifier checkRulesBeforeupdateMaxDriftThreshold(uint256 newMaxDrift) {
		bytes memory encoded = abi.encodeWithSelector(msg.sig,newMaxDrift);
		_invokeRulesEngine(encoded);
		_;
	}

	modifier checkRulesAfterupdateMaxDriftThreshold(uint256 newMaxDrift) {
		bytes memory encoded = abi.encodeWithSelector(msg.sig,newMaxDrift);
		_;
		_invokeRulesEngine(encoded);
	}


}
