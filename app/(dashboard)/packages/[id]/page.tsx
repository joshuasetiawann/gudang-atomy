import { PackageBuilder } from "@/components/forms/MasterDataForms";
import { PageHeader } from "@/components/layout/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { getCurrentProfile } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";
import { isUuidValue } from "@/lib/validation/uuid";

export default async function PackageDetailPage({ params }: { params: Promise<{ id: string }> | { id: string } }) {
  const { id } = await params;
  if (!isUuidValue(id)) return <p className="app-page text-sm text-muted-foreground">Paket tidak ditemukan.</p>;

  const profile = await getCurrentProfile();
  const supabase = await createClient();
  const [pkgResult, itemsResult, productsResult] = await Promise.all([
    supabase.from("package_templates").select("*").eq("id", id).single(),
    supabase.from("package_template_items").select("*, products(sku, product_name, unit)").eq("package_id", id),
    supabase.from("products").select("*").eq("is_active", true).order("product_name")
  ]);
  const canEdit = profile.role === "super_admin" || profile.role === "admin_gudang";

  if (!pkgResult.data) return <p className="app-page text-sm text-muted-foreground">Paket tidak ditemukan.</p>;

  const items = itemsResult.data ?? [];

  return (
    <div className="app-page space-y-6">
      <PageHeader
        kicker="Detail Paket"
        title={pkgResult.data.package_name}
        description={pkgResult.data.package_code}
      />
      {canEdit ? (
        <PackageBuilder
          products={productsResult.data ?? []}
          initialPackage={pkgResult.data}
          initialItems={itemsResult.data ?? []}
          mode="update"
        />
      ) : null}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between gap-3 space-y-0">
          <CardTitle>Isi paket</CardTitle>
          <span className="inline-flex items-center gap-1.5 rounded-md bg-primary/10 px-2.5 py-1 text-xs font-medium text-primary">
            <span className="tabular-nums">{items.length}</span>
            produk
          </span>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>SKU</TableHead>
                <TableHead>Produk</TableHead>
                <TableHead className="text-right">Qty per paket</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.length ? (
                items.map((item) => (
                  <TableRow key={item.id}>
                    <TableCell className="font-mono text-[13px] text-muted-foreground">{item.products?.sku ?? "-"}</TableCell>
                    <TableCell className="font-medium text-foreground">{item.products?.product_name ?? item.product_id}</TableCell>
                    <TableCell className="text-right tabular-nums">{item.qty_per_package}</TableCell>
                  </TableRow>
                ))
              ) : (
                <TableRow>
                  <TableCell colSpan={3} className="py-10 text-center text-sm text-muted-foreground">
                    Belum ada produk pada paket ini.
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
