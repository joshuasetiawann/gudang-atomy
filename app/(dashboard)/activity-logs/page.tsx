import { Activity, Database, ShieldCheck, UserCircle } from "lucide-react";
import { PageHeader } from "@/components/layout/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { requireRole } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";
import { formatDateTime, roleLabel } from "@/lib/utils";

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

export default async function ActivityLogsPage() {
  await requireRole(["super_admin"]);
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("v_activity_logs")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(200);

  const rows = (data ?? []) as ActivityLogRow[];

  return (
    <div className="space-y-5">
      <PageHeader
        kicker="Audit Trail"
        title="Activity Log"
        description="Riwayat aktivitas user, perubahan master data, scan, pergerakan stok, dan import."
        action={
          <div className="rounded-md border bg-background/80 px-3 py-2 text-sm font-medium text-muted-foreground">
            {rows.length} log terakhir
          </div>
        }
      />

      {error ? (
        <Card>
          <CardContent className="p-5">
            <p className="font-semibold text-destructive">Activity Log belum aktif di database.</p>
            <p className="mt-1 text-sm text-muted-foreground">
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
                <TableCell className="whitespace-nowrap">{formatDateTime(row.created_at)}</TableCell>
                <TableCell>
                  <div className="font-medium">{row.actor_name ?? "System"}</div>
                  <div className="text-xs text-muted-foreground">{row.actor_email ?? row.actor_user_id ?? "-"}</div>
                </TableCell>
                <TableCell>{roleLabel(row.actor_role)}</TableCell>
                <TableCell>
                  <ActionBadge action={row.action ?? "-"} />
                </TableCell>
                <TableCell className="font-mono text-xs">{row.entity_type ?? "-"}</TableCell>
                <TableCell>
                  <div className="max-w-xl break-words">{row.summary ?? "-"}</div>
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
      <CardContent className="flex gap-3 p-4">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary">
          <Icon className="h-5 w-5" />
        </div>
        <div>
          <p className="font-semibold">{title}</p>
          <p className="mt-1 text-sm text-muted-foreground">{description}</p>
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
