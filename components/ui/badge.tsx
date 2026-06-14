import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva("inline-flex items-center whitespace-nowrap rounded-sm px-2 py-1 text-xs font-medium", {
  variants: {
    variant: {
      default: "bg-secondary text-secondary-foreground",
      active: "bg-success/12 text-success ring-1 ring-success/25",
      partial: "bg-warning/14 text-warning-foreground ring-1 ring-warning/30",
      empty: "bg-muted text-muted-foreground ring-1 ring-border",
      taken: "bg-sky-100 text-sky-700 ring-1 ring-sky-200",
      void: "bg-destructive/10 text-destructive ring-1 ring-destructive/20"
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
