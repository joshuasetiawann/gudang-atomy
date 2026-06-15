import Link from "next/link";
import type { ReactNode } from "react";
import { LogOut, PackageCheck } from "lucide-react";
import { signOutAction } from "@/app/(dashboard)/actions";
import { AppNavigation } from "@/components/layout/AppNavigation";
import { Button } from "@/components/ui/button";
import { roleLabel } from "@/lib/utils";
import type { Profile } from "@/lib/types";

export function AppShell({ children, profile }: { children: ReactNode; profile: Profile }) {
  return (
    <div className="min-h-screen">
      <a href="#main-content" className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-50 focus:rounded-md focus:bg-primary focus:px-4 focus:py-2 focus:text-sm focus:font-semibold focus:text-primary-foreground">
        Lewati ke konten
      </a>
      <aside className="no-print fixed inset-y-0 left-0 z-30 hidden w-72 border-r bg-card/94 shadow-[12px_0_36px_rgb(15_23_42_/_0.06)] backdrop-blur-xl lg:flex lg:flex-col">
        <div className="flex h-20 items-center gap-3 border-b px-5">
          <Link
            href="/dashboard"
            aria-label="Gudang Atomy — dashboard"
            className="interactive-lift relative flex h-11 w-11 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-[linear-gradient(150deg,hsl(var(--primary)),hsl(var(--primary)/0.82))] text-primary-foreground shadow-lift ring-1 ring-inset ring-primary-foreground/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-card"
          >
            <span className="pointer-events-none absolute inset-x-0 top-0 h-1/2 bg-primary-foreground/10" />
            <PackageCheck className="relative h-5 w-5" />
          </Link>
          <div className="min-w-0">
            <p className="truncate text-base font-semibold tracking-tight">Gudang Atomy</p>
            <p className="truncate text-xs font-medium text-muted-foreground">{roleLabel(profile.role)}</p>
          </div>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto">
          <AppNavigation role={profile.role} variant="sidebar" />
        </div>
        <form action={signOutAction} className="border-t bg-card/60 p-3">
          <Button className="w-full" variant="outline">
            <LogOut className="h-4 w-4" />
            Keluar
          </Button>
        </form>
      </aside>

      <div className="dashboard-shell-content lg:pl-72">
        <header className="no-print sticky top-0 z-20 flex h-16 items-center justify-between gap-3 border-b border-border/70 bg-background/80 px-4 shadow-[0_8px_28px_-12px_hsl(var(--primary)/0.18)] backdrop-blur-xl supports-[backdrop-filter]:bg-background/70 lg:px-8">
          <div className="flex min-w-0 items-center gap-3">
            <Link
              href="/dashboard"
              aria-label="Gudang Atomy — dashboard"
              className="interactive-lift relative flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-[linear-gradient(150deg,hsl(var(--primary)),hsl(var(--primary)/0.82))] text-primary-foreground shadow-lift ring-1 ring-inset ring-primary-foreground/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background lg:hidden"
            >
              <span className="pointer-events-none absolute inset-x-0 top-0 h-1/2 bg-primary-foreground/10" />
              <PackageCheck className="relative h-5 w-5" />
            </Link>
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold tracking-tight">{profile.full_name}</p>
              <p className="truncate text-xs text-muted-foreground">
                <span className="font-mono">{profile.email}</span> <span className="text-border">|</span> {roleLabel(profile.role)}
              </p>
            </div>
          </div>
          <form action={signOutAction} className="lg:hidden">
            <Button size="icon" variant="ghost" aria-label="Keluar">
              <LogOut className="h-4 w-4" />
            </Button>
          </form>
        </header>
        <main id="main-content" className="app-page mx-auto min-h-[calc(100vh-4rem)] w-full max-w-7xl px-3 py-4 pb-32 sm:px-4 sm:py-5 lg:px-8 lg:py-7">{children}</main>
      </div>

      <div className="no-print">
        <AppNavigation role={profile.role} variant="mobile" />
      </div>
    </div>
  );
}
