import { Skeleton } from "@/components/ui/skeleton";
import { TableLoading } from "@/components/layout/LoadingPatterns";

export default function DashboardRouteLoading() {
  return (
    <div className="app-page space-y-6" role="status" aria-label="Memuat halaman">
      <span className="sr-only">Memuat halaman</span>
      <div className="surface-panel relative overflow-hidden rounded-xl border p-5 shadow-card sm:p-6">
        <div aria-hidden="true" className="absolute inset-x-0 top-0 h-1 bg-[linear-gradient(90deg,hsl(var(--primary)/0.4),hsl(var(--accent)/0.4))]" />
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <Skeleton className="h-3 w-28" />
            <Skeleton className="mt-3 h-8 w-56" />
            <Skeleton className="mt-3 h-4 w-full max-w-md" />
          </div>
          <Skeleton className="h-11 w-44 rounded-md" />
        </div>
      </div>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {Array.from({ length: 8 }).map((_, index) => (
          <div key={index} className="surface-panel rounded-lg border p-5 shadow-card">
            <div className="flex items-center justify-between gap-4">
              <div className="w-full max-w-48">
                <Skeleton className="h-4 w-28" />
                <Skeleton className="mt-4 h-8 w-16" />
              </div>
              <Skeleton className="h-12 w-12 rounded-lg" />
            </div>
          </div>
        ))}
      </div>
      <TableLoading rows={8} columns={5} />
    </div>
  );
}
