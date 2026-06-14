"use client";

import { useEffect, useState } from "react";
import QRCode from "qrcode";
import { Printer } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatDate } from "@/lib/utils";

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
  const [qrUrl, setQrUrl] = useState("");

  useEffect(() => {
    QRCode.toDataURL(box.barcode_value, { margin: 1, width: 280 }).then(setQrUrl);
  }, [box.barcode_value]);

  return (
    <div className="space-y-4">
      <div className="print-page w-full max-w-md rounded-lg border bg-white p-5 text-slate-950 shadow-soft">
        <h2 className="text-center text-xl font-bold">Gudang Atomy</h2>
        <div className="mt-4 grid gap-2 text-sm">
          <Row label="Label Client" value={box.box_name} />
          <Row label="ID Box App" value={box.id_box} />
          <Row label="Pemilik" value={box.owners?.owner_name ?? "-"} />
          <Row label="Pemilik ID Box" value={box.pemilik_id_box} />
          <Row label="Expired" value={formatDate(box.expired_at)} />
          <Row label="Lokasi" value={box.location_code ?? "-"} />
        </div>
        <div className="mt-5 flex justify-center">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {qrUrl ? <img src={qrUrl} alt={box.barcode_value} className="h-52 w-52" /> : <div className="h-52 w-52 bg-muted" />}
        </div>
        <p className="mt-3 break-all text-center font-mono text-xs">{box.barcode_value}</p>
      </div>
      <Button type="button" className="no-print" onClick={() => window.print()}>
        <Printer className="h-4 w-4" />
        Print
      </Button>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="grid grid-cols-[110px_1fr] gap-2">
      <span className="font-semibold">{label}</span>
      <span className="break-words">{value}</span>
    </div>
  );
}
