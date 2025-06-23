import Header from "./Header";
import Footer from "./Footer";
import AppSidebar from "./Sidebar";
import { SidebarProvider, SidebarTrigger, SidebarInset } from "./ui/sidebar";
import React from "react";

export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <SidebarProvider>
      <div className="flex min-h-screen bg-gradient-to-br from-background via-background to-accent/5 min-w-full">
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-primary/5 via-transparent to-transparent pointer-events-none"></div>
        <AppSidebar />
        <SidebarInset className="flex flex-col flex-1">
          <Header />
          <main className="flex-1 p-6 overflow-y-auto relative">
            <div className="flex items-center mb-6">
              <SidebarTrigger className="mr-4 p-2 hover:bg-accent/50 rounded-md transition-colors" />
              <div className="h-6 w-px bg-border" />
            </div>
            <div className="relative z-10">
              {children}
            </div>
          </main>
          <Footer />
        </SidebarInset>
      </div>
    </SidebarProvider>
  );
}
