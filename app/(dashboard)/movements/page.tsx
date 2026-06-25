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
import { formatDateTime, jakartaDateToUtcRange } from "@/lib/utils";

const movementBadgeVariant: Record<string, BadgeProps["variant"]> = {
  in: "active",
  out_full_box: "taken",
  out_partial_item: "partial",
  adjustment: "default",
  void: "void"
};

type MovementGroup = {
  key: string;
  created_at: string;
  movement_type: string;
  id_box: string | null;
  owner_name: string | null;
  actor_name: string | null;
  totalQty: number;
  items: { key: string; product_name: string; qty: number }[];
};

// Gabungkan movement yang berasal dari box yang sama dan terjadi dalam satu aksi
// (box, tipe, dan waktu yang sama) menjadi satu baris — misal "Ambil Semua Box"
// yang menghasilkan satu movement per produk. Movement tanpa box tetap sendiri-sendiri.
function groupMovements(rows: any[]): MovementGroup[] {
  const map = new Map<string, MovementGroup>();
  for (const row of rows) {
    const key = row.box_id
      ? `${row.box_id}|${row.movement_type}|${row.created_at}`
      : `single|${row.id}`;
    let group = map.get(key);
    if (!group) {
      group = {
        key,
        created_at: row.created_at,
        movement_type: row.movement_type,
        id_box: row.boxes?.id_box ?? null,
        owner_name: row.owners?.owner_name ?? null,
        actor_name: row.profiles?.full_name ?? null,
        totalQty: 0,
        items: []
      };
      map.set(key, group);
    }
    const qty = Number(row.qty) || 0;
    group.totalQty += qty;
    group.items.push({
      key: row.id,
      product_name: row.products?.product_name ?? "-",
      qty
    });
  }
  return [...map.values()];
}

export default async function MovementsPage({ searchParams }: { searchParams: Promise<{ type?: string; date_from?: string; date_to?: string; product?: string; owner?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  let query = supabase
    .from("stock_movements")
    .select("*, boxes(id_box), owners(owner_name), products(sku, product_name), profiles(full_name)")
    .order("created_at", { ascending: false })
    .limit(200);
  if (params.type) query = query.eq("movement_type", params.type);
  const fromRange = params.date_from ? jakartaDateToUtcRange(params.date_from) : null;
  const toRange = params.date_to ? jakartaDateToUtcRange(params.date_to) : null;
  if (fromRange) query = query.gte("created_at", fromRange.startIso);
  if (toRange) query = query.lte("created_at", toRange.endIso);
  const { data } = await query;

  const groups = groupMovements(data ?? []);

  return (
    <div className="app-page space-y-6">
      <PageHeader kicker="Jejak Audit" title="Pergerakan Stok" description="Riwayat barang masuk, keluar, penyesuaian, dan pembatalan." action={<ExportCsvButton />} />
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
      {groups.length ? (
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
            {groups.map((group) => (
              <TableRow key={group.key}>
                <TableCell className="whitespace-nowrap font-mono text-[13px] text-muted-foreground">{formatDateTime(group.created_at)}</TableCell>
                <TableCell>
                  <Badge variant={movementBadgeVariant[group.movement_type] ?? "default"} className="font-mono">
                    {group.movement_type}
                  </Badge>
                </TableCell>
                <TableCell className="font-mono text-[13px] text-muted-foreground">{group.id_box ?? "-"}</TableCell>
                <TableCell className="text-foreground">{group.owner_name ?? "-"}</TableCell>
                <TableCell className="text-foreground">
                  {group.items.length > 1 ? (
                    <div className="space-y-1">
                      <span className="text-xs font-medium text-muted-foreground">{group.items.length} produk</span>
                      <ul className="space-y-0.5">
                        {group.items.map((item) => (
                          <li key={item.key} className="flex items-baseline justify-between gap-3">
                            <span className="font-medium">{item.product_name}</span>
                            <span className="shrink-0 font-mono text-xs text-muted-foreground tabular-nums">×{item.qty}</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  ) : (
                    <span className="font-medium">{group.items[0]?.product_name ?? "-"}</span>
                  )}
                </TableCell>
                <TableCell className="text-right tabular-nums">{group.totalQty}</TableCell>
                <TableCell className="text-muted-foreground">{group.actor_name ?? "-"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : (
        <Card>
          <CardContent className="p-4">
            <EmptyState title="Belum ada pergerakan" description="Riwayat akan terisi setelah barang masuk atau keluar." />
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
