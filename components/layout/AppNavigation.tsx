"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Archive,
  BarChart3,
  Boxes,
  ClipboardList,
  Download,
  History,
  Home,
  Package,
  PackagePlus,
  Printer,
  ScanLine,
  ShieldCheck,
  Users
} from "lucide-react";
import { cn } from "@/lib/utils";
import type { UserRole } from "@/lib/types";

const navigation = [
  { href: "/dashboard", label: "Dashboard", shortLabel: "Home", icon: Home },
  { href: "/barang-masuk", label: "Barang Masuk", shortLabel: "Masuk", icon: PackagePlus },
  { href: "/ambil-barang", label: "Ambil Barang", shortLabel: "Ambil", icon: ScanLine },
  { href: "/boxes", label: "Data Box", shortLabel: "Box", icon: Boxes },
  { href: "/print-resi", label: "Print Resi", shortLabel: "Print", icon: Printer },
  { href: "/owners", label: "Owners", shortLabel: "Owner", icon: Users },
  { href: "/products", label: "Products", shortLabel: "Produk", icon: Package },
  { href: "/packages", label: "Packages", shortLabel: "Paket", icon: Archive },
  { href: "/movements", label: "Movements", shortLabel: "Mutasi", icon: ClipboardList },
  { href: "/reports", label: "Reports", shortLabel: "Report", icon: BarChart3 },
  { href: "/imports", label: "Imports", shortLabel: "Import", icon: Download },
  { href: "/activity-logs", label: "Activity Log", shortLabel: "Log", icon: History, superOnly: true },
  { href: "/admin-users", label: "Admin", shortLabel: "Admin", icon: ShieldCheck, superOnly: true }
];

export function AppNavigation({ role, variant }: { role: UserRole; variant: "sidebar" | "mobile" }) {
  const pathname = usePathname();
  const items = navigation.filter((item) => !item.superOnly || role === "super_admin");

  if (variant === "mobile") {
    return (
      <nav className="fixed inset-x-0 bottom-0 z-50 flex gap-1 overflow-x-auto overscroll-x-contain border-t border-border/70 bg-card/90 px-2 pb-[max(0.5rem,env(safe-area-inset-bottom))] pt-2 shadow-[0_-10px_30px_-12px_hsl(var(--primary)/0.22)] backdrop-blur-xl supports-[backdrop-filter]:bg-card/80 lg:hidden">
        {items.map((item) => {
          const active = isActive(pathname, item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "relative flex h-14 min-w-16 flex-col items-center justify-center gap-1 rounded-md px-2 text-[11px] font-medium text-muted-foreground transition-all duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring hover:bg-muted hover:text-foreground active:scale-[0.98] sm:h-16 sm:min-w-20 sm:gap-1.5 sm:text-xs",
                active && "bg-primary/10 text-primary"
              )}
            >
              {active ? <span className="absolute inset-x-4 top-0 h-0.5 rounded-full bg-primary" /> : null}
              <item.icon className={cn("h-5 w-5 shrink-0 transition-transform duration-200", active && "scale-105")} />
              <span className="max-w-full truncate px-1">{item.shortLabel}</span>
            </Link>
          );
        })}
      </nav>
    );
  }

  return (
    <nav className="space-y-1 p-3">
      {items.map((item) => {
        const active = isActive(pathname, item.href);
        return (
          <Link
            key={item.href}
            href={item.href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "group relative flex items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium text-muted-foreground transition-all duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring hover:bg-muted hover:text-foreground active:translate-y-px",
              active &&
                "bg-[linear-gradient(120deg,hsl(var(--primary)),hsl(var(--primary)/0.88))] text-primary-foreground shadow-card hover:text-primary-foreground"
            )}
          >
            {active ? (
              <span className="absolute left-0 top-1/2 h-6 w-1 -translate-y-1/2 rounded-r-full bg-primary-foreground/85" />
            ) : (
              <span className="absolute left-0 top-1/2 h-5 w-1 -translate-y-1/2 scale-y-0 rounded-r-full bg-primary/40 transition-transform duration-200 group-hover:scale-y-100" />
            )}
            <item.icon
              className={cn(
                "h-4 w-4 shrink-0 transition-colors duration-200",
                active ? "text-primary-foreground" : "text-muted-foreground group-hover:text-foreground"
              )}
            />
            <span className="truncate">{item.label}</span>
          </Link>
        );
      })}
    </nav>
  );
}

function isActive(pathname: string, href: string) {
  return pathname === href || pathname.startsWith(`${href}/`);
}
