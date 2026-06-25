import { CalendarClock, Layers, PackageSearch, Users } from "lucide-react";
import { ExportCsvButton } from "@/components/forms/ExportCsvButton";
import { PageHeader } from "@/components/layout/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createClient } from "@/lib/supabase/server";
import { formatDate } from "@/lib/utils";

export default async function ReportsPage() {
  const supabase = await createClient();
  const expiryLimit = new Date();
  expiryLimit.setFullYear(expiryLimit.getFullYear() + 1);
  const [activeStock, perOwner, perProduct, expired] = await Promise.all([
    supabase.from("v_active_stock").select("*").order("expired_at", { ascending: true }).limit(50),
    supabase.from("v_active_stock").select("owner_name, qty_available"),
    supabase.from("v_active_stock").select("product_name, qty_available"),
    supabase.from("v_active_stock").select("*").lte("expired_at", expiryLimit.toISOString().slice(0, 10)).limit(50)
  ]);

  const ownerRows = groupQty(perOwner.data ?? [], "owner_name");
  const productRows = groupQty(perProduct.data ?? [], "product_name");

  const totalQty = (perOwner.data ?? []).reduce((sum, row) => sum + Number(row.qty_available ?? 0), 0);
  const expiredCount = (expired.data ?? []).length;

  return (
    <div className="app-page space-y-6">
      <PageHeader kicker="Analitik" title="Laporan" description="Stok aktif, pemilik, produk, kedaluwarsa, dan ekspor CSV." action={<ExportCsvButton />} />

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <SummaryCard title="Total stok tersedia" value={totalQty} icon={Layers} tone="primary" />
        <SummaryCard title="Owner aktif" value={ownerRows.length} icon={Users} tone="success" />
        <SummaryCard title="Produk aktif" value={productRows.length} icon={PackageSearch} tone="muted" />
        <SummaryCard title="Mendekati expired" value={expiredCount} icon={CalendarClock} tone="warning" />
      </div>

      <div className="grid gap-5 xl:grid-cols-2">
        <ReportTable title="Stok Per Owner" icon={Users} rows={ownerRows} />
        <ReportTable title="Stok Per Produk" icon={PackageSearch} rows={productRows} />
      </div>

      <Card>
        <CardHeader className="flex-row items-center gap-2.5 space-y-0">
          <span className="flex h-8 w-8 items-center justify-center rounded-md bg-warning/14 text-warning-foreground ring-1 ring-warning/25">
            <CalendarClock className="h-4 w-4" />
          </span>
          <CardTitle>Box/Produk Mendekati Expired</CardTitle>
        </CardHeader>
        <CardContent>
          {(expired.data ?? []).length ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>ID Box App</TableHead>
                  <TableHead>Owner</TableHead>
                  <TableHead>Produk</TableHead>
                  <TableHead className="text-right">Qty</TableHead>
                  <TableHead>Expired</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(expired.data ?? []).map((row, index) => (
                  <TableRow key={`${row.id_box}-${row.sku}-${index}`}>
                    <TableCell className="font-mono text-xs">{row.id_box}</TableCell>
                    <TableCell>{row.owner_name}</TableCell>
                    <TableCell className="font-medium text-foreground">{row.product_name}</TableCell>
                    <TableCell className="text-right font-mono font-semibold tabular-nums">{row.qty_available}</TableCell>
                    <TableCell className="whitespace-nowrap font-mono text-xs text-muted-foreground">{formatDate(row.expired_at)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <EmptyState title="Tidak ada box mendekati expired" description="Box dan produk yang mendekati tanggal expired dalam 1 tahun akan muncul di sini." />
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center gap-2.5 space-y-0">
          <span className="flex h-8 w-8 items-center justify-center rounded-md bg-primary/10 text-primary ring-1 ring-primary/15">
            <Layers className="h-4 w-4" />
          </span>
          <CardTitle>Stok Aktif Terbaru</CardTitle>
        </CardHeader>
        <CardContent>
          {(activeStock.data ?? []).length ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>ID Box App</TableHead>
                  <TableHead>Owner</TableHead>
                  <TableHead>Produk</TableHead>
                  <TableHead className="text-right">Qty</TableHead>
                  <TableHead>Lokasi</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(activeStock.data ?? []).map((row, index) => (
                  <TableRow key={`${row.id_box}-${row.sku}-${index}`}>
                    <TableCell className="font-mono text-xs">{row.id_box}</TableCell>
                    <TableCell>{row.owner_name}</TableCell>
                    <TableCell className="font-medium text-foreground">{row.product_name}</TableCell>
                    <TableCell className="text-right font-mono font-semibold tabular-nums">{row.qty_available}</TableCell>
                    <TableCell className="font-mono text-xs text-muted-foreground">{row.location_code ?? "-"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <EmptyState title="Belum ada stok aktif" description="Stok aktif terbaru akan muncul di sini setelah barang masuk." />
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function groupQty(rows: Array<Record<string, unknown>>, key: string) {
  const grouped = new Map<string, number>();
  rows.forEach((row) => {
    const name = String(row[key] ?? "-");
    grouped.set(name, (grouped.get(name) ?? 0) + Number(row.qty_available ?? 0));
  });
  return Array.from(grouped.entries()).map(([name, qty]) => ({ name, qty }));
}

function SummaryCard({
  title,
  value,
  icon: Icon,
  tone
}: {
  title: string;
  value: number;
  icon: typeof Layers;
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
          <p className="mt-2 text-3xl font-semibold tabular-nums tracking-tight">{value.toLocaleString("id-ID")}</p>
        </div>
        <div className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-lg ring-1 ${toneClass}`}>
          <Icon className="h-5 w-5" />
        </div>
      </CardContent>
    </Card>
  );
}

function ReportTable({ title, icon: Icon, rows }: { title: string; icon: typeof Layers; rows: Array<{ name: string; qty: number }> }) {
  const total = rows.reduce((sum, row) => sum + row.qty, 0);

  return (
    <Card>
      <CardHeader className="flex-row items-center gap-2.5 space-y-0">
        <span className="flex h-8 w-8 items-center justify-center rounded-md bg-primary/10 text-primary ring-1 ring-primary/15">
          <Icon className="h-4 w-4" />
        </span>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent>
        {rows.length ? (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nama</TableHead>
                <TableHead className="text-right">Qty</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((row) => (
                <TableRow key={row.name}>
                  <TableCell className="font-medium text-foreground">{row.name}</TableCell>
                  <TableCell className="text-right font-mono font-semibold tabular-nums">{row.qty.toLocaleString("id-ID")}</TableCell>
                </TableRow>
              ))}
              <TableRow className="bg-muted/40 hover:bg-muted/40">
                <TableCell className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Total</TableCell>
                <TableCell className="text-right font-mono font-semibold tabular-nums text-primary">{total.toLocaleString("id-ID")}</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        ) : (
          <EmptyState title="Belum ada data" description="Data stok akan muncul di sini setelah barang masuk." />
        )}
      </CardContent>
    </Card>
  );
}
