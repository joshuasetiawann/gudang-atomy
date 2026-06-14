import { ReceiveBoxForm } from "@/components/forms/ReceiveBoxForm";
import { PageHeader } from "@/components/layout/PageHeader";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { getCurrentProfile } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";

export default async function BarangMasukPage() {
  const profile = await getCurrentProfile();
  const supabase = await createClient();
  const [owners, products, packages] = await Promise.all([
    supabase.from("owners").select("*").eq("is_active", true).order("owner_name"),
    supabase.from("products").select("*").eq("is_active", true).order("product_name"),
    supabase.from("package_templates").select("*").eq("is_active", true).order("package_name")
  ]);
  const canEdit = profile.role === "super_admin" || profile.role === "admin_gudang";

  return (
    <div className="space-y-5">
      <PageHeader kicker="Receiving" title="Barang Masuk" description="Input box baru, generate ID, dan cetak label QR." />
      {!canEdit ? (
        <Alert>
          <AlertTitle>Akses hanya lihat</AlertTitle>
          <AlertDescription>Role viewer tidak dapat membuat barang masuk.</AlertDescription>
        </Alert>
      ) : (
        <ReceiveBoxForm owners={owners.data ?? []} products={products.data ?? []} packages={packages.data ?? []} />
      )}
    </div>
  );
}
