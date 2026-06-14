"use client";

import { useMemo, useState, useTransition } from "react";
import Papa from "papaparse";
import { AlertTriangle, CheckCircle2, Upload } from "lucide-react";
import { importCsvRowsAction } from "@/server/actions/warehouse";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import type { ActionState } from "@/lib/types";

const importTypes = [
  { value: "owners", label: "Owners", required: ["owner_code", "owner_name"] },
  { value: "products", label: "Products", required: ["product_name"] },
  { value: "packages", label: "Packages", required: ["package_code", "package_name"] },
  { value: "package_items", label: "Package Items", required: ["package_code", "sku", "qty_per_package"] },
  { value: "boxes", label: "Boxes", required: ["id_box", "owner_code", "box_name"] },
  { value: "box_items", label: "Box Items", required: ["id_box", "sku", "qty_initial", "qty_available"] }
];

export function CsvImportPanel() {
  return (
    <Tabs defaultValue="owners" className="app-page">
      <TabsList className="flex h-auto flex-wrap gap-1">
        {importTypes.map((type) => (
          <TabsTrigger key={type.value} value={type.value}>
            {type.label}
          </TabsTrigger>
        ))}
      </TabsList>
      {importTypes.map((type) => (
        <TabsContent key={type.value} value={type.value}>
          <CsvImportTab importType={type.value} required={type.required} />
        </TabsContent>
      ))}
    </Tabs>
  );
}

function CsvImportTab({ importType, required }: { importType: string; required: string[] }) {
  const [fileName, setFileName] = useState("");
  const [rows, setRows] = useState<Array<Record<string, string>>>([]);
  const [message, setMessage] = useState<ActionState | null>(null);
  const [pending, startTransition] = useTransition();

  const errors = useMemo(() => {
    return rows.flatMap((row, index) =>
      required
        .filter((field) => !row[field])
        .map((field) => `Baris ${index + 2}: ${field} wajib diisi`)
    );
  }, [required, rows]);

  function parseFile(file: File) {
    setFileName(file.name);
    Papa.parse<Record<string, string>>(file, {
      header: true,
      skipEmptyLines: true,
      complete(result) {
        setRows(result.data.map((row) => Object.fromEntries(Object.entries(row).map(([key, value]) => [key.trim(), String(value ?? "").trim()]))));
      }
    });
  }

  function submit() {
    startTransition(async () => {
      const validRows = rows.filter((row) => required.every((field) => row[field]));
      const result = await importCsvRowsAction(importType, fileName, validRows);
      setMessage(result);
    });
  }

  const headers = Object.keys(rows[0] ?? {});

  return (
    <div className="space-y-4 rounded-lg border bg-card/95 p-5 shadow-card backdrop-blur-sm">
      <div className="grid gap-3 md:grid-cols-[1fr_auto]">
        <Input type="file" accept=".csv,text/csv" onChange={(event) => event.target.files?.[0] && parseFile(event.target.files[0])} className="cursor-pointer file:mr-3 file:cursor-pointer file:rounded-sm file:px-2 file:py-1 file:text-primary" />
        <Button type="button" onClick={submit} disabled={!rows.length || errors.length > 0 || pending}>
          <Upload className="h-4 w-4" />
          {pending ? "Import..." : "Import"}
        </Button>
      </div>

      <div className="flex flex-wrap items-center gap-1.5 text-sm text-muted-foreground">
        <span className="font-medium">Kolom wajib:</span>
        {required.map((field) => (
          <span key={field} className="inline-flex items-center rounded-sm bg-primary/10 px-2 py-0.5 font-mono text-xs font-medium text-primary">
            {field}
          </span>
        ))}
      </div>
      {errors.length ? (
        <div role="alert" className="animate-rise max-h-40 space-y-1 overflow-auto rounded-md border border-destructive/20 bg-destructive/10 p-3 text-sm text-destructive">
          <p className="mb-1 flex items-center gap-2 font-semibold">
            <AlertTriangle className="h-4 w-4 shrink-0" />
            {errors.length} kesalahan ditemukan
          </p>
          {errors.slice(0, 20).map((error) => (
            <p key={error} className="pl-6">{error}</p>
          ))}
        </div>
      ) : null}
      {message?.message ? (
        <p
          role="status"
          aria-live="polite"
          className={
            message.ok
              ? "animate-rise flex items-start gap-2 rounded-md border border-success/20 bg-success/10 p-3 text-sm font-medium text-success"
              : "animate-rise flex items-start gap-2 rounded-md border border-destructive/20 bg-destructive/10 p-3 text-sm font-medium text-destructive"
          }
        >
          {message.ok ? <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" /> : <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />}
          <span>{message.message}</span>
        </p>
      ) : null}

      {rows.length ? (
        <div className="space-y-2">
          <p className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
            Pratinjau <span className="font-mono tabular-nums">{Math.min(rows.length, 10)}</span> dari <span className="font-mono tabular-nums">{rows.length}</span> baris
          </p>
          <Table>
            <TableHeader>
              <TableRow>
                {headers.map((header) => (
                  <TableHead key={header} className="font-mono normal-case">{header}</TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.slice(0, 10).map((row, index) => (
                <TableRow key={index}>
                  {headers.map((header) => (
                    <TableCell key={header} className="font-mono text-xs">{row[header]}</TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      ) : null}
    </div>
  );
}
