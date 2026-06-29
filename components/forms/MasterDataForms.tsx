"use client";

import { useActionState, useMemo, useState } from "react";
import Link from "next/link";
import { Activity, AlertTriangle, CheckCircle2, Eye, EyeOff, KeyRound, Plus, Save, Trash2 } from "lucide-react";
import {
  createOwnerAction,
  createAdminUserAction,
  createPackageAction,
  createProductAction,
  deleteAdminUserAction,
  deleteOwnerAction,
  resetUserPasswordAction,
  updateOwnerAction,
  updatePackageAction,
  updateProductAction,
  updateProfileRoleAction
} from "@/server/actions/warehouse";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { EmptyState } from "@/components/ui/empty-state";
import { cn, roleLabel } from "@/lib/utils";
import type { ActionState, Owner, PackageTemplate, PackageTemplateItem, Product, Profile, UserRole } from "@/lib/types";

const initialState: ActionState = { ok: true, message: "" };

export function OwnerManager({ owners, canEdit, canDelete = false }: { owners: Owner[]; canEdit: boolean; canDelete?: boolean }) {
  const [state, formAction, pending] = useActionState(createOwnerAction, initialState);

  return (
    <div className="app-page space-y-5">
      {canEdit ? (
        <Card>
          <CardHeader>
            <CardTitle>Tambah Owner</CardTitle>
            <CardDescription>Buat pemilik baru untuk penerimaan box.</CardDescription>
          </CardHeader>
          <CardContent>
            <form action={formAction} className="grid gap-3 md:grid-cols-2">
              <Input name="owner_code" placeholder="OWN-000001, kosongkan untuk otomatis" className="font-mono" />
              <Input name="owner_name" placeholder="Nama pemilik" required />
              <Input name="phone" placeholder="Nomor HP" className="font-mono" />
              <Input name="atomy_member_id" placeholder="Atomy member ID" className="font-mono" />
              <Textarea name="notes" placeholder="Catatan" className="md:col-span-2" />
              <label className="flex items-center gap-2 text-sm font-medium">
                <input type="checkbox" name="is_active" defaultChecked className="h-4 w-4 rounded-sm border-input text-primary accent-primary focus-visible:ring-2 focus-visible:ring-ring" />
                Aktif
              </label>
              <SubmitMessage state={state} />
              <Button disabled={pending} className="md:w-fit">
                <Plus className="h-4 w-4" />
                Tambah
              </Button>
            </form>
          </CardContent>
        </Card>
      ) : null}

      <div className="grid gap-3">
        {owners.length ? owners.map((owner) => <OwnerRow key={owner.id} owner={owner} canEdit={canEdit} canDelete={canDelete} />) : <EmptyState title="Belum ada owner" description="Tambahkan pemilik pertama agar barang masuk bisa dibuat." />}
      </div>
    </div>
  );
}

function OwnerRow({ owner, canEdit, canDelete }: { owner: Owner; canEdit: boolean; canDelete: boolean }) {
  const [state, formAction, pending] = useActionState(updateOwnerAction, initialState);
  if (!canEdit) {
    return (
      <Card>
        <CardContent className="p-4">
          <p className="font-medium">{owner.owner_name}</p>
          <p className="font-mono text-sm text-muted-foreground">{owner.owner_code}</p>
        </CardContent>
      </Card>
    );
  }
  return (
    <Card>
      <CardContent className="space-y-3 p-4">
        <form action={formAction} className="grid items-center gap-3 md:grid-cols-[140px_minmax(180px,1fr)_150px_170px_minmax(180px,1fr)_80px_auto]">
          <input type="hidden" name="id" value={owner.id} />
          <Input name="owner_code" defaultValue={owner.owner_code} className="font-mono" />
          <Input name="owner_name" defaultValue={owner.owner_name} required />
          <Input name="phone" defaultValue={owner.phone ?? ""} className="font-mono" />
          <Input name="atomy_member_id" defaultValue={owner.atomy_member_id ?? ""} className="font-mono" />
          <Input name="notes" defaultValue={owner.notes ?? ""} />
          <label className="flex items-center gap-2 text-sm font-medium">
            <input type="checkbox" name="is_active" defaultChecked={owner.is_active} className="h-4 w-4 rounded-sm border-input text-primary accent-primary focus-visible:ring-2 focus-visible:ring-ring" />
            Aktif
          </label>
          <Button disabled={pending} size="sm" variant="outline">
            <Save className="h-4 w-4" />
            Simpan
          </Button>
          <SubmitMessage state={state} compact className="md:col-span-7" />
        </form>
        {canDelete ? (
          <div className="flex justify-end border-t pt-3">
            <DeleteConfirm
              action={deleteOwnerAction}
              id={owner.id}
              triggerLabel="Hapus owner"
              title="Hapus owner permanen?"
              description={`Owner "${owner.owner_name}" akan dihapus permanen. Owner yang masih punya box harus dikosongkan dari box-nya dulu.`}
            />
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}

export type ProductPrintSummary = { printed: number; unprinted: number };
export type ProductPrintSummaryMap = Record<string, ProductPrintSummary>;

export function ProductManager({
  products,
  canEdit,
  printSummary = {}
}: {
  products: Product[];
  canEdit: boolean;
  printSummary?: ProductPrintSummaryMap;
}) {
  const [state, formAction, pending] = useActionState(createProductAction, initialState);

  return (
    <div className="app-page space-y-5">
      {canEdit ? (
        <Card>
          <CardHeader>
            <CardTitle>Tambah Produk</CardTitle>
            <CardDescription>Tambah produk inventory atau komponen paket.</CardDescription>
          </CardHeader>
          <CardContent>
            <form action={formAction} className="grid gap-3 md:grid-cols-2">
              <Input name="sku" placeholder="SKU" className="font-mono" />
              <Input name="product_name" placeholder="Nama produk" required />
              <Input name="category" placeholder="Kategori" />
              <Input name="unit" placeholder="pcs" defaultValue="pcs" />
              <Input name="default_barcode" placeholder="Barcode produk opsional" className="font-mono" />
              <label className="flex items-center gap-2 text-sm font-medium">
                <input type="checkbox" name="is_active" defaultChecked className="h-4 w-4 rounded-sm border-input text-primary accent-primary focus-visible:ring-2 focus-visible:ring-ring" />
                Aktif
              </label>
              <SubmitMessage state={state} />
              <Button disabled={pending} className="md:w-fit">
                <Plus className="h-4 w-4" />
                Tambah
              </Button>
            </form>
          </CardContent>
        </Card>
      ) : null}

      <div className="grid gap-3">
        {products.length ? products.map((product) => <ProductRow key={product.id} product={product} canEdit={canEdit} summary={printSummary[product.id]} />) : <EmptyState title="Belum ada produk" description="Tambahkan master produk sebelum membuat box." />}
      </div>
    </div>
  );
}

function ProductPrintSummaryBadge({ summary }: { summary?: ProductPrintSummary }) {
  if (!summary || summary.printed + summary.unprinted === 0) return null;
  return (
    <span className="inline-flex flex-wrap items-center gap-1.5 text-xs">
      <span className="inline-flex items-center gap-1 rounded-md bg-success/10 px-2 py-0.5 font-medium text-success">
        Diprint <span className="tabular-nums">{summary.printed}</span>
      </span>
      <span className="inline-flex items-center gap-1 rounded-md bg-warning/10 px-2 py-0.5 font-medium text-warning">
        Belum <span className="tabular-nums">{summary.unprinted}</span>
      </span>
    </span>
  );
}

function ProductRow({ product, canEdit, summary }: { product: Product; canEdit: boolean; summary?: ProductPrintSummary }) {
  const [state, formAction, pending] = useActionState(updateProductAction, initialState);
  if (!canEdit) {
    return (
      <Card>
        <CardContent className="space-y-2 p-4 sm:p-5">
          <p className="font-medium">{product.product_name}</p>
          <p className="font-mono text-sm text-muted-foreground">{product.sku ?? "-"}</p>
          <ProductPrintSummaryBadge summary={summary} />
        </CardContent>
      </Card>
    );
  }
  return (
    <Card>
      <CardContent className="space-y-3 p-4 sm:p-5">
        {summary && summary.printed + summary.unprinted > 0 ? (
          <div className="flex items-center justify-between gap-2">
            <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Status print label</span>
            <ProductPrintSummaryBadge summary={summary} />
          </div>
        ) : null}
        <form action={formAction} className="grid items-center gap-3 md:grid-cols-[150px_minmax(220px,1.4fr)_170px_100px_minmax(180px,1fr)_80px_auto]">
          <input type="hidden" name="id" value={product.id} />
          <Input name="sku" defaultValue={product.sku ?? ""} className="font-mono" />
          <Input name="product_name" defaultValue={product.product_name} required />
          <Input name="category" defaultValue={product.category ?? ""} />
          <Input name="unit" defaultValue={product.unit ?? "pcs"} />
          <Input name="default_barcode" defaultValue={product.default_barcode ?? ""} className="font-mono" />
          <label className="flex items-center gap-2 text-sm font-medium">
            <input type="checkbox" name="is_active" defaultChecked={product.is_active} className="h-4 w-4 rounded-sm border-input text-primary accent-primary focus-visible:ring-2 focus-visible:ring-ring" />
            Aktif
          </label>
          <Button disabled={pending} size="sm" variant="outline">
            <Save className="h-4 w-4" />
            Simpan
          </Button>
          <SubmitMessage state={state} compact className="md:col-span-7" />
        </form>
      </CardContent>
    </Card>
  );
}

type PackageItemDraft = {
  product_id: string;
  qty_per_package: number;
};

export function PackageBuilder({
  products,
  initialPackage,
  initialItems,
  mode
}: {
  products: Product[];
  initialPackage?: PackageTemplate;
  initialItems?: PackageTemplateItem[];
  mode: "create" | "update";
}) {
  const action = mode === "create" ? createPackageAction : updatePackageAction;
  const [state, formAction, pending] = useActionState(action, initialState);
  const [items, setItems] = useState<PackageItemDraft[]>(
    initialItems?.length
      ? initialItems.map((item) => ({ product_id: item.product_id, qty_per_package: Number(item.qty_per_package) }))
      : [{ product_id: "", qty_per_package: 1 }]
  );
  const itemsJson = useMemo(() => JSON.stringify(items.filter((item) => item.product_id && Number(item.qty_per_package) > 0)), [items]);
  const hasPackageItem = items.some((item) => item.product_id && Number(item.qty_per_package) > 0);

  function updateItem(index: number, patch: Partial<PackageItemDraft>) {
    setItems((current) => current.map((item, itemIndex) => (itemIndex === index ? { ...item, ...patch } : item)));
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{mode === "create" ? "Tambah Paket" : "Edit Paket"}</CardTitle>
        <CardDescription>Atur template paket dan daftar produk di dalamnya.</CardDescription>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="space-y-4">
          <input type="hidden" name="id" value={initialPackage?.id ?? ""} />
          <input type="hidden" name="items_json" value={itemsJson} />
          <div className="grid gap-3 md:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="package_code">Kode paket</Label>
              <Input id="package_code" name="package_code" defaultValue={initialPackage?.package_code ?? ""} required className="font-mono" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="package_name">Nama paket</Label>
              <Input id="package_name" name="package_name" defaultValue={initialPackage?.package_name ?? ""} required />
            </div>
            <Textarea name="description" defaultValue={initialPackage?.description ?? ""} placeholder="Deskripsi" className="md:col-span-2" />
            <label className="flex items-center gap-2 text-sm font-medium">
              <input type="checkbox" name="is_active" defaultChecked={initialPackage?.is_active ?? true} className="h-4 w-4 rounded-sm border-input text-primary accent-primary focus-visible:ring-2 focus-visible:ring-ring" />
              Aktif
            </label>
          </div>
          <div className="space-y-3">
            {products.length ? (
              items.length ? (
                items.map((item, index) => (
                  <div key={index} className="grid items-center gap-3 rounded-md border bg-background/65 p-3 transition-colors hover:border-primary/30 md:grid-cols-[1fr_120px_40px]">
                    <select
                      className="h-10 rounded-md border bg-card px-3 text-sm outline-none transition-all focus-visible:border-primary/50 focus-visible:ring-2 focus-visible:ring-ring"
                      value={item.product_id}
                      onChange={(event) => updateItem(index, { product_id: event.target.value })}
                    >
                      <option value="" disabled>
                        Pilih produk
                      </option>
                      {products.map((product) => (
                        <option key={product.id} value={product.id}>
                          {product.sku ? `${product.sku} - ` : ""}
                          {product.product_name}
                        </option>
                      ))}
                    </select>
                    <Input
                      type="number"
                      min="1"
                      step="1"
                      value={item.qty_per_package}
                      onChange={(event) => updateItem(index, { qty_per_package: Number(event.target.value) })}
                      className="tabular-nums"
                    />
                    <Button type="button" size="icon" variant="ghost" aria-label="Hapus produk" onClick={() => setItems((current) => current.filter((_, itemIndex) => itemIndex !== index))} className="text-muted-foreground hover:text-destructive">
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                ))
              ) : (
                <EmptyState title="Belum ada produk di paket" description="Tambahkan minimal satu produk agar paket bisa dipakai saat barang masuk." />
              )
            ) : (
              <EmptyState title="Belum ada master produk" description="Tambahkan produk dulu sebelum membuat paket." />
            )}
            <Button type="button" variant="outline" disabled={!products.length} onClick={() => setItems((current) => [...current, { product_id: "", qty_per_package: 1 }])}>
              <Plus className="h-4 w-4" />
              Tambah Produk
            </Button>
          </div>
          <SubmitMessage state={state} />
          <Button disabled={pending || !products.length || !hasPackageItem}>
            <Save className="h-4 w-4" />
            {pending ? "Menyimpan..." : "Simpan Paket"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}

export function AdminUsersManager({ profiles, currentUserId }: { profiles: Profile[]; currentUserId: string }) {
  const [state, formAction, pending] = useActionState(createAdminUserAction, initialState);
  return (
    <div className="app-page space-y-5">
      <Card>
        <CardHeader>
          <CardTitle>Tambah User Login</CardTitle>
        </CardHeader>
        <CardContent>
          <form action={formAction} className="grid gap-3 md:grid-cols-[1fr_1fr_180px_100px]">
            <Input name="full_name" placeholder="Nama lengkap" required />
            <Input name="email" placeholder="Email login" type="email" required className="font-mono" />
            <select name="role" className="h-10 rounded-md border bg-card px-3 text-sm outline-none transition-all focus-visible:border-primary/50 focus-visible:ring-2 focus-visible:ring-ring" defaultValue="admin_gudang">
              <option value="super_admin">{roleLabel("super_admin")}</option>
              <option value="admin_gudang">{roleLabel("admin_gudang")}</option>
              <option value="viewer">{roleLabel("viewer")}</option>
            </select>
            <label className="flex items-center gap-2 text-sm font-medium">
              <input type="checkbox" name="is_active" defaultChecked className="h-4 w-4 rounded-sm border-input text-primary accent-primary focus-visible:ring-2 focus-visible:ring-ring" />
              Aktif
            </label>
            <PasswordField name="password" placeholder="Password awal (min. 6 karakter)" wrapperClassName="md:col-span-2" />
            <SubmitMessage state={state} />
            <Button disabled={pending} className="md:w-fit">
              <Save className="h-4 w-4" />
              Buat User
            </Button>
          </form>
        </CardContent>
      </Card>

      <div className="grid gap-3">
        {profiles.length ? profiles.map((profile) => <ProfileRow key={profile.id} profile={profile} isSelf={profile.id === currentUserId} />) : <EmptyState title="Belum ada profile" description="Buat user login pertama dari form di atas." />}
      </div>
    </div>
  );
}

function ProfileRow({ profile, isSelf }: { profile: Profile; isSelf: boolean }) {
  const [state, formAction, pending] = useActionState(updateProfileRoleAction, initialState);
  return (
    <Card>
      <CardContent className="space-y-3 p-4">
        <form action={formAction} className="grid items-center gap-3 md:grid-cols-[1fr_1fr_170px_100px]">
          <input type="hidden" name="id" value={profile.id} />
          <Input name="full_name" defaultValue={profile.full_name} required />
          <Input name="email" defaultValue={profile.email ?? ""} className="font-mono" />
          <select name="role" className="h-10 rounded-md border bg-card px-3 text-sm outline-none transition-all focus-visible:border-primary/50 focus-visible:ring-2 focus-visible:ring-ring" defaultValue={profile.role as UserRole}>
            <option value="super_admin">{roleLabel("super_admin")}</option>
            <option value="admin_gudang">{roleLabel("admin_gudang")}</option>
            <option value="viewer">{roleLabel("viewer")}</option>
          </select>
          <label className="flex items-center gap-2 text-sm font-medium">
            <input type="checkbox" name="is_active" defaultChecked={profile.is_active} className="h-4 w-4 rounded-sm border-input text-primary accent-primary focus-visible:ring-2 focus-visible:ring-ring" />
            Aktif
          </label>
          <Button disabled={pending} size="sm" variant="outline" className="md:w-fit">
            <Save className="h-4 w-4" />
            Simpan
          </Button>
          <SubmitMessage state={state} compact className="md:col-span-4" />
        </form>
        <div className="flex flex-wrap items-center gap-2 border-t pt-3">
          <Button asChild size="sm" variant="ghost">
            <Link href={`/activity-logs?actor=${profile.id}`}>
              <Activity className="h-4 w-4" />
              Lihat aktivitas
            </Link>
          </Button>
          <PasswordResetDialog userId={profile.id} userName={profile.full_name} />
          {!isSelf ? (
            <DeleteConfirm
              action={deleteAdminUserAction}
              id={profile.id}
              triggerLabel="Hapus user"
              title="Hapus user permanen?"
              description={`Akun login "${profile.full_name}" akan dihapus permanen beserta akses loginnya. Riwayat aktivitasnya tetap tersimpan tanpa nama pelaku.`}
            />
          ) : null}
        </div>
      </CardContent>
    </Card>
  );
}

function PasswordResetDialog({ userId, userName }: { userId: string; userName: string }) {
  const [state, formAction, pending] = useActionState(resetUserPasswordAction, initialState);
  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button type="button" size="sm" variant="outline">
          <KeyRound className="h-4 w-4" />
          Reset password
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Reset password</DialogTitle>
          <DialogDescription>Atur password baru untuk akun &quot;{userName}&quot;.</DialogDescription>
        </DialogHeader>
        <form action={formAction} className="space-y-3">
          <input type="hidden" name="id" value={userId} />
          <PasswordField name="password" placeholder="Password baru (min. 6 karakter)" />
          <SubmitMessage state={state} compact />
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline">
                Batal
              </Button>
            </DialogClose>
            <Button type="submit" disabled={pending}>
              <KeyRound className="h-4 w-4" />
              {pending ? "Menyimpan..." : "Simpan password"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function DeleteConfirm({
  action,
  id,
  triggerLabel,
  title,
  description,
  confirmLabel = "Ya, hapus permanen"
}: {
  action: (state: ActionState, formData: FormData) => Promise<ActionState>;
  id: string;
  triggerLabel: string;
  title: string;
  description: string;
  confirmLabel?: string;
}) {
  const [state, formAction, pending] = useActionState(action, initialState);
  return (
    <div className="flex flex-wrap items-center gap-2">
      <Dialog>
        <DialogTrigger asChild>
          <Button type="button" size="sm" variant="outline" className="border-destructive/30 text-destructive hover:bg-destructive/10 hover:text-destructive">
            <Trash2 className="h-4 w-4" />
            {triggerLabel}
          </Button>
        </DialogTrigger>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            <DialogDescription>{description}</DialogDescription>
          </DialogHeader>
          <form action={formAction}>
            <input type="hidden" name="id" value={id} />
            <DialogFooter>
              <DialogClose asChild>
                <Button type="button" variant="outline">
                  Batal
                </Button>
              </DialogClose>
              <Button type="submit" variant="destructive" disabled={pending}>
                {pending ? "Menghapus..." : confirmLabel}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
      {!state.ok && state.message ? (
        <p role="status" aria-live="polite" className="flex items-center gap-1.5 text-sm font-medium text-destructive">
          <AlertTriangle className="h-4 w-4 shrink-0" />
          <span>{state.message}</span>
        </p>
      ) : null}
    </div>
  );
}

function PasswordField({ name, placeholder, wrapperClassName }: { name: string; placeholder: string; wrapperClassName?: string }) {
  const [show, setShow] = useState(false);
  return (
    <div className={cn("relative", wrapperClassName)}>
      <Input name={name} type={show ? "text" : "password"} placeholder={placeholder} minLength={6} required className="pr-10 font-mono" />
      <button
        type="button"
        onClick={() => setShow((current) => !current)}
        className="absolute right-2 top-1/2 -translate-y-1/2 rounded-sm p-1 text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        aria-label={show ? "Sembunyikan password" : "Lihat password"}
        tabIndex={-1}
      >
        {show ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
      </button>
    </div>
  );
}

function SubmitMessage({ state, compact = false, className = "" }: { state: ActionState; compact?: boolean; className?: string }) {
  if (!state.message) return null;
  return (
    <p
      role="status"
      aria-live="polite"
      className={
        state.ok
          ? `${compact ? "" : "md:col-span-2"} ${className} flex items-center gap-1.5 text-sm font-medium text-success`
          : `${compact ? "" : "md:col-span-2"} ${className} flex items-center gap-1.5 text-sm font-medium text-destructive`
      }
    >
      {state.ok ? <CheckCircle2 className="h-4 w-4 shrink-0" /> : <AlertTriangle className="h-4 w-4 shrink-0" />}
      <span>{state.message}</span>
    </p>
  );
}
