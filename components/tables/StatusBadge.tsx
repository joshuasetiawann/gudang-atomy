import { Badge } from "@/components/ui/badge";
import type { BoxStatus } from "@/lib/types";

const labels: Record<BoxStatus, string> = {
  active: "Active",
  partial: "Partial",
  empty: "Empty",
  taken: "Taken",
  void: "Void"
};

export function StatusBadge({ status }: { status: BoxStatus }) {
  return <Badge variant={status}>{labels[status]}</Badge>;
}
