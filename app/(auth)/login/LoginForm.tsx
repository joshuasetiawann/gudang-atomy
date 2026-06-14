"use client";

import { useActionState } from "react";
import { AlertCircle, LogIn, PackageCheck } from "lucide-react";
import { loginAction, type LoginState } from "./actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const initialState: LoginState = {};

export function LoginForm({ next }: { next: string }) {
  const [state, formAction, pending] = useActionState(loginAction, initialState);

  return (
    <Card className="animate-rise w-full rounded-xl border-border/70 shadow-lift">
      <CardContent className="p-7 sm:p-8">
        <div className="mb-7 flex flex-col items-center text-center">
          <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-xl bg-primary text-primary-foreground shadow-soft shadow-primary/30 ring-1 ring-primary/20">
            <PackageCheck className="h-7 w-7" />
          </div>
          <h1 className="mt-4 text-2xl font-semibold tracking-normal">Gudang Atomy</h1>
          <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">Masuk untuk mengelola stok, box, dan paket gudang.</p>
        </div>
        <form action={formAction} className="space-y-4">
          <input type="hidden" name="next" value={next} />
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input id="email" name="email" type="email" autoComplete="email" placeholder="nama@perusahaan.com" required />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">Password</Label>
            <Input id="password" name="password" type="password" autoComplete="current-password" placeholder="••••••••" required />
          </div>
          {state.error ? (
            <p role="alert" aria-live="polite" className="flex items-start gap-2 rounded-md border border-destructive/20 bg-destructive/10 p-3 text-sm font-medium text-destructive">
              <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{state.error}</span>
            </p>
          ) : null}
          <Button size="lg" className="mt-1 w-full" disabled={pending}>
            <LogIn className="h-4 w-4" />
            {pending ? "Masuk..." : "Masuk"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
