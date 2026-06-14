import { Badge } from "@/components/ui/badge";
import type { BoxStatus } from "@/lib/types";

const labels: Record<BoxStatus, string> = {
  active: "Aktif",
  partial: "Sebagian",
  empty: "Kosong",
  taken: "Diambil",
  void: "Batal"
};

export function StatusBadge({ status }: { status: BoxStatus }) {
  return (
    <Badge variant={status} className="gap-1.5">
      <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-current opacity-70" />
      {labels[status]}
    </Badge>
  );
}
