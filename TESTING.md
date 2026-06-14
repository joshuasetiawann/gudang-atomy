# Manual Testing Gudang Atomy

Gunakan checklist ini setelah Supabase env dan profile user tersedia.

- `npm run typecheck`
- `npm run build`
- Login sebagai `super_admin`, `admin_gudang`, dan `viewer`
- Buat owner baru tanpa `owner_code`, pastikan kode otomatis `OWN-000001`
- Buat produk aktif
- Buat paket dengan beberapa produk, pastikan produk duplikat ditolak
- Input barang masuk mode `custom`
- Input barang masuk mode `package`
- Input barang masuk mode `mixed`
- Cetak label dari halaman success
- Lookup barcode dari `/ambil-barang`
- Checkout partial item dengan qty valid
- Coba checkout partial melebihi stok, pastikan ditolak
- Checkout full box
- Coba checkout box yang sudah `taken`, pastikan disabled/ditolak
- Cek `stock_movements` dan `scan_logs`
- Export CSV di `/reports` atau `/movements`
- Import `owners.csv`, `products.csv`, `packages.csv`, `package_items.csv`, `boxes.csv`, `box_items.csv`
- Cek `import_batches`
- Login sebagai viewer dan pastikan mutasi tidak bisa dilakukan
