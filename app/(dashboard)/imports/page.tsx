import { CheckCircle2, FileSpreadsheet, History, XCircle } from "lucide-react";
import { CsvImportPanel } from "@/components/forms/CsvImportPanel";
import { PageHeader } from "@/components/layout/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { requireRole } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";
import { formatDateTime } from "@/lib/utils";

export default async function ImportsPage() {
  await requireRole(["super_admin"]);
  const supabase = await createClient();
  const { data } = await supabase.from("import_batches").select("*").order("created_at", { ascending: false }).limit(20);

  const batches = data ?? [];

  return (
    <div className="app-page space-y-6">
      <PageHeader kicker="Data Tools" title="Imports" description="Import CSV dengan preview dan validasi kolom wajib." />
      <CsvImportPanel />
      <Card>
        <CardHeader className="flex-row items-center gap-2.5 space-y-0">
          <span className="flex h-8 w-8 items-center justify-center rounded-md bg-primary/10 text-primary ring-1 ring-primary/15">
            <History className="h-4 w-4" />
          </span>
          <CardTitle>Riwayat Import</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {batches.length ? (
            batches.map((batch) => (
              <div
                key={batch.id}
                className="interactive-lift rounded-md border bg-background/65 p-4 shadow-soft"
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="flex min-w-0 items-center gap-2.5">
                    <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary ring-1 ring-primary/15">
                      <FileSpreadsheet className="h-4 w-4" />
                    </span>
                    <div className="min-w-0">
                      <p className="truncate font-mono text-sm font-medium text-foreground">{batch.file_name ?? batch.import_type}</p>
                      <p className="font-mono text-xs text-muted-foreground">{formatDateTime(batch.created_at)}</p>
                    </div>
                  </div>
                  <span className="inline-flex items-center rounded-sm bg-secondary px-2 py-1 text-xs font-medium text-secondary-foreground">
                    {batch.status}
                  </span>
                </div>
                <div className="mt-3 flex flex-wrap items-center gap-2">
                  <span className="inline-flex items-center gap-1.5 rounded-sm bg-success/12 px-2 py-1 text-xs font-medium text-success ring-1 ring-success/25">
                    <CheckCircle2 className="h-3.5 w-3.5" />
                    <span className="tabular-nums">{batch.success_rows}</span> berhasil
                  </span>
                  <span className="inline-flex items-center gap-1.5 rounded-sm bg-destructive/10 px-2 py-1 text-xs font-medium text-destructive ring-1 ring-destructive/20">
                    <XCircle className="h-3.5 w-3.5" />
                    <span className="tabular-nums">{batch.failed_rows}</span> gagal
                  </span>
                </div>
              </div>
            ))
          ) : (
            <EmptyState title="Belum ada riwayat import" description="Riwayat import CSV akan muncul di sini setelah file diproses." />
          )}
        </CardContent>
      </Card>
    </div>
  );
}
