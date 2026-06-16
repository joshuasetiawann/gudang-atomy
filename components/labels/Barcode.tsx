import { code128Bars, code128Modules } from "@/lib/barcode/code128";
import { cn } from "@/lib/utils";

const QUIET_ZONE = 10; // modul kosong di kiri/kanan (quiet zone) agar mudah discan

// Render `value` sebagai barcode 1D (Code 128) berupa garis. Nilai yang
// di-encode sama persis dengan barcode_value, jadi scanner & database tidak
// berubah — hanya tampilannya yang jadi garis, bukan QR.
export function Barcode({
  value,
  className,
  height = 64
}: {
  value: string;
  className?: string;
  height?: number;
}) {
  const modules = code128Modules(value);
  const bars = code128Bars(modules);
  const totalWidth = modules.length + QUIET_ZONE * 2;

  if (!modules) {
    return null;
  }

  return (
    <svg
      className={cn("block h-full w-full", className)}
      viewBox={`0 0 ${totalWidth} ${height}`}
      preserveAspectRatio="none"
      shapeRendering="crispEdges"
      role="img"
      aria-label={value}
    >
      <rect x={0} y={0} width={totalWidth} height={height} fill="#ffffff" />
      {bars.map((bar) => (
        <rect key={bar.x} x={bar.x + QUIET_ZONE} y={0} width={bar.width} height={height} fill="#000000" />
      ))}
    </svg>
  );
}
