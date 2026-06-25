import { ProductManager } from "@/components/forms/MasterDataForms";
import { PageHeader } from "@/components/layout/PageHeader";
import { getCurrentProfile } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";

export default async function ProductsPage() {
  const profile = await getCurrentProfile();
  const supabase = await createClient();
  const { data } = await supabase.from("products").select("*").order("product_name");
  const canEdit = profile.role === "super_admin" || profile.role === "admin_gudang";

  return (
    <div className="app-page space-y-6">
      <PageHeader kicker="Data Master" title="Produk" description="Master produk Atomy dan komponen paket GudangKu." />
      <ProductManager products={data ?? []} canEdit={canEdit} />
    </div>
  );
}
