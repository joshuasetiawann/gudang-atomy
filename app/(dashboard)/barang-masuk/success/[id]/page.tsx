import Link from "next/link";
import { CheckCircle2 } from "lucide-react";
import { BoxLabel } from "@/components/labels/BoxLabel";
import { PageHeader } from "@/components/layout/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { createClient } from "@/lib/supabase/server";
import { isUuidValue } from "@/lib/validation/uuid";

export default async function BarangMasukSuccessPage({ params }: { params: Promise<{ id: string }> | { id: string } }) {
  const { id } = await params;
  if (!isUuidValue(id)) {
    return <EmptyState title="Box tidak ditemukan" description="ID box tidak valid atau sudah dihapus." />;
  }

  const supabase = await createClient();
  const { data: box } = await supabase.from("boxes").select("*, owners(owner_name)").eq("id", id).single();

  if (!box) {
    return <EmptyState title="Box tidak ditemukan" description="ID box tidak valid atau sudah dihapus." />;
  }

  return (
    <div className="app-page space-y-6">
      <div className="no-print">
        <PageHeader
          kicker="Receiving Complete"
          title="Barang Masuk Berhasil"
          description="Box berhasil dibuat. Cetak label QR atau buka detail box."
          action={
            <Button asChild variant="outline">
              <Link href={`/boxes/${box.id}`}>Detail box</Link>
            </Button>
          }
        />
      </div>
      <Card className="no-print animate-rise border-success/30 bg-success/[0.06]">
        <CardContent className="flex items-center gap-3 p-5">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-success/15 text-success ring-1 ring-success/25">
            <CheckCircle2 className="h-5 w-5" aria-hidden="true" />
          </span>
          <div className="min-w-0">
            <p className="text-sm font-semibold text-card-foreground">Box tersimpan</p>
            <p className="mt-0.5 text-sm text-muted-foreground">
              ID Box App <span className="font-mono font-semibold text-foreground">{box.id_box}</span>
            </p>
          </div>
        </CardContent>
      </Card>
      <Card className="no-print">
        <CardHeader>
          <CardTitle>Barcode value</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="break-all rounded-md border bg-background/65 p-3 font-mono text-sm tabular-nums text-foreground shadow-soft">{box.barcode_value}</p>
        </CardContent>
      </Card>
      <BoxLabel box={box} />
    </div>
  );
}
