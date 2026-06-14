"use client";

import { useState, useTransition } from "react";
import { AlertTriangle, CheckCircle2, PackageCheck, ScanLine } from "lucide-react";
import { BarcodeScanner } from "@/components/scanner/BarcodeScanner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { StatusBadge } from "@/components/tables/StatusBadge";
import { checkoutFullBoxAction, checkoutPartialItemAction, lookupBoxByBarcodeAction, type LookupBoxResult } from "@/server/actions/warehouse";
import type { ActionState, BoxItem, BoxStatus } from "@/lib/types";
import { formatDate } from "@/lib/utils";

export function CheckoutPanel() {
  const [box, setBox] = useState<LookupBoxResult | null>(null);
  const [message, setMessage] = useState<ActionState | null>(null);
  const [qtyByProduct, setQtyByProduct] = useState<Record<string, string>>({});
  const [pending, startTransition] = useTransition();

  const disabled = box ? ["taken", "empty", "void"].includes(box.status) : true;

  function lookup(value: string) {
    startTransition(async () => {
      setMessage(null);
      const result = await lookupBoxByBarcodeAction(value);
      setMessage(result);
      if (result.ok) {
        setBox(result.data as LookupBoxResult);
        setQtyByProduct({});
      }
    });
  }

  function refresh() {
    if (box?.barcode_value) lookup(box.barcode_value);
  }

  function checkoutFull() {
    if (!box) return;
    startTransition(async () => {
      const result = await checkoutFullBoxAction(box.barcode_value);
      setMessage(result);
      refresh();
    });
  }

  function checkoutPartial(item: BoxItem) {
    if (!box) return;
    const qty = Number(qtyByProduct[item.product_id] ?? 0);
    startTransition(async () => {
      const result = await checkoutPartialItemAction(box.barcode_value, item.product_id, qty);
      setMessage(result);
      refresh();
    });
  }

  return (
    <div className="grid gap-5 lg:grid-cols-[420px_1fr]">
      <div className="space-y-4">
        <BarcodeScanner onDetected={lookup} />
        {message?.message ? (
          <p className={message.ok ? "rounded-md border border-success/20 bg-success/10 p-3 text-sm font-medium text-success" : "rounded-md border border-destructive/20 bg-destructive/10 p-3 text-sm font-medium text-destructive"}>
            {message.message}
          </p>
        ) : null}
      </div>

      <div className="rounded-lg border bg-card/95 p-5 shadow-card">
        {!box ? (
          <div className="flex min-h-80 flex-col items-center justify-center text-center text-sm text-muted-foreground">
            <div className="mb-4 rounded-lg bg-primary/10 p-4 text-primary">
              <ScanLine className="h-7 w-7" />
            </div>
            <p className="font-medium text-foreground">Belum ada box dipilih</p>
            <p className="mt-1 max-w-sm">Scan QR atau input barcode manual untuk menampilkan detail box.</p>
          </div>
        ) : (
          <div className="space-y-5">
            <div className="flex flex-wrap items-start justify-between gap-3 border-b pb-4">
              <div>
                <h2 className="text-lg font-semibold">{box.box_name}</h2>
                <p className="font-mono text-sm text-muted-foreground">ID Box App: {box.id_box}</p>
              </div>
              <StatusBadge status={box.status as BoxStatus} />
            </div>

            <div className="grid gap-3 text-sm md:grid-cols-2">
              <Info label="Pemilik" value={box.owners?.owner_name ?? "-"} />
              <Info label="Expired" value={formatDate(box.expired_at)} />
              <Info label="Lokasi" value={box.location_code ?? "-"} />
              <Info label="Pemilik ID Box" value={box.pemilik_id_box} />
            </div>

            {disabled ? (
              <div className="flex items-start gap-2 rounded-md bg-warning/15 p-3 text-sm text-warning-foreground">
                <AlertTriangle className="mt-0.5 h-4 w-4" />
                Box dengan status ini tidak bisa diambil lagi.
              </div>
            ) : null}

            <div className="flex flex-wrap gap-2">
              <Dialog>
                <DialogTrigger asChild>
                  <Button disabled={disabled || pending} variant="destructive">
                    <PackageCheck className="h-4 w-4" />
                    Ambil Semua Box
                  </Button>
                </DialogTrigger>
                <DialogContent>
                  <DialogHeader>
                    <DialogTitle>Konfirmasi ambil semua box</DialogTitle>
                    <DialogDescription>Semua qty_available akan menjadi 0 dan box berubah menjadi taken.</DialogDescription>
                  </DialogHeader>
                  <DialogFooter>
                    <DialogClose asChild>
                      <Button type="button" variant="outline">
                        Batal
                      </Button>
                    </DialogClose>
                    <DialogClose asChild>
                      <Button type="button" variant="destructive" onClick={checkoutFull}>
                        Ambil Semua
                      </Button>
                    </DialogClose>
                  </DialogFooter>
                </DialogContent>
              </Dialog>
            </div>

            <div>
              <h3 className="mb-3 text-sm font-semibold">Ambil Per Produk</h3>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Produk</TableHead>
                    <TableHead>Sisa</TableHead>
                    <TableHead>Ambil</TableHead>
                    <TableHead></TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {box.box_items.map((item) => (
                    <PartialRow
                      key={item.id}
                      item={item}
                      disabled={disabled}
                      pending={pending}
                      qtyValue={qtyByProduct[item.product_id] ?? ""}
                      onQtyChange={(value) => setQtyByProduct((current) => ({ ...current, [item.product_id]: value }))}
                      onCheckout={() => checkoutPartial(item)}
                    />
                  ))}
                </TableBody>
              </Table>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function PartialRow({
  item,
  disabled,
  pending,
  qtyValue,
  onQtyChange,
  onCheckout
}: {
  item: BoxItem;
  disabled: boolean;
  pending: boolean;
  qtyValue: string;
  onQtyChange: (value: string) => void;
  onCheckout: () => void;
}) {
  const qty = Number(qtyValue);
  const available = Number(item.qty_available);
  const invalidQty = !Number.isFinite(qty) || qty <= 0 || qty > available;

  return (
    <TableRow>
      <TableCell>
        <div className="font-medium">{item.products?.product_name ?? item.product_id}</div>
        <div className="text-xs text-muted-foreground">{item.products?.sku ?? "-"}</div>
      </TableCell>
      <TableCell>{item.qty_available}</TableCell>
      <TableCell>
        <Input
          className="w-24"
          type="number"
          min="0"
          max={item.qty_available}
          step="1"
          value={qtyValue}
          onChange={(event) => onQtyChange(event.target.value)}
          disabled={disabled || available <= 0}
        />
      </TableCell>
      <TableCell>
        <Button type="button" size="sm" variant="outline" disabled={disabled || pending || invalidQty} onClick={onCheckout}>
          <CheckCircle2 className="h-4 w-4" />
          Ambil
        </Button>
      </TableCell>
    </TableRow>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border bg-background/70 p-3">
      <p className="text-xs font-medium text-muted-foreground">{label}</p>
      <p className="mt-1 break-words font-semibold">{value}</p>
    </div>
  );
}
