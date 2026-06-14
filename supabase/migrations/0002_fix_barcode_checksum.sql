-- Align database barcode checksum generation with lib/barcode/generate.ts.
-- Run this if 0001 was already applied before this fix.

create or replace function public.build_box_barcode_value(p_id_box text)
returns text
language plpgsql
immutable
as $$
declare
  v_hash bigint := 0;
  v_char int;
  v_checksum text;
begin
  for v_char in 1..length(p_id_box) loop
    v_hash := mod((v_hash * 31 + ascii(substr(p_id_box, v_char, 1)))::numeric, 4294967296)::bigint;
  end loop;

  v_checksum := right(public.to_base36(v_hash), 4);
  if length(v_checksum) < 4 then
    v_checksum := lpad(v_checksum, 4, '0');
  end if;

  return 'ATMY_BOX:' || p_id_box || ':' || v_checksum;
end;
$$;

create or replace function public.generate_box_identifiers(p_owner_id uuid)
returns table(id_box text, pemilik_id_box text, barcode_value text)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_owner_code text;
  v_number text;
  v_id_box text;
begin
  if not public.is_gudang_admin() then
    raise exception 'Tidak punya akses generate box';
  end if;

  select owner_code into v_owner_code from public.owners where id = p_owner_id;
  if v_owner_code is null then
    raise exception 'Owner tidak ditemukan';
  end if;

  v_number := lpad(nextval('public.box_number_seq')::text, 6, '0');
  v_id_box := 'BOX-' || to_char(now(), 'YYYYMMDD') || '-' || v_number;

  id_box := v_id_box;
  pemilik_id_box := v_owner_code || '-' || v_id_box;
  barcode_value := public.build_box_barcode_value(v_id_box);
  return next;
end;
$$;

update public.stock_movements sm
set scanned_barcode = public.build_box_barcode_value(b.id_box)
from public.boxes b
where sm.box_id = b.id
  and sm.scanned_barcode like 'ATMY_BOX:%';

update public.scan_logs sl
set raw_value = public.build_box_barcode_value(b.id_box)
from public.boxes b
where sl.box_id = b.id
  and sl.raw_value like 'ATMY_BOX:%';

update public.boxes
set barcode_value = public.build_box_barcode_value(id_box)
where barcode_value is distinct from public.build_box_barcode_value(id_box);
