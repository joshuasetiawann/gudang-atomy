import type { ReactNode } from "react";

export function PageHeader({
  kicker,
  title,
  description,
  action
}: {
  kicker?: string;
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="animate-rise surface-panel relative overflow-hidden rounded-lg border shadow-card p-5 sm:p-6">
      <div className="absolute inset-x-0 top-0 h-1 bg-[linear-gradient(90deg,hsl(var(--primary)),hsl(var(--accent)))]" />
      <div className="pointer-events-none absolute -right-16 -top-20 h-48 w-48 rounded-full bg-primary/10 blur-3xl" aria-hidden="true" />
      <div className="relative flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div className="min-w-0">
          {kicker ? (
            <p className="flex items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.14em] text-primary">
              <span className="h-1 w-1 rounded-full bg-primary" aria-hidden="true" />
              {kicker}
            </p>
          ) : null}
          <h1 className="mt-1.5 break-words text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">{title}</h1>
          {description ? <p className="mt-1.5 max-w-2xl text-sm leading-relaxed text-muted-foreground">{description}</p> : null}
        </div>
        {action ? <div className="w-full sm:w-auto sm:shrink-0">{action}</div> : null}
      </div>
    </div>
  );
}
