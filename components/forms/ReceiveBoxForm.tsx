"use client";

import { useActionState, useMemo, useState } from "react";
import { Plus, PackagePlus, Trash2 } from "lucide-react";
import { receiveBoxAction } from "@/server/actions/warehouse";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import type { ActionState, Owner, PackageTemplate, Product } from "@/lib/types";

type ManualItem = {
  product_id: string;
  qty: number;
  expired_at?: string;
  batch_no?: string;
};

const initialState: ActionState = { ok: true, message: "" };
const sourceOptions = [
  { value: "custom", label: "Custom", description: "Input produk manual" },
  { value: "package", label: "Paket", description: "Pakai template paket" },
  { value: "mixed", label: "Mixed", description: "Paket + tambahan" }
] as const;

export function ReceiveBoxForm({
  owners,
  products,
  packages
}: {
  owners: Owner[];
  products: Product[];
  packages: PackageTemplate[];
}) {
  const [state, formAction, pending] = useActionState(receiveBoxAction, initialState);
  const [sourceType, setSourceType] = useState<"custom" | "package" | "mixed">("custom");
  const [items, setItems] = useState<ManualItem[]>([{ product_id: "", qty: 1 }]);
  const itemsJson = useMemo(() => JSON.stringify(items.filter((item) => item.product_id && Number(item.qty) > 0)), [items]);
  const hasManualItem = items.some((item) => item.product_id && Number(item.qty) > 0);
  const needsPackage = sourceType !== "custom";
  const needsProductMaster = sourceType !== "package";
  const submitDisabled =
    pending ||
    (needsPackage && packages.length === 0) ||
    (needsProductMaster && products.length === 0) ||
    (sourceType === "custom" && !hasManualItem);

  function updateItem(index: number, patch: Partial<ManualItem>) {
    setItems((current) => current.map((item, itemIndex) => (itemIndex === index ? { ...item, ...patch } : item)));
  }

  return (
    <form action={formAction} className="space-y-5">
      <input type="hidden" name="source_type" value={sourceType} />
      <input type="hidden" name="items_json" value={sourceType === "package" ? "[]" : itemsJson} />
      <Card>
        <CardHeader>
          <CardTitle>Data Box</CardTitle>
          <CardDescription>Isi pemilik, label box, lokasi, dan tipe penerimaan barang.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 md:grid-cols-2">
          <div className="space-y-2">
            <Label htmlFor="owner_id">Pemilik existing</Label>
            <select id="owner_id" name="owner_id" className="h-10 w-full rounded-md border bg-card px-3 text-sm outline-none focus:ring-2 focus:ring-ring">
              <option value="">Pilih pemilik</option>
              {owners.map((owner) => (
                <option key={owner.id} value={owner.id}>
                  {owner.owner_code} - {owner.owner_name}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="quick_owner_name">Tambah pemilik cepat</Label>
            <Input id="quick_owner_name" name="quick_owner_name" placeholder="Isi jika belum ada owner" />
          </div>
          <div className="space-y-2">
            <Label htmlFor="box_name">Nama box</Label>
            <Input id="box_name" name="box_name" required placeholder="Kotak Budi 001" />
          </div>
          <div className="space-y-2">
            <Label htmlFor="expired_at">Expired date</Label>
            <Input id="expired_at" name="expired_at" type="date" />
          </div>
          <div className="space-y-2">
            <Label htmlFor="location_code">Lokasi/rak</Label>
            <Input id="location_code" name="location_code" placeholder="Rak A1" />
          </div>
          <div className="space-y-2">
            <Label>Tipe barang</Label>
            <div className="grid grid-cols-3 rounded-lg border bg-muted/45 p-1">
              {sourceOptions.map((option) => (
                <button
                  key={option.value}
                  type="button"
                  onClick={() => setSourceType(option.value)}
                  className={`rounded-md px-2 py-2 text-left transition-colors ${sourceType === option.value ? "bg-card text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground"}`}
                >
                  <span className="block truncate text-sm font-semibold">{option.label}</span>
                  <span className="hidden truncate text-xs md:block">{option.description}</span>
                </button>
              ))}
            </div>
          </div>
          <div className="space-y-2 md:col-span-2">
            <Label htmlFor="notes">Catatan</Label>
            <Textarea id="notes" name="notes" placeholder="Catatan penerimaan barang" />
          </div>
        </CardContent>
      </Card>

      {sourceType !== "custom" ? (
        <Card>
          <CardHeader>
            <CardTitle>Paket</CardTitle>
            <CardDescription>Pilih template paket GudangKu dan jumlah paket yang masuk.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4 md:grid-cols-2">
            {packages.length ? (
              <>
                <div className="space-y-2">
                  <Label htmlFor="package_id">Template paket</Label>
                  <select id="package_id" name="package_id" required className="h-10 w-full rounded-md border bg-card px-3 text-sm outline-none focus:ring-2 focus:ring-ring">
                    <option value="">Pilih paket</option>
                    {packages.map((pkg) => (
                      <option key={pkg.id} value={pkg.id}>
                        {pkg.package_code} - {pkg.package_name}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="package_qty">Jumlah paket</Label>
                  <Input id="package_qty" name="package_qty" type="number" min="1" step="1" defaultValue="1" required />
                </div>
              </>
            ) : (
              <EmptyState className="md:col-span-2" title="Belum ada paket" description="Buat template paket dulu, atau ubah source type ke Custom untuk input produk manual." />
            )}
          </CardContent>
        </Card>
      ) : (
        <input type="hidden" name="package_qty" value="0" />
      )}

      {sourceType !== "package" ? (
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0">
            <div>
              <CardTitle>Produk Manual</CardTitle>
              <CardDescription>Tambahkan item satuan jika box bukan dari paket, atau ada tambahan di luar paket.</CardDescription>
            </div>
            <Button type="button" variant="outline" size="sm" disabled={!products.length} onClick={() => setItems((current) => [...current, { product_id: "", qty: 1 }])}>
              <Plus className="h-4 w-4" />
              Tambah
            </Button>
          </CardHeader>
          <CardContent className="space-y-3">
            {products.length ? (
              items.map((item, index) => (
                <div key={index} className="grid gap-3 rounded-md border bg-background/65 p-3 md:grid-cols-[1fr_110px_150px_150px_40px]">
                  <select
                    value={item.product_id}
                    onChange={(event) => updateItem(index, { product_id: event.target.value })}
                    className="h-10 rounded-md border bg-card px-3 text-sm outline-none focus:ring-2 focus:ring-ring"
                  >
                    <option value="" disabled>
                      Pilih produk
                    </option>
                    {products.map((product) => (
                      <option key={product.id} value={product.id}>
                        {product.sku ? `${product.sku} - ` : ""}
                        {product.product_name}
                      </option>
                    ))}
                  </select>
                  <Input value={item.qty} onChange={(event) => updateItem(index, { qty: Number(event.target.value) })} type="number" min="1" step="1" />
                  <Input value={item.expired_at ?? ""} onChange={(event) => updateItem(index, { expired_at: event.target.value })} type="date" />
                  <Input value={item.batch_no ?? ""} onChange={(event) => updateItem(index, { batch_no: event.target.value })} placeholder="Batch" />
                  <Button type="button" size="icon" variant="ghost" onClick={() => setItems((current) => current.filter((_, itemIndex) => itemIndex !== index))} aria-label="Hapus produk">
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              ))
            ) : (
              <EmptyState title="Belum ada produk" description="Tambahkan master produk dulu di menu Products sebelum membuat box manual." />
            )}
          </CardContent>
        </Card>
      ) : null}

      {state.message ? (
        <p className={state.ok ? "rounded-md border border-success/20 bg-success/10 p-3 text-sm font-medium text-success" : "rounded-md border border-destructive/20 bg-destructive/10 p-3 text-sm font-medium text-destructive"}>
          {state.message}
        </p>
      ) : null}
      <Button disabled={submitDisabled} className="h-11">
        <PackagePlus className="h-4 w-4" />
        {pending ? "Menyimpan..." : "Simpan Barang Masuk"}
      </Button>
    </form>
  );
}
