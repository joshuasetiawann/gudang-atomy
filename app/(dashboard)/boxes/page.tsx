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
  if (params.status) query = query.eq("status", params.status);
  if (params.owner) query = query.ilike("owner_name", `%${params.owner}%`);
  if (params.location) query = query.ilike("location_code", `%${params.location}%`);
  const { data } = await query;

  return (
    <div className="space-y-5">
      <PageHeader
        kicker="Inventory Boxes"
        title="Data Box"
        description="Daftar box dengan filter status, owner, dan lokasi."
        action={
          <div className="rounded-md border bg-background/80 px-3 py-2 text-sm font-medium text-muted-foreground">
            {(data ?? []).length} box tampil
          </div>
        }
      />
      <Card>
        <CardContent className="p-4">
          <form className="grid gap-3 md:grid-cols-[1.2fr_1fr_1fr_160px_auto]">
            <div className="relative">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input name="q" placeholder="Search ID Box / label client" defaultValue={params.q ?? ""} className="pl-9" />
            </div>
            <Input name="owner" placeholder="Owner" defaultValue={params.owner ?? ""} />
            <Input name="location" placeholder="Lokasi" defaultValue={params.location ?? ""} />
            <select
              name="status"
              defaultValue={params.status ?? ""}
              className="h-10 rounded-md border bg-card px-3 text-sm outline-none transition-all focus:border-primary/50 focus:ring-2 focus:ring-ring"
            >
              <option value="">Semua status</option>
              <option value="active">active</option>
              <option value="partial">partial</option>
              <option value="empty">empty</option>
              <option value="taken">taken</option>
              <option value="void">void</option>
            </select>
            <Button className="md:w-fit">
              <Filter className="h-4 w-4" />
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
              <TableHead>Sisa</TableHead>
              <TableHead>Dibuat</TableHead>
              <TableHead></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(data ?? []).map((box) => (
              <TableRow key={box.id}>
                <TableCell className="font-mono">{box.id_box}</TableCell>
                <TableCell>{box.box_name}</TableCell>
                <TableCell>{box.owner_name}</TableCell>
                <TableCell><StatusBadge status={box.status as BoxStatus} /></TableCell>
                <TableCell>{formatDate(box.expired_at)}</TableCell>
                <TableCell>{box.location_code ?? "-"}</TableCell>
                <TableCell>{box.total_qty_available}</TableCell>
                <TableCell>{formatDateTime(box.created_at)}</TableCell>
                <TableCell>
                  <Button asChild size="icon" variant="ghost" aria-label="Detail box">
                    <Link href={`/boxes/${box.id}`}>
                      <Eye className="h-4 w-4" />
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
