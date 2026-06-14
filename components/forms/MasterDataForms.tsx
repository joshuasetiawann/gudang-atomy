"use client";

import { useActionState, useMemo, useState } from "react";
import { Plus, Save, Trash2 } from "lucide-react";
import {
  createOwnerAction,
  createAdminUserAction,
  createPackageAction,
  createProductAction,
  updateOwnerAction,
  updatePackageAction,
  updateProductAction,
  updateProfileRoleAction
} from "@/server/actions/warehouse";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { EmptyState } from "@/components/ui/empty-state";
import { roleLabel } from "@/lib/utils";
import type { ActionState, Owner, PackageTemplate, PackageTemplateItem, Product, Profile, UserRole } from "@/lib/types";

const initialState: ActionState = { ok: true, message: "" };

export function OwnerManager({ owners, canEdit }: { owners: Owner[]; canEdit: boolean }) {
  const [state, formAction, pending] = useActionState(createOwnerAction, initialState);

  return (
    <div className="space-y-5">
      {canEdit ? (
        <Card>
          <CardHeader>
            <CardTitle>Tambah Owner</CardTitle>
            <CardDescription>Buat pemilik baru untuk penerimaan box.</CardDescription>
          </CardHeader>
          <CardContent>
            <form action={formAction} className="grid gap-3 md:grid-cols-2">
              <Input name="owner_code" placeholder="OWN-000001, kosongkan untuk otomatis" />
              <Input name="owner_name" placeholder="Nama pemilik" required />
              <Input name="phone" placeholder="Nomor HP" />
              <Input name="atomy_member_id" placeholder="Atomy member ID" />
              <Textarea name="notes" placeholder="Catatan" className="md:col-span-2" />
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" name="is_active" defaultChecked />
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
        {owners.length ? owners.map((owner) => <OwnerRow key={owner.id} owner={owner} canEdit={canEdit} />) : <EmptyState title="Belum ada owner" description="Tambahkan pemilik pertama agar barang masuk bisa dibuat." />}
      </div>
    </div>
  );
}

function OwnerRow({ owner, canEdit }: { owner: Owner; canEdit: boolean }) {
  const [state, formAction, pending] = useActionState(updateOwnerAction, initialState);
  if (!canEdit) {
    return (
      <Card>
        <CardContent className="p-4">
          <p className="font-medium">{owner.owner_name}</p>
          <p className="text-sm text-muted-foreground">{owner.owner_code}</p>
        </CardContent>
      </Card>
    );
  }
  return (
    <Card>
      <CardContent className="p-4">
        <form action={formAction} className="grid gap-3 md:grid-cols-[140px_minmax(180px,1fr)_150px_170px_minmax(180px,1fr)_80px_auto]">
          <input type="hidden" name="id" value={owner.id} />
          <Input name="owner_code" defaultValue={owner.owner_code} />
          <Input name="owner_name" defaultValue={owner.owner_name} required />
          <Input name="phone" defaultValue={owner.phone ?? ""} />
          <Input name="atomy_member_id" defaultValue={owner.atomy_member_id ?? ""} />
          <Input name="notes" defaultValue={owner.notes ?? ""} />
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" name="is_active" defaultChecked={owner.is_active} />
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

export function ProductManager({ products, canEdit }: { products: Product[]; canEdit: boolean }) {
  const [state, formAction, pending] = useActionState(createProductAction, initialState);

  return (
    <div className="space-y-5">
      {canEdit ? (
        <Card>
          <CardHeader>
            <CardTitle>Tambah Produk</CardTitle>
            <CardDescription>Tambah produk inventory atau komponen paket.</CardDescription>
          </CardHeader>
          <CardContent>
            <form action={formAction} className="grid gap-3 md:grid-cols-2">
              <Input name="sku" placeholder="SKU" />
              <Input name="product_name" placeholder="Nama produk" required />
              <Input name="category" placeholder="Kategori" />
              <Input name="unit" placeholder="pcs" defaultValue="pcs" />
              <Input name="default_barcode" placeholder="Barcode produk opsional" />
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" name="is_active" defaultChecked />
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
        {products.length ? products.map((product) => <ProductRow key={product.id} product={product} canEdit={canEdit} />) : <EmptyState title="Belum ada produk" description="Tambahkan master produk sebelum membuat box." />}
      </div>
    </div>
  );
}

function ProductRow({ product, canEdit }: { product: Product; canEdit: boolean }) {
  const [state, formAction, pending] = useActionState(updateProductAction, initialState);
  if (!canEdit) {
    return (
      <Card>
        <CardContent className="p-4">
          <p className="font-medium">{product.product_name}</p>
          <p className="text-sm text-muted-foreground">{product.sku ?? "-"}</p>
        </CardContent>
      </Card>
    );
  }
  return (
    <Card>
      <CardContent className="p-4">
        <form action={formAction} className="grid gap-3 md:grid-cols-[150px_minmax(220px,1.4fr)_170px_100px_minmax(180px,1fr)_80px_auto]">
          <input type="hidden" name="id" value={product.id} />
          <Input name="sku" defaultValue={product.sku ?? ""} />
          <Input name="product_name" defaultValue={product.product_name} required />
          <Input name="category" defaultValue={product.category ?? ""} />
          <Input name="unit" defaultValue={product.unit ?? "pcs"} />
          <Input name="default_barcode" defaultValue={product.default_barcode ?? ""} />
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" name="is_active" defaultChecked={product.is_active} />
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
              <Input id="package_code" name="package_code" defaultValue={initialPackage?.package_code ?? ""} required />
            </div>
            <div className="space-y-2">
              <Label htmlFor="package_name">Nama paket</Label>
              <Input id="package_name" name="package_name" defaultValue={initialPackage?.package_name ?? ""} required />
            </div>
            <Textarea name="description" defaultValue={initialPackage?.description ?? ""} placeholder="Deskripsi" className="md:col-span-2" />
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" name="is_active" defaultChecked={initialPackage?.is_active ?? true} />
              Aktif
            </label>
          </div>
          <div className="space-y-3">
            {products.length ? (
              items.length ? (
                items.map((item, index) => (
                  <div key={index} className="grid gap-3 rounded-md border bg-background/65 p-3 md:grid-cols-[1fr_120px_40px]">
                    <select
                      className="h-10 rounded-md border bg-card px-3 text-sm outline-none focus:ring-2 focus:ring-ring"
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
                    />
                    <Button type="button" size="icon" variant="ghost" aria-label="Hapus produk" onClick={() => setItems((current) => current.filter((_, itemIndex) => itemIndex !== index))}>
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

export function AdminUsersManager({ profiles }: { profiles: Profile[] }) {
  const [state, formAction, pending] = useActionState(createAdminUserAction, initialState);
  return (
    <div className="space-y-5">
      <Card>
        <CardHeader>
          <CardTitle>Tambah User Login</CardTitle>
        </CardHeader>
        <CardContent>
          <form action={formAction} className="grid gap-3 md:grid-cols-[1fr_1fr_180px_100px]">
            <Input name="full_name" placeholder="Nama lengkap" required />
            <Input name="email" placeholder="Email login" type="email" required />
            <select name="role" className="h-10 rounded-md border bg-card px-3 text-sm outline-none focus:ring-2 focus:ring-ring" defaultValue="admin_gudang">
              <option value="super_admin">{roleLabel("super_admin")}</option>
              <option value="admin_gudang">{roleLabel("admin_gudang")}</option>
              <option value="viewer">{roleLabel("viewer")}</option>
            </select>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" name="is_active" defaultChecked />
              Aktif
            </label>
            <Input name="password" placeholder="Password awal" type="password" minLength={6} required className="md:col-span-2" />
            <SubmitMessage state={state} />
            <Button disabled={pending} className="md:w-fit">
              <Save className="h-4 w-4" />
              Buat User
            </Button>
          </form>
        </CardContent>
      </Card>

      <div className="grid gap-3">
        {profiles.length ? profiles.map((profile) => <ProfileRow key={profile.id} profile={profile} />) : <EmptyState title="Belum ada profile" description="Buat user login pertama dari form di atas." />}
      </div>
    </div>
  );
}

function ProfileRow({ profile }: { profile: Profile }) {
  const [state, formAction, pending] = useActionState(updateProfileRoleAction, initialState);
  return (
    <Card>
      <CardContent className="p-4">
        <form action={formAction} className="grid gap-3 md:grid-cols-[1fr_1fr_170px_100px]">
          <input type="hidden" name="id" value={profile.id} />
          <Input name="full_name" defaultValue={profile.full_name} required />
          <Input name="email" defaultValue={profile.email ?? ""} />
          <select name="role" className="h-10 rounded-md border bg-card px-3 text-sm outline-none focus:ring-2 focus:ring-ring" defaultValue={profile.role as UserRole}>
            <option value="super_admin">{roleLabel("super_admin")}</option>
            <option value="admin_gudang">{roleLabel("admin_gudang")}</option>
            <option value="viewer">{roleLabel("viewer")}</option>
          </select>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" name="is_active" defaultChecked={profile.is_active} />
            Aktif
          </label>
          <Button disabled={pending} size="sm" variant="outline" className="md:w-fit">
            <Save className="h-4 w-4" />
            Simpan
          </Button>
          <SubmitMessage state={state} compact className="md:col-span-4" />
        </form>
      </CardContent>
    </Card>
  );
}

function SubmitMessage({ state, compact = false, className = "" }: { state: ActionState; compact?: boolean; className?: string }) {
  if (!state.message) return null;
  return (
    <p className={state.ok ? `${compact ? "" : "md:col-span-2"} ${className} text-sm font-medium text-success` : `${compact ? "" : "md:col-span-2"} ${className} text-sm font-medium text-destructive`}>
      {state.message}
    </p>
  );
}
