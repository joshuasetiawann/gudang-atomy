import Link from "next/link";
import { Eye } from "lucide-react";
import { PackageBuilder } from "@/components/forms/MasterDataForms";
import { PageHeader } from "@/components/layout/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { getCurrentProfile } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";

export default async function PackagesPage() {
  const profile = await getCurrentProfile();
  const supabase = await createClient();
  const [products, packages] = await Promise.all([
    supabase.from("products").select("*").eq("is_active", true).order("product_name"),
    supabase.from("package_templates").select("*, package_template_items(id)").order("package_name")
  ]);
  const canEdit = profile.role === "super_admin" || profile.role === "admin_gudang";

  return (
    <div className="space-y-5">
      <PageHeader kicker="Master Data" title="Packages" description="Template paket dan komposisi produk." />
      {canEdit ? <PackageBuilder products={products.data ?? []} mode="create" /> : null}
      <Card>
        <CardContent className="p-4">
          {(packages.data ?? []).length ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Kode</TableHead>
                  <TableHead>Nama</TableHead>
                  <TableHead>Produk</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(packages.data ?? []).map((pkg) => (
                  <TableRow key={pkg.id}>
                    <TableCell>{pkg.package_code}</TableCell>
                    <TableCell>{pkg.package_name}</TableCell>
                    <TableCell>{pkg.package_template_items?.length ?? 0}</TableCell>
                    <TableCell>{pkg.is_active ? "Aktif" : "Nonaktif"}</TableCell>
                    <TableCell>
                      <Button asChild size="icon" variant="ghost" aria-label="Detail paket">
                        <Link href={`/packages/${pkg.id}`}>
                          <Eye className="h-4 w-4" />
                        </Link>
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <EmptyState title="Belum ada paket" description="Buat template paket untuk mempercepat barang masuk." />
          )}
        </CardContent>
      </Card>
    </div>
  );
}
