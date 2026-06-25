-- =====================================================================
-- Import box SORTIR batch 2 — lokasi: KANTOR BUNDA (pemilik: Bunda)
-- =====================================================================
-- Isi: 1 box single (BSTR-EOP-0005) + 5 box CAMPURAN (BSTR-MIX-0001..0005).
-- Total 6 box, 13 item. Tanpa temp table (CTE) → aman di Supabase SQL Editor.
-- Idempotent: ON CONFLICT DO NOTHING.
--
-- Beda dari batch Gudang Kapuk:
--   • location_code = 'Kantor Bunda'
--   • BSTR-MIX-xxxx -> source_type = 'mixed', 1 box berisi BANYAK produk
--   • Item MIX tidak punya exp date → expired_at NULL
--   • + 10 produk baru ditambahkan ke master `products`
--
-- Catatan: kalau batch Gudang Kapuk (bstr_bunda_import.sql) belum dijalankan,
-- file ini tetap jalan sendiri (owner & produk yang dipakai ikut di-insert).
-- =====================================================================

-- ---- 1) Owner: Bunda (kalau belum ada) ------------------------------
insert into public.owners (owner_code, owner_name, notes)
select public.generate_owner_code(), 'Bunda', 'Pemilik barang hasil sortir BSTR'
where not exists (
  select 1 from public.owners where lower(owner_name) = 'bunda'
);

-- ---- 2) Products: yang dipakai (lama + baru) ------------------------
insert into public.products (sku, product_name, category, unit) values
  -- dipakai ulang (sudah ada dari batch Gudang Kapuk)
  ('ATM-EOP',        'Atomy Ethereal Oil Patch',          'Kesehatan', 'pcs'),
  ('ATM-FZ',         'Atomy Finezyme',                    'Kesehatan', 'pcs'),
  ('ATM-VITC',       'Atomy Color Food Vitamin C',        'Kesehatan', 'pcs'),
  -- produk baru
  ('ATM-HRB-SHMP',   'Atomy Herbal Hair Shampoo',         'Personal',  'pcs'),
  ('ATM-HRB-BODY',   'Atomy Herbal Body Cleanser',        'Personal',  'pcs'),
  ('ATM-HRB-COND',   'Atomy Herbal Hair Conditioner',     'Personal',  'pcs'),
  ('ATM-SCALP-SHMP', 'Atomy Scalpcare Hair Shampoo',      'Personal',  'pcs'),
  ('ATM-TP-MINT',    'Atomy Bright Teeth Mint Toothpaste','Personal',  'pcs'),
  ('ATM-TP-PROP4',   'Atomy Toothpaste Propolis Isi 4',   'Personal',  'pcs'),
  ('ATM-TP-PROP200', 'Atomy Propolis Toothpaste 200g',    'Personal',  'pcs'),
  ('ATM-TBRUSH8',    'Atomy Toothbrush Isi 8',            'Personal',  'pcs'),
  ('ATM-CAFE50',     'Atomy Cafe Arabica 50 Sticks',      'Minuman',   'pcs'),
  ('ATM-CAFE200',    'Atomy Cafe Arabica 200 Sticks',     'Minuman',   'pcs')
on conflict (sku) do nothing;

-- ---- 3) Boxes + 4) Box items (1 statement, tanpa temp table) --------
with box_src(id_box, box_name, source_type, expired_at) as (
  values
    ('BSTR-EOP-0005', 'Atomy Ethereal Oil Patch', 'custom', date '2029-01-18'),
    ('BSTR-MIX-0001', 'Box Campuran',             'mixed',  null::date),
    ('BSTR-MIX-0002', 'Box Campuran',             'mixed',  null::date),
    ('BSTR-MIX-0003', 'Box Campuran',             'mixed',  null::date),
    ('BSTR-MIX-0004', 'Box Campuran',             'mixed',  null::date),
    ('BSTR-MIX-0005', 'Box Campuran',             'mixed',  null::date)
),
item_src(id_box, sku, qty, expired_at) as (
  values
    ('BSTR-EOP-0005', 'ATM-EOP',         7, date '2029-01-18'),
    -- MIX-0001
    ('BSTR-MIX-0001', 'ATM-FZ',          3, null::date),
    ('BSTR-MIX-0001', 'ATM-VITC',       10, null::date),
    -- MIX-0002
    ('BSTR-MIX-0002', 'ATM-HRB-SHMP',    5, null::date),
    ('BSTR-MIX-0002', 'ATM-HRB-BODY',    6, null::date),
    ('BSTR-MIX-0002', 'ATM-HRB-COND',    3, null::date),
    ('BSTR-MIX-0002', 'ATM-SCALP-SHMP',  1, null::date),
    -- MIX-0003
    ('BSTR-MIX-0003', 'ATM-TP-MINT',     4, null::date),
    ('BSTR-MIX-0003', 'ATM-TP-PROP4',    5, null::date),
    -- MIX-0004
    ('BSTR-MIX-0004', 'ATM-TP-PROP200', 57, null::date),
    ('BSTR-MIX-0004', 'ATM-TBRUSH8',     4, null::date),
    -- MIX-0005
    ('BSTR-MIX-0005', 'ATM-CAFE50',      2, null::date),
    ('BSTR-MIX-0005', 'ATM-CAFE200',     2, null::date)
),
own as (
  select id, owner_code from public.owners where lower(owner_name) = 'bunda' limit 1
),
new_boxes as (
  insert into public.boxes (
    id_box, pemilik_id_box, barcode_value, box_name,
    owner_id, source_type, package_qty, expired_at, location_code, status
  )
  select
    b.id_box,
    o.owner_code || '-' || b.id_box,
    public.build_box_barcode_value(b.id_box),
    b.box_name,
    o.id,
    b.source_type,
    0,
    b.expired_at,
    'Kantor Bunda',
    'active'
  from box_src b
  cross join own o
  on conflict (id_box) do nothing
  returning id, id_box
)
insert into public.box_items (box_id, product_id, qty_initial, qty_available, expired_at)
select nb.id, p.id, i.qty, i.qty, i.expired_at
from item_src i
join new_boxes nb on nb.id_box = i.id_box
join public.products p on p.sku = i.sku
on conflict (box_id, product_id, expired_at, batch_no) do nothing;

-- ---- 5) Verifikasi: rekap per box -----------------------------------
select
  b.id_box,
  b.source_type,
  b.location_code,
  count(bi.id)         as jml_item,
  sum(bi.qty_initial)  as total_pcs
from public.boxes b
join public.box_items bi on bi.box_id = b.id
where b.id_box = 'BSTR-EOP-0005' or b.id_box like 'BSTR-MIX-%'
group by b.id_box, b.source_type, b.location_code
order by b.id_box;
