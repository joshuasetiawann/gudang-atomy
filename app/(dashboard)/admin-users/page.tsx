import { AdminUsersManager } from "@/components/forms/MasterDataForms";
import { PageHeader } from "@/components/layout/PageHeader";
import { requireRole } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";

export default async function AdminUsersPage() {
  await requireRole(["super_admin"]);
  const supabase = await createClient();
  const { data } = await supabase.from("profiles").select("id, full_name, email, role, is_active").order("full_name");

  return (
    <div className="space-y-5">
      <PageHeader kicker="Access Control" title="Admin Users" description="Kelola role profile user Supabase Auth." />
      <AdminUsersManager profiles={data ?? []} />
    </div>
  );
}
