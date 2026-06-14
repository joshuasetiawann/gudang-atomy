import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import Papa from "papaparse";

const inputPath = process.argv[2];
const outputPath = process.argv[3] ?? "supabase/seed/client_inventory_import.sql";

if (!inputPath) {
  throw new Error("Usage: node scripts/convert-client-inventory.mjs /path/to/inventory.csv [output.sql]");
}

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

const aliases = {
  sourceBoxId: ["id_box", "box_id", "id_kardus", "kardus_id", "id", "box", "nomor_box"],
  sku: ["sku", "kode_produk", "kode_barang", "product_code", "barcode", "kode"],
  productName: ["product_name", "nama_produk", "produk", "nama_barang", "barang", "item", "item_name"],
  category: ["category", "kategori"],
  unit: ["unit", "satuan"],
  qty: ["qty", "quantity", "jumlah", "stok", "qty_initial", "qty_available"],
  expiredAt: ["expired_at", "expiry", "exp", "tanggal_expired", "expired"],
  batchNo: ["batch_no", "batch", "lot", "no_batch"],
  notes: ["notes", "note", "catatan", "keterangan"]
};

function normalizeText(value) {
  return String(value ?? "").trim().replace(/\s+/g, " ");
}

function normalizeHeader(value) {
  return normalizeText(value).toLowerCase().replace(/[\s-]+/g, "_");
}

function normalizeSku(value) {
  return normalizeText(value).toUpperCase().replace(/[^A-Z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

function stableUuid(value) {
  const bytes = Buffer.from(crypto.createHash("md5").update(value).digest("hex"), "hex");
  bytes[6] = (bytes[6] & 0x0f) | 0x30;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function shortHash(value) {
  return crypto.createHash("sha1").update(value).digest("hex").slice(0, 8).toUpperCase();
}

function sourceIdToIdBox(sourceId) {
  const normalized = normalizeText(sourceId);
  if (!normalized) throw new Error("Kolom id_box/id_kardus pada CSV inventory wajib diisi");
  return `GK-KARDUS-${normalized.padStart(6, "0")}`;
}

function findColumn(fields, kind) {
  const normalized = new Map(fields.map((field) => [normalizeHeader(field), field]));
  for (const alias of aliases[kind]) {
    const found = normalized.get(alias);
    if (found) return found;
  }
  return null;
}

function valueOf(row, columns, kind) {
  const column = columns[kind];
  return column ? row[column] : "";
}

function parseQty(value) {
  const normalized = normalizeText(value).replace(",", ".");
  if (!normalized) return 1;
  const qty = Number(normalized);
  if (!Number.isFinite(qty) || qty < 0) throw new Error(`Qty tidak valid: ${value}`);
  return qty;
}

function parseDateOnly(value) {
  const normalized = normalizeText(value);
  if (!normalized) return null;

  const iso = /^(\d{4})-(\d{2})-(\d{2})/.exec(normalized);
  if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}`;

  const slash = /^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/.exec(normalized);
  if (slash) return `${slash[3]}-${slash[2].padStart(2, "0")}-${slash[1].padStart(2, "0")}`;

  const words = /^(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})/.exec(normalized);
  if (words) {
    const month = monthByName.get(words[2].toLowerCase());
    if (!month) throw new Error(`Nama bulan tidak dikenali: ${value}`);
    return `${words[3]}-${month}-${words[1].padStart(2, "0")}`;
  }

  throw new Error(`Tanggal expired tidak dikenali: ${value}`);
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

const csv = fs.readFileSync(inputPath, "utf8");
const parsed = Papa.parse(csv, { header: true, skipEmptyLines: true });
if (parsed.errors.length) throw new Error(parsed.errors.map((error) => error.message).join("\n"));

const fields = parsed.meta.fields ?? [];
const columns = Object.fromEntries(Object.keys(aliases).map((kind) => [kind, findColumn(fields, kind)]));
const missing = ["sourceBoxId", "productName"].filter((kind) => !columns[kind]);
if (missing.length) {
  throw new Error(
    `CSV inventory belum punya kolom wajib: ${missing.join(", ")}. Header yang terbaca: ${fields.join(", ")}`
  );
}

const rawRows = parsed.data.map((row, index) => {
  const rowNo = index + 1;
  const sourceBoxId = normalizeText(valueOf(row, columns, "sourceBoxId"));
  const idBox = sourceIdToIdBox(sourceBoxId);
  const productName = normalizeText(valueOf(row, columns, "productName"));
  if (!productName) throw new Error(`Baris ${rowNo}: nama produk kosong`);

  const skuFromCsv = normalizeSku(valueOf(row, columns, "sku"));
  const sku = skuFromCsv || `GK-PROD-${shortHash(productName.toUpperCase())}`;
  const category = normalizeText(valueOf(row, columns, "category")) || "GudangKu Inventory";
  const unit = normalizeText(valueOf(row, columns, "unit")) || "pcs";
  const qty = parseQty(valueOf(row, columns, "qty"));
  const expiredAt = parseDateOnly(valueOf(row, columns, "expiredAt"));
  const batchNo = normalizeText(valueOf(row, columns, "batchNo")) || "INV-GUDANGKU";
  const notes = normalizeText(valueOf(row, columns, "notes"));

  return {
    rowNo,
    sourceBoxId,
    idBox,
    sku,
    productName,
    category,
    unit,
    qty,
    expiredAt,
    batchNo,
    notes,
    rawData: JSON.stringify(row)
  };
});

const productsBySku = new Map();
for (const row of rawRows) {
  if (!productsBySku.has(row.sku)) productsBySku.set(row.sku, row);
}

const itemsByKey = new Map();
for (const row of rawRows) {
  const key = [row.idBox, row.sku, row.expiredAt ?? "", row.batchNo].join("|");
  const existing = itemsByKey.get(key);
  if (existing) {
    existing.qty += row.qty;
    existing.rowNos.push(row.rowNo);
    continue;
  }
  itemsByKey.set(key, { ...row, rowNos: [row.rowNo] });
}

const products = Array.from(productsBySku.values());
const items = Array.from(itemsByKey.values());
const importBatchUuid = stableUuid(`gudangku-inventory-import:${path.basename(inputPath)}:${rawRows.length}`);

const rawValues = rawRows.map((row) =>
  valuesRow([
    row.rowNo,
    row.sourceBoxId,
    row.idBox,
    row.sku,
    row.productName,
    row.category,
    row.unit,
    row.qty,
    row.expiredAt,
    row.batchNo,
    row.notes,
    row.rawData
  ])
);

const productValues = products.map((row) =>
  valuesRow([
    stableUuid(`gudangku-product:${row.sku}`),
    row.sku,
    row.productName,
    row.category,
    row.unit,
    null,
    true
  ])
);

const itemValues = items.map((row) =>
  valuesRow([
    stableUuid(`gudangku-box-item:${row.idBox}:${row.sku}:${row.expiredAt ?? "no-exp"}:${row.batchNo}`),
    stableUuid(`gudangku-movement:${row.idBox}:${row.sku}:${row.expiredAt ?? "no-exp"}:${row.batchNo}`),
    row.idBox,
    row.sku,
    row.qty,
    row.expiredAt,
    row.batchNo,
    row.rowNos.join("|")
  ])
);

const output = `-- Import data client GudangKu: inventory isi kardus
-- Source CSV: ${inputPath}
-- Generated by: scripts/convert-client-inventory.mjs
-- Total CSV rows: ${rawRows.length}
-- Total products: ${products.length}
-- Total aggregated box items: ${items.length}
--
-- Mapping:
-- - id_box/id/id_kardus CSV dipetakan ke boxes.id_box: GK-KARDUS-000001, GK-KARDUS-000002, dst.
-- - Baris dengan id box + produk + expired + batch yang sama digabung dan qty dijumlahkan.
-- - Produk dibuat dari SKU CSV, atau dari nama produk kalau SKU tidak ada.

begin;

create extension if not exists pgcrypto;

delete from public.stock_movements
where reason = 'Import data client GudangKu inventory';

delete from public.box_items
where batch_no like 'INV-GUDANGKU%';

create table if not exists public.client_gudangku_inventory_raw (
  import_row_no integer primary key,
  source_box_id text,
  mapped_id_box text,
  sku text,
  product_name text,
  category text,
  unit text,
  qty numeric,
  expired_at date,
  batch_no text,
  notes text,
  raw_data jsonb,
  imported_at timestamptz not null default now()
);

insert into public.client_gudangku_inventory_raw(
  import_row_no,
  source_box_id,
  mapped_id_box,
  sku,
  product_name,
  category,
  unit,
  qty,
  expired_at,
  batch_no,
  notes,
  raw_data
)
values
${rawValues.join(",\n")}
on conflict (import_row_no) do update set
  source_box_id = excluded.source_box_id,
  mapped_id_box = excluded.mapped_id_box,
  sku = excluded.sku,
  product_name = excluded.product_name,
  category = excluded.category,
  unit = excluded.unit,
  qty = excluded.qty,
  expired_at = excluded.expired_at,
  batch_no = excluded.batch_no,
  notes = excluded.notes,
  raw_data = excluded.raw_data,
  imported_at = now();

insert into public.products(id, sku, product_name, category, unit, default_barcode, is_active)
values
${productValues.join(",\n")}
on conflict (sku) do update set
  product_name = excluded.product_name,
  category = excluded.category,
  unit = excluded.unit,
  is_active = true;

with source_items(id, movement_id, id_box, sku, qty, expired_at, batch_no, source_rows) as (
  values
${itemValues.join(",\n")}
)
insert into public.box_items(id, box_id, product_id, qty_initial, qty_available, expired_at, batch_no)
select
  source_items.id::uuid,
  boxes.id,
  products.id,
  source_items.qty::numeric,
  source_items.qty::numeric,
  source_items.expired_at::date,
  source_items.batch_no
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
  updated_at = now();

with source_items(id, movement_id, id_box, sku, qty, expired_at, batch_no, source_rows) as (
  values
${itemValues.join(",\n")}
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
  notes
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
  'Import data client GudangKu inventory',
  'source_rows=' || source_items.source_rows
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
  notes = excluded.notes;

insert into public.import_batches(
  id,
  import_type,
  file_name,
  status,
  total_rows,
  success_rows,
  failed_rows,
  completed_at
)
values (
  ${sql(importBatchUuid)},
  'client_inventory',
  ${sql(path.basename(inputPath))},
  'success',
  ${rawRows.length},
  ${items.length},
  0,
  now()
)
on conflict (id) do update set
  status = excluded.status,
  total_rows = excluded.total_rows,
  success_rows = excluded.success_rows,
  failed_rows = excluded.failed_rows,
  completed_at = excluded.completed_at;

commit;
`;

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, output);

console.log(`Generated ${outputPath}`);
console.log(`Rows: ${rawRows.length}`);
console.log(`Products: ${products.length}`);
console.log(`Aggregated box items: ${items.length}`);
