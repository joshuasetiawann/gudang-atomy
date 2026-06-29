-- =====================================================================
-- 0004 — Status "sudah diprint" per box (label/barcode)
-- =====================================================================
-- Menambah kolom boxes.printed_at:
--   NULL          = label box belum pernah diprint
--   timestamptz   = kapan terakhir ditandai sudah diprint
--
-- Dipakai oleh halaman Print Resi (badge + filter + auto-mark saat print)
-- dan ringkasan "Diprint/Belum" di halaman Produk.
--
-- Idempotent: aman dijalankan ulang.
-- Jalankan sekali di Supabase SQL Editor. Setelah itu PostgREST otomatis
-- reload schema dan kolom langsung bisa dipakai REST/aplikasi.
-- =====================================================================

alter table public.boxes
  add column if not exists printed_at timestamptz;

comment on column public.boxes.printed_at is
  'Kapan label/barcode box terakhir ditandai sudah diprint. NULL = belum diprint.';

-- Index untuk filter "belum/sudah diprint" di Print Resi.
create index if not exists boxes_printed_at_idx on public.boxes (printed_at);

-- Refresh cache schema PostgREST (Supabase otomatis, baris ini jaga-jaga).
notify pgrst, 'reload schema';
