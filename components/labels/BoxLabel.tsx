"use client";

import { Printer } from "lucide-react";
import { QrCodeImage } from "@/components/labels/QrCodeImage";
import { Button } from "@/components/ui/button";
import { cn, formatDate } from "@/lib/utils";

type LabelBox = {
  box_name: string;
  id_box: string;
  pemilik_id_box: string;
  barcode_value: string;
  expired_at: string | null;
  location_code: string | null;
  owners?: {
    owner_name: string;
  } | null;
};

export function BoxLabel({ box }: { box: LabelBox }) {
  return (
    <div className="space-y-4">
      <div className="print-page w-full max-w-md rounded-lg border bg-white p-5 text-slate-950 shadow-soft">
        <h2 className="text-center text-xl font-bold tracking-normal">Gudang Atomy</h2>
        <div className="mx-auto mt-2 h-px w-16 bg-slate-200" />
        <div className="mt-4 grid gap-2 text-sm">
          <Row label="Produk" value={box.box_name} />
          <Row label="ID Box App" value={box.id_box} mono />
          <Row label="Pemilik" value={box.owners?.owner_name ?? "-"} />
          <Row label="Pemilik ID Box" value={box.pemilik_id_box} mono />
          <Row label="Expired" value={formatDate(box.expired_at)} mono />
          <Row label="Lokasi" value={box.location_code ?? "-"} mono />
        </div>
        <div className="mt-5 flex justify-center">
          <QrCodeImage value={box.barcode_value} className="h-52 w-52" />
        </div>
        <p className="mt-3 break-all text-center font-mono text-xs tracking-tight">{box.id_box}</p>
      </div>
      <Button type="button" className="no-print w-full sm:w-auto" onClick={() => window.print()}>
        <Printer className="h-4 w-4" />
        Print
      </Button>
    </div>
  );
}

function Row({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="grid grid-cols-[110px_1fr] gap-2">
      <span className="font-semibold">{label}</span>
      <span className={cn("break-words", mono && "font-mono text-[13px] tracking-tight")}>{value}</span>
    </div>
  );
}
