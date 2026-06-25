import { BoxEditor } from "@/components/forms/BoxEditor";
import { BoxLabel } from "@/components/labels/BoxLabel";
import { PageHeader } from "@/components/layout/PageHeader";
import { StatusBadge } from "@/components/tables/StatusBadge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { getCurrentProfile } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";
import { cn, formatDate, formatDateTime } from "@/lib/utils";
import { isUuidValue } from "@/lib/validation/uuid";
import type { BoxStatus, Product } from "@/lib/types";

export default async function BoxDetailPage({ params }: { params: Promise<{ id: string }> | { id: string } }) {
  const { id } = await params;
  if (!isUuidValue(id)) return <p className="text-sm text-muted-foreground">Box tidak ditemukan.</p>;

  const profile = await getCurrentProfile();
  const supabase = await createClient();
  const [boxResult, movementResult, productsResult] = await Promise.all([
    supabase.from("boxes").select("*, owners(owner_code, owner_name), box_items(*, products(sku, product_name, unit))").eq("id", id).single(),
    supabase
      .from("stock_movements")
      .select("movement_type, qty, before_qty, after_qty, created_at, reason, notes, products(sku, product_name)")
      .eq("box_id", id)
      .order("created_at", { ascending: false }),
    supabase.from("products").select("*").eq("is_active", true).order("product_name")
  ]);
  const box = boxResult.data as unknown as BoxDetail | null;
  const movements = (movementResult.data ?? []) as unknown as BoxMovement[];
  const products = (productsResult.data ?? []) as Product[];
  const canEdit = profile.role === "super_admin" || profile.role === "admin_gudang";
  const canDelete = profile.role === "super_admin";

  if (!box) {
    return <EmptyState title="Box tidak ditemukan" description="ID box tidak valid atau sudah dihapus." />;
  }

  return (
    <div className="app-page space-y-6">
      <PageHeader
        kicker="Detail Box"
        title={box.box_name}
        description={`ID Box App: ${box.id_box}`}
        action={<StatusBadge status={box.status as BoxStatus} />}
      />

      <div className="grid gap-5 xl:grid-cols-[420px_1fr]">
        <BoxLabel box={box} />
        <Card>
          <CardHeader>
            <CardTitle>Detail box</CardTitle>
          </CardHeader>
          <CardContent className="grid gap-3 text-sm md:grid-cols-2">
            <Info label="Pemilik" value={`${box.owners?.owner_code ?? "-"} - ${box.owners?.owner_name ?? "-"}`} />
            <Info label="Pemilik ID box" value={box.pemilik_id_box} mono />
            <Info label="Barcode" value={box.barcode_value} mono />
            <Info label="Source" value={box.source_type} />
            <Info label="Expired" value={formatDate(box.expired_at)} mono />
            <Info label="Lokasi" value={box.location_code ?? "-"} mono />
            <Info label="Created by" value={box.created_by ?? "-"} />
            <Info label="Created at" value={formatDateTime(box.created_at)} mono />
            <Info label="Checked out by" value={box.checked_out_by ?? "-"} />
            <Info label="Checked out at" value={formatDateTime(box.checked_out_at)} mono />
          </CardContent>
        </Card>
      </div>

      {canEdit ? (
        <BoxEditor
          key={`${box.box_name}|${box.location_code ?? ""}|${box.expired_at ?? ""}|${box.notes ?? ""}|${box.box_items
            .map((item) => `${item.id}:${item.qty_available}:${item.expired_at ?? ""}:${item.batch_no ?? ""}`)
            .join(",")}`}
          box={{
            id: box.id,
            box_name: box.box_name,
            expired_at: box.expired_at,
            location_code: box.location_code,
            notes: box.notes,
            status: box.status
          }}
          items={box.box_items.map((item) => ({
            id: item.id,
            product_id: item.product_id,
            qty_available: item.qty_available,
            expired_at: item.expired_at,
            batch_no: item.batch_no
          }))}
          products={products}
          canDelete={canDelete}
        />
      ) : (
        <Card>
          <CardHeader>
            <CardTitle>Isi produk</CardTitle>
          </CardHeader>
          <CardContent>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>SKU</TableHead>
                  <TableHead>Produk</TableHead>
                  <TableHead className="text-right">Qty awal</TableHead>
                  <TableHead className="text-right">Qty sisa</TableHead>
                  <TableHead>Expired</TableHead>
                  <TableHead>Batch</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {box.box_items.length ? (
                  box.box_items.map((item) => (
                    <TableRow key={item.id}>
                      <TableCell className="font-mono text-foreground">{item.products?.sku ?? "-"}</TableCell>
                      <TableCell className="font-medium">{item.products?.product_name ?? item.product_id}</TableCell>
                      <TableCell className="text-right tabular-nums text-muted-foreground">{item.qty_initial}</TableCell>
                      <TableCell className="text-right font-semibold tabular-nums text-foreground">{item.qty_available}</TableCell>
                      <TableCell className="font-mono tabular-nums text-muted-foreground">{formatDate(item.expired_at)}</TableCell>
                      <TableCell className="font-mono">{item.batch_no ?? <span className="text-muted-foreground">-</span>}</TableCell>
                    </TableRow>
                  ))
                ) : (
                  <TableRow>
                    <TableCell colSpan={6} className="py-8 text-center text-sm text-muted-foreground">
                      Belum ada produk di dalam box ini.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Riwayat movement</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Waktu</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Produk</TableHead>
                <TableHead className="text-right">Qty</TableHead>
                <TableHead className="text-right">Before</TableHead>
                <TableHead className="text-right">After</TableHead>
                <TableHead>Catatan</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {movements.length ? (
                movements.map((movement, index) => (
                  <TableRow key={`${movement.created_at}-${index}`}>
                    <TableCell className="whitespace-nowrap font-mono tabular-nums text-muted-foreground">{formatDateTime(movement.created_at)}</TableCell>
                    <TableCell>
                      <span className="inline-flex items-center rounded-sm bg-primary/10 px-2 py-0.5 font-mono text-xs font-medium text-primary ring-1 ring-primary/15">
                        {movement.movement_type}
                      </span>
                    </TableCell>
                    <TableCell className="font-medium">{movement.products?.product_name ?? <span className="font-normal text-muted-foreground">-</span>}</TableCell>
                    <TableCell className="text-right font-semibold tabular-nums text-foreground">{movement.qty}</TableCell>
                    <TableCell className="text-right tabular-nums text-muted-foreground">{movement.before_qty ?? "-"}</TableCell>
                    <TableCell className="text-right tabular-nums text-muted-foreground">{movement.after_qty ?? "-"}</TableCell>
                    <TableCell className="text-muted-foreground">{movement.reason ?? movement.notes ?? "-"}</TableCell>
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={7} className="py-8 text-center text-sm text-muted-foreground">
                    Belum ada riwayat movement untuk box ini.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}

type BoxDetail = {
  id: string;
  id_box: string;
  pemilik_id_box: string;
  barcode_value: string;
  box_name: string;
  source_type: string;
  expired_at: string | null;
  location_code: string | null;
  status: BoxStatus;
  notes: string | null;
  created_by: string | null;
  checked_out_by: string | null;
  created_at: string;
  checked_out_at: string | null;
  owners: { owner_code: string; owner_name: string } | null;
  box_items: Array<{
    id: string;
    product_id: string;
    qty_initial: number;
    qty_available: number;
    expired_at: string | null;
    batch_no: string | null;
    products: { sku: string | null; product_name: string; unit: string | null } | null;
  }>;
};

type BoxMovement = {
  movement_type: string;
  qty: number;
  before_qty: number | null;
  after_qty: number | null;
  created_at: string;
  reason: string | null;
  notes: string | null;
  products: { sku: string | null; product_name: string } | null;
};

function Info({ label, value, mono = false }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="rounded-md border bg-background/65 p-3 shadow-soft transition-colors duration-200 hover:border-primary/30">
      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className={cn("mt-1 break-words font-semibold text-foreground", mono && "font-mono tabular-nums")}>{value}</p>
    </div>
  );
}
