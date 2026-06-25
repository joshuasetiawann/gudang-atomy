-- =====================================================================
-- Import box hasil SORTIR (format baru "BSTR-") — pemilik: Bunda
-- =====================================================================
-- Sumber: data ketikan 23–24 Juni 2026 (50 baris).
-- Target tabel existing: owners, products, boxes, box_items.
-- Idempotent: aman dijalankan ulang (pakai ON CONFLICT / WHERE NOT EXISTS).
-- Jalankan di Supabase SQL Editor (role postgres/service_role → bypass RLS).
--
-- CATATAN: TIDAK pakai temporary table. Di Supabase SQL Editor tiap statement
-- seakan auto-commit, jadi "create temp table ... on commit drop" langsung
-- terhapus → error "relation _bstr_stg does not exist". Versi ini pakai CTE
-- (VALUES) supaya semua jalan dalam 1 statement. Aman.
--
-- Konvensi:
--   id_box         = kode BSTR (mis. BSTR-EOP-0001)
--   pemilik_id_box = <owner_code>-<id_box>  (mis. OWN-000006-BSTR-EOP-0001) → mengandung ID owner
--   barcode_value  = public.build_box_barcode_value(id_box)  → ATMY_BOX:<kode>:<checksum>
--   source_type    = 'custom'  (1 box = 1 jenis barang)
--   location_code  = 'GUDANG KAPUK' (semua box)
--   created_at     = kolom "Waktu" saat box disortir (WIB / +07)
--
-- CATATAN DATA:
--   • BSTR-EOP-0005  -> HILANG. Urutan EOP loncat 0004 → 0006.
--                       Template insert-nya ada di bagian paling bawah (di-comment).
--   • BSTR-HEMO-0009 -> DOBEL di data asli (baris 33 & 35). Karena id_box WAJIB UNIK, box ke-2
--                       diberi kode BSTR-HEMO-0009-2 supaya 2-2nya benar tersimpan → total 50 box.
-- =====================================================================

-- ---- 1) Owner: Bunda -------------------------------------------------
insert into public.owners (owner_code, owner_name, notes)
select public.generate_owner_code(), 'Bunda', 'Pemilik barang hasil sortir BSTR'
where not exists (
  select 1 from public.owners where lower(owner_name) = 'bunda'
);

-- ---- 2) Products (master barang) ------------------------------------
insert into public.products (sku, product_name, category, unit) values
  ('ATM-EOP',  'Atomy Ethereal Oil Patch',     'Kesehatan', 'pcs'),
  ('ATM-FZ',   'Atomy Finezyme',               'Kesehatan', 'pcs'),
  ('ATM-VITC', 'Atomy Color Food Vitamin C',   'Kesehatan', 'pcs'),
  ('ATM-HEMO', 'Hemohim 1 Set',                'Kesehatan', 'pcs'),
  ('ATM-PH',   'Atomy Psyllium Husk',          'Kesehatan', 'pcs'),
  ('ATM-HSD',  'Atomy Hongsamdan Red Ginseng', 'Kesehatan', 'pcs')
on conflict (sku) do nothing;

-- ---- 3) Boxes + 4) Box items (1 statement, tanpa temp table) --------
with src(id_box, sku, qty, expired_at, created_at) as (
  values
    ('BSTR-EOP-0001',  'ATM-EOP',  10, date '2029-01-18', timestamptz '2026-06-23 23:51+07'),
    ('BSTR-FZ-0001',   'ATM-FZ',   12, date '2027-09-18', timestamptz '2026-06-23 23:57+07'),
    ('BSTR-VITC-0001', 'ATM-VITC', 14, date '2027-09-11', timestamptz '2026-06-24 00:07+07'),
    ('BSTR-FZ-0002',   'ATM-FZ',   14, date '2027-12-09', timestamptz '2026-06-24 01:51+07'),
    ('BSTR-FZ-0003',   'ATM-FZ',   12, date '2027-09-18', timestamptz '2026-06-24 01:52+07'),
    ('BSTR-VITC-0002', 'ATM-VITC', 14, date '2027-12-14', timestamptz '2026-06-24 01:59+07'),
    ('BSTR-HEMO-0001', 'ATM-HEMO',  5, date '2027-12-10', timestamptz '2026-06-24 02:04+07'),
    ('BSTR-HEMO-0002', 'ATM-HEMO',  5, date '2027-12-10', timestamptz '2026-06-24 02:04+07'),
    ('BSTR-HEMO-0003', 'ATM-HEMO',  5, date '2027-12-10', timestamptz '2026-06-24 02:04+07'),
    ('BSTR-HEMO-0004', 'ATM-HEMO',  5, date '2027-12-10', timestamptz '2026-06-24 02:04+07'),
    ('BSTR-HEMO-0005', 'ATM-HEMO',  5, date '2027-12-10', timestamptz '2026-06-24 02:04+07'),
    ('BSTR-HEMO-0006', 'ATM-HEMO',  5, date '2027-12-10', timestamptz '2026-06-24 02:04+07'),
    ('BSTR-PH-0001',   'ATM-PH',   17, date '2027-11-12', timestamptz '2026-06-24 02:11+07'),
    ('BSTR-HSD-0001',  'ATM-HSD',   8, date '2027-11-01', timestamptz '2026-06-24 02:15+07'),
    ('BSTR-HSD-0002',  'ATM-HSD',   8, date '2027-11-01', timestamptz '2026-06-24 02:16+07'),
    ('BSTR-HSD-0003',  'ATM-HSD',   8, date '2027-11-01', timestamptz '2026-06-24 02:19+07'),
    ('BSTR-HSD-0004',  'ATM-HSD',   8, date '2027-11-01', timestamptz '2026-06-24 02:20+07'),
    ('BSTR-EOP-0002',  'ATM-EOP',   8, date '2029-01-18', timestamptz '2026-06-24 02:22+07'),
    ('BSTR-EOP-0003',  'ATM-EOP',   8, date '2029-01-18', timestamptz '2026-06-24 02:26+07'),
    ('BSTR-HSD-0005',  'ATM-HSD',   8, date '2027-11-01', timestamptz '2026-06-24 02:27+07'),
    ('BSTR-HSD-0006',  'ATM-HSD',   8, date '2027-11-01', timestamptz '2026-06-24 02:30+07'),
    ('BSTR-HSD-0007',  'ATM-HSD',   8, date '2027-11-01', timestamptz '2026-06-24 02:33+07'),
    ('BSTR-HSD-0008',  'ATM-HSD',   8, date '2027-11-01', timestamptz '2026-06-24 02:33+07'),
    ('BSTR-FZ-0004',   'ATM-FZ',   12, date '2027-09-18', timestamptz '2026-06-24 02:35+07'),
    ('BSTR-EOP-0004',  'ATM-EOP',   8, date '2029-01-18', timestamptz '2026-06-24 02:40+07'),
    ('BSTR-EOP-0006',  'ATM-EOP',   8, date '2029-01-18', timestamptz '2026-06-24 02:46+07'),  -- NB: 0005 hilang
    ('BSTR-HSD-0009',  'ATM-HSD',   8, date '2027-11-01', timestamptz '2026-06-24 03:02+07'),
    ('BSTR-HSD-0010',  'ATM-HSD',   8, date '2027-11-01', timestamptz '2026-06-24 06:27+07'),
    ('BSTR-HEMO-0007', 'ATM-HEMO',  5, date '2027-10-10', timestamptz '2026-06-24 06:27+07'),
    ('BSTR-HEMO-0008', 'ATM-HEMO',  5, date '2027-10-10', timestamptz '2026-06-24 06:28+07'),
    ('BSTR-FZ-0005',   'ATM-FZ',   12, date '2027-12-01', timestamptz '2026-06-24 06:29+07'),
    ('BSTR-HSD-0011',  'ATM-HSD',   8, date '2027-11-01', timestamptz '2026-06-24 06:33+07'),
    ('BSTR-HEMO-0009',   'ATM-HEMO',  5, date '2027-10-10', timestamptz '2026-06-24 06:36+07'),  -- baris 33
    ('BSTR-HEMO-0009-2', 'ATM-HEMO',  5, date '2027-10-10', timestamptz '2026-06-24 06:46+07'),  -- baris 35: kembar 0009 → kode dibedakan jadi -2 supaya 2-2nya tersimpan
    ('BSTR-EOP-0007',  'ATM-EOP',   8, date '2029-01-18', timestamptz '2026-06-24 06:40+07'),
    ('BSTR-HEMO-0010', 'ATM-HEMO',  5, date '2027-10-10', timestamptz '2026-06-24 06:46+07'),
    ('BSTR-HEMO-0011', 'ATM-HEMO',  5, date '2027-10-10', timestamptz '2026-06-24 06:46+07'),
    ('BSTR-HEMO-0012', 'ATM-HEMO',  5, date '2027-10-10', timestamptz '2026-06-24 06:46+07'),
    ('BSTR-HEMO-0013', 'ATM-HEMO',  5, date '2027-10-10', timestamptz '2026-06-24 06:46+07'),
    ('BSTR-VITC-0003', 'ATM-VITC', 12, date '2027-12-14', timestamptz '2026-06-24 06:50+07'),
    ('BSTR-VITC-0004', 'ATM-VITC', 12, date '2027-12-14', timestamptz '2026-06-24 06:51+07'),
    ('BSTR-HEMO-0014', 'ATM-HEMO',  5, date '2027-12-01', timestamptz '2026-06-24 06:52+07'),
    ('BSTR-HEMO-0015', 'ATM-HEMO',  5, date '2027-11-01', timestamptz '2026-06-24 06:54+07'),
    ('BSTR-HEMO-0016', 'ATM-HEMO',  5, date '2027-11-01', timestamptz '2026-06-24 06:54+07'),
    ('BSTR-HEMO-0017', 'ATM-HEMO',  5, date '2027-11-01', timestamptz '2026-06-24 06:54+07'),
    ('BSTR-VITC-0005', 'ATM-VITC', 12, date '2027-12-01', timestamptz '2026-06-24 07:02+07'),
    ('BSTR-HEMO-0018', 'ATM-HEMO',  5, date '2027-10-01', timestamptz '2026-06-24 07:06+07'),
    ('BSTR-HSD-0012',  'ATM-HSD',   8, date '2027-12-01', timestamptz '2026-06-24 07:10+07'),
    ('BSTR-HEMO-0019', 'ATM-HEMO',  5, date '2027-11-01', timestamptz '2026-06-24 07:11+07'),
    ('BSTR-HSD-0013',  'ATM-HSD',   8, date '2027-11-01', timestamptz '2026-06-24 07:14+07')
),
own as (
  select id, owner_code from public.owners where lower(owner_name) = 'bunda' limit 1
),
new_boxes as (
  insert into public.boxes (
    id_box, pemilik_id_box, barcode_value, box_name,
    owner_id, source_type, package_qty, expired_at, location_code, status, created_at
  )
  select
    s.id_box,
    o.owner_code || '-' || s.id_box,          -- pemilik_id_box = <owner_code>-<id_box>
    public.build_box_barcode_value(s.id_box),
    p.product_name,
    o.id,
    'custom',
    0,
    s.expired_at,
    'GUDANG KAPUK',                           -- location_code: semua box di Gudang Kapuk
    'active',
    s.created_at
  from src s
  join public.products p on p.sku = s.sku
  cross join own o
  on conflict (id_box) do nothing
  returning id, id_box
)
insert into public.box_items (box_id, product_id, qty_initial, qty_available, expired_at)
select nb.id, p.id, s.qty, s.qty, s.expired_at
from src s
join new_boxes nb on nb.id_box = s.id_box
join public.products p on p.sku = s.sku
on conflict (box_id, product_id, expired_at, batch_no) do nothing;

-- ---- 5) Verifikasi: rekap per produk --------------------------------
select
  p.product_name,
  count(*)              as jumlah_box,
  sum(bi.qty_initial)   as total_pcs
from public.boxes b
join public.box_items bi on bi.box_id = b.id
join public.products  p  on p.id = bi.product_id
where b.id_box like 'BSTR-%'
group by p.product_name
order by p.product_name;

-- =====================================================================
-- TEMPLATE — BSTR-EOP-0005 (data hilang). Lengkapi qty & exp lalu jalankan.
-- =====================================================================
-- with own as (
--   select id, owner_code from public.owners where lower(owner_name)='bunda' limit 1
-- ),
-- new_box as (
--   insert into public.boxes (id_box, pemilik_id_box, barcode_value, box_name,
--     owner_id, source_type, package_qty, expired_at, location_code, status)
--   select 'BSTR-EOP-0005', o.owner_code || '-BSTR-EOP-0005',
--          public.build_box_barcode_value('BSTR-EOP-0005'),
--          'Atomy Ethereal Oil Patch',
--          o.id, 'custom', 0, date '2029-01-18', 'GUDANG KAPUK', 'active'
--   from own o
--   on conflict (id_box) do nothing
--   returning id
-- )
-- insert into public.box_items (box_id, product_id, qty_initial, qty_available, expired_at)
-- select nb.id, p.id, /*QTY*/ 8, /*QTY*/ 8, date '2029-01-18'
-- from new_box nb, public.products p
-- where p.sku = 'ATM-EOP'
-- on conflict (box_id, product_id, expired_at, batch_no) do nothing;
