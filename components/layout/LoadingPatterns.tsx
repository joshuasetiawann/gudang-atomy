import { Skeleton, SkeletonText } from "@/components/ui/skeleton";

export function DashboardLoading() {
  return (
    <div className="app-page space-y-6" role="status" aria-label="Memuat halaman">
      <span className="sr-only">Memuat halaman</span>
      <div className="surface-panel relative overflow-hidden rounded-lg border shadow-card p-5 sm:p-6">
        <div className="absolute inset-x-0 top-0 h-1 bg-[linear-gradient(90deg,hsl(var(--primary)/0.4),hsl(var(--accent)/0.4))]" />
        <Skeleton className="h-3 w-28" />
        <Skeleton className="mt-3 h-8 w-56" />
        <Skeleton className="mt-3 h-4 w-full max-w-md" />
      </div>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {Array.from({ length: 6 }).map((_, index) => (
          <div key={index} className="surface-panel rounded-lg border shadow-card p-5">
            <div className="flex items-center justify-between">
              <div className="w-full max-w-48">
                <Skeleton className="h-4 w-28" />
                <Skeleton className="mt-4 h-8 w-16" />
              </div>
              <Skeleton className="h-11 w-11 rounded-md" />
            </div>
          </div>
        ))}
      </div>
      <TableLoading rows={8} columns={5} />
    </div>
  );
}

export function TableLoading({ rows = 8, columns = 5 }: { rows?: number; columns?: number }) {
  return (
    <div className="overflow-hidden rounded-lg border bg-card shadow-card" role="status" aria-label="Memuat tabel">
      <span className="sr-only">Memuat tabel</span>
      <div className="grid gap-4 border-b bg-muted/55 p-4" style={{ gridTemplateColumns: `repeat(${columns}, minmax(92px, 1fr))` }}>
        {Array.from({ length: columns }).map((_, index) => (
          <Skeleton key={index} className="h-3 w-20" />
        ))}
      </div>
      <div className="divide-y">
        {Array.from({ length: rows }).map((_, rowIndex) => (
          <div key={rowIndex} className="grid gap-4 p-4 transition-colors" style={{ gridTemplateColumns: `repeat(${columns}, minmax(92px, 1fr))` }}>
            {Array.from({ length: columns }).map((_, columnIndex) => (
              <Skeleton key={columnIndex} className="h-4 w-full" />
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}

export function FormLoading() {
  return (
    <div className="app-page space-y-5" role="status" aria-label="Memuat form">
      <span className="sr-only">Memuat form</span>
      <div className="surface-panel rounded-lg border shadow-card p-5 sm:p-6">
        <Skeleton className="h-5 w-32" />
        <SkeletonText className="mt-4" lines={2} />
        <div className="mt-5 grid gap-4 md:grid-cols-2">
          {Array.from({ length: 6 }).map((_, index) => (
            <Skeleton key={index} className="h-10 w-full" />
          ))}
        </div>
      </div>
      <div className="surface-panel rounded-lg border shadow-card p-5 sm:p-6">
        <Skeleton className="h-5 w-40" />
        <div className="mt-5 space-y-3">
          {Array.from({ length: 4 }).map((_, index) => (
            <Skeleton key={index} className="h-12 w-full" />
          ))}
        </div>
      </div>
    </div>
  );
}

export function LoginLoading() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-[linear-gradient(180deg,hsl(210_28%_98%),hsl(178_28%_94%))] p-4" role="status" aria-label="Memuat halaman masuk">
      <span className="sr-only">Memuat halaman masuk</span>
      <div className="surface-panel animate-rise w-full max-w-md rounded-xl border p-7 shadow-lift">
        <div className="flex items-start gap-4">
          <Skeleton className="h-12 w-12 rounded-lg" />
          <div className="flex-1">
            <Skeleton className="h-7 w-44" />
            <Skeleton className="mt-3 h-4 w-full" />
          </div>
        </div>
        <div className="mt-7 space-y-4">
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-11 w-full" />
        </div>
      </div>
    </main>
  );
}
