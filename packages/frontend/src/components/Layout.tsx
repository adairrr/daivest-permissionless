import Header from "./Header";
import Footer from "./Footer";
import AppSidebar from "./Sidebar";
import { SidebarProvider, SidebarTrigger } from "./ui/sidebar";
import React from "react";

export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <SidebarProvider>
      <div className="flex flex-col min-h-screen bg-background">
        <Header />
        <div className="flex flex-1">
          <AppSidebar />
          <main className="flex-1 p-6 overflow-y-auto">
            <SidebarTrigger className="mb-4" />
            {children}
          </main>
        </div>
        <Footer />
      </div>
    </SidebarProvider>
  );
}
