-- Relax the server-side barcode format check so imported boxes can be checked out.
--
-- Background: boxes created in-app use id_box "BOX-YYYYMMDD-NNNNNN", but boxes
-- imported from GudangKu/client CSVs use codes like "GK-KARDUS-000001". The
-- checkout functions hardcoded the BOX-YYYYMMDD shape and rejected every imported
-- box with "Format barcode tidak valid". The checksum still guarantees integrity,
-- so we only need to accept any uppercase alphanumeric/hyphen id_box.
--
-- New boxes (BOX-...) keep working unchanged — this is purely additive/backward
-- compatible. Mirrors lib/barcode/generate.ts isValidBarcodeValue.

create or replace function public.checkout_full_box(p_barcode_value text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_box public.boxes%rowtype;
  v_item public.box_items%rowtype;
begin
  if not public.is_gudang_admin() then
    return jsonb_build_object('ok', false, 'message', 'Role tidak boleh mengambil barang.');
  end if;

  if p_barcode_value !~ '^ATMY_BOX:[A-Z0-9][A-Z0-9-]{1,48}:[A-Z0-9]{4}$' then
    insert into public.scan_logs(scan_type, raw_value, actor_user_id, result, message)
    values ('check_out', p_barcode_value, v_actor, 'invalid', 'Format barcode tidak valid');
    return jsonb_build_object('ok', false, 'message', 'Format barcode tidak valid.');
  end if;

  select * into v_box
  from public.boxes
  where barcode_value = p_barcode_value
  for update;

  if not found then
    insert into public.scan_logs(scan_type, raw_value, actor_user_id, result, message)
    values ('check_out', p_barcode_value, v_actor, 'not_found', 'Barcode tidak ditemukan');
    return jsonb_build_object('ok', false, 'message', 'Barcode tidak ditemukan.');
  end if;

  if v_box.status in ('taken', 'empty', 'void') then
    insert into public.scan_logs(scan_type, raw_value, box_id, actor_user_id, result, message)
    values ('check_out', p_barcode_value, v_box.id, v_actor, 'already_taken', 'Box tidak bisa diambil lagi');
    return jsonb_build_object('ok', false, 'message', 'Box tidak bisa diambil lagi.');
  end if;

  for v_item in
    select * from public.box_items where box_id = v_box.id and qty_available > 0 for update
  loop
    insert into public.stock_movements(
      movement_type, box_id, owner_id, product_id, qty, before_qty, after_qty, actor_user_id, scanned_barcode
    )
    values (
      'out_full_box', v_box.id, v_box.owner_id, v_item.product_id, v_item.qty_available,
      v_item.qty_available, 0, v_actor, p_barcode_value
    );

    update public.box_items
    set qty_available = 0
    where id = v_item.id;
  end loop;

  update public.boxes
  set status = 'taken',
      checked_out_by = v_actor,
      checked_out_at = now()
  where id = v_box.id;

  insert into public.scan_logs(scan_type, raw_value, box_id, actor_user_id, result, message)
  values ('check_out', p_barcode_value, v_box.id, v_actor, 'success', 'Box diambil penuh');

  return jsonb_build_object('ok', true, 'message', 'Box berhasil diambil penuh.', 'box_id', v_box.id);
end;
$$;

create or replace function public.checkout_partial_item(p_barcode_value text, p_product_id uuid, p_qty numeric)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_box public.boxes%rowtype;
  v_item public.box_items%rowtype;
  v_remaining numeric;
begin
  if not public.is_gudang_admin() then
    return jsonb_build_object('ok', false, 'message', 'Role tidak boleh mengambil barang.');
  end if;

  if p_qty <= 0 then
    return jsonb_build_object('ok', false, 'message', 'Qty harus lebih dari 0.');
  end if;

  if p_barcode_value !~ '^ATMY_BOX:[A-Z0-9][A-Z0-9-]{1,48}:[A-Z0-9]{4}$' then
    insert into public.scan_logs(scan_type, raw_value, actor_user_id, result, message)
    values ('check_out', p_barcode_value, v_actor, 'invalid', 'Format barcode tidak valid');
    return jsonb_build_object('ok', false, 'message', 'Format barcode tidak valid.');
  end if;

  select * into v_box
  from public.boxes
  where barcode_value = p_barcode_value
  for update;

  if not found then
    insert into public.scan_logs(scan_type, raw_value, actor_user_id, result, message)
    values ('check_out', p_barcode_value, v_actor, 'not_found', 'Barcode tidak ditemukan');
    return jsonb_build_object('ok', false, 'message', 'Barcode tidak ditemukan.');
  end if;

  if v_box.status in ('taken', 'empty', 'void') then
    insert into public.scan_logs(scan_type, raw_value, box_id, actor_user_id, result, message)
    values ('check_out', p_barcode_value, v_box.id, v_actor, 'already_taken', 'Box tidak bisa diambil lagi');
    return jsonb_build_object('ok', false, 'message', 'Box tidak bisa diambil lagi.');
  end if;

  select * into v_item
  from public.box_items
  where box_id = v_box.id and product_id = p_product_id
  for update;

  if not found then
    insert into public.scan_logs(scan_type, raw_value, box_id, actor_user_id, result, message)
    values ('check_out', p_barcode_value, v_box.id, v_actor, 'error', 'Produk tidak ada di box');
    return jsonb_build_object('ok', false, 'message', 'Produk tidak ada di box.');
  end if;

  if p_qty > v_item.qty_available then
    insert into public.scan_logs(scan_type, raw_value, box_id, actor_user_id, result, message)
    values ('check_out', p_barcode_value, v_box.id, v_actor, 'error', 'Qty melebihi stok tersedia');
    return jsonb_build_object('ok', false, 'message', 'Qty melebihi stok tersedia.');
  end if;

  update public.box_items
  set qty_available = qty_available - p_qty
  where id = v_item.id;

  insert into public.stock_movements(
    movement_type, box_id, owner_id, product_id, qty, before_qty, after_qty, actor_user_id, scanned_barcode
  )
  values (
    'out_partial_item', v_box.id, v_box.owner_id, v_item.product_id, p_qty,
    v_item.qty_available, v_item.qty_available - p_qty, v_actor, p_barcode_value
  );

  select coalesce(sum(qty_available), 0) into v_remaining
  from public.box_items
  where box_id = v_box.id;

  update public.boxes
  set status = case when v_remaining = 0 then 'empty' else 'partial' end
  where id = v_box.id;

  insert into public.scan_logs(scan_type, raw_value, box_id, actor_user_id, result, message)
  values ('check_out', p_barcode_value, v_box.id, v_actor, 'success', 'Produk berhasil diambil sebagian');

  return jsonb_build_object(
    'ok', true,
    'message', 'Produk berhasil diambil.',
    'box_id', v_box.id,
    'remaining_qty', v_remaining
  );
end;
$$;
