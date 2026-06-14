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
  return <ToastPrimitive.Root className={cn("rounded-lg border bg-card p-4 text-sm shadow-lift animate-rise", className)} {...props} />;
}

export function ToastTitle({ className, ...props }: ToastPrimitive.ToastTitleProps) {
  return <ToastPrimitive.Title className={cn("font-semibold tracking-tight", className)} {...props} />;
}

export function ToastDescription({ className, ...props }: ToastPrimitive.ToastDescriptionProps) {
  return <ToastPrimitive.Description className={cn("mt-1 text-sm leading-relaxed text-muted-foreground", className)} {...props} />;
}
