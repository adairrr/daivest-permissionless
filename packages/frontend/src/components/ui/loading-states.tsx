import { Skeleton } from "./skeleton";
import { Card } from "./card";

export function DashboardCardSkeleton() {
  return (
    <Card className="p-6">
      <div className="flex items-center justify-between space-y-0 pb-2">
        <div className="flex items-center space-x-2">
          <Skeleton className="h-4 w-4" />
          <Skeleton className="h-4 w-24" />
        </div>
        <Skeleton className="h-3 w-8" />
      </div>
      <Skeleton className="h-8 w-20" />
    </Card>
  );
}

export function ChartSkeleton() {
  return (
    <Card className="col-span-2 p-6">
      <div className="flex items-center space-x-2 mb-4">
        <Skeleton className="h-5 w-5" />
        <Skeleton className="h-5 w-32" />
      </div>
      <div className="h-64 bg-gradient-to-br from-primary/5 to-accent/5 rounded-lg flex items-center justify-center">
        <div className="flex flex-col items-center space-y-2">
          <Skeleton className="h-4 w-32" />
          <div className="flex space-x-1">
            {[...Array(5)].map((_, i) => (
              <Skeleton key={i} className="h-16 w-6" />
            ))}
          </div>
        </div>
      </div>
    </Card>
  );
}

export function AccountStatusSkeleton() {
  return (
    <Card className="p-6">
      <div className="flex items-center space-x-2 mb-4">
        <Skeleton className="h-5 w-5" />
        <Skeleton className="h-5 w-24" />
      </div>
      <div className="space-y-4">
        <div className="flex justify-between">
          <Skeleton className="h-4 w-16" />
          <Skeleton className="h-4 w-20" />
        </div>
        <div className="flex justify-between">
          <Skeleton className="h-4 w-12" />
          <Skeleton className="h-4 w-32" />
        </div>
        <div className="flex justify-between">
          <Skeleton className="h-4 w-14" />
          <Skeleton className="h-4 w-16" />
        </div>
      </div>
    </Card>
  );
}

export function InsightCardSkeleton() {
  return (
    <div className="p-4 bg-gradient-to-br from-blue-50 to-blue-100 dark:from-blue-900/20 dark:to-blue-800/20 rounded-lg">
      <Skeleton className="h-4 w-24 mb-2" />
      <Skeleton className="h-3 w-full" />
      <Skeleton className="h-3 w-3/4 mt-1" />
    </div>
  );
}

export function LoadingSpinner({ className }: { className?: string }) {
  return (
    <div className={`animate-spin rounded-full border-2 border-primary border-t-transparent ${className || "h-6 w-6"}`} />
  );
}

export function FullPageLoader() {
  return (
    <div className="flex items-center justify-center min-h-screen">
      <div className="flex flex-col items-center space-y-4">
        <LoadingSpinner className="h-8 w-8" />
        <p className="text-muted-foreground">Loading Simplifai...</p>
      </div>
    </div>
  );
}