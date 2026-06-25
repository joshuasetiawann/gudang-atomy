import Link from "next/link";
import { Eye, Filter, Search } from "lucide-react";
import { PageHeader } from "@/components/layout/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { StatusBadge } from "@/components/tables/StatusBadge";
import { createClient } from "@/lib/supabase/server";
import { formatDate, formatDateTime } from "@/lib/utils";
import type { BoxStatus } from "@/lib/types";

export default async function BoxesPage({ searchParams }: { searchParams: Promise<{ q?: string; status?: string; owner?: string; location?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const search = params.q?.replace(/[%,()]/g, " ").trim();
  let query = supabase
    .from("v_box_summary")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(1000);
  if (search) query = query.or(`id_box.ilike.%${search}%,box_name.ilike.%${search}%`);
  if (params.status === "__empty") {
    query = query.eq("total_product_types", 0);
  } else if (params.status && params.status !== "__all") {
    query = query.eq("status", params.status);
  } else if (params.status !== "__all") {
    query = query.gt("total_product_types", 0);
  }
  if (params.owner) query = query.ilike("owner_name", `%${params.owner}%`);
  if (params.location) query = query.ilike("location_code", `%${params.location}%`);
  const { data } = await query;

  return (
    <div className="app-page space-y-6">
      <PageHeader
        kicker="Box Inventori"
        title="Data Box"
        description="Daftar box dengan filter status, pemilik, dan lokasi."
        action={
          <div className="inline-flex items-center gap-2 rounded-md border bg-background/80 px-3 py-2 text-sm font-medium text-muted-foreground shadow-soft">
            <span className="text-base font-semibold tabular-nums text-foreground">{(data ?? []).length}</span>
            box tampil
          </div>
        }
      />
      <Card>
        <CardContent className="p-4">
          <form className="grid gap-3 md:grid-cols-[1.2fr_1fr_1fr_160px_auto]">
            <div className="relative">
              <label htmlFor="filter-q" className="sr-only">Cari ID box atau label client</label>
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
              <Input id="filter-q" name="q" placeholder="Cari ID box / label client" defaultValue={params.q ?? ""} className="pl-9" />
            </div>
            <div>
              <label htmlFor="filter-owner" className="sr-only">Owner</label>
              <Input id="filter-owner" name="owner" placeholder="Owner" defaultValue={params.owner ?? ""} />
            </div>
            <div>
              <label htmlFor="filter-location" className="sr-only">Lokasi</label>
              <Input id="filter-location" name="location" placeholder="Lokasi" defaultValue={params.location ?? ""} />
            </div>
            <div>
              <label htmlFor="filter-status" className="sr-only">Status</label>
              <select
                id="filter-status"
                name="status"
                defaultValue={params.status ?? ""}
                className="h-10 w-full rounded-md border border-input bg-card px-3 text-sm outline-none transition-all focus-visible:border-primary/50 focus-visible:ring-2 focus-visible:ring-ring"
              >
                <option value="">Box berisi produk</option>
                <option value="__empty">Tanpa isi (kosong)</option>
                <option value="__all">Semua status</option>
                <option value="active">active</option>
                <option value="partial">partial</option>
                <option value="empty">empty</option>
                <option value="taken">taken</option>
                <option value="void">void</option>
              </select>
            </div>
            <Button className="md:w-fit">
              <Filter className="h-4 w-4" aria-hidden="true" />
              Filter
            </Button>
          </form>
        </CardContent>
      </Card>
      {(data ?? []).length ? (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>ID Box App</TableHead>
              <TableHead>Label Client</TableHead>
              <TableHead>Owner</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Expired</TableHead>
              <TableHead>Lokasi</TableHead>
              <TableHead className="text-right">Sisa</TableHead>
              <TableHead>Dibuat</TableHead>
              <TableHead className="text-right">Aksi</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(data ?? []).map((box) => (
              <TableRow key={box.id}>
                <TableCell className="font-mono font-medium text-foreground">{box.id_box}</TableCell>
                <TableCell className="font-medium">{box.box_name}</TableCell>
                <TableCell className="text-muted-foreground">{box.owner_name}</TableCell>
                <TableCell><StatusBadge status={box.status as BoxStatus} /></TableCell>
                <TableCell className="font-mono tabular-nums text-muted-foreground">{formatDate(box.expired_at)}</TableCell>
                <TableCell className="font-mono">{box.location_code ?? <span className="text-muted-foreground">-</span>}</TableCell>
                <TableCell className="text-right font-semibold tabular-nums text-foreground">{box.total_qty_available}</TableCell>
                <TableCell className="font-mono tabular-nums text-muted-foreground">{formatDateTime(box.created_at)}</TableCell>
                <TableCell className="text-right">
                  <Button asChild size="icon" variant="ghost" aria-label={`Detail box ${box.id_box}`}>
                    <Link href={`/boxes/${box.id}`}>
                      <Eye className="h-4 w-4" aria-hidden="true" />
                    </Link>
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : (
        <EmptyState title="Box tidak ditemukan" description="Coba ubah filter atau input barang masuk baru." />
      )}
    </div>
  );
}
