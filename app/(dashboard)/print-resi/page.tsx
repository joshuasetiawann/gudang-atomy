import { PrintResiClient, type PrintResiLabel, type PrintResiProductOption } from "@/components/labels/PrintResiClient";
import { PageHeader } from "@/components/layout/PageHeader";
import { EmptyState } from "@/components/ui/empty-state";
import { createClient } from "@/lib/supabase/server";
import type { BoxStatus } from "@/lib/types";

type RawOwner = {
  owner_code: string | null;
  owner_name: string | null;
};

type RawProduct = {
  id: string;
  sku: string | null;
  product_name: string | null;
  unit: string | null;
};

type RawBoxItem = {
  product_id: string;
  qty_initial: number | string | null;
  qty_available: number | string | null;
  expired_at: string | null;
  products: RawProduct | RawProduct[] | null;
};

type RawBox = {
  id: string;
  box_name: string | null;
  id_box: string;
  pemilik_id_box: string;
  barcode_value: string;
  expired_at: string | null;
  location_code: string | null;
  status: string;
  owners: RawOwner | RawOwner[] | null;
  box_items: RawBoxItem[] | null;
};

export default async function PrintResiPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("boxes")
    .select(
      "id, box_name, id_box, pemilik_id_box, barcode_value, expired_at, location_code, status, owners(owner_code, owner_name), box_items(product_id, qty_initial, qty_available, expired_at, products(id, sku, product_name, unit))"
    )
    .order("created_at", { ascending: false })
    .range(0, 1999);

  if (error) {
    return (
      <div className="space-y-5">
        <PageHeader
          kicker="Batch Print"
          title="Print Resi"
          description="Cetak label box massal berdasarkan pesanan, produk, owner, atau status."
        />
        <EmptyState title="Data gagal dimuat" description={error.message} />
      </div>
    );
  }

  const labels = normalizeLabels((data ?? []) as unknown as RawBox[]);
  const productOptions = buildProductOptions(labels);

  return (
    <div className="space-y-5">
      <div className="no-print">
        <PageHeader
          kicker="Batch Print"
          title="Print Resi"
          description="Pilih pesanan atau filter box, lalu print semua label sekaligus untuk ditempel ke box."
        />
      </div>
      <PrintResiClient labels={labels} productOptions={productOptions} />
    </div>
  );
}

function normalizeLabels(rows: RawBox[]): PrintResiLabel[] {
  return rows.map((box) => {
    const owner = pickOne(box.owners);
    return {
      id: box.id,
      box_name: box.box_name ?? box.id_box,
      id_box: box.id_box,
      pemilik_id_box: box.pemilik_id_box,
      barcode_value: box.barcode_value,
      expired_at: box.expired_at,
      location_code: box.location_code,
      status: box.status as BoxStatus,
      owner_code: owner?.owner_code ?? null,
      owner_name: owner?.owner_name ?? null,
      items: (box.box_items ?? []).map((item) => {
        const product = pickOne(item.products);
        return {
          product_id: product?.id ?? item.product_id,
          sku: product?.sku ?? null,
          product_name: product?.product_name ?? "Produk tanpa nama",
          unit: product?.unit ?? "pcs",
          qty_initial: Number(item.qty_initial ?? 0),
          qty_available: Number(item.qty_available ?? 0),
          expired_at: item.expired_at
        };
      })
    };
  });
}

function buildProductOptions(labels: PrintResiLabel[]): PrintResiProductOption[] {
  const productMap = new Map<string, PrintResiProductOption>();

  labels.forEach((label) => {
    label.items.forEach((item) => {
      const current = productMap.get(item.product_id);
      if (current) {
        current.count += 1;
      } else {
        productMap.set(item.product_id, {
          id: item.product_id,
          name: item.product_name,
          count: 1
        });
      }
    });
  });

  return Array.from(productMap.values()).sort((left, right) => left.name.localeCompare(right.name, "id-ID"));
}

function pickOne<T>(value: T | T[] | null | undefined) {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}
