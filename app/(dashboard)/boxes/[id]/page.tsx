import { BoxLabel } from "@/components/labels/BoxLabel";
import { PageHeader } from "@/components/layout/PageHeader";
import { StatusBadge } from "@/components/tables/StatusBadge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createClient } from "@/lib/supabase/server";
import { formatDate, formatDateTime } from "@/lib/utils";
import { isUuidValue } from "@/lib/validation/uuid";
import type { BoxStatus } from "@/lib/types";

export default async function BoxDetailPage({ params }: { params: Promise<{ id: string }> | { id: string } }) {
  const { id } = await params;
  if (!isUuidValue(id)) return <p className="text-sm text-muted-foreground">Box tidak ditemukan.</p>;

  const supabase = await createClient();
  const [boxResult, movementResult] = await Promise.all([
    supabase.from("boxes").select("*, owners(owner_code, owner_name), box_items(*, products(sku, product_name, unit))").eq("id", id).single(),
    supabase
      .from("stock_movements")
      .select("movement_type, qty, before_qty, after_qty, created_at, reason, notes, products(sku, product_name)")
      .eq("box_id", id)
      .order("created_at", { ascending: false })
  ]);
  const box = boxResult.data as unknown as BoxDetail | null;
  const movements = (movementResult.data ?? []) as unknown as BoxMovement[];

  if (!box) return <p className="text-sm text-muted-foreground">Box tidak ditemukan.</p>;

  return (
    <div className="space-y-5">
      <PageHeader kicker="Box Detail" title={box.box_name} description={`ID Box App: ${box.id_box}`} action={<StatusBadge status={box.status as BoxStatus} />} />

      <div className="grid gap-5 xl:grid-cols-[420px_1fr]">
        <BoxLabel box={box} />
        <Card>
          <CardHeader>
            <CardTitle>Detail Box</CardTitle>
          </CardHeader>
          <CardContent className="grid gap-3 text-sm md:grid-cols-2">
            <Info label="Pemilik" value={`${box.owners?.owner_code ?? "-"} - ${box.owners?.owner_name ?? "-"}`} />
            <Info label="Pemilik ID Box" value={box.pemilik_id_box} />
            <Info label="Barcode" value={box.barcode_value} />
            <Info label="Source" value={box.source_type} />
            <Info label="Expired" value={formatDate(box.expired_at)} />
            <Info label="Lokasi" value={box.location_code ?? "-"} />
            <Info label="Created by" value={box.created_by ?? "-"} />
            <Info label="Created at" value={formatDateTime(box.created_at)} />
            <Info label="Checked out by" value={box.checked_out_by ?? "-"} />
            <Info label="Checked out at" value={formatDateTime(box.checked_out_at)} />
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Isi Produk</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>SKU</TableHead>
                <TableHead>Produk</TableHead>
                <TableHead>Qty Awal</TableHead>
                <TableHead>Qty Sisa</TableHead>
                <TableHead>Expired</TableHead>
                <TableHead>Batch</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {box.box_items.map((item) => (
                <TableRow key={item.id}>
                  <TableCell>{item.products?.sku ?? "-"}</TableCell>
                  <TableCell>{item.products?.product_name ?? item.product_id}</TableCell>
                  <TableCell>{item.qty_initial}</TableCell>
                  <TableCell>{item.qty_available}</TableCell>
                  <TableCell>{formatDate(item.expired_at)}</TableCell>
                  <TableCell>{item.batch_no ?? "-"}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Riwayat Movement</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Waktu</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Produk</TableHead>
                <TableHead>Qty</TableHead>
                <TableHead>Before</TableHead>
                <TableHead>After</TableHead>
                <TableHead>Catatan</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {movements.map((movement, index) => (
                <TableRow key={`${movement.created_at}-${index}`}>
                  <TableCell>{formatDateTime(movement.created_at)}</TableCell>
                  <TableCell>{movement.movement_type}</TableCell>
                  <TableCell>{movement.products?.product_name ?? "-"}</TableCell>
                  <TableCell>{movement.qty}</TableCell>
                  <TableCell>{movement.before_qty ?? "-"}</TableCell>
                  <TableCell>{movement.after_qty ?? "-"}</TableCell>
                  <TableCell>{movement.reason ?? movement.notes ?? "-"}</TableCell>
                </TableRow>
              ))}
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

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border bg-background/65 p-3">
      <p className="text-xs font-medium text-muted-foreground">{label}</p>
      <p className="mt-1 break-words font-semibold">{value}</p>
    </div>
  );
}
