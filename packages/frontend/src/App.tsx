import Layout from "./components/Layout";
import { useAccount } from "wagmi";
import { Card } from "./components/ui/card";
import { Wallet, Network, Shield, Activity, TrendingUp, Zap } from "lucide-react";

function App() {
  const account = useAccount();

  const stats = [
    { icon: Wallet, label: "Total Balance", value: "$12,345.67", change: "+5.2%" },
    { icon: Activity, label: "Active Positions", value: "8", change: "+2" },
    { icon: TrendingUp, label: "24h P&L", value: "+$234.56", change: "+1.8%" },
    { icon: Zap, label: "AI Suggestions", value: "12", change: "New" },
  ];

  return (
    <Layout>
      <div className="space-y-8">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-4xl font-bold tracking-tight bg-gradient-to-r from-foreground to-foreground/70 bg-clip-text text-transparent">
              Dashboard
            </h1>
            <p className="text-lg text-muted-foreground mt-2">
              Welcome back to your AI-powered trading hub
            </p>
          </div>
          <div className="flex items-center space-x-4">
            <div className="flex items-center space-x-2 px-4 py-2 bg-green-100 dark:bg-green-900/20 rounded-full border border-green-200 dark:border-green-800">
              <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
              <span className="text-sm font-medium text-green-700 dark:text-green-400">Live Market Data</span>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          {stats.map((stat, index) => (
            <Card key={index} className="p-6 hover:shadow-lg transition-all duration-200 hover:-translate-y-1 bg-card/50 backdrop-blur-sm border-border/50">
              <div className="flex items-center justify-between space-y-0 pb-3">
                <div className="flex items-center space-x-3">
                  <div className="p-2 bg-primary/10 rounded-lg">
                    <stat.icon className="h-5 w-5 text-primary" />
                  </div>
                  <p className="text-sm font-medium text-muted-foreground">
                    {stat.label}
                  </p>
                </div>
                <span className="text-xs text-green-600 dark:text-green-400 font-semibold bg-green-100 dark:bg-green-900/30 px-2 py-1 rounded">
                  {stat.change}
                </span>
              </div>
              <div className="text-3xl font-bold text-foreground">{stat.value}</div>
            </Card>
          ))}
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <Card className="col-span-2 p-6 bg-card/50 backdrop-blur-sm border-border/50">
            <div className="flex items-center space-x-3 mb-6">
              <div className="p-2 bg-primary/10 rounded-lg">
                <Activity className="h-6 w-6 text-primary" />
              </div>
              <h3 className="text-xl font-semibold">Portfolio Performance</h3>
            </div>
            <div className="h-64 bg-gradient-to-br from-primary/10 via-accent/5 to-transparent rounded-xl border border-border/20 flex items-center justify-center relative overflow-hidden">
              <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-primary/5 via-transparent to-transparent"></div>
              <div className="relative z-10 text-center">
                <p className="text-muted-foreground text-lg mb-2">Chart visualization coming soon</p>
                <p className="text-sm text-muted-foreground/70">Real-time portfolio analytics</p>
              </div>
            </div>
          </Card>

          <Card className="p-6 bg-card/50 backdrop-blur-sm border-border/50">
            <div className="flex items-center space-x-3 mb-6">
              <div className="p-2 bg-primary/10 rounded-lg">
                <Shield className="h-6 w-6 text-primary" />
              </div>
              <h3 className="text-xl font-semibold">Account Status</h3>
            </div>
            <div className="space-y-4">
              <div className="flex justify-between items-center p-3 bg-accent/10 rounded-lg">
                <span className="text-sm font-medium text-muted-foreground">Connection</span>
                <span className={`text-sm font-semibold px-3 py-1 rounded-full ${
                  account.status === 'connected'
                    ? 'text-green-700 bg-green-100 dark:text-green-400 dark:bg-green-900/30'
                    : 'text-yellow-700 bg-yellow-100 dark:text-yellow-400 dark:bg-yellow-900/30'
                }`}>
                  {account.status === 'connected' ? 'Connected' : 'Disconnected'}
                </span>
              </div>
              {account.addresses && (
                <div className="flex justify-between items-center p-3 bg-accent/10 rounded-lg">
                  <span className="text-sm font-medium text-muted-foreground">Address</span>
                  <span className="text-sm font-mono bg-background/50 px-2 py-1 rounded">
                    {account.addresses[0]?.slice(0, 6)}...{account.addresses[0]?.slice(-4)}
                  </span>
                </div>
              )}
              <div className="flex justify-between items-center p-3 bg-accent/10 rounded-lg">
                <span className="text-sm font-medium text-muted-foreground">Network</span>
                <div className="flex items-center space-x-2">
                  <Network className="h-4 w-4 text-primary" />
                  <span className="text-sm font-medium">
                    {account.chainId ? `Chain ${account.chainId}` : 'Unknown'}
                  </span>
                </div>
              </div>
            </div>
          </Card>
        </div>
      </div>
    </Layout>
  );
}

export default App;
