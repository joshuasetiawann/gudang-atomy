import { CheckoutPanel } from "@/components/forms/CheckoutPanel";
import { PageHeader } from "@/components/layout/PageHeader";
import { requireRole } from "@/lib/auth/guards";

export default async function AmbilBarangPage() {
  await requireRole(["super_admin", "admin_gudang"]);
  return (
    <div className="app-page space-y-6">
      <PageHeader kicker="Pengambilan" title="Ambil Barang" description="Pindai QR untuk mengambil seluruh box atau per produk." />
      <CheckoutPanel />
    </div>
  );
}
