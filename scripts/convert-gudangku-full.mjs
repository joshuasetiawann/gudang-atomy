import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import Papa from "papaparse";

const DEFAULT_KARDUS_INPUT = "/home/joo/Downloads/GudangKu Database - kardus.csv";
const DEFAULT_INVENTORY_INPUT = "/home/joo/Downloads/GudangKu Database - inventory.csv";
const DEFAULT_PACKAGE_INPUT = "/home/joo/Downloads/GudangKu Database - paket.csv";
const DEFAULT_OUTPUT = "supabase/seed/gudangku_full_import.sql";
const DEFAULT_FULL_OUTPUT = "supabase/seed/final_gudang_atomy.sql";

const kardusInputPath = process.argv[2] ?? DEFAULT_KARDUS_INPUT;
const inventoryInputPath = process.argv[3] ?? DEFAULT_INVENTORY_INPUT;
const packageInputPath = process.argv[4] ?? DEFAULT_PACKAGE_INPUT;
const outputPath = process.argv[5] ?? DEFAULT_OUTPUT;

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

function parseQty(value, rowNo) {
  const qty = Number(normalizeText(value).replace(",", "."));
  if (!Number.isFinite(qty) || qty < 0) throw new Error(`Qty tidak valid di inventory row ${rowNo}: ${value}`);
  return qty;
}

function parsePackageQty(value, rowNo) {
  const normalized = normalizeText(value);
  const match = /^(\d+(?:[.,]\d+)?)\s*([A-Za-z]*)$/.exec(normalized);
  if (!match) throw new Error(`Qty paket tidak valid di row ${rowNo}: ${value}`);

  const qty = Number(match[1].replace(",", "."));
  if (!Number.isFinite(qty) || qty <= 0) throw new Error(`Qty paket tidak valid di row ${rowNo}: ${value}`);

  const unitSource = normalizeText(match[2]).toLowerCase();
  const unit = unitSource === "set" ? "set" : "pcs";
  return { qty, unit };
}

function parseMoney(value) {
  const normalized = normalizeText(value).replace(",", ".");
  if (!normalized) return 0;
  const amount = Number(normalized);
  return Number.isFinite(amount) ? amount : 0;
}

function stableUuid(value) {
  const bytes = Buffer.from(crypto.createHash("md5").update(value).digest("hex"), "hex");
  bytes[6] = (bytes[6] & 0x0f) | 0x30;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function shortHash(value, length = 6) {
  return crypto.createHash("sha1").update(value).digest("hex").slice(0, length).toUpperCase();
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
  if (!normalized) throw new Error("Kolom id/kardus_id wajib diisi");
  return `GK-KARDUS-${normalized.padStart(6, "0")}`;
}

function readCsv(filePath) {
  const parsed = Papa.parse(fs.readFileSync(filePath, "utf8"), { header: true, skipEmptyLines: true });
  if (parsed.errors.length) throw new Error(parsed.errors.map((error) => error.message).join("\n"));
  return parsed.data;
}

function productSkuForName(productName, usedSkuByName) {
  const normalizedName = normalizeText(productName);
  const base = normalizeSku(normalizedName) || `PRODUK-${shortHash(normalizedName, 8)}`;
  const existingName = usedSkuByName.get(base);
  if (!existingName || existingName === normalizedName.toUpperCase()) return base;
  return `${base}-${shortHash(normalizedName, 6)}`;
}

const kardusCsvRows = readCsv(kardusInputPath);
const inventoryCsvRows = readCsv(inventoryInputPath);
const packageCsvRows = readCsv(packageInputPath);

const kardusRows = kardusCsvRows.map((row, index) => {
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
for (const row of kardusRows) {
  if (!ownersByCode.has(row.ownerCode)) ownersByCode.set(row.ownerCode, row);
}

const boxesBySourceId = new Map();
const duplicateBoxRows = [];
for (const row of kardusRows) {
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

const allBoxes = Array.from(boxesBySourceId.values());
const boxSourceIds = new Set(allBoxes.map((box) => box.sourceId));

const usedSkuByName = new Map();
const productsByName = new Map();

function ensureProduct(productName, category, unit = "pcs") {
  const normalizedProductName = normalizeText(productName).toUpperCase();
  if (!normalizedProductName) throw new Error("Nama produk kosong");

  const existingProduct = productsByName.get(normalizedProductName);
  if (existingProduct) return existingProduct;

  const cleanProductName = normalizeText(productName);
  const sku = productSkuForName(cleanProductName, usedSkuByName);
  usedSkuByName.set(sku, normalizedProductName);
  const product = {
    id: stableUuid(`gudangku-product:${normalizedProductName}`),
    sku,
    productName: cleanProductName,
    category,
    unit
  };
  productsByName.set(normalizedProductName, product);
  return product;
}

const inventoryRows = inventoryCsvRows.map((row, index) => {
  const rowNo = index + 1;
  const sourceId = normalizeText(row.id);
  const sourceBoxId = normalizeText(row.kardus_id);
  const idBox = sourceIdToIdBox(sourceBoxId);
  const productName = normalizeText(row.product_name);
  if (!productName) throw new Error(`Inventory row ${rowNo}: product_name kosong`);

  const normalizedProductName = productName.toUpperCase();
  const product = ensureProduct(productName, "GudangKu Inventory", "pcs");

  return {
    rowNo,
    sourceId,
    movementTypeSource: normalizeText(row.type).toUpperCase(),
    date: parseClientDate(row.date),
    sourceBoxId,
    idBox,
    productName,
    productNameKey: normalizedProductName,
    sku: product.sku,
    qty: parseQty(row.qty, rowNo),
    price: parseMoney(row.price),
    buyerName: normalizeText(row.buyer_name),
    transferTo: normalizeText(row.transfer_to),
    transferAmount: parseMoney(row.transfer_amount),
    performedBy: normalizeText(row.performed_by),
    notes: normalizeText(row.notes)
  };
});

const missingInventoryBoxes = Array.from(new Set(inventoryRows.filter((row) => !boxSourceIds.has(row.sourceBoxId)).map((row) => row.sourceBoxId)));
if (missingInventoryBoxes.length) {
  throw new Error(`Inventory punya kardus_id yang tidak ada di kardus CSV: ${missingInventoryBoxes.join(", ")}`);
}

const inventoryBoxSourceIds = new Set(inventoryRows.map((row) => row.sourceBoxId));
const boxesWithoutInventory = allBoxes.filter((box) => !inventoryBoxSourceIds.has(box.sourceId));
const boxes = allBoxes.filter((box) => inventoryBoxSourceIds.has(box.sourceId));

const skippedPackageRows = [];
const packageTemplatesByCode = new Map();
const packageItemByKey = new Map();
const packageRows = [];

for (const row of packageCsvRows.map((csvRow, index) => ({ csvRow, rowNo: index + 1 }))) {
  const packageNo = normalizeText(row.csvRow.No);
  const packageName = normalizeText(row.csvRow["Nama Paket"]);
  const productName = normalizeText(row.csvRow.Produk);
  const sourceQty = normalizeText(row.csvRow.Qty);
  const isBlankRow = !packageNo && !packageName && !productName && !sourceQty;
  const isPlaceholderRow = packageNo && !packageName && !productName && !sourceQty;

  if (isBlankRow || isPlaceholderRow) {
    skippedPackageRows.push(row.rowNo);
    continue;
  }

  if (!packageNo || !packageName || !productName || !sourceQty) {
    throw new Error(`Paket row ${row.rowNo}: kolom No, Nama Paket, Produk, dan Qty wajib diisi`);
  }

  const { qty, unit } = parsePackageQty(sourceQty, row.rowNo);
  const packageCode = `GKP-${normalizeSku(packageNo).padStart(3, "0")}`;
  const product = ensureProduct(productName, "GudangKu Package Component", unit);
  const packageTemplate =
    packageTemplatesByCode.get(packageCode) ??
    {
      id: stableUuid(`gudangku-package:${packageNo}:${packageName.toUpperCase()}`),
      packageNo,
      packageCode,
      packageName,
      description: `Import GudangKu paket. no=${packageNo}.`
    };

  if (packageTemplate.packageName.toUpperCase() !== packageName.toUpperCase()) {
    throw new Error(`Paket row ${row.rowNo}: No paket ${packageNo} dipakai untuk nama paket berbeda`);
  }

  packageTemplatesByCode.set(packageCode, packageTemplate);

  const itemKey = `${packageCode}|${product.sku}`;
  const existingItem = packageItemByKey.get(itemKey);
  if (existingItem) {
    existingItem.qtyPerPackage += qty;
    existingItem.sourceRows.push(row.rowNo);
  } else {
    packageItemByKey.set(itemKey, {
      id: stableUuid(`gudangku-package-item:${itemKey}`),
      packageCode,
      sku: product.sku,
      productName,
      qtyPerPackage: qty,
      unit,
      sourceQty,
      sourceRows: [row.rowNo]
    });
  }

  packageRows.push({
    rowNo: row.rowNo,
    packageNo,
    packageCode,
    packageName,
    productName,
    sku: product.sku,
    sourceQty,
    qtyPerPackage: qty,
    unit
  });
}

const packageTemplates = Array.from(packageTemplatesByCode.values()).sort((a, b) => Number(a.packageNo) - Number(b.packageNo));
const packageItems = Array.from(packageItemByKey.values()).sort((a, b) => a.packageCode.localeCompare(b.packageCode) || a.productName.localeCompare(b.productName));
const products = Array.from(productsByName.values()).sort((a, b) => a.productName.localeCompare(b.productName));

const currentQtyByKey = new Map();
const initialQtyByKey = new Map();
const itemMetaByKey = new Map();
const runningQtyByKey = new Map();
const movementRows = [];

for (const row of inventoryRows) {
  const key = `${row.idBox}|${row.sku}`;
  const isIn = row.movementTypeSource === "MASUK";
  const isOut = ["PENJUALAN", "KELUAR", "OUT"].includes(row.movementTypeSource);
  if (!isIn && !isOut) throw new Error(`Inventory row ${row.rowNo}: type tidak dikenali: ${row.movementTypeSource}`);

  const beforeQty = runningQtyByKey.get(key) ?? 0;
  const afterQty = isIn ? beforeQty + row.qty : beforeQty - row.qty;
  if (afterQty < 0) throw new Error(`Inventory row ${row.rowNo}: stok ${row.productName} di ${row.idBox} menjadi negatif`);
  runningQtyByKey.set(key, afterQty);

  currentQtyByKey.set(key, (currentQtyByKey.get(key) ?? 0) + (isIn ? row.qty : -row.qty));
  if (isIn) initialQtyByKey.set(key, (initialQtyByKey.get(key) ?? 0) + row.qty);

  const existingMeta = itemMetaByKey.get(key);
  if (existingMeta) {
    existingMeta.updatedAt = row.date > existingMeta.updatedAt ? row.date : existingMeta.updatedAt;
    existingMeta.sourceRows.push(row.rowNo);
  } else {
    itemMetaByKey.set(key, {
      idBox: row.idBox,
      sku: row.sku,
      createdAt: row.date,
      updatedAt: row.date,
      sourceRows: [row.rowNo]
    });
  }

  movementRows.push({
    id: stableUuid(`gudangku-stock-movement:${row.rowNo}:${row.sourceId}:${row.idBox}:${row.sku}:${row.movementTypeSource}`),
    movementType: isIn ? "in" : "out_partial_item",
    idBox: row.idBox,
    sku: row.sku,
    qty: row.qty,
    beforeQty,
    afterQty,
    scannedBarcode: null,
    reason: isIn ? "Import data client GudangKu inventory" : "Import penjualan client GudangKu inventory",
    notes: [
      `source_id=${row.sourceId}`,
      `type=${row.movementTypeSource}`,
      `product_name=${row.productName}`,
      row.buyerName ? `buyer=${row.buyerName}` : null,
      row.transferTo ? `transfer_to=${row.transferTo}` : null,
      row.price ? `price=${row.price}` : null,
      row.transferAmount ? `transfer_amount=${row.transferAmount}` : null,
      row.notes ? `notes=${row.notes}` : null,
      row.performedBy ? `performed_by=${row.performedBy}` : null
    ].filter(Boolean).join("; "),
    createdAt: row.date
  });
}

const boxItems = Array.from(itemMetaByKey.entries()).map(([key, meta]) => {
  const qtyInitial = initialQtyByKey.get(key) ?? 0;
  const qtyAvailable = currentQtyByKey.get(key) ?? 0;
  if (qtyInitial <= 0) throw new Error(`Box item ${key}: qty_initial kosong`);
  if (qtyAvailable < 0) throw new Error(`Box item ${key}: qty_available negatif`);
  return {
    id: stableUuid(`gudangku-box-item:${key}`),
    idBox: meta.idBox,
    sku: meta.sku,
    qtyInitial,
    qtyAvailable,
    createdAt: meta.createdAt,
    updatedAt: meta.updatedAt,
    sourceRows: meta.sourceRows
  };
});

const rawKardusValues = kardusRows.map((row) =>
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

const rawInventoryValues = inventoryRows.map((row) =>
  valuesRow([
    row.rowNo,
    row.sourceId,
    row.movementTypeSource,
    row.date,
    row.sourceBoxId,
    row.idBox,
    row.productName,
    row.sku,
    row.qty,
    row.price,
    row.buyerName,
    row.transferTo,
    row.transferAmount,
    row.performedBy,
    row.notes
  ])
);

const rawPackageValues = packageRows.map((row) =>
  valuesRow([
    row.rowNo,
    row.packageNo,
    row.packageCode,
    row.packageName,
    row.productName,
    row.sku,
    row.sourceQty,
    row.qtyPerPackage,
    row.unit
  ])
);

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

const packageTemplateValues = packageTemplates.map((packageTemplate) =>
  valuesRow([
    packageTemplate.id,
    packageTemplate.packageCode,
    packageTemplate.packageName,
    packageTemplate.description,
    true
  ])
);

const packageItemValues = packageItems.map((item) =>
  valuesRow([
    item.id,
    item.packageCode,
    item.sku,
    item.qtyPerPackage
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
      "Import GudangKu kardus",
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

const boxItemValues = boxItems.map((item) =>
  valuesRow([
    item.id,
    item.idBox,
    item.sku,
    item.qtyInitial,
    item.qtyAvailable,
    item.createdAt,
    item.updatedAt,
    `source_inventory_rows=${item.sourceRows.join("|")}`
  ])
);

const movementValues = movementRows.map((movement) =>
  valuesRow([
    movement.id,
    movement.movementType,
    movement.idBox,
    movement.sku,
    movement.qty,
    movement.beforeQty,
    movement.afterQty,
    movement.reason,
    movement.notes,
    movement.createdAt
  ])
);

const importBatchKardusUuid = stableUuid(`gudangku-import:${path.basename(kardusInputPath)}:${kardusRows.length}`);
const importBatchInventoryUuid = stableUuid(`gudangku-import:${path.basename(inventoryInputPath)}:${inventoryRows.length}`);
const importBatchPackageUuid = stableUuid(`gudangku-import:${path.basename(packageInputPath)}:${packageRows.length}`);
const errorSummary = duplicateBoxRows.length
  ? `Ada ${duplicateBoxRows.length} baris CSV kardus dengan id box yang sama tetapi metadata berbeda. Master box memakai baris pertama, raw tetap disimpan.`
  : null;

const output = `-- Import full data client GudangKu: kardus + inventory produk asli + paket
-- Source kardus CSV: ${kardusInputPath}
-- Source inventory CSV: ${inventoryInputPath}
-- Source paket CSV: ${packageInputPath}
-- Generated by: scripts/convert-gudangku-full.mjs
-- Kardus rows: ${kardusRows.length}
-- Inventory rows: ${inventoryRows.length}
-- Paket rows: ${packageRows.length}
-- Paket skipped empty rows: ${skippedPackageRows.length}
-- Owners: ${ownersByCode.size}
-- Boxes: ${boxes.length}
-- Kardus boxes without inventory skipped from app boxes: ${boxesWithoutInventory.length}
-- Products: ${products.length}
-- Box items: ${boxItems.length}
-- Stock movements: ${movementRows.length}
-- Package templates: ${packageTemplates.length}
-- Package items: ${packageItems.length}
--
-- Mapping:
-- - raw kardus tetap menyimpan semua baris CSV kardus.
-- - boxes aplikasi hanya dibuat dari id CSV kardus yang muncul sebagai kardus_id di inventory.
-- - boxes dibuat dari kolom id pada CSV kardus: GK-KARDUS-000001, dst.
-- - Jika id kardus sama, dianggap box yang sama.
-- - products dibuat dari product_name Google Sheet inventory, dedupe exact normalized name.
-- - package_templates dibuat dari Nama Paket Google Sheet paket.
-- - package_template_items dibuat dari Produk + Qty Google Sheet paket.
-- - box_items dibuat dari kardus_id + product_name, qty_initial dari total MASUK, qty_available dari MASUK - PENJUALAN.
-- - stock_movements dibuat dari semua baris inventory: MASUK -> in, PENJUALAN -> out_partial_item.

begin;

create extension if not exists pgcrypto;

delete from public.stock_movements
where reason in ('Import data client GudangKu', 'Import data client GudangKu inventory', 'Import penjualan client GudangKu inventory');

delete from public.box_items
where batch_no in ('IMPORT-GUDANGKU', 'IMPORT-GUDANGKU-KARDUS', 'IMPORT-GUDANGKU-PESANAN', 'IMPORT-GUDANGKU-INVENTORY');

delete from public.scan_logs
where box_id in (
  select id from public.boxes
  where notes like 'Import GudangKu kardus%'
);

delete from public.boxes
where notes like 'Import GudangKu kardus%';

delete from public.package_template_items
where package_id in (
  select id from public.package_templates
  where package_code like 'GKP-%'
);

delete from public.package_templates
where package_code like 'GKP-%';

delete from public.products
where sku = 'CLIENT-KARDUS'
   or category in ('GudangKu Kardus', 'GudangKu Pesanan', 'GudangKu Inventory', 'GudangKu Package Component');

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

create table if not exists public.client_gudangku_inventory_raw (
  import_row_no integer primary key,
  client_id text,
  type text,
  date timestamptz,
  kardus_id text,
  mapped_id_box text,
  product_name text,
  mapped_sku text,
  qty numeric,
  price numeric,
  buyer_name text,
  transfer_to text,
  transfer_amount numeric,
  performed_by text,
  notes text,
  imported_at timestamptz not null default now()
);

create table if not exists public.client_gudangku_paket_raw (
  import_row_no integer primary key,
  package_no text,
  package_code text,
  package_name text,
  product_name text,
  mapped_sku text,
  source_qty text,
  qty_per_package numeric,
  unit text,
  imported_at timestamptz not null default now()
);

truncate table
  public.client_gudangku_kardus_raw,
  public.client_gudangku_inventory_raw,
  public.client_gudangku_paket_raw;

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
${rawKardusValues.join(",\n")}
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

insert into public.client_gudangku_inventory_raw(
  import_row_no,
  client_id,
  type,
  date,
  kardus_id,
  mapped_id_box,
  product_name,
  mapped_sku,
  qty,
  price,
  buyer_name,
  transfer_to,
  transfer_amount,
  performed_by,
  notes
)
values
${rawInventoryValues.join(",\n")}
on conflict (import_row_no) do update set
  client_id = excluded.client_id,
  type = excluded.type,
  date = excluded.date,
  kardus_id = excluded.kardus_id,
  mapped_id_box = excluded.mapped_id_box,
  product_name = excluded.product_name,
  mapped_sku = excluded.mapped_sku,
  qty = excluded.qty,
  price = excluded.price,
  buyer_name = excluded.buyer_name,
  transfer_to = excluded.transfer_to,
  transfer_amount = excluded.transfer_amount,
  performed_by = excluded.performed_by,
  notes = excluded.notes,
  imported_at = now();

insert into public.client_gudangku_paket_raw(
  import_row_no,
  package_no,
  package_code,
  package_name,
  product_name,
  mapped_sku,
  source_qty,
  qty_per_package,
  unit
)
values
${rawPackageValues.join(",\n")}
on conflict (import_row_no) do update set
  package_no = excluded.package_no,
  package_code = excluded.package_code,
  package_name = excluded.package_name,
  product_name = excluded.product_name,
  mapped_sku = excluded.mapped_sku,
  source_qty = excluded.source_qty,
  qty_per_package = excluded.qty_per_package,
  unit = excluded.unit,
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

insert into public.package_templates(id, package_code, package_name, description, is_active)
values
${packageTemplateValues.join(",\n")}
on conflict (package_code) do update set
  package_name = excluded.package_name,
  description = excluded.description,
  is_active = excluded.is_active;

with source_package_items(id, package_code, sku, qty_per_package) as (
  values
${packageItemValues.join(",\n")}
)
insert into public.package_template_items(id, package_id, product_id, qty_per_package)
select
  source_package_items.id::uuid,
  package_templates.id,
  products.id,
  source_package_items.qty_per_package::numeric
from source_package_items
join public.package_templates on package_templates.package_code = source_package_items.package_code
join public.products on products.sku = source_package_items.sku
on conflict (package_id, product_id) do update set
  qty_per_package = excluded.qty_per_package;

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

with source_items(id, id_box, sku, qty_initial, qty_available, created_at, updated_at, notes) as (
  values
${boxItemValues.join(",\n")}
)
insert into public.box_items(id, box_id, product_id, qty_initial, qty_available, expired_at, batch_no, created_at, updated_at)
select
  source_items.id::uuid,
  boxes.id,
  products.id,
  source_items.qty_initial::numeric,
  source_items.qty_available::numeric,
  null,
  'IMPORT-GUDANGKU-INVENTORY',
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

with source_movements(id, movement_type, id_box, sku, qty, before_qty, after_qty, reason, notes, created_at) as (
  values
${movementValues.join(",\n")}
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
  source_movements.id::uuid,
  source_movements.movement_type,
  boxes.id,
  boxes.owner_id,
  products.id,
  source_movements.qty::numeric,
  source_movements.before_qty::numeric,
  source_movements.after_qty::numeric,
  boxes.barcode_value,
  source_movements.reason,
  source_movements.notes,
  source_movements.created_at::timestamptz
from source_movements
join public.boxes on boxes.id_box = source_movements.id_box
join public.products on products.sku = source_movements.sku
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
values
  (${sql(importBatchKardusUuid)}, 'client_kardus', ${sql(path.basename(kardusInputPath))}, 'success', ${kardusRows.length}, ${boxes.length}, ${duplicateBoxRows.length}, ${sql(errorSummary)}, now()),
  (${sql(importBatchInventoryUuid)}, 'client_inventory', ${sql(path.basename(inventoryInputPath))}, 'success', ${inventoryRows.length}, ${boxItems.length}, 0, null, now()),
  (${sql(importBatchPackageUuid)}, 'client_package', ${sql(path.basename(packageInputPath))}, 'success', ${packageCsvRows.length}, ${packageRows.length}, 0, ${sql(skippedPackageRows.length ? `Skipped empty rows: ${skippedPackageRows.join(", ")}` : null)}, now())
on conflict (id) do update set
  status = excluded.status,
  total_rows = excluded.total_rows,
  success_rows = excluded.success_rows,
  failed_rows = excluded.failed_rows,
  error_summary = excluded.error_summary,
  completed_at = excluded.completed_at;

commit;
`;

const adminProfileSql = `-- Siapkan user demo untuk login aplikasi.
-- Super User:
-- email: super@demo.local
-- password: super123
-- Admin:
-- email: admin@demo.local
-- password: admin123
do $$
declare
  v_seed record;
  v_user_id uuid;
begin
  for v_seed in
    select *
    from jsonb_to_recordset($seed$
      [
        {
          "id": "00000000-0000-4000-8000-000000000001",
          "email": "super@demo.local",
          "password": "super123",
          "full_name": "Super User Demo",
          "profile_role": "super_admin"
        },
        {
          "id": "00000000-0000-4000-8000-000000000002",
          "email": "admin@demo.local",
          "password": "admin123",
          "full_name": "Admin Demo",
          "profile_role": "admin_gudang"
        }
      ]
    $seed$::jsonb) as seed(id text, email text, password text, full_name text, profile_role text)
  loop
    select id into v_user_id
    from auth.users
    where lower(email) = lower(v_seed.email)
    limit 1;

    if v_user_id is null then
      v_user_id := v_seed.id::uuid;

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
          v_user_id,
          '00000000-0000-0000-0000-000000000000',
          'authenticated',
          'authenticated',
          v_seed.email,
          crypt(v_seed.password, gen_salt('bf')),
          now(),
          '{"provider":"email","providers":["email"]}'::jsonb,
          jsonb_build_object('full_name', v_seed.full_name),
          now(),
          now()
        );
      exception
        when unique_violation then
          select id into v_user_id
          from auth.users
          where lower(email) = lower(v_seed.email)
          limit 1;
        when others then
          raise notice 'Auth user demo tidak dibuat otomatis untuk %: %', v_seed.email, sqlerrm;
          select id into v_user_id
          from auth.users
          where lower(email) = lower(v_seed.email)
          limit 1;
      end;
    else
      update auth.users
      set
        encrypted_password = crypt(v_seed.password, gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"provider":"email","providers":["email"]}'::jsonb,
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('full_name', v_seed.full_name),
        updated_at = now()
      where id = v_user_id;
    end if;

    if v_user_id is not null then
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
          v_user_id::text,
          v_user_id,
          jsonb_build_object('sub', v_user_id::text, 'email', v_seed.email),
          'email',
          now(),
          now(),
          now()
        )
        on conflict do nothing;
      exception
        when others then
          raise notice 'Auth identity demo dilewati untuk %: %', v_seed.email, sqlerrm;
      end;

      insert into public.profiles(id, full_name, email, role, is_active)
      values (v_user_id, v_seed.full_name, v_seed.email, v_seed.profile_role, true)
      on conflict (id) do update set
        full_name = excluded.full_name,
        email = excluded.email,
        role = excluded.role,
        is_active = true;
    end if;
  end loop;
end $$;`;

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, output);

const schemaSql = fs.readFileSync("supabase/migrations/0001_gudang_atomy_schema.sql", "utf8");
const barcodeFixSql = fs.readFileSync("supabase/migrations/0002_fix_barcode_checksum.sql", "utf8");
const fullOutput = `-- Full setup Gudang Atomy + import full data client GudangKu.
-- Jalankan file ini di Supabase SQL Editor.
-- Urutan isi:
-- 1. Schema aplikasi Gudang Atomy
-- 2. Fix barcode checksum
-- 3. Sync user demo Super User + Admin
-- 4. Import GudangKu kardus + inventory produk asli + paket

-- ============================================================
-- 1. Schema aplikasi
-- ============================================================

${schemaSql}

-- ============================================================
-- 2. Fix barcode checksum
-- ============================================================

${barcodeFixSql}

-- ============================================================
-- 3. Sync user demo Super User + Admin
-- ============================================================

${adminProfileSql}

-- ============================================================
-- 4. Import data client GudangKu
-- ============================================================

${output}`;

fs.writeFileSync(DEFAULT_FULL_OUTPUT, fullOutput);

console.log(`Generated ${outputPath}`);
console.log(`Generated ${DEFAULT_FULL_OUTPUT}`);
console.log(`Kardus rows: ${kardusRows.length}`);
console.log(`Inventory rows: ${inventoryRows.length}`);
console.log(`Paket rows: ${packageRows.length}`);
console.log(`Paket skipped empty rows: ${skippedPackageRows.length}`);
console.log(`Owners: ${ownersByCode.size}`);
console.log(`Boxes: ${boxes.length}`);
console.log(`Kardus boxes without inventory skipped from app boxes: ${boxesWithoutInventory.length}`);
console.log(`Products: ${products.length}`);
console.log(`Box items: ${boxItems.length}`);
console.log(`Stock movements: ${movementRows.length}`);
console.log(`Package templates: ${packageTemplates.length}`);
console.log(`Package items: ${packageItems.length}`);
if (duplicateBoxRows.length) console.log(`Duplicate box metadata conflicts: ${duplicateBoxRows.length}`);
