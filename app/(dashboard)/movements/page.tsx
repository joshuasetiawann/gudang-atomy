import { Filter } from "lucide-react";
import { ExportCsvButton } from "@/components/forms/ExportCsvButton";
import { PageHeader } from "@/components/layout/PageHeader";
import { Badge, type BadgeProps } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createClient } from "@/lib/supabase/server";
import { formatDateTime } from "@/lib/utils";

const movementBadgeVariant: Record<string, BadgeProps["variant"]> = {
  in: "active",
  out_full_box: "taken",
  out_partial_item: "partial",
  adjustment: "default",
  void: "void"
};

export default async function MovementsPage({ searchParams }: { searchParams: Promise<{ type?: string; date_from?: string; date_to?: string; product?: string; owner?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  let query = supabase
    .from("stock_movements")
    .select("*, boxes(id_box), owners(owner_name), products(sku, product_name), profiles(full_name)")
    .order("created_at", { ascending: false })
    .limit(200);
  if (params.type) query = query.eq("movement_type", params.type);
  if (params.date_from) query = query.gte("created_at", `${params.date_from}T00:00:00`);
  if (params.date_to) query = query.lte("created_at", `${params.date_to}T23:59:59`);
  const { data } = await query;

  return (
    <div className="app-page space-y-6">
      <PageHeader kicker="Audit Trail" title="Movements" description="Riwayat barang masuk, keluar, adjustment, dan void." action={<ExportCsvButton />} />
      <Card>
        <CardContent className="p-4 sm:p-5">
          <form className="grid items-end gap-4 md:grid-cols-4">
            <div className="space-y-1.5">
              <label htmlFor="date_from" className="text-xs font-medium text-muted-foreground">
                Dari tanggal
              </label>
              <Input id="date_from" name="date_from" type="date" defaultValue={params.date_from ?? ""} className="font-mono" />
            </div>
            <div className="space-y-1.5">
              <label htmlFor="date_to" className="text-xs font-medium text-muted-foreground">
                Sampai tanggal
              </label>
              <Input id="date_to" name="date_to" type="date" defaultValue={params.date_to ?? ""} className="font-mono" />
            </div>
            <div className="space-y-1.5">
              <label htmlFor="type" className="text-xs font-medium text-muted-foreground">
                Tipe movement
              </label>
              <select
                id="type"
                name="type"
                defaultValue={params.type ?? ""}
                className="h-10 w-full rounded-md border bg-card px-3 font-mono text-sm shadow-soft outline-none transition-colors duration-200 focus-visible:ring-2 focus-visible:ring-ring"
              >
                <option value="">Semua tipe</option>
                <option value="in">in</option>
                <option value="out_full_box">out_full_box</option>
                <option value="out_partial_item">out_partial_item</option>
                <option value="adjustment">adjustment</option>
                <option value="void">void</option>
              </select>
            </div>
            <ButtonSubmit />
          </form>
        </CardContent>
      </Card>
      {(data ?? []).length ? (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Waktu</TableHead>
              <TableHead>Tipe</TableHead>
              <TableHead>Box</TableHead>
              <TableHead>Owner</TableHead>
              <TableHead>Produk</TableHead>
              <TableHead className="text-right">Qty</TableHead>
              <TableHead>Aktor</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(data ?? []).map((movement) => (
              <TableRow key={movement.id}>
                <TableCell className="whitespace-nowrap font-mono text-[13px] text-muted-foreground">{formatDateTime(movement.created_at)}</TableCell>
                <TableCell>
                  <Badge variant={movementBadgeVariant[movement.movement_type] ?? "default"} className="font-mono">
                    {movement.movement_type}
                  </Badge>
                </TableCell>
                <TableCell className="font-mono text-[13px] text-muted-foreground">{movement.boxes?.id_box ?? "-"}</TableCell>
                <TableCell className="text-foreground">{movement.owners?.owner_name ?? "-"}</TableCell>
                <TableCell className="font-medium text-foreground">{movement.products?.product_name ?? "-"}</TableCell>
                <TableCell className="text-right tabular-nums">{movement.qty}</TableCell>
                <TableCell className="text-muted-foreground">{movement.profiles?.full_name ?? "-"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : (
        <Card>
          <CardContent className="p-4">
            <EmptyState title="Belum ada movement" description="Riwayat akan terisi setelah barang masuk atau keluar." />
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function ButtonSubmit() {
  return (
    <Button className="w-full md:w-auto">
      <Filter className="h-4 w-4" />
      Filter
    </Button>
  );
}
