import { PackageBuilder } from "@/components/forms/MasterDataForms";
import { PageHeader } from "@/components/layout/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { getCurrentProfile } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";
import { isUuidValue } from "@/lib/validation/uuid";

export default async function PackageDetailPage({ params }: { params: Promise<{ id: string }> | { id: string } }) {
  const { id } = await params;
  if (!isUuidValue(id)) return <p className="text-sm text-muted-foreground">Paket tidak ditemukan.</p>;

  const profile = await getCurrentProfile();
  const supabase = await createClient();
  const [pkgResult, itemsResult, productsResult] = await Promise.all([
    supabase.from("package_templates").select("*").eq("id", id).single(),
    supabase.from("package_template_items").select("*, products(sku, product_name, unit)").eq("package_id", id),
    supabase.from("products").select("*").eq("is_active", true).order("product_name")
  ]);
  const canEdit = profile.role === "super_admin" || profile.role === "admin_gudang";

  if (!pkgResult.data) return <p className="text-sm text-muted-foreground">Paket tidak ditemukan.</p>;

  return (
    <div className="space-y-5">
      <PageHeader kicker="Package Detail" title={pkgResult.data.package_name} description={pkgResult.data.package_code} />
      {canEdit ? (
        <PackageBuilder
          products={productsResult.data ?? []}
          initialPackage={pkgResult.data}
          initialItems={itemsResult.data ?? []}
          mode="update"
        />
      ) : null}
      <Card>
        <CardHeader>
          <CardTitle>Isi Paket</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>SKU</TableHead>
                <TableHead>Produk</TableHead>
                <TableHead>Qty/Paket</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(itemsResult.data ?? []).map((item) => (
                <TableRow key={item.id}>
                  <TableCell>{item.products?.sku ?? "-"}</TableCell>
                  <TableCell>{item.products?.product_name ?? item.product_id}</TableCell>
                  <TableCell>{item.qty_per_package}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
