"use client";

import { useMemo, useState, useTransition } from "react";
import Papa from "papaparse";
import { Upload } from "lucide-react";
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
    <Tabs defaultValue="owners">
      <TabsList className="flex h-auto flex-wrap">
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
    <div className="space-y-4 rounded-lg border bg-card p-4 shadow-soft">
      <div className="grid gap-3 md:grid-cols-[1fr_auto]">
        <Input type="file" accept=".csv,text/csv" onChange={(event) => event.target.files?.[0] && parseFile(event.target.files[0])} />
        <Button type="button" onClick={submit} disabled={!rows.length || errors.length > 0 || pending}>
          <Upload className="h-4 w-4" />
          {pending ? "Import..." : "Import"}
        </Button>
      </div>

      <p className="text-sm text-muted-foreground">Kolom wajib: {required.join(", ")}</p>
      {errors.length ? (
        <div className="max-h-40 overflow-auto rounded-md bg-destructive/10 p-3 text-sm text-destructive">
          {errors.slice(0, 20).map((error) => (
            <p key={error}>{error}</p>
          ))}
        </div>
      ) : null}
      {message?.message ? (
        <p className={message.ok ? "rounded-md bg-success/10 p-3 text-sm text-success" : "rounded-md bg-destructive/10 p-3 text-sm text-destructive"}>
          {message.message}
        </p>
      ) : null}

      {rows.length ? (
        <Table>
          <TableHeader>
            <TableRow>
              {headers.map((header) => (
                <TableHead key={header}>{header}</TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.slice(0, 10).map((row, index) => (
              <TableRow key={index}>
                {headers.map((header) => (
                  <TableCell key={header}>{row[header]}</TableCell>
                ))}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : null}
    </div>
  );
}
