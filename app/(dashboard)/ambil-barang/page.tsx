import { CheckoutPanel } from "@/components/forms/CheckoutPanel";
import { PageHeader } from "@/components/layout/PageHeader";
import { requireRole } from "@/lib/auth/guards";

export default async function AmbilBarangPage() {
  await requireRole(["super_admin", "admin_gudang"]);
  return (
    <div className="space-y-5">
      <PageHeader kicker="Checkout" title="Ambil Barang" description="Scan QR untuk checkout full box atau per produk." />
      <CheckoutPanel />
    </div>
  );
}
