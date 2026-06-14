import type { ComponentType } from "react";
import { Activity, Archive, Boxes, CalendarClock, PackageCheck, PackageOpen, TrendingUp } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createClient } from "@/lib/supabase/server";
import { formatDateTime } from "@/lib/utils";

export default async function DashboardPage() {
  const supabase = await createClient();
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const in30Days = new Date();
  in30Days.setDate(in30Days.getDate() + 30);

  const [totalBoxes, active, empty, partial, taken, stock, expired, todayMovements, latest] = await Promise.all([
    supabase.from("boxes").select("id", { count: "exact", head: true }),
    supabase.from("boxes").select("id", { count: "exact", head: true }).eq("status", "active"),
    supabase.from("boxes").select("id", { count: "exact", head: true }).eq("status", "empty"),
    supabase.from("boxes").select("id", { count: "exact", head: true }).eq("status", "partial"),
    supabase.from("boxes").select("id", { count: "exact", head: true }).eq("status", "taken"),
    supabase.from("v_active_stock").select("qty_available"),
    supabase.from("boxes").select("id", { count: "exact", head: true }).in("status", ["active", "partial"]).lte("expired_at", in30Days.toISOString().slice(0, 10)),
    supabase.from("stock_movements").select("id", { count: "exact", head: true }).gte("created_at", today.toISOString()),
    supabase
      .from("stock_movements")
      .select("movement_type, qty, created_at, boxes(id_box, box_name), products(sku, product_name)")
      .order("created_at", { ascending: false })
      .limit(8)
  ]);

  const totalStock = (stock.data ?? []).reduce((sum, row) => sum + Number(row.qty_available ?? 0), 0);
  const latestRows = (latest.data ?? []) as unknown as LatestMovement[];

  return (
    <div className="app-page space-y-6">
      <div className="animate-rise surface-panel relative flex flex-col gap-4 overflow-hidden rounded-xl border p-5 shadow-card sm:flex-row sm:items-center sm:justify-between sm:p-6">
        <div aria-hidden="true" className="absolute inset-x-0 top-0 h-1 bg-[linear-gradient(90deg,hsl(var(--primary)/0.55),hsl(var(--accent)/0.45))]" />
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-primary">Gudang Atomy</p>
          <h1 className="mt-1.5 text-2xl font-semibold tracking-normal sm:text-3xl">Dashboard</h1>
          <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">Ringkasan stok, box, dan aktivitas terbaru.</p>
        </div>
        <div className="flex items-center gap-2.5 rounded-md border bg-background/80 px-3.5 py-2.5 text-sm font-medium text-foreground shadow-soft">
          <span className="flex h-7 w-7 items-center justify-center rounded-sm bg-primary/10 text-primary ring-1 ring-primary/15">
            <TrendingUp className="h-4 w-4" />
          </span>
          <span>
            <span className="font-mono tabular-nums">{todayMovements.count ?? 0}</span>
            <span className="text-muted-foreground"> transaksi hari ini</span>
          </span>
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <Metric title="Total box terdata" value={totalBoxes.count ?? 0} icon={Boxes} tone="primary" />
        <Metric title="Total box aktif" value={active.count ?? 0} icon={PackageCheck} tone="success" />
        <Metric title="Total box kosong" value={empty.count ?? 0} icon={Archive} tone="muted" />
        <Metric title="Total box partial" value={partial.count ?? 0} icon={PackageOpen} tone="warning" />
        <Metric title="Total box taken" value={taken.count ?? 0} icon={Boxes} tone="muted" />
        <Metric title="Total stok tersedia" value={totalStock} icon={Archive} tone="success" />
        <Metric title="Expired 30 hari" value={expired.count ?? 0} icon={CalendarClock} tone="warning" />
        <Metric title="Transaksi hari ini" value={todayMovements.count ?? 0} icon={Activity} tone="primary" />
      </div>

      <Card>
        <CardHeader className="flex-row items-center gap-2.5 space-y-0">
          <span className="flex h-8 w-8 items-center justify-center rounded-md bg-primary/10 text-primary ring-1 ring-primary/15">
            <Activity className="h-4 w-4" />
          </span>
          <CardTitle>Aktivitas Terbaru</CardTitle>
        </CardHeader>
        <CardContent>
          {latestRows.length ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Waktu</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead>Box</TableHead>
                  <TableHead>Produk</TableHead>
                  <TableHead className="text-right">Qty</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {latestRows.map((movement, index) => (
                  <TableRow key={`${movement.created_at}-${index}`}>
                    <TableCell className="whitespace-nowrap font-mono text-xs text-muted-foreground">{formatDateTime(movement.created_at)}</TableCell>
                    <TableCell>
                      <span className="inline-flex items-center rounded-sm bg-secondary px-2 py-0.5 text-xs font-medium text-secondary-foreground">{movement.movement_type}</span>
                    </TableCell>
                    <TableCell className="font-mono text-xs">{movement.boxes?.id_box ?? "-"}</TableCell>
                    <TableCell className="font-medium text-foreground">{movement.products?.product_name ?? "-"}</TableCell>
                    <TableCell className="text-right font-mono font-semibold tabular-nums">{movement.qty}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <EmptyState title="Belum ada aktivitas" description="Aktivitas barang masuk dan keluar akan muncul di sini." />
          )}
        </CardContent>
      </Card>
    </div>
  );
}

type LatestMovement = {
  movement_type: string;
  qty: number;
  created_at: string;
  boxes: { id_box: string; box_name: string } | null;
  products: { sku: string | null; product_name: string } | null;
};

function Metric({
  title,
  value,
  icon: Icon,
  tone
}: {
  title: string;
  value: number;
  icon: ComponentType<{ className?: string }>;
  tone: "primary" | "success" | "warning" | "muted";
}) {
  const toneClass = {
    primary: "bg-primary/10 text-primary ring-primary/15",
    success: "bg-success/10 text-success ring-success/15",
    warning: "bg-warning/14 text-warning-foreground ring-warning/25",
    muted: "bg-secondary text-muted-foreground ring-border"
  }[tone];

  return (
    <Card className="overflow-hidden">
      <CardContent className="flex items-center justify-between gap-4 p-5">
        <div className="min-w-0">
          <p className="truncate text-sm font-medium text-muted-foreground">{title}</p>
          <p className="mt-2 text-3xl font-semibold tabular-nums tracking-tight sm:text-[2rem]">{value.toLocaleString("id-ID")}</p>
        </div>
        <div className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-lg ring-1 ${toneClass}`}>
          <Icon className="h-5 w-5" />
        </div>
      </CardContent>
    </Card>
  );
}
