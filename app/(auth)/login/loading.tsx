import { Skeleton } from "@/components/ui/skeleton";

export default function LoginRouteLoading() {
  return (
    <main
      className="relative flex min-h-screen items-center justify-center overflow-hidden bg-[linear-gradient(180deg,hsl(210_28%_98%),hsl(178_28%_94%))] p-4"
      role="status"
      aria-label="Memuat halaman masuk"
    >
      <span className="sr-only">Memuat halaman masuk</span>
      <div aria-hidden="true" className="pointer-events-none absolute inset-0 overflow-hidden">
        <div className="absolute -left-32 -top-40 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
        <div className="absolute -right-40 top-1/4 h-[28rem] w-[28rem] rounded-full bg-accent/10 blur-3xl" />
      </div>
      <div className="relative z-10 w-full max-w-md">
        <div className="surface-panel animate-rise w-full rounded-xl border p-7 shadow-lift sm:p-8">
          <div className="flex flex-col items-center">
            <Skeleton className="h-14 w-14 rounded-xl" />
            <Skeleton className="mt-4 h-7 w-44" />
            <Skeleton className="mt-3 h-4 w-64" />
          </div>
          <div className="mt-7 space-y-4">
            <div className="space-y-2">
              <Skeleton className="h-4 w-16" />
              <Skeleton className="h-10 w-full" />
            </div>
            <div className="space-y-2">
              <Skeleton className="h-4 w-20" />
              <Skeleton className="h-10 w-full" />
            </div>
            <Skeleton className="h-11 w-full" />
          </div>
        </div>
        <div className="mt-6 flex justify-center">
          <Skeleton className="h-3 w-56" />
        </div>
      </div>
    </main>
  );
}
