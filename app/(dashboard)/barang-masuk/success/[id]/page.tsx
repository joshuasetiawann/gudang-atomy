import Link from "next/link";
import { BoxLabel } from "@/components/labels/BoxLabel";
import { PageHeader } from "@/components/layout/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/server";
import { isUuidValue } from "@/lib/validation/uuid";

export default async function BarangMasukSuccessPage({ params }: { params: Promise<{ id: string }> | { id: string } }) {
  const { id } = await params;
  if (!isUuidValue(id)) return <p className="text-sm text-muted-foreground">Box tidak ditemukan.</p>;

  const supabase = await createClient();
  const { data: box } = await supabase.from("boxes").select("*, owners(owner_name)").eq("id", id).single();

  if (!box) {
    return <p className="text-sm text-muted-foreground">Box tidak ditemukan.</p>;
  }

  return (
    <div className="space-y-5">
      <div className="no-print">
        <PageHeader
          kicker="Receiving Complete"
          title="Barang Masuk Berhasil"
          description={`ID Box App: ${box.id_box}`}
          action={
            <Button asChild variant="outline">
              <Link href={`/boxes/${box.id}`}>Detail Box</Link>
            </Button>
          }
        />
      </div>
      <Card className="no-print">
        <CardHeader>
          <CardTitle>Barcode Value</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="rounded-md border bg-background/65 p-3 break-all font-mono text-sm">{box.barcode_value}</p>
        </CardContent>
      </Card>
      <BoxLabel box={box} />
    </div>
  );
}
