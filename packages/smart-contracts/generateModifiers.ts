import { policyModifierGeneration } from "@thrackle-io/forte-rules-engine-sdk";

const modifiersPath = "src/RulesEngineClientCustom.sol";
const yourContract = "src/PortfolioManagerExecutor.sol";

policyModifierGeneration("policy.json", modifiersPath, [yourContract]);