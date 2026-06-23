# Spec: Edit & Hapus Box

**Tanggal:** 2026-06-23
**Branch:** codex/push-main

## Ringkasan (Bahasa Indonesia)

Menambahkan fitur **Edit box** dan **Hapus box** di halaman detail box (`/boxes/[id]`).
Motivasi: ada box yang belum ada isi/rinciannya, dan user ingin mengisi/memperbaikinya
sendiri. **Tidak ada perubahan database** (skema, RLS, function) — murni kode aplikasi.

Keputusan yang sudah disepakati user:
1. **Hapus** = permanen ("hilang semuanya", termasuk riwayat stok & scan). Hanya **Super Admin**.
   Syarat: hanya box yang **isinya kosong** (tidak ada stok tersedia) yang boleh dihapus.
   Box yang masih ada stoknya ditolak (harus dikosongkan dulu).
2. **Edit** mencakup **isi produk** (tambah/ubah jumlah/hapus) **+ rincian box**
   (nama, lokasi, expired, catatan). **Owner tetap** agar ID & barcode box tidak berubah.
3. Hak akses: **Edit** = Admin Gudang & Super Admin. **Hapus** = Super Admin saja.

## Kenapa tanpa migrasi DB

Skema saat ini tidak punya RLS policy `DELETE` untuk `boxes`, `box_items`,
`stock_movements`, `scan_logs`, dan FK `stock_movements.box_id`/`scan_logs.box_id`
ke `boxes(id)` tanpa cascade. Daripada menambah policy/migrasi, operasi hapus
(termasuk hapus baris isi box saat edit) memakai **service-role admin client**
(`createAdminClient()`), yang sudah dipakai fitur "buat user login" dan
melewati RLS. Operasi insert/update tetap memakai client biasa (`createClient()`)
agar `auth.uid()` tetap tercatat di audit trigger.

## Arsitektur & Komponen

### 1. Validasi — `lib/validation/schemas.ts`
Tambah:
- `boxItemDraftSchema`: `{ id?: uuid, product_id: uuid, qty: number>0, expired_at?, batch_no? }`
- `editBoxSchema`: `{ box_name: string(min1), expired_at?, location_code?, notes?, items: boxItemDraftSchema[] }`

### 2. Server actions — `server/actions/warehouse.ts`

**`updateBoxAction(state, formData)`** — role: `super_admin | admin_gudang`
- Validasi `id` box (UUID) + `editBoxSchema` (items dari `items_json`).
- Ambil box (`id, owner_id, status`); tolak bila tidak ada / `status === 'void'`.
- Cek duplikat item pada gabungan kunci `product_id|expired_at|batch_no`.
- Ambil `box_items` saat ini.
- Update rincian `boxes` (box_name, expired_at, location_code, notes) — client biasa.
- Diff item terhadap `box_items` saat ini:
  - **Dihapus** (item lama tak ada di submit): delete `box_items` via **admin client**;
    catat movement `adjustment` (before=qty_available, after=0) bila qty_available>0.
  - **Diubah** (id cocok): update `qty_available=qty`, `qty_initial=max(qty_initial, qty)`,
    expired/batch — client biasa; bila qty berubah catat movement `adjustment`
    (before=qty_available lama, after=qty).
  - **Baru** (tanpa id): insert `box_items` (`qty_initial=qty_available=qty`) — client biasa;
    catat movement `adjustment` (before=0, after=qty).
  - Urutan operasi: hapus → update → insert (hindari bentrok unique constraint sementara).
- Insert semua movement `adjustment` sekaligus (`actor_user_id=profile.id`,
  `owner_id=box.owner_id`, `reason="Edit isi box"`) — client biasa.
- Hitung ulang status: `total_available<=0 → 'empty'`; selain itu bila status lama
  `'partial'` pertahankan `'partial'`, jika tidak `'active'`.
- `revalidatePath("/boxes")`, `"/dashboard"`, `` `/boxes/${id}` ``. Return `ok(...)`.

**`deleteBoxAction(state, formData)`** — role: `super_admin`
- Validasi `box_id`. Ambil box; tolak bila tidak ada.
- Hitung total `qty_available`; bila `>0` → `fail("Box masih berisi stok...")`.
- `createAdminClient()` (bungkus try/catch → pesan ramah bila service key tak ada).
- Hapus (admin client, urut): `scan_logs` where box_id → `stock_movements` where box_id
  → `boxes` where id (cascade menghapus `box_items`).
- `revalidatePath("/boxes")`, `"/dashboard"`, lalu `redirect("/boxes")`.

### 3. UI — `components/forms/BoxEditor.tsx` (client)
Props: `box` (id, box_name, expired_at, location_code, notes, status), `items`
(box_items + products), `products` (master aktif), `canDelete: boolean`.
- `useActionState(updateBoxAction)`. Hidden input `id`, `items_json`.
- State `items: EditItem[]` (existing diisi `qty = qty_available`, simpan `id`).
- Card "Edit rincian box": box_name, location_code, expired_at (date), notes.
- Card "Edit isi produk": baris produk via `SearchableSelect` + qty + expired + batch +
  tombol hapus baris; tombol "Tambah produk". Pola sama seperti `ReceiveBoxForm`.
- Tombol "Simpan perubahan" + pesan status (pola `SubmitMessage`/state message).
- Bila `canDelete`: Card "Zona berbahaya" dengan `Dialog` konfirmasi (pola `CheckoutPanel`)
  → form `deleteBoxAction` (hidden `box_id`). Dialog menjelaskan hapus permanen +
  ikut menghapus riwayat. Tombol hapus disable bila masih ada stok (info ke user).

### 4. Halaman detail — `app/(dashboard)/boxes/[id]/page.tsx`
- Tambah `getCurrentProfile()` + fetch master products aktif (`is_active=true`).
- `canEdit = role in (super_admin, admin_gudang)`, `canDelete = role === super_admin`.
- Bila `canEdit`: render `<BoxEditor/>` menggantikan card read-only "Isi produk".
  Bila tidak: tampilkan card "Isi produk" read-only seperti sekarang.
- BoxLabel, card Detail (read-only), dan Riwayat movement tetap untuk semua.

### 5. Daftar box — `app/(dashboard)/boxes/page.tsx`
- Tambah opsi filter status **"Tanpa isi"** (`value="__empty"`) → query
  `.eq("total_product_types", 0)` agar box tanpa isi mudah ditemukan
  (default sekarang `total_product_types > 0` menyembunyikannya).

## Error handling
- Semua action mengembalikan `ActionState` (`ok`/`fail`) seperti action lain.
- `errorMessage()` dipakai untuk pesan error Supabase.
- Operasi hapus mengecek error tiap langkah; bila gagal kembalikan pesan.

## Testing / verifikasi
- `npm run typecheck` dan `npm run lint` harus lulus.
- Manual: (a) isi box kosong via edit → status jadi active, muncul di daftar;
  (b) ubah jumlah → riwayat adjustment tercatat; (c) hapus baris produk;
  (d) hapus box kosong (super admin) → redirect ke /boxes; (e) hapus box berisi → ditolak;
  (f) viewer tidak melihat editor; admin gudang tidak melihat tombol hapus.

## Di luar lingkup (YAGNI)
- Tidak ada perubahan skema/RLS/RPC database.
- Tidak mengubah owner box (ID/barcode tetap).
- Tidak menambah edit/hapus inline di tabel daftar (aksi lewat halaman detail).
