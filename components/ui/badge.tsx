import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva("inline-flex items-center gap-1 whitespace-nowrap rounded-md px-2.5 py-1 text-xs font-semibold tracking-wide ring-1", {
  variants: {
    variant: {
      default: "bg-secondary text-secondary-foreground ring-border",
      active: "bg-success/12 text-success ring-success/30",
      partial: "bg-warning/15 text-warning-foreground ring-warning/30",
      empty: "bg-muted text-muted-foreground ring-border",
      taken: "bg-primary/10 text-primary ring-primary/25",
      void: "bg-destructive/10 text-destructive ring-destructive/25"
    }
  },
  defaultVariants: {
    variant: "default"
  }
});

export interface BadgeProps extends React.HTMLAttributes<HTMLDivElement>, VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, ...props }: BadgeProps) {
  return <div className={cn(badgeVariants({ variant }), className)} {...props} />;
}
