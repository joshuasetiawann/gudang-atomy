"use client";

import { useMemo, useState } from "react";
import { CheckSquare, Filter, Printer, RotateCcw, Search, Square } from "lucide-react";
import { Barcode } from "@/components/labels/Barcode";
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
  // Simpan ID yang TIDAK dipilih. Dengan begitu label baru (hasil filter) otomatis ikut tercetak.
  const [excludedIds, setExcludedIds] = useState<Set<string>>(() => new Set());

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

  const selectedLabels = useMemo(
    () => filteredLabels.filter((label) => !excludedIds.has(label.id)),
    [filteredLabels, excludedIds]
  );
  const selectedCount = selectedLabels.length;
  const allSelected = filteredLabels.length > 0 && selectedCount === filteredLabels.length;
  const canPrint = selectedCount > 0;

  function toggleLabel(id: string) {
    setExcludedIds((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function selectAll() {
    setExcludedIds(new Set());
  }

  function clearSelection() {
    setExcludedIds(new Set(filteredLabels.map((label) => label.id)));
  }

  function resetFilters() {
    setSearch("");
    setStatus("ready");
    setProductId("");
    setExcludedIds(new Set());
  }

  function printLabels() {
    window.print();
  }

  return (
    <div className="space-y-5">
      <div className="no-print surface-panel rounded-lg border p-4">
        <div className="grid gap-3 lg:grid-cols-[minmax(220px,1fr)_190px_minmax(220px,300px)]">
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
              className="h-10 w-full rounded-md border bg-card px-3 text-sm shadow-soft outline-none transition-all duration-200 focus:border-primary/50 focus:ring-2 focus:ring-ring"
            >
              <option value="ready">Siap ditempel</option>
              <option value="all">Semua status</option>
              <option value="active">Aktif</option>
              <option value="partial">Sebagian</option>
              <option value="empty">Kosong</option>
              <option value="taken">Diambil</option>
              <option value="void">Batal</option>
            </select>
          </label>
          <label className="space-y-2">
            <span className="text-xs font-semibold uppercase text-muted-foreground">Pesanan / Produk</span>
            <select
              value={productId}
              onChange={(event) => setProductId(event.target.value)}
              className="h-10 w-full rounded-md border bg-card px-3 text-sm shadow-soft outline-none transition-all duration-200 focus:border-primary/50 focus:ring-2 focus:ring-ring"
            >
              <option value="">Semua pesanan</option>
              {productOptions.map((option) => (
                <option key={option.id} value={option.id}>
                  {option.name} ({option.count})
                </option>
              ))}
            </select>
          </label>
        </div>

        <div className="mt-4 flex flex-col gap-3 border-t pt-4 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
          <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
            <span className="inline-flex items-center gap-2 rounded-md border bg-background/70 px-3 py-2 shadow-soft">
              <Filter className="h-4 w-4 text-primary" />
              <span>
                <span className="font-mono font-semibold tabular-nums text-foreground">{filteredLabels.length}</span> label terfilter dari{" "}
                <span className="font-mono tabular-nums text-foreground">{labels.length}</span> box
              </span>
            </span>
            <span
              className={cn(
                "inline-flex items-center gap-2 rounded-md border bg-background/70 px-3 py-2 shadow-soft transition-colors duration-200",
                canPrint && "border-success/30 bg-success/10 text-success"
              )}
            >
              {canPrint ? <span className="h-1.5 w-1.5 rounded-full bg-success" /> : null}
              <span>
                Dipilih cetak <span className="font-mono font-semibold tabular-nums">{selectedCount}</span>/
                <span className="font-mono tabular-nums">{filteredLabels.length}</span>
              </span>
            </span>
          </div>

          <div className="grid grid-cols-2 gap-2 sm:flex sm:flex-wrap sm:items-center">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={allSelected ? clearSelection : selectAll}
              disabled={filteredLabels.length === 0}
            >
              {allSelected ? <Square className="h-4 w-4" /> : <CheckSquare className="h-4 w-4" />}
              {allSelected ? "Kosongkan" : "Pilih semua"}
            </Button>
            <Button type="button" variant="outline" size="sm" onClick={resetFilters}>
              <RotateCcw className="h-4 w-4" />
              Reset
            </Button>
            <Button type="button" size="sm" className="col-span-2 sm:col-span-1" disabled={!canPrint} onClick={printLabels}>
              <Printer className="h-4 w-4" />
              Print {selectedCount > 0 ? `(${selectedCount})` : ""}
            </Button>
          </div>
        </div>
      </div>

      {filteredLabels.length ? (
        <div className="print-label-sheet grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {filteredLabels.map((label) => (
            <ResiLabelCard
              key={label.id}
              label={label}
              selected={!excludedIds.has(label.id)}
              onToggle={() => toggleLabel(label.id)}
            />
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

function ResiLabelCard({
  label,
  selected,
  onToggle
}: {
  label: PrintResiLabel;
  selected: boolean;
  onToggle: () => void;
}) {
  const visibleItems = label.items.slice(0, 4);
  const hiddenItemCount = Math.max(label.items.length - visibleItems.length, 0);

  return (
    <article
      className={cn(
        "print-label-card relative flex flex-col rounded-lg border bg-white p-4 text-slate-950 shadow-soft transition-all duration-200",
        // Label yang tidak dipilih tidak ikut tercetak, dan diredupkan di layar.
        selected ? "hover:shadow-lift" : "no-print opacity-45 grayscale"
      )}
    >
      <div className="print-screen-label flex min-h-full flex-col">
        <label className="no-print absolute left-3 top-3 z-10 flex cursor-pointer items-center gap-2 rounded-md bg-white/90 px-2 py-1 text-xs font-medium text-slate-600 shadow-soft ring-1 ring-slate-200">
          <input type="checkbox" checked={selected} onChange={onToggle} className="h-4 w-4 accent-emerald-600" />
          Cetak
        </label>
        <div className="no-print absolute right-3 top-3 z-10">
          <StatusBadge status={label.status} />
        </div>

        <h2 className="mt-1 text-center text-lg font-bold tracking-normal print:text-base">Gudang Atomy</h2>

        <div className="mt-3 grid gap-1.5 text-[13px] print:gap-1 print:text-xs">
          <Row label="Label Client" value={label.box_name} />
          <Row label="ID Box App" value={label.id_box} mono />
          <Row label="Pemilik" value={label.owner_name ?? "-"} />
          <Row label="Pemilik ID Box" value={label.pemilik_id_box} mono />
          <div className="grid grid-cols-2 gap-2">
            <Row label="Expired" value={formatDate(label.expired_at)} mono compact />
            <Row label="Lokasi" value={label.location_code ?? "-"} mono compact />
          </div>
        </div>

        <div className="mt-2 rounded-md border border-slate-200 bg-slate-50 p-2 text-[11px]">
          <p className="font-bold uppercase tracking-wide text-slate-600">Isi box</p>
          {visibleItems.length ? (
            <div className="mt-1 space-y-0.5">
              {visibleItems.map((item) => (
                <div key={`${item.product_id}-${item.sku ?? ""}`} className="grid grid-cols-[1fr_auto] gap-2">
                  <span className="truncate">{item.product_name}</span>
                  <span className="font-semibold tabular-nums">
                    {item.qty_available} {item.unit ?? "pcs"}
                  </span>
                </div>
              ))}
              {hiddenItemCount ? (
                <p className="text-slate-500">
                  +<span className="tabular-nums">{hiddenItemCount}</span> produk lain
                </p>
              ) : null}
            </div>
          ) : (
            <p className="mt-1 text-slate-500">-</p>
          )}
        </div>

        <div className="mt-auto pt-3">
          <div className="h-14 w-full">
            <Barcode value={label.barcode_value} />
          </div>
          <p className="mt-1 break-all text-center font-mono text-[10px] leading-tight tracking-tight">{label.barcode_value}</p>
        </div>
      </div>

      <div className="print-compact-label">
        <div>
          <p className="text-[9px] font-bold uppercase tracking-wide text-slate-500">Label Client</p>
          <p className="print-compact-client mt-1 text-center text-[15px] font-bold leading-snug text-slate-950">{label.box_name}</p>
        </div>
        <div className="print-compact-barcode h-16 w-full">
          <Barcode value={label.barcode_value} />
        </div>
        <p className="break-all text-center font-mono text-[10px] leading-tight tracking-tight">{label.barcode_value}</p>
      </div>
    </article>
  );
}

function Row({ label, value, mono, compact }: { label: string; value: string; mono?: boolean; compact?: boolean }) {
  return (
    <div className={cn("grid gap-2", compact ? "grid-cols-[1fr]" : "grid-cols-[104px_1fr] print:grid-cols-[92px_1fr]")}>
      <span className={cn("font-bold", compact && "text-[10px] uppercase tracking-wide text-slate-500")}>{label}</span>
      <span className={cn("break-words", mono && "font-mono text-[12px] tracking-tight")}>{value}</span>
    </div>
  );
}
