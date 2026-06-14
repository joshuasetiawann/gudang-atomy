"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type LoginState = {
  error?: string;
};

export async function loginAction(_state: LoginState, formData: FormData): Promise<LoginState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const next = String(formData.get("next") ?? "/dashboard");

  if (!email || !password) {
    return { error: "Email dan password wajib diisi." };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    return { error: error.message };
  }

  const {
    data: { user }
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: "Login berhasil, tapi sesi user tidak terbaca. Coba login ulang." };
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("id, is_active")
    .eq("id", user.id)
    .single();

  if (profileError || !profile) {
    await supabase.auth.signOut();
    return {
      error:
        "Login Auth berhasil, tapi profile admin belum ada di tabel profiles. Jalankan SQL profile untuk email ini di Supabase SQL Editor."
    };
  }

  if (!profile.is_active) {
    await supabase.auth.signOut();
    return { error: "User ini nonaktif di tabel profiles." };
  }

  redirect(next.startsWith("/") ? next : "/dashboard");
}
