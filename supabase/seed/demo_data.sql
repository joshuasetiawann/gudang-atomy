-- Demo data Gudang Atomy
-- Jalankan setelah migration `0001_gudang_atomy_schema.sql`.
-- Aman dijalankan ulang: semua baris demo memakai UUID tetap dan ON CONFLICT.

begin;

create or replace function pg_temp.demo_barcode_value(p_id_box text)
returns text
language plpgsql
as $$
declare
  v_hash bigint := 0;
  v_index int;
  v_checksum text;
begin
  for v_index in 1..length(p_id_box) loop
    v_hash := mod((v_hash * 31 + ascii(substr(p_id_box, v_index, 1)))::numeric, 4294967296)::bigint;
  end loop;

  v_checksum := right(public.to_base36(v_hash), 4);
  if length(v_checksum) < 4 then
    v_checksum := lpad(v_checksum, 4, '0');
  end if;

  return 'ATMY_BOX:' || p_id_box || ':' || v_checksum;
end;
$$;

insert into public.owners(id, owner_code, owner_name, phone, atomy_member_id, notes, is_active)
values
  ('10000000-0000-0000-0000-000000000101', 'OWN-000101', 'Ana Wijaya Demo', '0812-0000-0101', 'ATM-DEMO-101', 'Owner demo untuk box aktif dan empty', true),
  ('10000000-0000-0000-0000-000000000102', 'OWN-000102', 'Budi Santoso Demo', '0812-0000-0102', 'ATM-DEMO-102', 'Owner demo untuk box partial dan expired', true),
  ('10000000-0000-0000-0000-000000000103', 'OWN-000103', 'Citra Lestari Demo', '0812-0000-0103', 'ATM-DEMO-103', 'Owner demo untuk box taken', true),
  ('10000000-0000-0000-0000-000000000104', 'OWN-000104', 'Gudang Internal Demo', null, null, 'Owner demo untuk box void/koreksi', true)
on conflict (id) do update set
  owner_code = excluded.owner_code,
  owner_name = excluded.owner_name,
  phone = excluded.phone,
  atomy_member_id = excluded.atomy_member_id,
  notes = excluded.notes,
  is_active = excluded.is_active;

insert into public.products(id, sku, product_name, category, unit, default_barcode, is_active)
values
  ('20000000-0000-0000-0000-000000000101', 'DEMO-TONER', 'Atomy Toner Demo', 'Skincare', 'pcs', null, true),
  ('20000000-0000-0000-0000-000000000102', 'DEMO-LOTION', 'Atomy Lotion Demo', 'Skincare', 'pcs', null, true),
  ('20000000-0000-0000-0000-000000000103', 'DEMO-CREAM', 'Atomy Cream Demo', 'Skincare', 'pcs', null, true),
  ('20000000-0000-0000-0000-000000000104', 'DEMO-CLEANSER', 'Atomy Cleanser Demo', 'Skincare', 'pcs', null, true),
  ('20000000-0000-0000-0000-000000000105', 'DEMO-SUNSCREEN', 'Atomy Sunscreen Demo', 'Skincare', 'pcs', null, true),
  ('20000000-0000-0000-0000-000000000106', 'DEMO-HMO', 'Atomy HemoHIM Demo', 'Health', 'box', null, true),
  ('20000000-0000-0000-0000-000000000107', 'DEMO-TOOTHPASTE', 'Atomy Toothpaste Demo', 'Daily Care', 'pcs', null, true),
  ('20000000-0000-0000-0000-000000000108', 'DEMO-VITC', 'Atomy Vitamin C Demo', 'Health', 'pcs', null, true)
on conflict (id) do update set
  sku = excluded.sku,
  product_name = excluded.product_name,
  category = excluded.category,
  unit = excluded.unit,
  default_barcode = excluded.default_barcode,
  is_active = excluded.is_active;

insert into public.package_templates(id, package_code, package_name, description, is_active)
values
  ('30000000-0000-0000-0000-000000000101', 'PKG-DEMO-SKINCARE', 'Paket Skincare Demo', 'Toner, lotion, cream, cleanser, sunscreen masing-masing 1 pcs.', true),
  ('30000000-0000-0000-0000-000000000102', 'PKG-DEMO-FAMILY', 'Paket Family Care Demo', 'Toothpaste 2 pcs, HemoHIM 1 box, Vitamin C 1 pcs.', true)
on conflict (id) do update set
  package_code = excluded.package_code,
  package_name = excluded.package_name,
  description = excluded.description,
  is_active = excluded.is_active;

insert into public.package_template_items(id, package_id, product_id, qty_per_package)
values
  ('31000000-0000-0000-0000-000000000101', '30000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000101', 1),
  ('31000000-0000-0000-0000-000000000102', '30000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000102', 1),
  ('31000000-0000-0000-0000-000000000103', '30000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000103', 1),
  ('31000000-0000-0000-0000-000000000104', '30000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000104', 1),
  ('31000000-0000-0000-0000-000000000105', '30000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000105', 1),
  ('31000000-0000-0000-0000-000000000106', '30000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000107', 2),
  ('31000000-0000-0000-0000-000000000107', '30000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000106', 1),
  ('31000000-0000-0000-0000-000000000108', '30000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000108', 1)
on conflict (id) do update set
  package_id = excluded.package_id,
  product_id = excluded.product_id,
  qty_per_package = excluded.qty_per_package;

insert into public.boxes(
  id, id_box, pemilik_id_box, barcode_value, box_name, owner_id, source_type,
  package_id, package_qty, expired_at, location_code, status, created_at,
  updated_at, checked_out_at, notes
)
values
  (
    '40000000-0000-0000-0000-000000000101',
    'BOX-20260614-000101',
    'OWN-000101-BOX-20260614-000101',
    pg_temp.demo_barcode_value('BOX-20260614-000101'),
    'Demo Box Skincare Aktif',
    '10000000-0000-0000-0000-000000000101',
    'package',
    '30000000-0000-0000-0000-000000000101',
    2,
    '2027-01-20',
    'Rak A1',
    'active',
    '2026-06-14 08:00:00+07',
    now(),
    null,
    'Box aktif dari paket skincare x2'
  ),
  (
    '40000000-0000-0000-0000-000000000102',
    'BOX-20260614-000102',
    'OWN-000102-BOX-20260614-000102',
    pg_temp.demo_barcode_value('BOX-20260614-000102'),
    'Demo Box Family Partial',
    '10000000-0000-0000-0000-000000000102',
    'mixed',
    '30000000-0000-0000-0000-000000000102',
    1,
    '2026-12-10',
    'Rak B2',
    'partial',
    '2026-06-14 09:00:00+07',
    now(),
    null,
    'Box partial: sebagian toothpaste dan vitamin C sudah diambil'
  ),
  (
    '40000000-0000-0000-0000-000000000103',
    'BOX-20260614-000103',
    'OWN-000103-BOX-20260614-000103',
    pg_temp.demo_barcode_value('BOX-20260614-000103'),
    'Demo Box Custom Taken',
    '10000000-0000-0000-0000-000000000103',
    'custom',
    null,
    0,
    '2026-11-30',
    'Rak C3',
    'taken',
    '2026-06-13 15:20:00+07',
    now(),
    '2026-06-14 11:15:00+07',
    'Box sudah diambil penuh'
  ),
  (
    '40000000-0000-0000-0000-000000000104',
    'BOX-20260614-000104',
    'OWN-000101-BOX-20260614-000104',
    pg_temp.demo_barcode_value('BOX-20260614-000104'),
    'Demo Box Empty',
    '10000000-0000-0000-0000-000000000101',
    'custom',
    null,
    0,
    '2026-09-15',
    'Rak A2',
    'empty',
    '2026-06-12 10:00:00+07',
    now(),
    null,
    'Box habis karena pengambilan per produk'
  ),
  (
    '40000000-0000-0000-0000-000000000105',
    'BOX-20260614-000105',
    'OWN-000102-BOX-20260614-000105',
    pg_temp.demo_barcode_value('BOX-20260614-000105'),
    'Demo Box Expired Soon',
    '10000000-0000-0000-0000-000000000102',
    'custom',
    null,
    0,
    '2026-06-25',
    'Rak EXP-1',
    'active',
    '2026-06-14 13:45:00+07',
    now(),
    null,
    'Box aktif yang mendekati expired'
  ),
  (
    '40000000-0000-0000-0000-000000000106',
    'BOX-20260614-000106',
    'OWN-000104-BOX-20260614-000106',
    pg_temp.demo_barcode_value('BOX-20260614-000106'),
    'Demo Box Void Koreksi',
    '10000000-0000-0000-0000-000000000104',
    'custom',
    null,
    0,
    '2026-10-01',
    'Rak HOLD',
    'void',
    '2026-06-13 17:30:00+07',
    now(),
    null,
    'Void demo karena salah input'
  )
on conflict (id) do update set
  id_box = excluded.id_box,
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
  created_at = excluded.created_at,
  updated_at = excluded.updated_at,
  checked_out_at = excluded.checked_out_at,
  notes = excluded.notes;

insert into public.box_items(id, box_id, product_id, qty_initial, qty_available, expired_at, batch_no)
values
  ('41000000-0000-0000-0000-000000000101', '40000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000101', 2, 2, '2027-01-20', 'SKN-ACT-001'),
  ('41000000-0000-0000-0000-000000000102', '40000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000102', 2, 2, '2027-01-20', 'SKN-ACT-001'),
  ('41000000-0000-0000-0000-000000000103', '40000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000103', 2, 2, '2027-01-20', 'SKN-ACT-001'),
  ('41000000-0000-0000-0000-000000000104', '40000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000104', 2, 2, '2027-01-20', 'SKN-ACT-001'),
  ('41000000-0000-0000-0000-000000000105', '40000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000105', 2, 2, '2027-01-20', 'SKN-ACT-001'),
  ('41000000-0000-0000-0000-000000000106', '40000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000107', 2, 1, '2026-12-10', 'FAM-PAR-001'),
  ('41000000-0000-0000-0000-000000000107', '40000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000106', 1, 1, '2026-12-10', 'FAM-PAR-001'),
  ('41000000-0000-0000-0000-000000000108', '40000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000108', 4, 2, '2026-12-10', 'FAM-PAR-001'),
  ('41000000-0000-0000-0000-000000000109', '40000000-0000-0000-0000-000000000103', '20000000-0000-0000-0000-000000000106', 10, 0, '2026-11-30', 'TAKEN-001'),
  ('41000000-0000-0000-0000-000000000110', '40000000-0000-0000-0000-000000000103', '20000000-0000-0000-0000-000000000107', 12, 0, '2026-11-30', 'TAKEN-001'),
  ('41000000-0000-0000-0000-000000000111', '40000000-0000-0000-0000-000000000104', '20000000-0000-0000-0000-000000000105', 5, 0, '2026-09-15', 'EMPTY-001'),
  ('41000000-0000-0000-0000-000000000112', '40000000-0000-0000-0000-000000000105', '20000000-0000-0000-0000-000000000103', 8, 8, '2026-06-25', 'EXP-001'),
  ('41000000-0000-0000-0000-000000000113', '40000000-0000-0000-0000-000000000106', '20000000-0000-0000-0000-000000000108', 3, 0, '2026-10-01', 'VOID-001')
on conflict (id) do update set
  box_id = excluded.box_id,
  product_id = excluded.product_id,
  qty_initial = excluded.qty_initial,
  qty_available = excluded.qty_available,
  expired_at = excluded.expired_at,
  batch_no = excluded.batch_no;

insert into public.stock_movements(
  id, movement_type, box_id, owner_id, product_id, qty, before_qty, after_qty,
  scanned_barcode, reason, notes, created_at
)
values
  ('50000000-0000-0000-0000-000000000101', 'in', '40000000-0000-0000-0000-000000000101', '10000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000101', 2, 0, 2, null, null, 'Demo receive skincare toner', '2026-06-14 08:00:00+07'),
  ('50000000-0000-0000-0000-000000000102', 'in', '40000000-0000-0000-0000-000000000101', '10000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000102', 2, 0, 2, null, null, 'Demo receive skincare lotion', '2026-06-14 08:00:00+07'),
  ('50000000-0000-0000-0000-000000000103', 'in', '40000000-0000-0000-0000-000000000101', '10000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000103', 2, 0, 2, null, null, 'Demo receive skincare cream', '2026-06-14 08:00:00+07'),
  ('50000000-0000-0000-0000-000000000104', 'in', '40000000-0000-0000-0000-000000000101', '10000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000104', 2, 0, 2, null, null, 'Demo receive skincare cleanser', '2026-06-14 08:00:00+07'),
  ('50000000-0000-0000-0000-000000000105', 'in', '40000000-0000-0000-0000-000000000101', '10000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000105', 2, 0, 2, null, null, 'Demo receive skincare sunscreen', '2026-06-14 08:00:00+07'),
  ('50000000-0000-0000-0000-000000000106', 'in', '40000000-0000-0000-0000-000000000102', '10000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000107', 2, 0, 2, null, null, 'Demo receive family toothpaste', '2026-06-14 09:00:00+07'),
  ('50000000-0000-0000-0000-000000000107', 'in', '40000000-0000-0000-0000-000000000102', '10000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000106', 1, 0, 1, null, null, 'Demo receive family HemoHIM', '2026-06-14 09:00:00+07'),
  ('50000000-0000-0000-0000-000000000108', 'in', '40000000-0000-0000-0000-000000000102', '10000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000108', 4, 0, 4, null, null, 'Demo receive mixed Vitamin C', '2026-06-14 09:00:00+07'),
  ('50000000-0000-0000-0000-000000000109', 'out_partial_item', '40000000-0000-0000-0000-000000000102', '10000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000107', 1, 2, 1, pg_temp.demo_barcode_value('BOX-20260614-000102'), 'Demo ambil toothpaste sebagian', null, '2026-06-14 10:30:00+07'),
  ('50000000-0000-0000-0000-000000000110', 'out_partial_item', '40000000-0000-0000-0000-000000000102', '10000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000108', 2, 4, 2, pg_temp.demo_barcode_value('BOX-20260614-000102'), 'Demo ambil vitamin C sebagian', null, '2026-06-14 10:35:00+07'),
  ('50000000-0000-0000-0000-000000000111', 'in', '40000000-0000-0000-0000-000000000103', '10000000-0000-0000-0000-000000000103', '20000000-0000-0000-0000-000000000106', 10, 0, 10, null, null, 'Demo receive taken HemoHIM', '2026-06-13 15:20:00+07'),
  ('50000000-0000-0000-0000-000000000112', 'in', '40000000-0000-0000-0000-000000000103', '10000000-0000-0000-0000-000000000103', '20000000-0000-0000-0000-000000000107', 12, 0, 12, null, null, 'Demo receive taken toothpaste', '2026-06-13 15:20:00+07'),
  ('50000000-0000-0000-0000-000000000113', 'out_full_box', '40000000-0000-0000-0000-000000000103', '10000000-0000-0000-0000-000000000103', '20000000-0000-0000-0000-000000000106', 10, 10, 0, pg_temp.demo_barcode_value('BOX-20260614-000103'), 'Demo ambil full box', null, '2026-06-14 11:15:00+07'),
  ('50000000-0000-0000-0000-000000000114', 'out_full_box', '40000000-0000-0000-0000-000000000103', '10000000-0000-0000-0000-000000000103', '20000000-0000-0000-0000-000000000107', 12, 12, 0, pg_temp.demo_barcode_value('BOX-20260614-000103'), 'Demo ambil full box', null, '2026-06-14 11:15:00+07'),
  ('50000000-0000-0000-0000-000000000115', 'in', '40000000-0000-0000-0000-000000000104', '10000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000105', 5, 0, 5, null, null, 'Demo receive empty sunscreen', '2026-06-12 10:00:00+07'),
  ('50000000-0000-0000-0000-000000000116', 'out_partial_item', '40000000-0000-0000-0000-000000000104', '10000000-0000-0000-0000-000000000101', '20000000-0000-0000-0000-000000000105', 5, 5, 0, pg_temp.demo_barcode_value('BOX-20260614-000104'), 'Demo ambil seluruh item per produk', null, '2026-06-14 12:05:00+07'),
  ('50000000-0000-0000-0000-000000000117', 'in', '40000000-0000-0000-0000-000000000105', '10000000-0000-0000-0000-000000000102', '20000000-0000-0000-0000-000000000103', 8, 0, 8, null, null, 'Demo receive expired soon cream', '2026-06-14 13:45:00+07'),
  ('50000000-0000-0000-0000-000000000118', 'in', '40000000-0000-0000-0000-000000000106', '10000000-0000-0000-0000-000000000104', '20000000-0000-0000-0000-000000000108', 3, 0, 3, null, null, 'Demo receive void Vitamin C', '2026-06-13 17:30:00+07'),
  ('50000000-0000-0000-0000-000000000119', 'void', '40000000-0000-0000-0000-000000000106', '10000000-0000-0000-0000-000000000104', '20000000-0000-0000-0000-000000000108', 3, 3, 0, null, 'Salah input demo', null, '2026-06-13 17:45:00+07')
on conflict (id) do update set
  movement_type = excluded.movement_type,
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

insert into public.scan_logs(id, scan_type, raw_value, box_id, result, message, created_at)
values
  ('60000000-0000-0000-0000-000000000101', 'lookup', pg_temp.demo_barcode_value('BOX-20260614-000101'), '40000000-0000-0000-0000-000000000101', 'success', 'Demo lookup box aktif', '2026-06-14 09:20:00+07'),
  ('60000000-0000-0000-0000-000000000102', 'check_out', pg_temp.demo_barcode_value('BOX-20260614-000102'), '40000000-0000-0000-0000-000000000102', 'success', 'Demo checkout partial berhasil', '2026-06-14 10:30:00+07'),
  ('60000000-0000-0000-0000-000000000103', 'check_out', pg_temp.demo_barcode_value('BOX-20260614-000103'), '40000000-0000-0000-0000-000000000103', 'already_taken', 'Demo box sudah pernah diambil', '2026-06-14 12:30:00+07'),
  ('60000000-0000-0000-0000-000000000104', 'lookup', 'ATMY_BOX:BOX-20260614-999999:XXXX', null, 'not_found', 'Demo barcode tidak ditemukan', '2026-06-14 12:35:00+07'),
  ('60000000-0000-0000-0000-000000000105', 'lookup', 'SALAH-FORMAT-DEMO', null, 'invalid', 'Demo format barcode tidak valid', '2026-06-14 12:40:00+07')
on conflict (id) do update set
  scan_type = excluded.scan_type,
  raw_value = excluded.raw_value,
  box_id = excluded.box_id,
  result = excluded.result,
  message = excluded.message,
  created_at = excluded.created_at;

insert into public.import_batches(
  id, import_type, file_name, status, total_rows, success_rows, failed_rows,
  error_summary, created_at, completed_at
)
values
  (
    '70000000-0000-0000-0000-000000000101',
    'owners',
    'demo_owners.csv',
    'success',
    4,
    4,
    0,
    null,
    '2026-06-14 07:30:00+07',
    '2026-06-14 07:31:00+07'
  ),
  (
    '70000000-0000-0000-0000-000000000102',
    'products',
    'demo_products.csv',
    'success',
    8,
    8,
    0,
    null,
    '2026-06-14 07:35:00+07',
    '2026-06-14 07:36:00+07'
  )
on conflict (id) do update set
  import_type = excluded.import_type,
  file_name = excluded.file_name,
  status = excluded.status,
  total_rows = excluded.total_rows,
  success_rows = excluded.success_rows,
  failed_rows = excluded.failed_rows,
  error_summary = excluded.error_summary,
  created_at = excluded.created_at,
  completed_at = excluded.completed_at;

select setval('public.owner_number_seq', greatest((select last_value from public.owner_number_seq), 200), true);
select setval('public.box_number_seq', greatest((select last_value from public.box_number_seq), 200), true);

commit;
