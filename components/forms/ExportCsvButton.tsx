"use client";

import { useTransition } from "react";
import { Download } from "lucide-react";
import { exportActiveStockCsvAction } from "@/server/actions/warehouse";
import { Button } from "@/components/ui/button";

export function ExportCsvButton() {
  const [pending, startTransition] = useTransition();

  return (
    <Button
      type="button"
      variant="outline"
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          const result = await exportActiveStockCsvAction();
          if (!result.ok || typeof result.data !== "string") return;
          const blob = new Blob([result.data], { type: "text/csv;charset=utf-8" });
          const url = URL.createObjectURL(blob);
          const link = document.createElement("a");
          link.href = url;
          link.download = `stok-aktif-${new Date().toISOString().slice(0, 10)}.csv`;
          link.click();
          URL.revokeObjectURL(url);
        });
      }}
    >
      <Download className="h-4 w-4" />
      {pending ? "Export..." : "Export CSV"}
    </Button>
  );
}
