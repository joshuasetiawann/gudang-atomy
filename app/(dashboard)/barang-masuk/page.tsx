import { Lock } from "lucide-react";
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
    <div className="app-page space-y-6">
      <PageHeader kicker="Penerimaan" title="Barang Masuk" description="Buat box baru, hasilkan ID, dan cetak label QR." />
      {!canEdit ? (
        <Alert className="animate-rise flex items-start gap-3 border-warning/30 bg-warning/10">
          <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-warning/15 text-warning ring-1 ring-warning/25">
            <Lock className="h-4 w-4" aria-hidden="true" />
          </span>
          <div className="min-w-0">
            <AlertTitle>Akses hanya lihat</AlertTitle>
            <AlertDescription>Role viewer tidak dapat membuat barang masuk.</AlertDescription>
          </div>
        </Alert>
      ) : (
        <ReceiveBoxForm owners={owners.data ?? []} products={products.data ?? []} packages={packages.data ?? []} />
      )}
    </div>
  );
}
