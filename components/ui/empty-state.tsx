import { Inbox } from "lucide-react";
import { cn } from "@/lib/utils";

export function EmptyState({ title, description, className }: { title: string; description?: string; className?: string }) {
  return (
    <div className={cn("animate-rise flex min-h-40 flex-col items-center justify-center rounded-lg border bg-card/92 p-6 text-center shadow-soft", className)}>
      <div className="mb-3 rounded-md bg-primary/10 p-3 text-primary">
        <Inbox className="h-5 w-5" />
      </div>
      <p className="font-medium">{title}</p>
      {description ? <p className="mt-1 max-w-sm text-sm text-muted-foreground">{description}</p> : null}
    </div>
  );
}
