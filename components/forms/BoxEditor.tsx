"use client";

import { useActionState, useMemo, useState } from "react";
import { AlertTriangle, CheckCircle2, Plus, Save, Trash2 } from "lucide-react";
import { deleteBoxAction, updateBoxAction } from "@/server/actions/warehouse";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger
} from "@/components/ui/dialog";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SearchableSelect } from "@/components/ui/searchable-select";
import { Textarea } from "@/components/ui/textarea";
import type { ActionState, BoxStatus, Product } from "@/lib/types";

type EditItem = { id?: string; product_id: string; qty: number; expired_at?: string; batch_no?: string };

type BoxEditorBox = {
  id: string;
  box_name: string;
  expired_at: string | null;
  location_code: string | null;
  notes: string | null;
  status: BoxStatus;
};

type BoxEditorItem = {
  id: string;
  product_id: string;
  qty_available: number;
  expired_at: string | null;
  batch_no: string | null;
};

const initialState: ActionState = { ok: true, message: "" };

export function BoxEditor({
  box,
  items,
  products,
  canDelete
}: {
  box: BoxEditorBox;
  items: BoxEditorItem[];
  products: Product[];
  canDelete: boolean;
}) {
  const [state, formAction, pending] = useActionState(updateBoxAction, initialState);
  const [lines, setLines] = useState<EditItem[]>(
    items.map((item) => ({
      id: item.id,
      product_id: item.product_id,
      qty: Number(item.qty_available),
      expired_at: item.expired_at ?? undefined,
      batch_no: item.batch_no ?? undefined
    }))
  );

  const productOptions = useMemo(
    () =>
      products.map((product) => ({
        value: product.id,
        label: `${product.sku ? `${product.sku} - ` : ""}${product.product_name}`,
        description: [product.category, product.unit].filter(Boolean).join(" / ") || undefined
      })),
    [products]
  );

  const itemsJson = useMemo(() => JSON.stringify(lines.filter((line) => line.product_id && Number(line.qty) > 0)), [lines]);
  const totalAvailable = lines.reduce((sum, line) => (line.product_id && Number(line.qty) > 0 ? sum + Number(line.qty) : sum), 0);

  function updateLine(index: number, patch: Partial<EditItem>) {
    setLines((current) => current.map((line, lineIndex) => (lineIndex === index ? { ...line, ...patch } : line)));
  }

  return (
    <div className="space-y-5">
      <form action={formAction} className="space-y-5">
        <input type="hidden" name="id" value={box.id} />
        <input type="hidden" name="items_json" value={itemsJson} />

        <Card>
          <CardHeader>
            <CardTitle>Edit rincian box</CardTitle>
            <CardDescription>Ubah nama, lokasi, tanggal expired, dan catatan box.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4 md:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="box_name">Nama box</Label>
              <Input id="box_name" name="box_name" defaultValue={box.box_name} required />
            </div>
            <div className="space-y-2">
              <Label htmlFor="location_code">Lokasi/rak</Label>
              <Input id="location_code" name="location_code" defaultValue={box.location_code ?? ""} placeholder="Rak A1" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="expired_at">Expired date</Label>
              <Input id="expired_at" name="expired_at" type="date" defaultValue={box.expired_at ?? ""} className="font-mono tabular-nums" />
            </div>
            <div className="space-y-2 md:col-span-2">
              <Label htmlFor="notes">Catatan</Label>
              <Textarea id="notes" name="notes" defaultValue={box.notes ?? ""} placeholder="Catatan box" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-col gap-3 space-y-0 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <CardTitle>Edit isi produk</CardTitle>
              <CardDescription>Tambah, ubah jumlah, atau hapus produk di dalam box ini.</CardDescription>
            </div>
            <Button
              className="w-full sm:w-auto"
              type="button"
              variant="outline"
              size="sm"
              disabled={!products.length}
              onClick={() => setLines((current) => [...current, { product_id: "", qty: 1 }])}
            >
              <Plus className="h-4 w-4" />
              Tambah produk
            </Button>
          </CardHeader>
          <CardContent className="space-y-3">
            {products.length ? (
              lines.length ? (
                lines.map((line, index) => (
                  <div
                    key={line.id ?? `new-${index}`}
                    className="grid min-w-0 items-center gap-3 rounded-md border bg-background/65 p-3 transition-colors hover:border-primary/30 md:grid-cols-[minmax(0,1fr)_110px_150px_150px_40px]"
                  >
                    <SearchableSelect
                      value={line.product_id}
                      onValueChange={(value) => updateLine(index, { product_id: value })}
                      options={productOptions}
                      placeholder="Pilih produk"
                      searchPlaceholder="Ketik nama produk atau SKU..."
                      emptyText="Produk tidak ditemukan"
                    />
                    <Input
                      value={line.qty}
                      onChange={(event) => updateLine(index, { qty: Number(event.target.value) })}
                      type="number"
                      min="1"
                      step="1"
                      className="tabular-nums"
                      aria-label="Jumlah"
                    />
                    <Input
                      value={line.expired_at ?? ""}
                      onChange={(event) => updateLine(index, { expired_at: event.target.value })}
                      type="date"
                      className="font-mono tabular-nums"
                      aria-label="Expired"
                    />
                    <Input
                      value={line.batch_no ?? ""}
                      onChange={(event) => updateLine(index, { batch_no: event.target.value })}
                      placeholder="Batch"
                      className="font-mono"
                      aria-label="Batch"
                    />
                    <Button
                      type="button"
                      size="icon"
                      variant="ghost"
                      onClick={() => setLines((current) => current.filter((_, lineIndex) => lineIndex !== index))}
                      aria-label="Hapus produk"
                      className="w-full text-muted-foreground hover:text-destructive md:w-10"
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                ))
              ) : (
                <EmptyState title="Box masih kosong" description="Klik 'Tambah produk' untuk mengisi box ini." />
              )
            ) : (
              <EmptyState title="Belum ada produk" description="Tambahkan master produk dulu di menu Products." />
            )}
          </CardContent>
        </Card>

        {state.message ? (
          <p
            role="status"
            aria-live="polite"
            className={
              state.ok
                ? "animate-rise flex items-start gap-2 rounded-md border border-success/20 bg-success/10 p-3 text-sm font-medium text-success"
                : "animate-rise flex items-start gap-2 rounded-md border border-destructive/20 bg-destructive/10 p-3 text-sm font-medium text-destructive"
            }
          >
            {state.ok ? <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" /> : <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />}
            <span>{state.message}</span>
          </p>
        ) : null}

        <Button className="w-full sm:w-auto" size="lg" disabled={pending}>
          <Save className="h-4 w-4" />
          {pending ? "Menyimpan..." : "Simpan perubahan"}
        </Button>
      </form>

      {canDelete ? <BoxDeleteCard boxId={box.id} hasStock={totalAvailable > 0} /> : null}
    </div>
  );
}

function BoxDeleteCard({ boxId, hasStock }: { boxId: string; hasStock: boolean }) {
  const [state, formAction, pending] = useActionState(deleteBoxAction, initialState);

  return (
    <Card className="border-destructive/30">
      <CardHeader>
        <CardTitle className="text-destructive">Zona berbahaya</CardTitle>
        <CardDescription>Hapus box ini secara permanen. Tindakan ini tidak bisa dibatalkan.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {hasStock ? (
          <div className="flex items-start gap-2 rounded-md border border-warning/20 bg-warning/15 p-3 text-sm text-warning-foreground">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
            <span>Box masih berisi stok. Kosongkan jumlah produknya jadi 0 lalu simpan dulu sebelum bisa dihapus.</span>
          </div>
        ) : null}
        {!state.ok && state.message ? (
          <p
            role="status"
            aria-live="polite"
            className="flex items-start gap-2 rounded-md border border-destructive/20 bg-destructive/10 p-3 text-sm font-medium text-destructive"
          >
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
            <span>{state.message}</span>
          </p>
        ) : null}
        <Dialog>
          <DialogTrigger asChild>
            <Button type="button" variant="destructive" disabled={hasStock || pending}>
              <Trash2 className="h-4 w-4" />
              Hapus box permanen
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Hapus box permanen?</DialogTitle>
              <DialogDescription>
                Box ini beserta seluruh isi dan riwayat stok/scan-nya akan dihapus permanen dan tidak bisa dikembalikan.
              </DialogDescription>
            </DialogHeader>
            <form action={formAction}>
              <input type="hidden" name="box_id" value={boxId} />
              <DialogFooter>
                <DialogClose asChild>
                  <Button type="button" variant="outline">
                    Batal
                  </Button>
                </DialogClose>
                <Button type="submit" variant="destructive" disabled={pending}>
                  {pending ? "Menghapus..." : "Ya, hapus permanen"}
                </Button>
              </DialogFooter>
            </form>
          </DialogContent>
        </Dialog>
      </CardContent>
    </Card>
  );
}
