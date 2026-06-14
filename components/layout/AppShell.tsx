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
      <aside className="no-print fixed inset-y-0 left-0 z-30 hidden w-72 border-r bg-card/94 shadow-[12px_0_36px_rgb(15_23_42_/_0.06)] backdrop-blur-xl lg:block">
        <div className="flex h-20 items-center gap-3 border-b px-5">
          <Link href="/dashboard" className="interactive-lift flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-primary text-primary-foreground shadow-sm">
            <PackageCheck className="h-5 w-5" />
          </Link>
          <div className="min-w-0">
            <p className="truncate text-base font-semibold">Gudang Atomy</p>
            <p className="truncate text-xs font-medium text-muted-foreground">{roleLabel(profile.role)}</p>
          </div>
        </div>
        <AppNavigation role={profile.role} variant="sidebar" />
        <form action={signOutAction} className="absolute bottom-4 left-3 right-3">
          <Button className="w-full" variant="outline">
            <LogOut className="h-4 w-4" />
            Keluar
          </Button>
        </form>
      </aside>

      <div className="dashboard-shell-content lg:pl-72">
        <header className="no-print sticky top-0 z-20 flex h-16 items-center justify-between border-b bg-background/88 px-4 shadow-[0_8px_28px_rgb(15_23_42_/_0.04)] backdrop-blur-xl lg:px-8">
          <div className="flex min-w-0 items-center gap-3">
            <Link href="/dashboard" className="interactive-lift flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary text-primary-foreground shadow-sm lg:hidden">
              <PackageCheck className="h-5 w-5" />
            </Link>
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold">{profile.full_name}</p>
              <p className="truncate text-xs text-muted-foreground">{profile.email} | {roleLabel(profile.role)}</p>
            </div>
          </div>
          <form action={signOutAction} className="lg:hidden">
            <Button size="icon" variant="ghost" aria-label="Keluar">
              <LogOut className="h-4 w-4" />
            </Button>
          </form>
        </header>
        <main id="main-content" className="app-page mx-auto min-h-[calc(100vh-4rem)] w-full max-w-7xl px-4 py-5 pb-28 lg:px-8 lg:py-7">{children}</main>
      </div>

      <div className="no-print">
        <AppNavigation role={profile.role} variant="mobile" />
      </div>
    </div>
  );
}
