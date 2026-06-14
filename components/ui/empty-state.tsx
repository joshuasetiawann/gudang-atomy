import { Inbox } from "lucide-react";
import { cn } from "@/lib/utils";

export function EmptyState({ title, description, className }: { title: string; description?: string; className?: string }) {
  return (
    <div className={cn("animate-rise flex min-h-48 flex-col items-center justify-center rounded-lg border border-dashed bg-card/92 px-6 py-10 text-center shadow-soft", className)}>
      <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-xl bg-primary/10 text-primary ring-1 ring-primary/15">
        <Inbox className="h-6 w-6" />
      </div>
      <p className="text-base font-semibold text-card-foreground">{title}</p>
      {description ? <p className="mt-1.5 max-w-sm text-sm leading-relaxed text-muted-foreground">{description}</p> : null}
    </div>
  );
}
