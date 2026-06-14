import { OwnerManager } from "@/components/forms/MasterDataForms";
import { PageHeader } from "@/components/layout/PageHeader";
import { getCurrentProfile } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";

export default async function OwnersPage() {
  const profile = await getCurrentProfile();
  const supabase = await createClient();
  const { data } = await supabase.from("owners").select("*").order("owner_name");
  const canEdit = profile.role === "super_admin" || profile.role === "admin_gudang";

  return (
    <div className="space-y-5">
      <PageHeader kicker="Master Data" title="Owners" description="Master pemilik box dan barang." />
      <OwnerManager owners={data ?? []} canEdit={canEdit} />
    </div>
  );
}
