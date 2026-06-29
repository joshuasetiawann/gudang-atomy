"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { buildBarcodeValue, isValidBarcodeValue } from "@/lib/barcode/generate";
import { rowsToCsv } from "@/lib/csv/export";
import { requireRole } from "@/lib/auth/guards";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import type { ActionState, BoxItem, BoxRecord, PackageTemplateItem, Product } from "@/lib/types";
import { editBoxSchema, ownerSchema, packageSchema, partialCheckoutSchema, productSchema, receiveBoxSchema } from "@/lib/validation/schemas";
import { isUuidValue } from "@/lib/validation/uuid";

const ok = (message: string, extra: Partial<ActionState> = {}): ActionState => ({ ok: true, message, ...extra });
const fail = (message: string): ActionState => ({ ok: false, message });

function text(formData: FormData, key: string) {
  const value = String(formData.get(key) ?? "").trim();
  return value.length ? value : undefined;
}

function nullable(value: string | undefined) {
  return value && value.length ? value : null;
}

function bool(formData: FormData, key: string) {
  return formData.get(key) === "on" || formData.get(key) === "true";
}

function parseJsonArray<T>(raw: FormDataEntryValue | null): T[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(String(raw));
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function formUuid(formData: FormData, key: string, label: string) {
  const value = text(formData, key);
  if (!value) return { error: `${label} tidak ditemukan.` };
  if (!isUuidValue(value)) return { error: `${label} tidak valid. Muat ulang halaman lalu coba lagi.` };
  return { value };
}

function errorMessage(error: { message: string } | null | undefined, fallback: string) {
  if (!error) return fallback;
  if (/invalid input syntax.*uuid|uuid/i.test(error.message)) return "ID tidak valid. Muat ulang halaman lalu coba lagi.";
  return error.message;
}

async function insertScanLog(rawValue: string, result: "success" | "not_found" | "already_taken" | "invalid" | "error", message: string, boxId?: string) {
  const supabase = await createClient();
  const profile = await requireRole(["super_admin", "admin_gudang"]);
  await supabase.from("scan_logs").insert({
    scan_type: "lookup",
    raw_value: rawValue,
    box_id: boxId,
    actor_user_id: profile.id,
    result,
    message
  });
}

export async function createOwnerAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const profile = await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  const parsed = ownerSchema.safeParse({
    owner_code: text(formData, "owner_code"),
    owner_name: text(formData, "owner_name"),
    phone: text(formData, "phone"),
    atomy_member_id: text(formData, "atomy_member_id"),
    notes: text(formData, "notes"),
    is_active: bool(formData, "is_active")
  });

  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? "Data owner tidak valid.");

  let ownerCode = parsed.data.owner_code;
  if (!ownerCode) {
    const { data, error } = await supabase.rpc("generate_owner_code");
    if (error) return fail(errorMessage(error, "Kode owner gagal dibuat."));
    ownerCode = data as string;
  }

  const { error } = await supabase.from("owners").insert({
    owner_code: ownerCode,
    owner_name: parsed.data.owner_name,
    phone: nullable(parsed.data.phone),
    atomy_member_id: nullable(parsed.data.atomy_member_id),
    notes: nullable(parsed.data.notes),
    is_active: parsed.data.is_active,
    created_by: profile.id
  });

  if (error) return fail(errorMessage(error, "Owner gagal dibuat."));
  revalidatePath("/owners");
  revalidatePath("/barang-masuk");
  return ok("Owner berhasil dibuat.");
}

export async function updateOwnerAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  const idResult = formUuid(formData, "id", "ID owner");
  if (idResult.error) return fail(idResult.error);
  const id = idResult.value;

  const parsed = ownerSchema.safeParse({
    owner_code: text(formData, "owner_code"),
    owner_name: text(formData, "owner_name"),
    phone: text(formData, "phone"),
    atomy_member_id: text(formData, "atomy_member_id"),
    notes: text(formData, "notes"),
    is_active: bool(formData, "is_active")
  });

  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? "Data owner tidak valid.");

  const { error } = await supabase
    .from("owners")
    .update({
      owner_code: parsed.data.owner_code,
      owner_name: parsed.data.owner_name,
      phone: nullable(parsed.data.phone),
      atomy_member_id: nullable(parsed.data.atomy_member_id),
      notes: nullable(parsed.data.notes),
      is_active: parsed.data.is_active
    })
    .eq("id", id);

  if (error) return fail(errorMessage(error, "Owner gagal diupdate."));
  revalidatePath("/owners");
  return ok("Owner berhasil diupdate.");
}

export async function createProductAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const profile = await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  const parsed = productSchema.safeParse({
    sku: text(formData, "sku"),
    product_name: text(formData, "product_name"),
    category: text(formData, "category"),
    unit: text(formData, "unit") ?? "pcs",
    default_barcode: text(formData, "default_barcode"),
    is_active: bool(formData, "is_active")
  });

  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? "Data produk tidak valid.");

  const { error } = await supabase.from("products").insert({
    sku: nullable(parsed.data.sku),
    product_name: parsed.data.product_name,
    category: nullable(parsed.data.category),
    unit: parsed.data.unit,
    default_barcode: nullable(parsed.data.default_barcode),
    is_active: parsed.data.is_active,
    created_by: profile.id
  });

  if (error) return fail(errorMessage(error, "Produk gagal dibuat."));
  revalidatePath("/products");
  revalidatePath("/barang-masuk");
  return ok("Produk berhasil dibuat.");
}

export async function updateProductAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  const idResult = formUuid(formData, "id", "ID produk");
  if (idResult.error) return fail(idResult.error);
  const id = idResult.value;

  const parsed = productSchema.safeParse({
    sku: text(formData, "sku"),
    product_name: text(formData, "product_name"),
    category: text(formData, "category"),
    unit: text(formData, "unit") ?? "pcs",
    default_barcode: text(formData, "default_barcode"),
    is_active: bool(formData, "is_active")
  });

  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? "Data produk tidak valid.");

  const { error } = await supabase
    .from("products")
    .update({
      sku: nullable(parsed.data.sku),
      product_name: parsed.data.product_name,
      category: nullable(parsed.data.category),
      unit: parsed.data.unit,
      default_barcode: nullable(parsed.data.default_barcode),
      is_active: parsed.data.is_active
    })
    .eq("id", id);

  if (error) return fail(errorMessage(error, "Produk gagal diupdate."));
  revalidatePath("/products");
  return ok("Produk berhasil diupdate.");
}

export async function createPackageAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const profile = await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  const items = parseJsonArray<{ product_id: string; qty_per_package: number }>(formData.get("items_json"));
  const parsed = packageSchema.safeParse({
    package_code: text(formData, "package_code"),
    package_name: text(formData, "package_name"),
    description: text(formData, "description"),
    is_active: bool(formData, "is_active"),
    items
  });

  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? "Data paket tidak valid.");

  const uniqueProducts = new Set(parsed.data.items.map((item) => item.product_id));
  if (uniqueProducts.size !== parsed.data.items.length) return fail("Produk duplikat dalam satu paket tidak boleh.");

  const { data: pkg, error } = await supabase
    .from("package_templates")
    .insert({
      package_code: parsed.data.package_code,
      package_name: parsed.data.package_name,
      description: nullable(parsed.data.description),
      is_active: parsed.data.is_active,
      created_by: profile.id
    })
    .select("id")
    .single();

  if (error || !pkg) return fail(errorMessage(error, "Paket gagal dibuat."));

  if (parsed.data.items.length) {
    const { error: itemError } = await supabase.from("package_template_items").insert(
      parsed.data.items.map((item) => ({
        package_id: pkg.id,
        product_id: item.product_id,
        qty_per_package: item.qty_per_package
      }))
    );
    if (itemError) return fail(errorMessage(itemError, "Isi paket gagal disimpan."));
  }

  revalidatePath("/packages");
  revalidatePath("/barang-masuk");
  return ok("Paket berhasil dibuat.", { id: pkg.id });
}

export async function updatePackageAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  const idResult = formUuid(formData, "id", "ID paket");
  if (idResult.error) return fail(idResult.error);
  const id = idResult.value;

  const items = parseJsonArray<{ product_id: string; qty_per_package: number }>(formData.get("items_json"));
  const parsed = packageSchema.safeParse({
    package_code: text(formData, "package_code"),
    package_name: text(formData, "package_name"),
    description: text(formData, "description"),
    is_active: bool(formData, "is_active"),
    items
  });

  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? "Data paket tidak valid.");
  const uniqueProducts = new Set(parsed.data.items.map((item) => item.product_id));
  if (uniqueProducts.size !== parsed.data.items.length) return fail("Produk duplikat dalam satu paket tidak boleh.");

  const { error } = await supabase
    .from("package_templates")
    .update({
      package_code: parsed.data.package_code,
      package_name: parsed.data.package_name,
      description: nullable(parsed.data.description),
      is_active: parsed.data.is_active
    })
    .eq("id", id);
  if (error) return fail(errorMessage(error, "Paket gagal diupdate."));

  const { error: deleteError } = await supabase.from("package_template_items").delete().eq("package_id", id);
  if (deleteError) return fail(errorMessage(deleteError, "Isi paket lama gagal dibersihkan."));
  if (parsed.data.items.length) {
    const { error: itemError } = await supabase.from("package_template_items").insert(
      parsed.data.items.map((item) => ({
        package_id: id,
        product_id: item.product_id,
        qty_per_package: item.qty_per_package
      }))
    );
    if (itemError) return fail(errorMessage(itemError, "Isi paket gagal disimpan."));
  }

  revalidatePath("/packages");
  revalidatePath(`/packages/${id}`);
  return ok("Paket berhasil diupdate.");
}

export async function receiveBoxAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const profile = await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  const manualItems = parseJsonArray<{ product_id: string; qty: number; expired_at?: string; batch_no?: string }>(formData.get("items_json"));

  const parsed = receiveBoxSchema.safeParse({
    owner_id: text(formData, "owner_id"),
    quick_owner_name: text(formData, "quick_owner_name"),
    id_box: text(formData, "id_box"),
    box_name: text(formData, "box_name"),
    expired_at: text(formData, "expired_at"),
    location_code: text(formData, "location_code"),
    source_type: text(formData, "source_type"),
    package_id: text(formData, "package_id"),
    package_qty: text(formData, "package_qty") ?? 0,
    notes: text(formData, "notes"),
    items: manualItems
  });

  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? "Barang masuk tidak valid.");

  let ownerId = parsed.data.owner_id;
  if (!ownerId && parsed.data.quick_owner_name) {
    const { data: ownerCode, error: codeError } = await supabase.rpc("generate_owner_code");
    if (codeError) return fail(errorMessage(codeError, "Kode owner gagal dibuat."));

    const { data: owner, error: ownerError } = await supabase
      .from("owners")
      .insert({
        owner_code: ownerCode as string,
        owner_name: parsed.data.quick_owner_name,
        created_by: profile.id
      })
      .select("id")
      .single();

    if (ownerError || !owner) return fail(errorMessage(ownerError, "Owner cepat gagal dibuat."));
    ownerId = owner.id;
  }

  if (!ownerId) return fail("Owner wajib dipilih.");

  const packageItems: Array<{ product_id: string; qty: number; expired_at?: string; batch_no?: string }> = [];
  if (parsed.data.source_type !== "custom" && parsed.data.package_id) {
    const { data, error } = await supabase
      .from("package_template_items")
      .select("product_id, qty_per_package")
      .eq("package_id", parsed.data.package_id);
    if (error) return fail(errorMessage(error, "Isi paket gagal dibaca."));

    const templateItems = (data as PackageTemplateItem[] | null) ?? [];
    if (!templateItems.length) return fail("Paket ini belum punya produk. Tambahkan produk ke template paket dulu.");

    templateItems.forEach((item) => {
      packageItems.push({
        product_id: item.product_id,
        qty: Number(item.qty_per_package) * parsed.data.package_qty,
        expired_at: parsed.data.expired_at
      });
    });
  }

  const merged = new Map<string, { product_id: string; qty: number; expired_at: string | null; batch_no: string | null }>();
  [...packageItems, ...parsed.data.items].forEach((item) => {
    const expiredAt = nullable(item.expired_at) ?? nullable(parsed.data.expired_at);
    const batchNo = nullable(item.batch_no);
    const key = `${item.product_id}|${expiredAt ?? ""}|${batchNo ?? ""}`;
    const existing = merged.get(key);
    merged.set(key, {
      product_id: item.product_id,
      qty: (existing?.qty ?? 0) + Number(item.qty),
      expired_at: expiredAt,
      batch_no: batchNo
    });
  });

  const boxItems = Array.from(merged.values()).filter((item) => item.qty > 0);
  if (!boxItems.length) return fail("Isi box belum ada.");

  // ID Box diketik manual (pola sama dengan data SQL inject); pemilik_id_box & barcode diturunkan dari kode tsb.
  const idBox = parsed.data.id_box;
  const { data: ownerRow, error: ownerCodeError } = await supabase.from("owners").select("owner_code").eq("id", ownerId).single();
  if (ownerCodeError || !ownerRow) return fail(errorMessage(ownerCodeError, "Owner tidak ditemukan."));

  const { count: existingCount, error: dupError } = await supabase
    .from("boxes")
    .select("id", { count: "exact", head: true })
    .eq("id_box", idBox);
  if (dupError) return fail(errorMessage(dupError, "Gagal cek ID Box."));
  if (existingCount && existingCount > 0) return fail(`ID Box "${idBox}" sudah dipakai. Gunakan kode lain.`);

  const identifiers = {
    id_box: idBox,
    pemilik_id_box: `${ownerRow.owner_code}-${idBox}`,
    barcode_value: buildBarcodeValue(idBox)
  };

  const { data: box, error: boxError } = await supabase
    .from("boxes")
    .insert({
      id_box: identifiers.id_box,
      pemilik_id_box: identifiers.pemilik_id_box,
      barcode_value: identifiers.barcode_value,
      box_name: parsed.data.box_name,
      owner_id: ownerId,
      source_type: parsed.data.source_type,
      package_id: nullable(parsed.data.package_id),
      package_qty: parsed.data.package_qty,
      expired_at: nullable(parsed.data.expired_at),
      location_code: nullable(parsed.data.location_code),
      status: "active",
      created_by: profile.id,
      notes: nullable(parsed.data.notes)
    })
    .select("id")
    .single();

  if (boxError || !box) return fail(errorMessage(boxError, "Gagal membuat box."));

  const { error: itemError } = await supabase.from("box_items").insert(
    boxItems.map((item) => ({
      box_id: box.id,
      product_id: item.product_id,
      qty_initial: item.qty,
      qty_available: item.qty,
      expired_at: item.expired_at,
      batch_no: item.batch_no
    }))
  );
  if (itemError) {
    await supabase.from("boxes").update({ status: "void", notes: `Void otomatis: ${itemError.message}` }).eq("id", box.id);
    return fail(errorMessage(itemError, "Isi box gagal disimpan."));
  }

  const { error: movementError } = await supabase.from("stock_movements").insert(
    boxItems.map((item) => ({
      movement_type: "in",
      box_id: box.id,
      owner_id: ownerId,
      product_id: item.product_id,
      qty: item.qty,
      before_qty: 0,
      after_qty: item.qty,
      actor_user_id: profile.id,
      notes: parsed.data.notes
    }))
  );
  if (movementError) {
    await supabase.from("boxes").update({ status: "void", notes: `Void otomatis: ${movementError.message}` }).eq("id", box.id);
    return fail(errorMessage(movementError, "Riwayat stok gagal disimpan."));
  }

  revalidatePath("/dashboard");
  revalidatePath("/boxes");
  redirect(`/barang-masuk/success/${box.id}`);
}

export async function markBoxesPrintedAction(boxIds: string[], printed = true): Promise<ActionState> {
  await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  const ids = Array.from(new Set((boxIds ?? []).filter((id) => isUuidValue(id))));
  if (!ids.length) return fail("Tidak ada label valid untuk ditandai.");
  const { error } = await supabase
    .from("boxes")
    .update({ printed_at: printed ? new Date().toISOString() : null })
    .in("id", ids);
  if (error) return fail(errorMessage(error, printed ? "Gagal menandai sudah diprint." : "Gagal mereset tanda print."));
  revalidatePath("/print-resi");
  revalidatePath("/products");
  return ok(printed ? `${ids.length} label ditandai sudah diprint.` : `${ids.length} tanda print direset (belum diprint).`);
}

export async function setBoxPrintedAction(boxId: string, printed: boolean): Promise<ActionState> {
  await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  if (!isUuidValue(boxId)) return fail("ID box tidak valid.");
  const { error } = await supabase
    .from("boxes")
    .update({ printed_at: printed ? new Date().toISOString() : null })
    .eq("id", boxId);
  if (error) return fail(errorMessage(error, "Gagal mengubah status print."));
  revalidatePath("/print-resi");
  revalidatePath("/products");
  return ok(printed ? "Ditandai sudah diprint." : "Ditandai belum diprint.");
}

export async function lookupBoxByBarcodeAction(barcodeValue: string): Promise<ActionState> {
  await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  const value = barcodeValue.replace(/\s+/g, "").trim().toUpperCase();
  const isFullBarcode = isValidBarcodeValue(value);
  const isBoxIdentifier = /^[A-Z0-9][A-Z0-9-]{1,80}$/.test(value);

  if (!isFullBarcode && !isBoxIdentifier) {
    await insertScanLog(value, "invalid", "Format barcode tidak valid");
    return fail("Format barcode tidak valid.");
  }

  let query = supabase
    .from("boxes")
    .select("*, owners(owner_code, owner_name), box_items(*, products(sku, product_name, unit))");

  query = isFullBarcode
    ? query.eq("barcode_value", value)
    : query.or(`id_box.eq.${value},pemilik_id_box.eq.${value}`);

  const { data: box, error } = await query.single();

  if (error || !box) {
    await insertScanLog(value, "not_found", "Barcode tidak ditemukan");
    return fail("Barcode tidak ditemukan.");
  }

  await insertScanLog(value, "success", "Lookup berhasil", box.id);
  return ok("Lookup berhasil.", { data: box });
}

export async function checkoutFullBoxAction(barcodeValue: string): Promise<ActionState> {
  await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("checkout_full_box", { p_barcode_value: barcodeValue.trim() });
  if (error) return fail(errorMessage(error, "Ambil semua box gagal."));
  const result = data as { ok: boolean; message: string; box_id?: string };
  revalidatePath("/dashboard");
  revalidatePath("/boxes");
  if (result.box_id) revalidatePath(`/boxes/${result.box_id}`);
  return result.ok ? ok(result.message, { id: result.box_id }) : fail(result.message);
}

export async function checkoutPartialItemAction(barcodeValue: string, productId: string, qty: number): Promise<ActionState> {
  await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  const parsed = partialCheckoutSchema.safeParse({
    barcode_value: barcodeValue,
    product_id: productId,
    qty
  });

  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? "Data ambil produk tidak valid.");

  const { data, error } = await supabase.rpc("checkout_partial_item", {
    p_barcode_value: parsed.data.barcode_value,
    p_product_id: parsed.data.product_id,
    p_qty: parsed.data.qty
  });
  if (error) return fail(errorMessage(error, "Ambil produk gagal."));
  const result = data as { ok: boolean; message: string; box_id?: string };
  revalidatePath("/dashboard");
  revalidatePath("/boxes");
  if (result.box_id) revalidatePath(`/boxes/${result.box_id}`);
  return result.ok ? ok(result.message, { id: result.box_id }) : fail(result.message);
}

export async function voidBoxAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const profile = await requireRole(["super_admin"]);
  const supabase = await createClient();
  const boxResult = formUuid(formData, "box_id", "ID box");
  const reason = text(formData, "reason") ?? "Void box";
  if (boxResult.error) return fail(boxResult.error);
  const boxId = boxResult.value;

  const { data: box, error: boxError } = await supabase.from("boxes").select("id, owner_id, status").eq("id", boxId).single();
  if (boxError || !box) return fail(errorMessage(boxError, "Box tidak ditemukan."));
  if (box.status === "void") return fail("Box sudah void.");

  const { data: items } = await supabase.from("box_items").select("product_id, qty_available").eq("box_id", boxId);
  await supabase.from("stock_movements").insert(
    ((items as Array<{ product_id: string; qty_available: number }> | null) ?? []).map((item) => ({
      movement_type: "void",
      box_id: boxId,
      owner_id: box.owner_id,
      product_id: item.product_id,
      qty: item.qty_available,
      before_qty: item.qty_available,
      after_qty: 0,
      actor_user_id: profile.id,
      reason
    }))
  );

  const { error } = await supabase.from("boxes").update({ status: "void", notes: reason }).eq("id", boxId);
  if (error) return fail(errorMessage(error, "Box gagal di-void."));
  revalidatePath("/boxes");
  revalidatePath(`/boxes/${boxId}`);
  return ok("Box berhasil di-void.");
}

export async function updateBoxAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const profile = await requireRole(["super_admin", "admin_gudang"]);
  const supabase = await createClient();
  const idResult = formUuid(formData, "id", "ID box");
  if (idResult.error) return fail(idResult.error);
  const id = idResult.value;

  const rawItems = parseJsonArray<{ id?: string; product_id: string; qty: number; expired_at?: string; batch_no?: string }>(formData.get("items_json"));
  const parsed = editBoxSchema.safeParse({
    box_name: text(formData, "box_name"),
    expired_at: text(formData, "expired_at"),
    location_code: text(formData, "location_code"),
    notes: text(formData, "notes"),
    items: rawItems
  });
  if (!parsed.success) return fail(parsed.error.issues[0]?.message ?? "Data box tidak valid.");

  const keyOf = (item: { product_id: string; expired_at?: string; batch_no?: string }) =>
    `${item.product_id}|${nullable(item.expired_at) ?? ""}|${nullable(item.batch_no) ?? ""}`;
  const keys = parsed.data.items.map(keyOf);
  if (new Set(keys).size !== keys.length) return fail("Produk dengan expired & batch yang sama tidak boleh dobel dalam satu box.");

  const { data: box, error: boxError } = await supabase.from("boxes").select("id, owner_id, status").eq("id", id).single();
  if (boxError || !box) return fail(errorMessage(boxError, "Box tidak ditemukan."));
  if (box.status === "void") return fail("Box yang sudah void tidak bisa diedit.");

  const { data: currentRaw, error: itemsError } = await supabase
    .from("box_items")
    .select("id, product_id, qty_initial, qty_available, expired_at, batch_no")
    .eq("box_id", id);
  if (itemsError) return fail(errorMessage(itemsError, "Isi box gagal dibaca."));
  const currentItems = (currentRaw ?? []) as Array<{ id: string; product_id: string; qty_initial: number; qty_available: number; expired_at: string | null; batch_no: string | null }>;
  const currentById = new Map(currentItems.map((item) => [item.id, item]));

  const { error: detailError } = await supabase
    .from("boxes")
    .update({
      box_name: parsed.data.box_name,
      expired_at: nullable(parsed.data.expired_at),
      location_code: nullable(parsed.data.location_code),
      notes: nullable(parsed.data.notes)
    })
    .eq("id", id);
  if (detailError) return fail(errorMessage(detailError, "Rincian box gagal diupdate."));

  const toUpdate = parsed.data.items.filter((item) => item.id && currentById.has(item.id));
  const toInsert = parsed.data.items.filter((item) => !item.id || !currentById.has(item.id));
  const keptIds = new Set(toUpdate.map((item) => item.id as string));
  const removed = currentItems.filter((item) => !keptIds.has(item.id));

  const movements: Array<{ product_id: string; qty: number; before_qty: number; after_qty: number }> = [];

  if (removed.length) {
    let admin;
    try {
      admin = createAdminClient();
    } catch {
      return fail("Menghapus baris isi box butuh konfigurasi server (service role key).");
    }
    const { error: deleteError } = await admin.from("box_items").delete().in("id", removed.map((item) => item.id));
    if (deleteError) return fail(errorMessage(deleteError, "Baris produk gagal dihapus."));
    removed.forEach((item) => {
      if (Number(item.qty_available) > 0) {
        movements.push({ product_id: item.product_id, qty: Number(item.qty_available), before_qty: Number(item.qty_available), after_qty: 0 });
      }
    });
  }

  for (const item of toUpdate) {
    const current = currentById.get(item.id as string);
    if (!current) continue;
    const newQty = Number(item.qty);
    const { error: updateError } = await supabase
      .from("box_items")
      .update({
        qty_available: newQty,
        qty_initial: Math.max(Number(current.qty_initial), newQty),
        expired_at: nullable(item.expired_at),
        batch_no: nullable(item.batch_no)
      })
      .eq("id", item.id as string);
    if (updateError) return fail(errorMessage(updateError, "Isi box gagal diupdate."));
    if (newQty !== Number(current.qty_available)) {
      movements.push({ product_id: current.product_id, qty: Math.abs(newQty - Number(current.qty_available)), before_qty: Number(current.qty_available), after_qty: newQty });
    }
  }

  if (toInsert.length) {
    const { error: insertError } = await supabase.from("box_items").insert(
      toInsert.map((item) => ({
        box_id: id,
        product_id: item.product_id,
        qty_initial: Number(item.qty),
        qty_available: Number(item.qty),
        expired_at: nullable(item.expired_at),
        batch_no: nullable(item.batch_no)
      }))
    );
    if (insertError) return fail(errorMessage(insertError, "Produk baru gagal ditambahkan."));
    toInsert.forEach((item) => movements.push({ product_id: item.product_id, qty: Number(item.qty), before_qty: 0, after_qty: Number(item.qty) }));
  }

  if (movements.length) {
    const { error: movementError } = await supabase.from("stock_movements").insert(
      movements.map((movement) => ({
        movement_type: "adjustment",
        box_id: id,
        owner_id: box.owner_id,
        product_id: movement.product_id,
        qty: movement.qty,
        before_qty: movement.before_qty,
        after_qty: movement.after_qty,
        actor_user_id: profile.id,
        reason: "Edit isi box"
      }))
    );
    if (movementError) return fail(errorMessage(movementError, "Riwayat penyesuaian gagal disimpan."));
  }

  const { data: remainingRaw } = await supabase.from("box_items").select("qty_available").eq("box_id", id);
  const totalAvailable = ((remainingRaw ?? []) as Array<{ qty_available: number }>).reduce((sum, item) => sum + Number(item.qty_available), 0);
  const nextStatus = totalAvailable <= 0 ? "empty" : box.status === "partial" ? "partial" : "active";
  if (nextStatus !== box.status) {
    const { error: statusError } = await supabase.from("boxes").update({ status: nextStatus }).eq("id", id);
    if (statusError) return fail(errorMessage(statusError, "Status box gagal diperbarui."));
  }

  revalidatePath("/boxes");
  revalidatePath("/dashboard");
  revalidatePath(`/boxes/${id}`);
  return ok("Box berhasil diperbarui.");
}

export async function deleteBoxAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  await requireRole(["super_admin"]);
  const supabase = await createClient();
  const idResult = formUuid(formData, "box_id", "ID box");
  if (idResult.error) return fail(idResult.error);
  const boxId = idResult.value;

  const { data: box, error: boxError } = await supabase.from("boxes").select("id").eq("id", boxId).single();
  if (boxError || !box) return fail(errorMessage(boxError, "Box tidak ditemukan."));

  // Super admin boleh menghapus box beserta seluruh isinya, walau masih ada stok.
  // box_items ikut terhapus otomatis lewat ON DELETE CASCADE pada boxes.
  let admin;
  try {
    admin = createAdminClient();
  } catch {
    return fail("Fitur hapus butuh konfigurasi server (service role key).");
  }

  const { error: scanError } = await admin.from("scan_logs").delete().eq("box_id", boxId);
  if (scanError) return fail(errorMessage(scanError, "Riwayat scan gagal dihapus."));
  const { error: movementError } = await admin.from("stock_movements").delete().eq("box_id", boxId);
  if (movementError) return fail(errorMessage(movementError, "Riwayat stok gagal dihapus."));
  const { error: deleteError } = await admin.from("boxes").delete().eq("id", boxId);
  if (deleteError) return fail(errorMessage(deleteError, "Box gagal dihapus."));

  revalidatePath("/boxes");
  revalidatePath("/dashboard");
  redirect("/boxes");
}

export async function deleteOwnerAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  await requireRole(["super_admin"]);
  const supabase = await createClient();
  const idResult = formUuid(formData, "id", "ID owner");
  if (idResult.error) return fail(idResult.error);
  const ownerId = idResult.value;

  const { data: owner, error: ownerError } = await supabase.from("owners").select("id").eq("id", ownerId).single();
  if (ownerError || !owner) return fail(errorMessage(ownerError, "Owner tidak ditemukan."));

  // Owner yang masih punya box tidak boleh dihapus supaya inventory tidak ikut hilang tanpa sengaja.
  const { data: boxes, error: boxesError } = await supabase.from("boxes").select("id").eq("owner_id", ownerId).limit(1);
  if (boxesError) return fail(errorMessage(boxesError, "Cek box owner gagal."));
  if (boxes && boxes.length) return fail("Owner ini masih punya box. Hapus atau pindahkan box-nya dulu sebelum owner dihapus.");

  let admin;
  try {
    admin = createAdminClient();
  } catch {
    return fail("Fitur hapus butuh konfigurasi server (service role key).");
  }

  // Lepaskan referensi di riwayat stok (kolom nullable) supaya FK tidak memblokir penghapusan,
  // sekaligus menjaga histori movement tetap ada.
  const { error: movementError } = await admin.from("stock_movements").update({ owner_id: null }).eq("owner_id", ownerId);
  if (movementError) return fail(errorMessage(movementError, "Riwayat stok owner gagal dilepas."));

  const { error: deleteError } = await admin.from("owners").delete().eq("id", ownerId);
  if (deleteError) return fail(errorMessage(deleteError, "Owner gagal dihapus."));

  revalidatePath("/owners");
  revalidatePath("/barang-masuk");
  return ok("Owner berhasil dihapus.");
}

export async function deleteAdminUserAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const actor = await requireRole(["super_admin"]);
  const supabase = await createClient();
  const idResult = formUuid(formData, "id", "ID user");
  if (idResult.error || !idResult.value) return fail(idResult.error ?? "ID user tidak valid.");
  const userId = idResult.value;

  if (userId === actor.id) return fail("Tidak bisa menghapus akun sendiri.");

  const { data: target, error: targetError } = await supabase.from("profiles").select("id, role").eq("id", userId).single();
  if (targetError || !target) return fail(errorMessage(targetError, "User tidak ditemukan."));

  if (target.role === "super_admin") {
    const { count } = await supabase.from("profiles").select("id", { count: "exact", head: true }).eq("role", "super_admin");
    if ((count ?? 0) <= 1) return fail("Tidak bisa menghapus super admin terakhir.");
  }

  let admin;
  try {
    admin = createAdminClient();
  } catch {
    return fail("Fitur hapus butuh konfigurasi server (service role key).");
  }

  // profiles direferensikan banyak tabel tanpa cascade, jadi lepaskan dulu semua referensinya
  // sebelum auth user dihapus (penghapusan auth user akan men-cascade baris profiles).
  const refs: Array<[string, string]> = [
    ["owners", "created_by"],
    ["products", "created_by"],
    ["package_templates", "created_by"],
    ["boxes", "created_by"],
    ["boxes", "checked_out_by"],
    ["stock_movements", "actor_user_id"],
    ["scan_logs", "actor_user_id"],
    ["import_batches", "created_by"],
    ["audit_logs", "actor_user_id"]
  ];
  for (const [table, column] of refs) {
    const { error } = await admin.from(table).update({ [column]: null }).eq(column, userId);
    if (error) return fail(errorMessage(error, `Referensi ${table} gagal dilepas.`));
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) return fail(errorMessage(deleteError, "User Auth gagal dihapus."));

  revalidatePath("/admin-users");
  return ok("User berhasil dihapus.");
}

export async function exportActiveStockCsvAction(): Promise<ActionState> {
  await requireRole(["super_admin", "admin_gudang", "viewer"]);
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("v_active_stock")
    .select("id_box,pemilik_id_box,box_name,status,owner_code,owner_name,sku,product_name,qty_initial,qty_available,expired_at,location_code")
    .order("expired_at", { ascending: true });
  if (error) return fail(errorMessage(error, "CSV stok aktif gagal dibuat."));
  const csv = rowsToCsv((data ?? []) as Record<string, unknown>[], [
    "id_box",
    "pemilik_id_box",
    "box_name",
    "status",
    "owner_code",
    "owner_name",
    "sku",
    "product_name",
    "qty_initial",
    "qty_available",
    "expired_at",
    "location_code"
  ]);
  return ok("CSV stok aktif siap.", { data: csv });
}

export async function importCsvRowsAction(importType: string, fileName: string, rows: Array<Record<string, string>>): Promise<ActionState> {
  const profile = await requireRole(["super_admin"]);
  const supabase = await createClient();
  let successRows = 0;
  const errors: string[] = [];

  const batchInsert = async (payload: Record<string, unknown>[]) => {
    if (!payload.length) return;
    const tableByType: Record<string, string> = {
      owners: "owners",
      products: "products",
      packages: "package_templates",
      boxes: "boxes"
    };
    const table = tableByType[importType];
    if (!table) throw new Error("Jenis import belum didukung untuk batch langsung.");
    const { error } = await supabase.from(table).insert(payload);
    if (error) throw error;
    successRows += payload.length;
  };

  try {
    if (importType === "owners") {
      await batchInsert(
        rows.map((row, index) => {
          if (!row.owner_code || !row.owner_name) errors.push(`Baris ${index + 2}: owner_code dan owner_name wajib.`);
          return {
            owner_code: row.owner_code,
            owner_name: row.owner_name,
            phone: row.phone || null,
            atomy_member_id: row.atomy_member_id || null,
            notes: row.notes || null,
            created_by: profile.id
          };
        }).filter((_, index) => !errors.some((error) => error.startsWith(`Baris ${index + 2}:`)))
      );
    } else if (importType === "products") {
      await batchInsert(
        rows.map((row, index) => {
          if (!row.product_name) errors.push(`Baris ${index + 2}: product_name wajib.`);
          return {
            sku: row.sku || null,
            product_name: row.product_name,
            category: row.category || null,
            unit: row.unit || "pcs",
            default_barcode: row.default_barcode || null,
            created_by: profile.id
          };
        }).filter((_, index) => !errors.some((error) => error.startsWith(`Baris ${index + 2}:`)))
      );
    } else if (importType === "packages") {
      await batchInsert(
        rows.map((row, index) => {
          if (!row.package_code || !row.package_name) errors.push(`Baris ${index + 2}: package_code dan package_name wajib.`);
          return {
            package_code: row.package_code,
            package_name: row.package_name,
            description: row.description || null,
            created_by: profile.id
          };
        }).filter((_, index) => !errors.some((error) => error.startsWith(`Baris ${index + 2}:`)))
      );
    } else if (importType === "package_items") {
      for (const [index, row] of rows.entries()) {
        if (!row.package_code || !row.sku || !row.qty_per_package) {
          errors.push(`Baris ${index + 2}: package_code, sku, qty_per_package wajib.`);
          continue;
        }
        const { data: pkg } = await supabase.from("package_templates").select("id").eq("package_code", row.package_code).single();
        const { data: product } = await supabase.from("products").select("id").eq("sku", row.sku).single();
        if (!pkg || !product) {
          errors.push(`Baris ${index + 2}: paket atau produk tidak ditemukan.`);
          continue;
        }
        const { error } = await supabase.from("package_template_items").insert({
          package_id: pkg.id,
          product_id: product.id,
          qty_per_package: Number(row.qty_per_package)
        });
        if (error) errors.push(`Baris ${index + 2}: ${error.message}`);
        else successRows += 1;
      }
    } else if (importType === "boxes") {
      for (const [index, row] of rows.entries()) {
        if (!row.id_box || !row.owner_code || !row.box_name) {
          errors.push(`Baris ${index + 2}: id_box, owner_code, box_name wajib.`);
          continue;
        }
        const { data: owner } = await supabase.from("owners").select("id, owner_code").eq("owner_code", row.owner_code).single();
        if (!owner) {
          errors.push(`Baris ${index + 2}: owner_code tidak ditemukan.`);
          continue;
        }
        const { error } = await supabase.from("boxes").insert({
          id_box: row.id_box,
          pemilik_id_box: `${owner.owner_code}-${row.id_box}`,
          barcode_value: buildBarcodeValue(row.id_box),
          box_name: row.box_name,
          owner_id: owner.id,
          source_type: "custom",
          expired_at: row.expired_at || null,
          location_code: row.location_code || null,
          status: row.status || "active",
          notes: row.notes || null,
          created_by: profile.id
        });
        if (error) errors.push(`Baris ${index + 2}: ${error.message}`);
        else successRows += 1;
      }
    } else if (importType === "box_items") {
      for (const [index, row] of rows.entries()) {
        if (!row.id_box || !row.sku || !row.qty_initial || !row.qty_available) {
          errors.push(`Baris ${index + 2}: id_box, sku, qty_initial, qty_available wajib.`);
          continue;
        }
        const { data: box } = await supabase.from("boxes").select("id").eq("id_box", row.id_box).single();
        const { data: product } = await supabase.from("products").select("id").eq("sku", row.sku).single();
        if (!box || !product) {
          errors.push(`Baris ${index + 2}: box atau produk tidak ditemukan.`);
          continue;
        }
        const { error } = await supabase.from("box_items").insert({
          box_id: box.id,
          product_id: product.id,
          qty_initial: Number(row.qty_initial),
          qty_available: Number(row.qty_available),
          expired_at: row.expired_at || null,
          batch_no: row.batch_no || null
        });
        if (error) errors.push(`Baris ${index + 2}: ${error.message}`);
        else successRows += 1;
      }
    } else {
      return fail("Jenis import tidak dikenal.");
    }
  } catch (error) {
    errors.push(error instanceof Error ? error.message : "Import gagal.");
  }

  await supabase.from("import_batches").insert({
    import_type: importType,
    file_name: fileName,
    status: errors.length ? "partial" : "success",
    total_rows: rows.length,
    success_rows: successRows,
    failed_rows: rows.length - successRows,
    error_summary: errors.join("\n") || null,
    created_by: profile.id,
    completed_at: new Date().toISOString()
  });

  revalidatePath("/imports");
  return errors.length
    ? fail(`Import selesai dengan ${errors.length} error: ${errors.slice(0, 5).join(" | ")}`)
    : ok(`Import berhasil: ${successRows} baris.`);
}

export async function updateProfileRoleAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  await requireRole(["super_admin"]);
  const supabase = await createClient();
  const idResult = formUuid(formData, "id", "ID user");
  if (idResult.error) return fail(idResult.error);
  const id = idResult.value;
  const fullName = text(formData, "full_name");
  const email = text(formData, "email");
  const role = text(formData, "role");
  if (!fullName || !role) return fail("Nama dan role wajib diisi.");
  if (!["super_admin", "admin_gudang", "viewer"].includes(role)) return fail("Role tidak valid.");

  const { error } = await supabase.from("profiles").upsert({
    id,
    full_name: fullName,
    email: nullable(email),
    role,
    is_active: bool(formData, "is_active")
  });

  if (error) return fail(errorMessage(error, "Profile user gagal disimpan."));
  revalidatePath("/admin-users");
  return ok("Profile user berhasil disimpan.");
}

export async function resetUserPasswordAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  await requireRole(["super_admin"]);
  const idResult = formUuid(formData, "id", "ID user");
  if (idResult.error || !idResult.value) return fail(idResult.error ?? "ID user tidak valid.");
  const userId = idResult.value;
  const password = String(formData.get("password") ?? "");
  if (password.length < 6) return fail("Password minimal 6 karakter.");

  let admin;
  try {
    admin = createAdminClient();
  } catch {
    return fail("Fitur reset password butuh konfigurasi server (service role key).");
  }

  const { error } = await admin.auth.admin.updateUserById(userId, { password });
  if (error) return fail(errorMessage(error, "Password gagal diubah."));
  revalidatePath("/admin-users");
  return ok("Password user berhasil diubah.");
}

export async function createAdminUserAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  await requireRole(["super_admin"]);
  const admin = createAdminClient();
  const email = text(formData, "email");
  const password = String(formData.get("password") ?? "");
  const fullName = text(formData, "full_name");
  const role = text(formData, "role") ?? "admin_gudang";

  if (!email || !password || !fullName) return fail("Nama, email, dan password wajib diisi.");
  if (password.length < 6) return fail("Password minimal 6 karakter.");
  if (!["super_admin", "admin_gudang", "viewer"].includes(role)) return fail("Role tidak valid.");

  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      full_name: fullName
    }
  });

  if (error || !data.user) return fail(errorMessage(error, "User Auth gagal dibuat."));

  const { error: profileError } = await admin.from("profiles").upsert({
    id: data.user.id,
    full_name: fullName,
    email,
    role,
    is_active: bool(formData, "is_active")
  });

  if (profileError) return fail(errorMessage(profileError, "Profile user gagal dibuat."));
  revalidatePath("/admin-users");
  return ok("User login berhasil dibuat.");
}

export type LookupBoxResult = BoxRecord & {
  box_items: BoxItem[];
};

export type ProductOption = Pick<Product, "id" | "sku" | "product_name" | "unit">;
