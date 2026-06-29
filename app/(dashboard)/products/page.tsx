import { ProductManager, type ProductPrintSummaryMap } from "@/components/forms/MasterDataForms";
import { PageHeader } from "@/components/layout/PageHeader";
import { getCurrentProfile } from "@/lib/auth/guards";
import { createClient } from "@/lib/supabase/server";

type RawBoxRef = { printed_at: string | null; status: string | null };
type RawBoxItemRef = { product_id: string; boxes: RawBoxRef | RawBoxRef[] | null };

// Box yang masih "di rak" (relevan untuk dicetak labelnya).
const ON_SHELF = new Set(["active", "partial", "empty"]);

export default async function ProductsPage() {
  const profile = await getCurrentProfile();
  const supabase = await createClient();
  const [{ data }, { data: itemRows }] = await Promise.all([
    supabase.from("products").select("*").order("product_name"),
    supabase.from("box_items").select("product_id, boxes(printed_at, status)").range(0, 4999)
  ]);
  const canEdit = profile.role === "super_admin" || profile.role === "admin_gudang";
  const printSummary = buildPrintSummary((itemRows ?? []) as unknown as RawBoxItemRef[]);

  return (
    <div className="app-page space-y-6">
      <PageHeader kicker="Data Master" title="Produk" description="Master produk Atomy dan komponen paket GudangKu." />
      <ProductManager products={data ?? []} canEdit={canEdit} printSummary={printSummary} />
    </div>
  );
}

function buildPrintSummary(rows: RawBoxItemRef[]): ProductPrintSummaryMap {
  const summary: ProductPrintSummaryMap = {};
  rows.forEach((row) => {
    const box = Array.isArray(row.boxes) ? row.boxes[0] : row.boxes;
    if (!box || !ON_SHELF.has(box.status ?? "")) return;
    const entry = summary[row.product_id] ?? { printed: 0, unprinted: 0 };
    if (box.printed_at) entry.printed += 1;
    else entry.unprinted += 1;
    summary[row.product_id] = entry;
  });
  return summary;
}
