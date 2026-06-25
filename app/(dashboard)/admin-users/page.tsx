import { AdminUsersManager } from "@/components/forms/MasterDataForms";
import { PageHeader } from "@/components/layout/PageHeader";
import { requireRole } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";

export default async function AdminUsersPage() {
  const profile = await requireRole(["super_admin"]);
  const supabase = await createClient();
  const { data } = await supabase.from("profiles").select("id, full_name, email, role, is_active").order("full_name");

  return (
    <div className="app-page space-y-6">
      <PageHeader kicker="Kontrol Akses" title="Pengguna Admin" description="Kelola peran, status, password, dan aktivitas pengguna." />
      <AdminUsersManager profiles={data ?? []} currentUserId={profile.id} />
    </div>
  );
}
