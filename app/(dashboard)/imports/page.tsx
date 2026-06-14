import { CsvImportPanel } from "@/components/forms/CsvImportPanel";
import { PageHeader } from "@/components/layout/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { requireRole } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";
import { formatDateTime } from "@/lib/utils";

export default async function ImportsPage() {
  await requireRole(["super_admin"]);
  const supabase = await createClient();
  const { data } = await supabase.from("import_batches").select("*").order("created_at", { ascending: false }).limit(20);

  return (
    <div className="space-y-5">
      <PageHeader kicker="Data Tools" title="Imports" description="Import CSV dengan preview dan validasi kolom wajib." />
      <CsvImportPanel />
      <Card>
        <CardHeader>
          <CardTitle>Riwayat Import</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {(data ?? []).map((batch) => (
            <div key={batch.id} className="rounded-md border bg-background/65 p-3 text-sm">
              <div className="flex flex-wrap justify-between gap-2">
                <p className="font-medium">{batch.file_name ?? batch.import_type}</p>
                <p className="text-muted-foreground">{formatDateTime(batch.created_at)}</p>
              </div>
              <p className="text-muted-foreground">
                {batch.status} - success {batch.success_rows}, failed {batch.failed_rows}
              </p>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}
