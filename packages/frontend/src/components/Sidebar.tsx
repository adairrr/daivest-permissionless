import {
  Sidebar,
  SidebarContent,
  SidebarHeader,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuButton,
  SidebarSeparator,
} from "./ui/sidebar";
import { 
  Home, 
  PieChart, 
  TrendingUp, 
  Wallet, 
  Settings, 
  Brain, 
  BarChart3,
  Zap,
  Shield,
  Bell,
  HelpCircle,
  Sparkles
} from "lucide-react";

const navigationItems = [
  {
    title: "Overview",
    items: [
      { icon: Home, label: "Dashboard", href: "#", active: true },
      { icon: PieChart, label: "Portfolio", href: "#" },
      { icon: TrendingUp, label: "Trading", href: "#" },
      { icon: BarChart3, label: "Analytics", href: "#" },
    ]
  },
  {
    title: "AI Features",
    items: [
      { icon: Brain, label: "AI Insights", href: "#" },
      { icon: Zap, label: "Smart Signals", href: "#" },
      { icon: Shield, label: "Risk Manager", href: "#" },
    ]
  },
  {
    title: "Account",
    items: [
      { icon: Wallet, label: "Wallet", href: "#" },
      { icon: Bell, label: "Notifications", href: "#" },
      { icon: Settings, label: "Settings", href: "#" },
    ]
  }
];

export default function AppSidebar() {
  return (
    <Sidebar className="border-r border-border/40">
      <SidebarHeader className="p-4 border-b border-border/40">
        <div className="flex items-center space-x-3">
          <div className="relative">
            <Brain className="h-8 w-8 text-primary" />
            <Sparkles className="h-4 w-4 text-accent absolute -top-1 -right-1 animate-pulse" />
          </div>
          <div className="flex flex-col">
            <h1 className="text-xl font-bold bg-gradient-to-r from-primary to-accent bg-clip-text text-transparent">
              Simplifai
            </h1>
            <p className="text-xs text-muted-foreground">AI-Powered Intelligence</p>
          </div>
        </div>
      </SidebarHeader>
      <SidebarContent className="px-2">
        {navigationItems.map((section, index) => (
          <SidebarGroup key={section.title}>
            <SidebarGroupLabel className="text-xs font-semibold text-muted-foreground/70 mb-2">
              {section.title}
            </SidebarGroupLabel>
            <SidebarMenu>
              {section.items.map((item) => (
                <SidebarMenuItem key={item.label}>
                  <SidebarMenuButton 
                    asChild 
                    className={`w-full justify-start hover:bg-accent/50 transition-colors ${
                      item.active ? 'bg-accent text-accent-foreground' : ''
                    }`}
                  >
                    <a href={item.href} className="flex items-center space-x-3 px-3 py-2">
                      <item.icon className="h-4 w-4" />
                      <span className="text-sm font-medium">{item.label}</span>
                    </a>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
            {index < navigationItems.length - 1 && <SidebarSeparator className="my-2" />}
          </SidebarGroup>
        ))}
        
        <SidebarSeparator className="my-4" />
        
        <SidebarGroup>
          <SidebarMenu>
            <SidebarMenuItem>
              <SidebarMenuButton asChild className="w-full justify-start hover:bg-accent/50 transition-colors">
                <a href="#" className="flex items-center space-x-3 px-3 py-2">
                  <HelpCircle className="h-4 w-4" />
                  <span className="text-sm font-medium">Help & Support</span>
                </a>
              </SidebarMenuButton>
            </SidebarMenuItem>
          </SidebarMenu>
        </SidebarGroup>
      </SidebarContent>
    </Sidebar>
  );
}
