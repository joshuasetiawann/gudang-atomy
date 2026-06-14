"use client";

import { useEffect, useMemo, useState } from "react";
import QRCode from "qrcode";
import { Filter, Printer, RotateCcw, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { StatusBadge } from "@/components/tables/StatusBadge";
import { cn, formatDate } from "@/lib/utils";
import type { BoxStatus } from "@/lib/types";

export type PrintResiItem = {
  product_id: string;
  sku: string | null;
  product_name: string;
  unit: string | null;
  qty_initial: number;
  qty_available: number;
  expired_at: string | null;
};

export type PrintResiLabel = {
  id: string;
  box_name: string;
  id_box: string;
  pemilik_id_box: string;
  barcode_value: string;
  expired_at: string | null;
  location_code: string | null;
  status: BoxStatus;
  owner_code: string | null;
  owner_name: string | null;
  items: PrintResiItem[];
};

export type PrintResiProductOption = {
  id: string;
  name: string;
  count: number;
};

export function PrintResiClient({
  labels,
  productOptions
}: {
  labels: PrintResiLabel[];
  productOptions: PrintResiProductOption[];
}) {
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("ready");
  const [productId, setProductId] = useState("");
  const [qrMap, setQrMap] = useState<Record<string, string>>({});

  const filteredLabels = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return labels.filter((label) => {
      const statusMatch =
        status === "all" ||
        (status === "ready" ? label.status === "active" || label.status === "partial" || label.status === "empty" : label.status === status);
      const productMatch = !productId || label.items.some((item) => item.product_id === productId);
      const searchMatch =
        !needle ||
        [
          label.box_name,
          label.id_box,
          label.pemilik_id_box,
          label.owner_code,
          label.owner_name,
          label.location_code,
          ...label.items.flatMap((item) => [item.product_name, item.sku])
        ]
          .filter(Boolean)
          .join(" ")
          .toLowerCase()
          .includes(needle);

      return statusMatch && productMatch && searchMatch;
    });
  }, [labels, productId, search, status]);

  useEffect(() => {
    let alive = true;

    if (filteredLabels.length === 0) return () => {
      alive = false;
    };

    Promise.all(
      filteredLabels.map(async (label) => {
        const url = await QRCode.toDataURL(label.barcode_value, { margin: 1, width: 260 });
        return [label.id, url] as const;
      })
    )
      .then((entries) => {
        if (alive) {
          setQrMap((current) => ({
            ...current,
            ...Object.fromEntries(entries)
          }));
        }
      });

    return () => {
      alive = false;
    };
  }, [filteredLabels]);

  const readyCount = filteredLabels.filter((label) => qrMap[label.id]).length;
  const isPreparing = filteredLabels.length > 0 && readyCount < filteredLabels.length;
  const canPrint = filteredLabels.length > 0 && !isPreparing;

  function resetFilters() {
    setSearch("");
    setStatus("ready");
    setProductId("");
  }

  function printLabels() {
    window.print();
  }

  return (
    <div className="space-y-5">
      <div className="no-print surface-panel rounded-lg border p-4">
        <div className="grid gap-3 lg:grid-cols-[minmax(220px,1fr)_190px_minmax(240px,320px)_auto_auto]">
          <label className="space-y-2">
            <span className="text-xs font-semibold uppercase text-muted-foreground">Cari label</span>
            <div className="relative">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                id="print-search"
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Nama, owner, ID box, lokasi"
                className="pl-9"
              />
            </div>
          </label>
          <label className="space-y-2">
            <span className="text-xs font-semibold uppercase text-muted-foreground">Status</span>
            <select
              value={status}
              onChange={(event) => setStatus(event.target.value)}
              className="h-10 w-full rounded-md border bg-card px-3 text-sm outline-none transition-all focus:border-primary/50 focus:ring-2 focus:ring-ring"
            >
              <option value="ready">Siap ditempel</option>
              <option value="all">Semua status</option>
              <option value="active">Active</option>
              <option value="partial">Partial</option>
              <option value="empty">Empty</option>
              <option value="taken">Taken</option>
              <option value="void">Void</option>
            </select>
          </label>
          <label className="space-y-2">
            <span className="text-xs font-semibold uppercase text-muted-foreground">Pesanan / Produk</span>
            <select
              value={productId}
              onChange={(event) => setProductId(event.target.value)}
              className="h-10 w-full rounded-md border bg-card px-3 text-sm outline-none transition-all focus:border-primary/50 focus:ring-2 focus:ring-ring"
            >
              <option value="">Semua pesanan</option>
              {productOptions.map((option) => (
                <option key={option.id} value={option.id}>
                  {option.name} ({option.count})
                </option>
              ))}
            </select>
          </label>
          <div className="flex items-end">
            <Button type="button" className="w-full lg:w-auto" disabled={!canPrint} onClick={printLabels}>
              <Printer className="h-4 w-4" />
              Print
            </Button>
          </div>
          <div className="flex items-end">
            <Button type="button" className="w-full lg:w-auto" variant="outline" onClick={resetFilters}>
              <RotateCcw className="h-4 w-4" />
              Reset
            </Button>
          </div>
        </div>

        <div className="mt-4 flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
          <span className="inline-flex items-center gap-2 rounded-md border bg-background/70 px-3 py-2">
            <Filter className="h-4 w-4 text-primary" />
            {filteredLabels.length} label terfilter dari {labels.length} box
          </span>
          <span className={cn("rounded-md border bg-background/70 px-3 py-2", canPrint && "text-success")}>
            {filteredLabels.length === 0 ? "Tidak ada label siap print" : `QR siap ${readyCount}/${filteredLabels.length}`}
          </span>
        </div>
      </div>

      {filteredLabels.length ? (
        <div className="print-label-sheet grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {filteredLabels.map((label) => (
            <ResiLabelCard key={label.id} label={label} qrUrl={qrMap[label.id]} />
          ))}
        </div>
      ) : (
        <div className="no-print">
          <EmptyState title="Tidak ada label" description="Ubah filter pesanan, status, atau pencarian untuk menampilkan label box." />
        </div>
      )}
    </div>
  );
}

function ResiLabelCard({ label, qrUrl }: { label: PrintResiLabel; qrUrl?: string }) {
  const visibleItems = label.items.slice(0, 5);
  const hiddenItemCount = Math.max(label.items.length - visibleItems.length, 0);

  return (
    <article className="print-label-card rounded-lg border bg-white p-5 text-slate-950 shadow-soft">
      <div className="relative">
        <h2 className="text-center text-xl font-bold tracking-normal">Gudang Atomy</h2>
        <div className="no-print absolute right-0 top-0">
          <StatusBadge status={label.status} />
        </div>
      </div>

      <div className="mt-4 grid gap-2 text-sm">
        <Row label="Label Client" value={label.box_name} />
        <Row label="ID Box App" value={label.id_box} />
        <Row label="Pemilik" value={label.owner_name ?? "-"} />
        <Row label="Pemilik ID Box" value={label.pemilik_id_box} />
        <Row label="Expired" value={formatDate(label.expired_at)} />
        <Row label="Lokasi" value={label.location_code ?? "-"} />
      </div>

      <div className="mt-3 rounded-md border border-slate-200 bg-slate-50 p-2 text-xs">
        <p className="font-bold">Isi Box</p>
        {visibleItems.length ? (
          <div className="mt-1 space-y-1">
            {visibleItems.map((item) => (
              <div key={`${item.product_id}-${item.sku ?? ""}`} className="grid grid-cols-[1fr_auto] gap-2">
                <span className="break-words">{item.product_name}</span>
                <span className="font-semibold">
                  {item.qty_available} {item.unit ?? "pcs"}
                </span>
              </div>
            ))}
            {hiddenItemCount ? <p className="text-slate-500">+{hiddenItemCount} produk lain</p> : null}
          </div>
        ) : (
          <p className="mt-1 text-slate-500">-</p>
        )}
      </div>

      <div className="mt-4 flex justify-center">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        {qrUrl ? <img src={qrUrl} alt={label.barcode_value} className="h-44 w-44" /> : <div className="skeleton-shimmer h-44 w-44 rounded-md" />}
      </div>
      <p className="mt-2 break-all text-center font-mono text-[11px]">{label.barcode_value}</p>
    </article>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="grid grid-cols-[104px_1fr] gap-2">
      <span className="font-bold">{label}</span>
      <span className="break-words">{value}</span>
    </div>
  );
}
