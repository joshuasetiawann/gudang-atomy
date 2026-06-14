# Gudang Atomy

Aplikasi web untuk pencatatan box barang masuk dan keluar Gudang Atomy berbasis Next.js App Router, Supabase Auth/PostgreSQL/RLS, QR scanner, label print, dan audit history.

## Stack

- Next.js App Router + TypeScript
- Tailwind CSS + komponen UI gaya shadcn
- Supabase PostgreSQL, Auth, RLS
- Server Actions untuk mutasi data
- `@zxing/browser` untuk scanner QR/barcode
- `qrcode` untuk label QR

## Install

```bash
npm install
cp .env.example .env.local
```

Isi `.env.local`:

```bash
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
```

`SUPABASE_SERVICE_ROLE_KEY` disiapkan untuk kebutuhan admin server-side. Jangan pernah pakai key ini di client component.

## Setup Supabase

1. Buat project Supabase.
2. Aktifkan email/password auth.
3. Jalankan migration:

```bash
supabase db push
```

Atau jalankan SQL dari `supabase/migrations/0001_gudang_atomy_schema.sql` di SQL Editor.

4. Isi sample data:

```bash
supabase db reset
```

Atau jalankan `supabase/seed/seed.sql` di SQL Editor.

Untuk data demo yang lebih lengkap, jalankan:

```sql
supabase/seed/demo_data.sql
```

File demo ini mengisi owner, produk, paket, box active/partial/taken/empty/void, stock movements, scan logs, dan import batch.

## User Admin Pertama

1. Buat user di Supabase Auth.
2. Ambil UUID user dari `auth.users`.
3. Insert profile:

```sql
insert into public.profiles(id, full_name, email, role, is_active)
values ('UUID_AUTH_USER', 'Super Admin', 'admin@example.com', 'super_admin', true);
```

Role yang tersedia:

- `super_admin`
- `admin_gudang`
- `viewer`

## Run Local

```bash
npm run dev
```

Buka `http://localhost:3000`. Jika port 3000 dipakai:

```bash
npm run dev -- -p 3001
```

## Build

```bash
npm run typecheck
npm run build
```

## Deploy Vercel

1. Push repo ke GitHub.
2. Import project ke Vercel.
3. Isi environment variable yang sama seperti `.env.example`.
4. Deploy.
5. Pastikan Supabase Auth redirect URL mengarah ke domain Vercel.

## Barang Masuk

1. Login sebagai `super_admin` atau `admin_gudang`.
2. Buka `/barang-masuk`.
3. Pilih owner existing atau isi pemilik cepat.
4. Isi nama box, expired date, lokasi, source type.
5. Untuk `custom`, tambah produk manual.
6. Untuk `package`, pilih template paket dan jumlah paket.
7. Untuk `mixed`, pilih paket dan tambah produk manual.
8. Submit.
9. Halaman success menampilkan `id_box`, `pemilik_id_box`, `barcode_value`, QR code, dan tombol print label.

## Ambil Barang

1. Buka `/ambil-barang`.
2. Start kamera scanner atau isi `barcode_value` manual.
3. Detail box dan semua item akan tampil.
4. Klik `Ambil Semua Box` untuk checkout full box.
5. Isi qty per produk lalu klik `Ambil` untuk checkout sebagian.
6. Box status akan berubah menjadi `taken`, `partial`, atau `empty`.
7. Semua transaksi tercatat di `stock_movements`.
8. Semua scan sukses/gagal tercatat di `scan_logs`.

## Import CSV

Buka `/imports` sebagai `super_admin`. Format file:

```csv
owners.csv: owner_code,owner_name,phone,atomy_member_id,notes
products.csv: sku,product_name,category,unit,default_barcode
packages.csv: package_code,package_name,description
package_items.csv: package_code,sku,qty_per_package
boxes.csv: id_box,owner_code,box_name,expired_at,location_code,status,notes
box_items.csv: id_box,sku,qty_initial,qty_available,expired_at,batch_no
```

Import menampilkan preview 10 baris, validasi kolom wajib, dan mencatat hasil ke `import_batches`.

## Struktur Penting

- `app/` halaman App Router
- `components/forms/` form barang masuk, checkout, import, master data
- `components/scanner/BarcodeScanner.tsx` scanner kamera
- `components/labels/BoxLabel.tsx` label QR print
- `server/actions/warehouse.ts` Server Actions utama
- `lib/supabase/` Supabase client/server helpers
- `supabase/migrations/` schema, RLS, views, RPC
- `supabase/seed/` sample master data

## Checklist Manual

- Login redirect ke `/dashboard`.
- Role terbaca dari `profiles`.
- Viewer tidak melihat form mutasi dan ditolak Server Action/RLS.
- Admin bisa membuat owner, product, package.
- Admin bisa input barang masuk custom/package/mixed.
- Sistem generate `BOX-YYYYMMDD-000001`, `pemilik_id_box`, dan `barcode_value`.
- Halaman success menampilkan QR dan label bisa diprint.
- Scanner kamera membaca QR atau fallback manual berjalan.
- Lookup barcode menampilkan detail box dan isi produk.
- Checkout full box mengubah status menjadi `taken`.
- Checkout partial mengurangi `qty_available`.
- Box `taken`, `empty`, atau `void` tidak bisa checkout lagi.
- `stock_movements` terisi untuk transaksi masuk dan keluar.
- `scan_logs` terisi untuk lookup/checkout sukses dan gagal.
- Export CSV stok aktif berhasil.
- Import CSV mencatat `import_batches`.
- `npm run typecheck` dan `npm run build` sukses.
