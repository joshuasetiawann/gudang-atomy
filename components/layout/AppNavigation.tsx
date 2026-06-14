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
      <nav className="fixed inset-x-0 bottom-0 z-30 flex gap-1 overflow-x-auto border-t bg-card/96 px-2 py-2 shadow-[0_-10px_30px_rgb(15_23_42_/_0.08)] backdrop-blur-xl lg:hidden">
        {items.map((item) => {
          const active = isActive(pathname, item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex h-16 min-w-20 flex-col items-center justify-center gap-1 rounded-md px-2 text-xs font-medium text-muted-foreground transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring hover:bg-muted hover:text-foreground active:scale-[0.98]",
                active && "bg-primary/10 text-primary shadow-sm"
              )}
            >
              <item.icon className="h-5 w-5" />
              <span className="max-w-full truncate px-1">{item.shortLabel}</span>
            </Link>
          );
        })}
      </nav>
    );
  }

  return (
    <nav className="space-y-1.5 p-3">
      {items.map((item) => {
        const active = isActive(pathname, item.href);
        return (
          <Link
            key={item.href}
            href={item.href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "group relative flex items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium text-muted-foreground transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring hover:bg-muted hover:text-foreground active:translate-y-px",
              active && "bg-primary text-primary-foreground shadow-sm hover:bg-primary hover:text-primary-foreground"
            )}
          >
            {active ? <span className="absolute left-0 top-1/2 h-6 w-1 -translate-y-1/2 rounded-r bg-primary-foreground/80" /> : null}
            <item.icon className={cn("h-4 w-4 shrink-0", active ? "text-primary-foreground" : "text-muted-foreground group-hover:text-foreground")} />
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
