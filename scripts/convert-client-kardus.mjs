import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import Papa from "papaparse";

const DEFAULT_INPUT = "/home/joo/Downloads/GudangKu Database - kardus.csv";
const DEFAULT_OUTPUT = "supabase/seed/client_kardus_import.sql";
const DEFAULT_FULL_OUTPUT = "supabase/seed/client_kardus_full_setup.sql";

const inputPath = process.argv[2] ?? DEFAULT_INPUT;
const outputPath = process.argv[3] ?? DEFAULT_OUTPUT;

const monthByName = new Map([
  ["jan", "01"],
  ["feb", "02"],
  ["mar", "03"],
  ["apr", "04"],
  ["mei", "05"],
  ["may", "05"],
  ["jun", "06"],
  ["jul", "07"],
  ["agu", "08"],
  ["aug", "08"],
  ["sep", "09"],
  ["okt", "10"],
  ["oct", "10"],
  ["nov", "11"],
  ["des", "12"],
  ["dec", "12"]
]);

function normalizeText(value) {
  return String(value ?? "").trim().replace(/\s+/g, " ");
}

function normalizeLocation(value) {
  return normalizeText(value).toUpperCase();
}

function normalizeSku(value) {
  return normalizeText(value).toUpperCase().replace(/[^A-Z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

function parseClientDate(value) {
  const normalized = normalizeText(value);
  const match = /^(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})\s+(\d{2}):(\d{2})$/.exec(normalized);
  if (!match) throw new Error(`Format tanggal tidak dikenali: ${value}`);

  const [, day, monthName, year, hour, minute] = match;
  const month = monthByName.get(monthName.toLowerCase());
  if (!month) throw new Error(`Nama bulan tidak dikenali: ${value}`);

  return `${year}-${month}-${day.padStart(2, "0")} ${hour}:${minute}:00+07`;
}

function stableUuid(value) {
  const bytes = Buffer.from(crypto.createHash("md5").update(value).digest("hex"), "hex");
  bytes[6] = (bytes[6] & 0x0f) | 0x30;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function shortHash(value) {
  return crypto.createHash("sha1").update(value).digest("hex").slice(0, 6).toUpperCase();
}

function sql(value) {
  if (value === null || value === undefined) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") return String(value);
  return `'${String(value).replaceAll("'", "''")}'`;
}

function valuesRow(values) {
  return `  (${values.map(sql).join(", ")})`;
}

function sourceIdToIdBox(sourceId) {
  const normalized = normalizeText(sourceId);
  if (!normalized) throw new Error("Kolom id pada CSV kardus wajib diisi");
  return `GK-KARDUS-${normalized.padStart(6, "0")}`;
}

function productForRow(row) {
  const nomorPesanan = normalizeText(row.nomorPesanan).padStart(4, "0");
  const sku = `PESANAN-${normalizeSku(nomorPesanan) || "UMUM"}`;
  return {
    sku,
    productName: `Pesanan ${nomorPesanan}`,
    category: "GudangKu Pesanan",
    unit: "pcs",
    id: stableUuid(`gudangku-product:${sku}`)
  };
}

const csv = fs.readFileSync(inputPath, "utf8");
const parsed = Papa.parse(csv, { header: true, skipEmptyLines: true });
if (parsed.errors.length) {
  throw new Error(parsed.errors.map((error) => error.message).join("\n"));
}

const rows = parsed.data.map((row, index) => {
  const rowNo = index + 1;
  const createdAt = parseClientDate(row.created_at);
  const updatedAt = parseClientDate(row.updated_at);
  const ownerName = normalizeText(row.owner_name);
  const nomorId = normalizeText(row.nomor_id).padStart(4, "0");
  const ownerCode = `GK-${nomorId}-${shortHash(ownerName.toUpperCase())}`;
  const sourceId = normalizeText(row.id);
  const idBox = sourceIdToIdBox(sourceId);

  return {
    rowNo,
    sourceId,
    label: normalizeText(row.label),
    nomorPesanan: normalizeText(row.nomor_pesanan).padStart(4, "0"),
    nomorId,
    ownerName,
    ownerCode,
    locationCode: normalizeLocation(row.location),
    clientType: normalizeText(row.type),
    createdAt,
    createdByName: normalizeText(row.created_by),
    updatedAt,
    updatedByName: normalizeText(row.updated_by),
    ownerUuid: stableUuid(`gudangku-owner:${ownerCode}`),
    boxUuid: stableUuid(`gudangku-box:${sourceId}`),
    idBox
  };
});

const ownersByCode = new Map();
for (const row of rows) {
  if (!ownersByCode.has(row.ownerCode)) ownersByCode.set(row.ownerCode, row);
}

const boxesBySourceId = new Map();
const duplicateBoxRows = [];
for (const row of rows) {
  const existing = boxesBySourceId.get(row.sourceId);
  if (!existing) {
    boxesBySourceId.set(row.sourceId, { ...row, duplicateRows: [row] });
    continue;
  }

  existing.duplicateRows.push(row);
  const isSameBox =
    existing.label.toUpperCase() === row.label.toUpperCase() &&
    existing.ownerCode === row.ownerCode &&
    existing.locationCode === row.locationCode;
  if (!isSameBox) duplicateBoxRows.push(row);
}

const boxes = Array.from(boxesBySourceId.values());
const productsBySku = new Map();
const itemsByKey = new Map();
for (const row of rows) {
  const product = productForRow(row);
  if (!productsBySku.has(product.sku)) productsBySku.set(product.sku, product);

  const key = `${row.idBox}|${product.sku}`;
  const existing = itemsByKey.get(key);
  if (existing) {
    existing.qty += 1;
    existing.updatedAt = row.updatedAt > existing.updatedAt ? row.updatedAt : existing.updatedAt;
    existing.rowNos.push(row.rowNo);
    existing.labels.push(row.label);
    continue;
  }

  itemsByKey.set(key, {
    idBox: row.idBox,
    sku: product.sku,
    qty: 1,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    rowNos: [row.rowNo],
    labels: [row.label]
  });
}

const products = Array.from(productsBySku.values());
const boxItems = Array.from(itemsByKey.values());
const importBatchUuid = stableUuid(`gudangku-import:${path.basename(inputPath)}:${rows.length}`);

const ownerValues = Array.from(ownersByCode.values()).map((row) =>
  valuesRow([
    row.ownerUuid,
    row.ownerCode,
    row.ownerName,
    row.nomorId,
    `Import GudangKu kardus. nomor_id=${row.nomorId}.`,
    true
  ])
);

const rawValues = rows.map((row) =>
  valuesRow([
    row.rowNo,
    row.sourceId,
    row.label,
    row.nomorPesanan,
    row.nomorId,
    row.ownerName,
    row.locationCode,
    row.clientType,
    row.createdAt,
    row.createdByName,
    row.updatedAt,
    row.updatedByName,
    row.ownerCode,
    row.idBox
  ])
);

const boxValues = boxes.map((row) =>
  valuesRow([
    row.boxUuid,
    row.idBox,
    `${row.ownerCode}-${row.idBox}`,
    row.label || row.idBox,
    row.ownerCode,
    row.locationCode,
    row.createdAt,
    row.updatedAt,
    [
      `Import GudangKu kardus`,
      `client_id=${row.sourceId}`,
      `label=${row.label}`,
      `nomor_pesanan=${row.nomorPesanan}`,
      `nomor_id=${row.nomorId}`,
      `type=${row.clientType}`,
      `created_by=${row.createdByName}`,
      `updated_by=${row.updatedByName}`,
      row.duplicateRows.length > 1 ? `duplicate_client_id_rows=${row.duplicateRows.map((item) => item.rowNo).join("|")}` : null
    ].filter(Boolean).join("; ")
  ])
);

const productValues = products.map((product) =>
  valuesRow([
    product.id,
    product.sku,
    product.productName,
    product.category,
    product.unit,
    null,
    true
  ])
);

const boxItemValues = boxItems.map((row) => {
  return valuesRow([
    stableUuid(`gudangku-box-item:${row.idBox}:${row.sku}`),
    stableUuid(`gudangku-movement:${row.idBox}:${row.sku}`),
    row.idBox,
    row.sku,
    row.qty,
    row.createdAt,
    row.updatedAt,
    `source_rows=${row.rowNos.join("|")}; labels=${Array.from(new Set(row.labels)).join(" | ")}`
  ]);
});

const errorSummary = duplicateBoxRows.length
  ? `Ada ${duplicateBoxRows.length} baris CSV dengan id box yang sama tetapi isi metadata berbeda. Import memakai baris pertama untuk master box dan menyimpan semua baris di client_gudangku_kardus_raw.`
  : null;

const output = `-- Import data client GudangKu: kardus
-- Source CSV: ${inputPath}
-- Generated by: scripts/convert-client-kardus.mjs
-- Total CSV rows: ${rows.length}
-- Total unique client box ids: ${boxes.length}
--
-- Mapping:
-- - client_gudangku_kardus_raw: semua kolom asli CSV disimpan supaya tidak ada data client yang hilang.
-- - owners: dibuat dari pasangan nomor_id + owner_name.
-- - boxes: dibuat dari kolom id CSV. ID box app menjadi GK-KARDUS-000001, GK-KARDUS-000002, dst.
-- - Jika id CSV sama, baris itu dianggap berada di box yang sama.
-- - products: dibuat dari kolom nomor_pesanan CSV, misalnya PESANAN-4400 dan PESANAN-9000.
-- - box_items: setiap baris CSV menjadi isi box; baris dengan id box + nomor_pesanan sama digabung dan qty dijumlahkan.
-- - stock_movements: movement "in" dibuat untuk setiap box_items hasil import.

begin;

create extension if not exists pgcrypto;

delete from public.stock_movements
where reason = 'Import data client GudangKu';

delete from public.box_items
where batch_no in ('IMPORT-GUDANGKU', 'IMPORT-GUDANGKU-KARDUS', 'IMPORT-GUDANGKU-PESANAN');

delete from public.scan_logs
where box_id in (
  select id from public.boxes
  where notes like 'Import GudangKu kardus%'
);

delete from public.boxes
where notes like 'Import GudangKu kardus%';

delete from public.products
where sku = 'CLIENT-KARDUS'
   or category in ('GudangKu Kardus', 'GudangKu Pesanan');

create table if not exists public.client_gudangku_kardus_raw (
  import_row_no integer primary key,
  client_id text,
  label text,
  nomor_pesanan text,
  nomor_id text,
  owner_name text,
  location text,
  type text,
  created_at timestamptz,
  created_by text,
  updated_at timestamptz,
  updated_by text,
  mapped_owner_code text,
  mapped_id_box text,
  imported_at timestamptz not null default now()
);

insert into public.client_gudangku_kardus_raw(
  import_row_no,
  client_id,
  label,
  nomor_pesanan,
  nomor_id,
  owner_name,
  location,
  type,
  created_at,
  created_by,
  updated_at,
  updated_by,
  mapped_owner_code,
  mapped_id_box
)
values
${rawValues.join(",\n")}
on conflict (import_row_no) do update set
  client_id = excluded.client_id,
  label = excluded.label,
  nomor_pesanan = excluded.nomor_pesanan,
  nomor_id = excluded.nomor_id,
  owner_name = excluded.owner_name,
  location = excluded.location,
  type = excluded.type,
  created_at = excluded.created_at,
  created_by = excluded.created_by,
  updated_at = excluded.updated_at,
  updated_by = excluded.updated_by,
  mapped_owner_code = excluded.mapped_owner_code,
  mapped_id_box = excluded.mapped_id_box,
  imported_at = now();

insert into public.owners(id, owner_code, owner_name, atomy_member_id, notes, is_active)
values
${ownerValues.join(",\n")}
on conflict (owner_code) do update set
  owner_name = excluded.owner_name,
  atomy_member_id = excluded.atomy_member_id,
  notes = excluded.notes,
  is_active = true;

insert into public.products(id, sku, product_name, category, unit, default_barcode, is_active)
values
${productValues.join(",\n")}
on conflict (sku) do update set
  product_name = excluded.product_name,
  category = excluded.category,
  unit = excluded.unit,
  is_active = true;

with source_boxes(id, id_box, pemilik_id_box, box_name, owner_code, location_code, created_at, updated_at, notes) as (
  values
${boxValues.join(",\n")}
)
insert into public.boxes(
  id,
  id_box,
  pemilik_id_box,
  barcode_value,
  box_name,
  owner_id,
  source_type,
  package_id,
  package_qty,
  expired_at,
  location_code,
  status,
  created_at,
  updated_at,
  checked_out_at,
  notes
)
select
  source_boxes.id::uuid,
  source_boxes.id_box,
  source_boxes.pemilik_id_box,
  public.build_box_barcode_value(source_boxes.id_box),
  source_boxes.box_name,
  owners.id,
  'custom',
  null,
  0,
  null,
  source_boxes.location_code,
  'active',
  source_boxes.created_at::timestamptz,
  source_boxes.updated_at::timestamptz,
  null,
  source_boxes.notes
from source_boxes
join public.owners on owners.owner_code = source_boxes.owner_code
on conflict (id_box) do update set
  pemilik_id_box = excluded.pemilik_id_box,
  barcode_value = excluded.barcode_value,
  box_name = excluded.box_name,
  owner_id = excluded.owner_id,
  source_type = excluded.source_type,
  package_id = excluded.package_id,
  package_qty = excluded.package_qty,
  expired_at = excluded.expired_at,
  location_code = excluded.location_code,
  status = excluded.status,
  updated_at = excluded.updated_at,
  notes = excluded.notes;

with source_items(id, movement_id, id_box, sku, qty, created_at, updated_at, label) as (
  values
${boxItemValues.join(",\n")}
)
insert into public.box_items(id, box_id, product_id, qty_initial, qty_available, expired_at, batch_no, created_at, updated_at)
select
  source_items.id::uuid,
  boxes.id,
  products.id,
  source_items.qty::numeric,
  source_items.qty::numeric,
  null,
  'IMPORT-GUDANGKU-PESANAN',
  source_items.created_at::timestamptz,
  source_items.updated_at::timestamptz
from source_items
join public.boxes on boxes.id_box = source_items.id_box
join public.products on products.sku = source_items.sku
on conflict (id) do update set
  box_id = excluded.box_id,
  product_id = excluded.product_id,
  qty_initial = excluded.qty_initial,
  qty_available = excluded.qty_available,
  expired_at = excluded.expired_at,
  batch_no = excluded.batch_no,
  updated_at = excluded.updated_at;

with source_items(id, movement_id, id_box, sku, qty, created_at, updated_at, label) as (
  values
${boxItemValues.join(",\n")}
)
insert into public.stock_movements(
  id,
  movement_type,
  box_id,
  owner_id,
  product_id,
  qty,
  before_qty,
  after_qty,
  scanned_barcode,
  reason,
  notes,
  created_at
)
select
  source_items.movement_id::uuid,
  'in',
  boxes.id,
  boxes.owner_id,
  products.id,
  source_items.qty::numeric,
  0,
  source_items.qty::numeric,
  boxes.barcode_value,
  'Import data client GudangKu',
  source_items.label,
  source_items.created_at::timestamptz
from source_items
join public.boxes on boxes.id_box = source_items.id_box
join public.products on products.sku = source_items.sku
on conflict (id) do update set
  box_id = excluded.box_id,
  owner_id = excluded.owner_id,
  product_id = excluded.product_id,
  qty = excluded.qty,
  before_qty = excluded.before_qty,
  after_qty = excluded.after_qty,
  scanned_barcode = excluded.scanned_barcode,
  reason = excluded.reason,
  notes = excluded.notes,
  created_at = excluded.created_at;

insert into public.import_batches(
  id,
  import_type,
  file_name,
  status,
  total_rows,
  success_rows,
  failed_rows,
  error_summary,
  completed_at
)
values (
  ${sql(importBatchUuid)},
  'client_kardus',
  ${sql(path.basename(inputPath))},
  'success',
  ${rows.length},
  ${boxes.length},
  ${duplicateBoxRows.length},
  ${sql(errorSummary)},
  now()
)
on conflict (id) do update set
  status = excluded.status,
  total_rows = excluded.total_rows,
  success_rows = excluded.success_rows,
  failed_rows = excluded.failed_rows,
  error_summary = excluded.error_summary,
  completed_at = excluded.completed_at;

commit;
`;

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, output);

if (outputPath === DEFAULT_OUTPUT) {
  const schemaSql = fs.readFileSync("supabase/migrations/0001_gudang_atomy_schema.sql", "utf8");
  const barcodeFixSql = fs.readFileSync("supabase/migrations/0002_fix_barcode_checksum.sql", "utf8");
  const adminProfileSql = `-- Siapkan admin demo untuk login aplikasi.
-- Jika belum ada, SQL akan mencoba membuat Auth user:
-- email: admin@demo.local
-- password: admin123
do $$
declare
  v_admin_email text := 'admin@demo.local';
  v_admin_password text := 'admin123';
  v_admin_user_id uuid;
begin
  select id into v_admin_user_id
  from auth.users
  where lower(email) = lower(v_admin_email)
  limit 1;

  if v_admin_user_id is null then
    v_admin_user_id := '00000000-0000-4000-8000-000000000001'::uuid;

    begin
      insert into auth.users(
        id,
        instance_id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at
      )
      values (
        v_admin_user_id,
        '00000000-0000-0000-0000-000000000000',
        'authenticated',
        'authenticated',
        v_admin_email,
        crypt(v_admin_password, gen_salt('bf')),
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{"full_name":"Admin Demo"}'::jsonb,
        now(),
        now()
      );
    exception
      when unique_violation then
        select id into v_admin_user_id
        from auth.users
        where lower(email) = lower(v_admin_email)
        limit 1;
      when others then
        raise notice 'Auth user admin demo tidak dibuat otomatis: %', sqlerrm;
        select id into v_admin_user_id
        from auth.users
        where lower(email) = lower(v_admin_email)
        limit 1;
    end;
  end if;

  if v_admin_user_id is not null then
    begin
      insert into auth.identities(
        provider_id,
        user_id,
        identity_data,
        provider,
        last_sign_in_at,
        created_at,
        updated_at
      )
      values (
        v_admin_user_id::text,
        v_admin_user_id,
        jsonb_build_object('sub', v_admin_user_id::text, 'email', v_admin_email),
        'email',
        now(),
        now(),
        now()
      )
      on conflict do nothing;
    exception
      when others then
        raise notice 'Auth identity admin demo dilewati: %', sqlerrm;
    end;
  end if;

  if v_admin_user_id is not null then
    insert into public.profiles(id, full_name, email, role, is_active)
    values (v_admin_user_id, 'Admin Demo', v_admin_email, 'super_admin', true)
    on conflict (id) do update set
      full_name = excluded.full_name,
      email = excluded.email,
      role = excluded.role,
      is_active = true;
  end if;
end $$;`;
  const fullOutput = `-- Full setup Gudang Atomy + import data client GudangKu.
-- Jalankan file ini kalau database Supabase masih kosong / tabel aplikasi belum ada.
-- Urutan isi:
-- 1. Schema aplikasi Gudang Atomy
-- 2. Fix barcode checksum
-- 3. Sync profile admin demo kalau Auth user sudah ada
-- 4. Import lengkap CSV GudangKu kardus

-- ============================================================
-- 1. Schema aplikasi
-- ============================================================

${schemaSql}

-- ============================================================
-- 2. Fix barcode checksum
-- ============================================================

${barcodeFixSql}

-- ============================================================
-- 3. Sync profile admin demo
-- ============================================================

${adminProfileSql}

-- ============================================================
-- 4. Import data client GudangKu
-- ============================================================

${output}`;

  fs.writeFileSync(DEFAULT_FULL_OUTPUT, fullOutput);
}

console.log(`Generated ${outputPath}`);
if (outputPath === DEFAULT_OUTPUT) console.log(`Generated ${DEFAULT_FULL_OUTPUT}`);
console.log(`Rows: ${rows.length}`);
console.log(`Owners: ${ownersByCode.size}`);
console.log(`Boxes: ${boxes.length}`);
console.log(`Products: ${products.length}`);
console.log(`Box items: ${boxItemValues.length}`);
console.log(`Stock movements: ${boxItemValues.length}`);
if (duplicateBoxRows.length) console.log(`Duplicate box metadata conflicts: ${duplicateBoxRows.length}`);
