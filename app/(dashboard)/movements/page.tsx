import { ExportCsvButton } from "@/components/forms/ExportCsvButton";
import { PageHeader } from "@/components/layout/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createClient } from "@/lib/supabase/server";
import { formatDateTime } from "@/lib/utils";

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
    <div className="space-y-5">
      <PageHeader kicker="Audit Trail" title="Movements" description="Riwayat barang masuk, keluar, adjustment, dan void." action={<ExportCsvButton />} />
      <Card>
        <CardContent className="p-4">
          <form className="grid gap-3 md:grid-cols-4">
            <Input name="date_from" type="date" defaultValue={params.date_from ?? ""} />
            <Input name="date_to" type="date" defaultValue={params.date_to ?? ""} />
            <select name="type" defaultValue={params.type ?? ""} className="h-10 rounded-md border bg-card px-3 text-sm outline-none focus:ring-2 focus:ring-ring">
              <option value="">Semua type</option>
              <option value="in">in</option>
              <option value="out_full_box">out_full_box</option>
              <option value="out_partial_item">out_partial_item</option>
              <option value="adjustment">adjustment</option>
              <option value="void">void</option>
            </select>
            <ButtonSubmit />
          </form>
        </CardContent>
      </Card>
      {(data ?? []).length ? (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Waktu</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Box</TableHead>
              <TableHead>Owner</TableHead>
              <TableHead>Produk</TableHead>
              <TableHead>Qty</TableHead>
              <TableHead>Actor</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(data ?? []).map((movement) => (
              <TableRow key={movement.id}>
                <TableCell>{formatDateTime(movement.created_at)}</TableCell>
                <TableCell>{movement.movement_type}</TableCell>
                <TableCell>{movement.boxes?.id_box ?? "-"}</TableCell>
                <TableCell>{movement.owners?.owner_name ?? "-"}</TableCell>
                <TableCell>{movement.products?.product_name ?? "-"}</TableCell>
                <TableCell>{movement.qty}</TableCell>
                <TableCell>{movement.profiles?.full_name ?? "-"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : (
        <EmptyState title="Belum ada movement" description="Riwayat akan terisi setelah barang masuk atau keluar." />
      )}
    </div>
  );
}

function ButtonSubmit() {
  return <Button>Filter</Button>;
}
