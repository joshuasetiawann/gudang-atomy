-- Add GudangKu kardus rows that do not appear in inventory as empty boxes.
-- Run after final_gudang_atomy.sql, because this relies on client_gudangku_*_raw tables and owners.

with missing_kardus as (
  select distinct on (k.mapped_id_box)
    k.client_id,
    k.label,
    k.nomor_pesanan,
    k.nomor_id,
    k.location,
    k.type,
    k.created_at,
    k.created_by,
    k.updated_at,
    k.updated_by,
    k.mapped_owner_code,
    k.mapped_id_box
  from public.client_gudangku_kardus_raw k
  left join public.client_gudangku_inventory_raw i on i.kardus_id = k.client_id
  where i.kardus_id is null
  order by k.mapped_id_box, k.import_row_no
)
insert into public.boxes(
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
  missing_kardus.mapped_id_box,
  missing_kardus.mapped_owner_code || '-' || missing_kardus.mapped_id_box,
  public.build_box_barcode_value(missing_kardus.mapped_id_box),
  missing_kardus.label,
  owners.id,
  'custom',
  null,
  0,
  null,
  upper(nullif(trim(missing_kardus.location), '')),
  'empty',
  missing_kardus.created_at,
  missing_kardus.updated_at,
  null,
  'Import GudangKu kardus kosong; client_id=' || missing_kardus.client_id ||
    '; label=' || missing_kardus.label ||
    '; nomor_pesanan=' || coalesce(missing_kardus.nomor_pesanan, '') ||
    '; nomor_id=' || coalesce(missing_kardus.nomor_id, '') ||
    '; type=' || coalesce(missing_kardus.type, '') ||
    '; created_by=' || coalesce(missing_kardus.created_by, '') ||
    '; updated_by=' || coalesce(missing_kardus.updated_by, '') ||
    '; reason=Tidak ada transaksi inventory'
from missing_kardus
join public.owners on owners.owner_code = missing_kardus.mapped_owner_code
on conflict (id_box) do update set
  pemilik_id_box = excluded.pemilik_id_box,
  barcode_value = excluded.barcode_value,
  box_name = excluded.box_name,
  owner_id = excluded.owner_id,
  location_code = excluded.location_code,
  status = excluded.status,
  created_at = excluded.created_at,
  updated_at = excluded.updated_at,
  notes = excluded.notes;
