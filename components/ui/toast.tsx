"use client";

import * as ToastPrimitive from "@radix-ui/react-toast";
import { cn } from "@/lib/utils";

export const ToastProvider = ToastPrimitive.Provider;
export const ToastViewport = (props: ToastPrimitive.ToastViewportProps) => (
  <ToastPrimitive.Viewport
    className="fixed bottom-4 right-4 z-50 flex w-[calc(100%-2rem)] max-w-sm flex-col gap-2"
    {...props}
  />
);

export function Toast({ className, ...props }: ToastPrimitive.ToastProps) {
  return <ToastPrimitive.Root className={cn("rounded-md border bg-card p-4 text-sm shadow-soft", className)} {...props} />;
}

export function ToastTitle({ className, ...props }: ToastPrimitive.ToastTitleProps) {
  return <ToastPrimitive.Title className={cn("font-medium", className)} {...props} />;
}

export function ToastDescription({ className, ...props }: ToastPrimitive.ToastDescriptionProps) {
  return <ToastPrimitive.Description className={cn("mt-1 text-muted-foreground", className)} {...props} />;
}
