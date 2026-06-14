import { ExportCsvButton } from "@/components/forms/ExportCsvButton";
import { PageHeader } from "@/components/layout/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { createClient } from "@/lib/supabase/server";
import { formatDate } from "@/lib/utils";

export default async function ReportsPage() {
  const supabase = await createClient();
  const expiryLimit = new Date();
  expiryLimit.setDate(expiryLimit.getDate() + 30);
  const [activeStock, perOwner, perProduct, expired] = await Promise.all([
    supabase.from("v_active_stock").select("*").order("expired_at", { ascending: true }).limit(50),
    supabase.from("v_active_stock").select("owner_name, qty_available"),
    supabase.from("v_active_stock").select("product_name, qty_available"),
    supabase.from("v_active_stock").select("*").lte("expired_at", expiryLimit.toISOString().slice(0, 10)).limit(50)
  ]);

  const ownerRows = groupQty(perOwner.data ?? [], "owner_name");
  const productRows = groupQty(perProduct.data ?? [], "product_name");

  return (
    <div className="space-y-5">
      <PageHeader kicker="Analytics" title="Reports" description="Stok aktif, owner, produk, expired, dan export CSV." action={<ExportCsvButton />} />

      <div className="grid gap-5 xl:grid-cols-2">
        <ReportTable title="Stok Per Owner" rows={ownerRows} />
        <ReportTable title="Stok Per Produk" rows={productRows} />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Box/Produk Mendekati Expired</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>ID Box App</TableHead>
                <TableHead>Owner</TableHead>
                <TableHead>Produk</TableHead>
                <TableHead>Qty</TableHead>
                <TableHead>Expired</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(expired.data ?? []).map((row, index) => (
                <TableRow key={`${row.id_box}-${row.sku}-${index}`}>
                  <TableCell>{row.id_box}</TableCell>
                  <TableCell>{row.owner_name}</TableCell>
                  <TableCell>{row.product_name}</TableCell>
                  <TableCell>{row.qty_available}</TableCell>
                  <TableCell>{formatDate(row.expired_at)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Stok Aktif Terbaru</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>ID Box App</TableHead>
                <TableHead>Owner</TableHead>
                <TableHead>Produk</TableHead>
                <TableHead>Qty</TableHead>
                <TableHead>Lokasi</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(activeStock.data ?? []).map((row, index) => (
                <TableRow key={`${row.id_box}-${row.sku}-${index}`}>
                  <TableCell>{row.id_box}</TableCell>
                  <TableCell>{row.owner_name}</TableCell>
                  <TableCell>{row.product_name}</TableCell>
                  <TableCell>{row.qty_available}</TableCell>
                  <TableCell>{row.location_code ?? "-"}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
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

function ReportTable({ title, rows }: { title: string; rows: Array<{ name: string; qty: number }> }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Nama</TableHead>
              <TableHead>Qty</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row) => (
              <TableRow key={row.name}>
                <TableCell>{row.name}</TableCell>
                <TableCell>{row.qty}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
