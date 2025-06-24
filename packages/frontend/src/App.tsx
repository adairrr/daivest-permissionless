import { useState, useCallback } from "react";
import Layout from "./components/Layout";
import { useAccount, useWalletClient, usePublicClient } from "wagmi";
import { Card } from "./components/ui/card";
import { Button } from "./components/ui/button";
import { Wallet, Plus, Shield, CheckCircle, AlertCircle, Loader2, Copy, ExternalLink } from "lucide-react";
import { toSafeSmartAccount, ToSafeSmartAccountReturnType } from "permissionless/accounts";
import { createSmartAccountClient, SmartAccountClient } from "permissionless";
import { entryPoint07Address, type PaymasterActions } from 'viem/account-abstraction'
import { Address, Chain, Transport, http } from "viem";
import { Erc7579Actions, erc7579Actions } from "permissionless/actions/erc7579";
import { bscTestnet, sepolia } from 'viem/chains'
import type { GetPaymasterDataParameters } from 'viem/account-abstraction/actions/paymaster/getPaymasterData.ts'
import type { GetPaymasterStubDataParameters } from 'viem/account-abstraction/actions/paymaster/getPaymasterStubData.ts'

interface SmartAccount {
  address: string;
  status: 'created' | 'module_installed' | 'configured';
  portfolioValue?: string;
  smartAccountClient?: SmartAccountClient<Transport, Chain, ToSafeSmartAccountReturnType<"0.7">> & Erc7579Actions<ToSafeSmartAccountReturnType<"0.7">>;
}

// Configuration constants
export const CURRENT_CHAIN = sepolia;
const CHAIN_NAME = CURRENT_CHAIN.name
const EXPLORER_URL = "https://sepolia.etherscan.io";
const ALCHEMY_API_KEY = import.meta.env.VITE_ALCHEMY_API_KEY || '';
const ALCHEMY_CHAIN_NAME = CURRENT_CHAIN.id === 97 ? 'bnb-testnet' : 'eth-sepolia'

// Portfolio Manager Executor address (deployed on BSC testnet, but using Sepolia for AA infrastructure)
const PORTFOLIO_MANAGER_EXECUTOR_ADDRESS = "0x216F8088DF93940e6117561d5b293F5151c6329c" as Address;

function App() {
  const account = useAccount();
  const { data: walletClient } = useWalletClient();
  const publicClient = usePublicClient();
  const [smartAccounts, setSmartAccounts] = useState<SmartAccount[]>([]);
  const [isCreating, setIsCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copiedAddress, setCopiedAddress] = useState<string | null>(null);

  const copyToClipboard = async (address: string) => {
    try {
      await navigator.clipboard.writeText(address);
      setCopiedAddress(address);
      setTimeout(() => setCopiedAddress(null), 2000);
    } catch (err) {
      console.error("Failed to copy:", err);
    }
  };

  const createPortfolio = useCallback(async () => {
    if (!account.address || !walletClient || !publicClient) {
      setError("Please connect your wallet first");
      return;
    }

    setIsCreating(true);
    setError(null);

    try {
      console.log("Creating Safe smart account...");

      // Create Safe smart account using permissionless SDK on Sepolia (better AA support)
      const safeAccount = await toSafeSmartAccount({
        saltNonce: BigInt(5), // Random salt for unique addresses
        client: publicClient,
        owners: [walletClient.account],
        version: "1.4.1",
        entryPoint: {
          address: entryPoint07Address,
          version: "0.7",
        },
        // Use known working addresses for Sepolia
        safe4337ModuleAddress: "0x7579EE8307284F293B1927136486880611F20002",
        erc7579LaunchpadAddress: "0x7579011aB74c46090561ea277Ba79D510c6C00ff",
        attesters: [],
        attestersThreshold: 0,
        validators: [],
      });

      const smartAccountClient = createSmartAccountClient({
        account: safeAccount,
        chain: CURRENT_CHAIN,
        bundlerTransport: http(`https://${ALCHEMY_CHAIN_NAME}.g.alchemy.com/v2/${ALCHEMY_API_KEY}`),
        // paymaster: pimlicoPaymasterClient,
      }).extend(erc7579Actions());

      console.log(`Smart account created: ${safeAccount.address}`);

      // Add to our state
      const newSmartAccount: SmartAccount = {
        address: safeAccount.address,
        status: 'created',
        smartAccountClient: smartAccountClient as unknown as any,
      };

      setSmartAccounts(prev => [...prev, newSmartAccount]);

    } catch (err) {
      console.error("Error creating portfolio:", err);
      setError(err instanceof Error ? err.message : "Failed to create portfolio");
    } finally {
      setIsCreating(false);
    }
  }, [account, walletClient, publicClient]);

  const installPortfolioModule = useCallback(async (smartAccount: SmartAccount) => {
    if (!smartAccount.smartAccountClient || !publicClient) {
      setError("Smart account client not available");
      return;
    }

    try {
      console.log("Installing Portfolio Manager Executor module...");

      // Check if the account is deployed first
      const accountCode = await publicClient.getCode({ address: smartAccount.address as Address });
      if (!accountCode || accountCode === "0x") {
        console.log("Account not deployed yet, deploying first...");

        // Send a simple transaction to deploy the account
        const deployTx = await smartAccount.smartAccountClient.sendUserOperation({
          calls: [{
            to: smartAccount.address as Address,
            value: BigInt(0),
            data: "0x",
          }],
        });

        console.log({deployTx})

        await smartAccount.smartAccountClient.waitForUserOperationReceipt({
          hash: deployTx,
        });

        console.log("Account deployed successfully");
      }

      // Now install the module using the correct ERC-7579 approach
      const userOpHash = await smartAccount.smartAccountClient.installModule({
        type: "executor",
        address: PORTFOLIO_MANAGER_EXECUTOR_ADDRESS,
        context: "0x", // Empty context for now
      });

      console.log("Module installation UserOp hash:", userOpHash);

      // Wait for the transaction to be confirmed
      const receipt = await smartAccount.smartAccountClient.waitForUserOperationReceipt({
        hash: userOpHash,
      });

      console.log("Module installation receipt:", receipt);

      // Update the smart account status
      setSmartAccounts(prev =>
        prev.map(acc =>
          acc.address === smartAccount.address
            ? { ...acc, status: 'module_installed' as const }
            : acc
        )
      );

    } catch (err) {
      console.error("Error installing module:", err);
      setError(err instanceof Error ? err.message : "Failed to install module");
    }
  }, [publicClient]);

  const getStatusColor = (status: SmartAccount['status']) => {
    switch (status) {
      case 'created':
        return 'text-yellow-700 bg-yellow-100 dark:text-yellow-400 dark:bg-yellow-900/30';
      case 'module_installed':
        return 'text-blue-700 bg-blue-100 dark:text-blue-400 dark:bg-blue-900/30';
      case 'configured':
        return 'text-green-700 bg-green-100 dark:text-green-400 dark:bg-green-900/30';
      default:
        return 'text-gray-700 bg-gray-100 dark:text-gray-400 dark:bg-gray-900/30';
    }
  };

  const getStatusIcon = (status: SmartAccount['status']) => {
    switch (status) {
      case 'created':
        return <AlertCircle className="h-4 w-4" />;
      case 'module_installed':
        return <Loader2 className="h-4 w-4 animate-spin" />;
      case 'configured':
        return <CheckCircle className="h-4 w-4" />;
      default:
        return <AlertCircle className="h-4 w-4" />;
    }
  };

  const getStatusText = (status: SmartAccount['status']) => {
    switch (status) {
      case 'created':
        return 'Created - Install Module';
      case 'module_installed':
        return 'Module Installed - Configure';
      case 'configured':
        return 'Ready';
      default:
        return 'Unknown';
    }
  };

  return (
    <Layout>
      <div className="space-y-8">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-4xl font-bold tracking-tight bg-gradient-to-r from-foreground to-foreground/70 bg-clip-text text-transparent">
              Portfolio Manager
            </h1>
            <p className="text-lg text-muted-foreground mt-2">
              Create and manage AI-powered smart account portfolios
            </p>
          </div>
          <div className="flex items-center space-x-4">
            <div className="flex items-center space-x-2 px-4 py-2 bg-green-100 dark:bg-green-900/20 rounded-full border border-green-200 dark:border-green-800">
              <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
              <span className="text-sm font-medium text-green-700 dark:text-green-400">{CHAIN_NAME}</span>
            </div>
          </div>
        </div>

        {/* Connection Status */}
        <Card className="p-6 bg-card/50 backdrop-blur-sm border-border/50">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <div className="p-2 bg-primary/10 rounded-lg">
                <Wallet className="h-6 w-6 text-primary" />
              </div>
              <div>
                <h3 className="text-xl font-semibold">Wallet Connection</h3>
                <p className="text-sm text-muted-foreground">
                  {account.status === 'connected'
                    ? `Connected: ${account.address?.slice(0, 6)}...${account.address?.slice(-4)}`
                    : 'Please connect your wallet to create portfolios'
                  }
                </p>
              </div>
            </div>
            <div className={`px-3 py-1 rounded-full text-sm font-semibold ${
              account.status === 'connected'
                ? 'text-green-700 bg-green-100 dark:text-green-400 dark:bg-green-900/30'
                : 'text-yellow-700 bg-yellow-100 dark:text-yellow-400 dark:bg-yellow-900/30'
            }`}>
              {account.status === 'connected' ? 'Connected' : 'Disconnected'}
            </div>
          </div>
        </Card>

        {/* Create Portfolio Section */}
        {account.status === 'connected' && (
          <Card className="p-6 bg-card/50 backdrop-blur-sm border-border/50">
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-3">
                <div className="p-2 bg-primary/10 rounded-lg">
                  <Plus className="h-6 w-6 text-primary" />
                </div>
                <div>
                  <h3 className="text-xl font-semibold">Create New Portfolio</h3>
                  <p className="text-sm text-muted-foreground">
                    Deploy a new ERC-7579 smart account with portfolio management capabilities
                  </p>
                </div>
              </div>
              <Button
                onClick={createPortfolio}
                disabled={isCreating}
                className="flex items-center space-x-2"
              >
                {isCreating ? (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin" />
                    <span>Creating...</span>
                  </>
                ) : (
                  <>
                    <Plus className="h-4 w-4" />
                    <span>Create Portfolio</span>
                  </>
                )}
              </Button>
            </div>
            {error && (
              <div className="mt-4 p-3 bg-red-100 dark:bg-red-900/20 rounded-lg border border-red-200 dark:border-red-800">
                <p className="text-sm text-red-700 dark:text-red-400">{error}</p>
              </div>
            )}
          </Card>
        )}

        {/* Smart Accounts List */}
        {smartAccounts.length > 0 && (
          <div className="space-y-4">
            <h2 className="text-2xl font-semibold">Your Portfolio Accounts</h2>
            <Card className="divide-y divide-border/50 bg-card/50 backdrop-blur-sm border-border/50">
              {smartAccounts.map((smartAccount, index) => (
                <div key={index} className="p-6">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center space-x-4">
                      <div className="p-2 bg-primary/10 rounded-lg">
                        <Shield className="h-5 w-5 text-primary" />
                      </div>
                      <div className="flex-1">
                        <div className="flex items-center space-x-3 mb-2">
                          <h3 className="text-lg font-semibold">Portfolio #{index + 1}</h3>
                          <div className={`flex items-center space-x-1 px-2 py-1 rounded-full text-xs font-semibold ${getStatusColor(smartAccount.status)}`}>
                            {getStatusIcon(smartAccount.status)}
                            <span>{getStatusText(smartAccount.status)}</span>
                          </div>
                        </div>
                        <div className="flex items-center space-x-4">
                          <div className="flex items-center space-x-2">
                            <span className="text-sm text-muted-foreground">Address:</span>
                            <span className="text-sm font-mono bg-background/50 px-2 py-1 rounded">
                              {smartAccount.address.slice(0, 6)}...{smartAccount.address.slice(-4)}
                            </span>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => copyToClipboard(smartAccount.address)}
                              className="h-8 w-8 p-0"
                            >
                              {copiedAddress === smartAccount.address ? (
                                <CheckCircle className="h-4 w-4 text-green-500" />
                              ) : (
                                <Copy className="h-4 w-4" />
                              )}
                            </Button>
                          </div>
                          {smartAccount.portfolioValue && (
                            <div className="flex items-center space-x-2">
                              <span className="text-sm text-muted-foreground">Value:</span>
                              <span className="text-lg font-bold text-foreground">{smartAccount.portfolioValue}</span>
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                    <div className="flex items-center space-x-2">
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => window.open(`${EXPLORER_URL}/address/${smartAccount.address}`, '_blank')}
                      >
                        <ExternalLink className="h-4 w-4 mr-2" />
                        View on {CURRENT_CHAIN.blockExplorers?.default.name || 'Explorer'}
                      </Button>
                      {smartAccount.status === 'created' && (
                        <Button
                          size="sm"
                          onClick={() => installPortfolioModule(smartAccount)}
                        >
                          Install Module
                        </Button>
                      )}
                      {smartAccount.status === 'module_installed' && (
                        <Button
                          size="sm"
                          disabled
                        >
                          Configure Portfolio
                        </Button>
                      )}
                      {smartAccount.status === 'configured' && (
                        <Button
                          size="sm"
                        >
                          Manage Portfolio
                        </Button>
                      )}
                    </div>
                  </div>

                  {smartAccount.status === 'created' && (
                    <div className="mt-4 p-3 bg-yellow-50 dark:bg-yellow-900/20 rounded-lg border border-yellow-200 dark:border-yellow-800">
                      <p className="text-sm text-yellow-700 dark:text-yellow-400">
                        Next step: Install the Portfolio Manager Executor module to enable AI-powered portfolio management.
                      </p>
                    </div>
                  )}

                  {smartAccount.status === 'module_installed' && (
                    <div className="mt-4 p-3 bg-blue-50 dark:bg-blue-900/20 rounded-lg border border-blue-200 dark:border-blue-800">
                      <p className="text-sm text-blue-700 dark:text-blue-400">
                        Module installed! Configure your initial portfolio allocation and risk parameters.
                      </p>
                    </div>
                  )}
                </div>
              ))}
            </Card>
          </div>
        )}

        {/* Info Section */}
        <Card className="p-6 bg-card/50 backdrop-blur-sm border-border/50">
          <div className="flex items-center space-x-3 mb-4">
            <div className="p-2 bg-primary/10 rounded-lg">
              <Shield className="h-6 w-6 text-primary" />
            </div>
            <h3 className="text-xl font-semibold">How It Works</h3>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="text-center">
              <div className="w-12 h-12 bg-primary/10 rounded-full flex items-center justify-center mx-auto mb-3">
                <span className="text-lg font-bold text-primary">1</span>
              </div>
              <h4 className="font-semibold mb-2">Create Smart Account</h4>
              <p className="text-sm text-muted-foreground">
                Deploy an ERC-7579 smart account owned by your wallet
              </p>
            </div>
            <div className="text-center">
              <div className="w-12 h-12 bg-primary/10 rounded-full flex items-center justify-center mx-auto mb-3">
                <span className="text-lg font-bold text-primary">2</span>
              </div>
              <h4 className="font-semibold mb-2">Install Portfolio Module</h4>
              <p className="text-sm text-muted-foreground">
                Add AI portfolio management with NAV protection
              </p>
            </div>
            <div className="text-center">
              <div className="w-12 h-12 bg-primary/10 rounded-full flex items-center justify-center mx-auto mb-3">
                <span className="text-lg font-bold text-primary">3</span>
              </div>
              <h4 className="font-semibold mb-2">Start Trading</h4>
              <p className="text-sm text-muted-foreground">
                Enjoy protected, AI-optimized portfolio management
              </p>
            </div>
          </div>
        </Card>
      </div>
    </Layout>
  );
}

export default App;
