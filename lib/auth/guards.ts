import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Profile, UserRole } from "@/lib/types";

export async function getCurrentProfile(): Promise<Profile> {
  const supabase = await createClient();
  const {
    data: { user },
    error: userError
  } = await supabase.auth.getUser();

  if (userError || !user) redirect("/login");

  const { data: profile, error } = await supabase
    .from("profiles")
    .select("id, full_name, email, role, is_active")
    .eq("id", user.id)
    .single();

  if (error || !profile || !profile.is_active) redirect("/login");

  return profile as Profile;
}

export async function requireRole(allowed: UserRole[]) {
  const profile = await getCurrentProfile();
  if (!allowed.includes(profile.role)) redirect("/dashboard");
  return profile;
}

export function canMutate(role: UserRole) {
  return role === "super_admin" || role === "admin_gudang";
}

export function canManageAdmins(role: UserRole) {
  return role === "super_admin";
}
