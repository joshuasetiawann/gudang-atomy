-- =====================================================================
-- Rapihkan data — 29 Jun 2026
-- =====================================================================
-- Tujuan: rekam SEMUA perubahan data yang sudah diterapkan ke DB live
-- (lewat REST API) agar reproducible & masuk version control.
--
-- Isi:
--   1) Fix qty Hemohim BLM: produk ATM-HEMO-BLM 5 -> 4 pcs (240 box)
--   2) Standarisasi penulisan nama produk (7 produk)
--   3) Sinkron box_name box Hemohim lama dengan nama produk barunya
--   4) Hapus 2 box test (sampah tes form) + owner test "Joshua"
--
-- Idempotent: aman dijalankan ulang di Supabase SQL Editor.
--   - UPDATE pakai filter spesifik (no-op kalau sudah sesuai)
--   - Fix qty diguard ke baris yang masih bernilai 5 (error injeksi awal)
--   - DELETE pakai kunci spesifik (no-op kalau baris sudah hilang)
-- =====================================================================

begin;

-- ---- 1) Fix qty Hemohim BLM: 5 -> 4 ---------------------------------
-- Produk 'Atomy Hemohim 4 pcs' (ATM-HEMO-BLM) sempat diinjeksi 5 pcs.
-- Hanya menyentuh baris yang MASIH 5 (belum ada checkout) -> idempotent.
update public.box_items bi
set qty_initial = 4,
    qty_available = 4,
    updated_at = now()
from public.products p
where bi.product_id = p.id
  and p.sku = 'ATM-HEMO-BLM'
  and bi.qty_initial = 5
  and bi.qty_available = 5;

-- ---- 2) Standarisasi penulisan nama produk (7 produk) ---------------
-- Konvensi: prefix "Atomy", spasi sebelum satuan, satuan/kata isi kecil.
update public.products set product_name = 'Atomy Cafe Arabica 200 sticks'   where sku = 'ATM-CAFE200';
update public.products set product_name = 'Atomy Cafe Arabica 50 sticks'    where sku = 'ATM-CAFE50';
update public.products set product_name = 'Atomy Hemohim 4 pcs'             where sku = 'ATM-HEMO-BLM';
update public.products set product_name = 'Atomy Hemohim Sortir 5 pcs'      where sku = 'ATM-HEMO-BSTR';
update public.products set product_name = 'Atomy Toothbrush isi 8'          where sku = 'ATM-TBRUSH8';
update public.products set product_name = 'Atomy Propolis Toothpaste 200 g' where sku = 'ATM-TP-PROP200';
update public.products set product_name = 'Atomy Propolis Toothpaste isi 4' where sku = 'ATM-TP-PROP4';

-- ---- 3) Sinkron box_name Hemohim lama dgn nama produk baru ----------
-- Box lama box_name = "Hemohim 1 Set"; samakan dengan produknya.
update public.boxes set box_name = 'Atomy Hemohim 4 pcs',        updated_at = now() where id_box like 'BLM-HEMO-%';
update public.boxes set box_name = 'Atomy Hemohim Sortir 5 pcs', updated_at = now() where id_box like 'BSTR-HEMO-%';

-- ---- 4) Hapus box test (sampah dari tes form 2026-06-29) ------------
-- Box: BOX-20260629-000009 (BSTR-TEST-0001), BOX-20260629-000010 (BSTR-TEST-00021).
-- box_items ikut ON DELETE CASCADE pada boxes.
delete from public.scan_logs
where box_id in (select id from public.boxes where id_box in ('BOX-20260629-000009', 'BOX-20260629-000010'));

delete from public.stock_movements
where box_id in (select id from public.boxes where id_box in ('BOX-20260629-000009', 'BOX-20260629-000010'));

delete from public.boxes
where id_box in ('BOX-20260629-000009', 'BOX-20260629-000010');

-- Owner test "Joshua" (OWN-000006) — quick-owner saat tes, tanpa box lain.
delete from public.owners
where owner_code = 'OWN-000006' and owner_name = 'Joshua';

commit;

-- ---- Verifikasi (opsional, jalankan terpisah) -----------------------
-- select sku, product_name from public.products order by sku;
-- select count(*) filter (where qty_initial = 4) as blm_4pcs
--   from public.box_items bi join public.products p on p.id = bi.product_id
--   where p.sku = 'ATM-HEMO-BLM';
-- select box_name, count(*) from public.boxes
--   where id_box like 'BLM-HEMO-%' or id_box like 'BSTR-HEMO-%' group by box_name;
-- select count(*) as total_boxes from public.boxes;
