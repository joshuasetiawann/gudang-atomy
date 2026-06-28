import Link from "next/link";
import { Activity, Database, ShieldCheck, UserCircle, X } from "lucide-react";
import { PageHeader } from "@/components/layout/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { requireRole } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";
import { formatDateTime, roleLabel } from "@/lib/utils";
import { isUuidValue } from "@/lib/validation/uuid";

type ActivityLogRow = {
  id: string;
  created_at: string;
  actor_user_id: string | null;
  actor_name: string | null;
  actor_email: string | null;
  actor_role: string | null;
  action: string | null;
  entity_type: string | null;
  record_id: string | null;
  summary: string | null;
  metadata: Record<string, unknown> | null;
};

export default async function ActivityLogsPage({ searchParams }: { searchParams: Promise<{ actor?: string }> }) {
  await requireRole(["super_admin"]);
  const params = await searchParams;
  const actorId = params.actor && isUuidValue(params.actor) ? params.actor : null;
  const supabase = await createClient();

  let query = supabase
    .from("v_activity_logs")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(200);
  if (actorId) query = query.eq("actor_user_id", actorId);
  const { data, error } = await query;

  const rows = (data ?? []) as ActivityLogRow[];

  let actorName: string | null = null;
  if (actorId) {
    const { data: actorProfile } = await supabase.from("profiles").select("full_name").eq("id", actorId).maybeSingle();
    actorName = actorProfile?.full_name ?? rows[0]?.actor_name ?? null;
  }

  return (
    <div className="app-page space-y-6">
      <PageHeader
        kicker="Jejak Audit"
        title="Log Aktivitas"
        description="Riwayat aktivitas user, perubahan master data, scan, pergerakan stok, dan import."
        action={
          <div className="inline-flex items-center gap-2.5 rounded-md border bg-background/80 px-3.5 py-2.5 text-sm font-medium text-foreground shadow-soft">
            <span className="flex h-7 w-7 items-center justify-center rounded-sm bg-primary/10 text-primary ring-1 ring-primary/15">
              <Activity className="h-4 w-4" />
            </span>
            <span>
              <span className="font-mono tabular-nums">{rows.length}</span>
              <span className="text-muted-foreground"> log terakhir</span>
            </span>
          </div>
        }
      />

      {actorId ? (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-md border bg-primary/5 px-4 py-3 text-sm">
          <span className="text-foreground">
            Menampilkan aktivitas untuk: <span className="font-semibold">{actorName ?? "user terpilih"}</span>
          </span>
          <Button asChild size="sm" variant="outline">
            <Link href="/activity-logs">
              <X className="h-4 w-4" />
              Tampilkan semua
            </Link>
          </Button>
        </div>
      ) : null}

      {error ? (
        <Card>
          <CardContent className="p-5">
            <p className="font-semibold text-destructive">Activity Log belum aktif di database.</p>
            <p className="mt-1 text-sm leading-relaxed text-muted-foreground">
              Jalankan file SQL final terbaru di Supabase SQL Editor agar view dan trigger log dibuat.
            </p>
            <p className="mt-3 rounded-md border bg-background/65 p-3 font-mono text-xs text-muted-foreground">{error.message}</p>
          </CardContent>
        </Card>
      ) : null}

      <div className="grid gap-4 md:grid-cols-3">
        <InfoCard icon={ShieldCheck} title="Super User" description="Bisa melihat seluruh log dan mengelola user." />
        <InfoCard icon={UserCircle} title="Admin" description="Aktivitas barang masuk, ambil barang, scan, dan edit data ikut tercatat." />
        <InfoCard icon={Database} title="Audit Data" description="Insert, update, delete, import, dan movement tampil dalam satu timeline." />
      </div>

      {!error && rows.length ? (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Waktu</TableHead>
              <TableHead>Aktor</TableHead>
              <TableHead>Role</TableHead>
              <TableHead>Aksi</TableHead>
              <TableHead>Area</TableHead>
              <TableHead>Ringkasan</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row) => (
              <TableRow key={`${row.entity_type}-${row.id}`}>
                <TableCell className="whitespace-nowrap font-mono text-xs text-muted-foreground">{formatDateTime(row.created_at)}</TableCell>
                <TableCell>
                  <div className="font-medium text-foreground">{row.actor_name ?? "System"}</div>
                  <div className="font-mono text-xs text-muted-foreground">{row.actor_email ?? row.actor_user_id ?? "-"}</div>
                </TableCell>
                <TableCell className="text-sm text-muted-foreground">{roleLabel(row.actor_role)}</TableCell>
                <TableCell>
                  <ActionBadge action={row.action ?? "-"} />
                </TableCell>
                <TableCell className="font-mono text-xs text-muted-foreground">{row.entity_type ?? "-"}</TableCell>
                <TableCell>
                  <div className="max-w-xl break-words leading-relaxed">{row.summary ?? "-"}</div>
                  {row.record_id ? <div className="mt-1 font-mono text-xs text-muted-foreground">{row.record_id}</div> : null}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : !error ? (
        <EmptyState title="Belum ada aktivitas" description="Log akan muncul setelah user melakukan scan, import, atau mengubah data." />
      ) : null}
    </div>
  );
}

function InfoCard({ icon: Icon, title, description }: { icon: typeof Activity; title: string; description: string }) {
  return (
    <Card>
      <CardContent className="flex h-full items-center gap-3.5 p-5">
        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary ring-1 ring-primary/15">
          <Icon className="h-5 w-5" />
        </div>
        <div className="min-w-0 md:pt-1.5">
          <p className="font-semibold text-card-foreground">{title}</p>
          <p className="mt-1 text-sm leading-relaxed text-muted-foreground">{description}</p>
        </div>
      </CardContent>
    </Card>
  );
}

function ActionBadge({ action }: { action: string }) {
  const normalized = action.toLowerCase();
  const variant =
    normalized.includes("delete") || normalized.includes("void")
      ? "void"
      : normalized.includes("update") || normalized.includes("partial")
        ? "partial"
        : normalized.includes("insert") || normalized.includes("in") || normalized.includes("success")
          ? "active"
          : "default";

  return <Badge variant={variant}>{action}</Badge>;
}
