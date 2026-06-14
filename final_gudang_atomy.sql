-- Full setup Gudang Atomy + import full data client GudangKu.
-- Jalankan file ini di Supabase SQL Editor.
-- Urutan isi:
-- 1. Schema aplikasi Gudang Atomy
-- 2. Fix barcode checksum
-- 3. Sync user demo Super User + Admin
-- 4. Import GudangKu kardus + inventory produk asli + paket

-- ============================================================
-- 1. Schema aplikasi
-- ============================================================

create extension if not exists pgcrypto;

create sequence if not exists public.box_number_seq start with 1 increment by 1;
create sequence if not exists public.owner_number_seq start with 1 increment by 1;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text,
  role text not null check (role in ('super_admin', 'admin_gudang', 'viewer')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.owners (
  id uuid primary key default gen_random_uuid(),
  owner_code text unique not null,
  owner_name text not null,
  phone text,
  atomy_member_id text,
  notes text,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  sku text unique,
  product_name text not null,
  category text,
  unit text not null default 'pcs',
  default_barcode text,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.package_templates (
  id uuid primary key default gen_random_uuid(),
  package_code text unique not null,
  package_name text not null,
  description text,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.package_template_items (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references public.package_templates(id) on delete cascade,
  product_id uuid not null references public.products(id),
  qty_per_package numeric not null check (qty_per_package > 0),
  unique(package_id, product_id)
);

create table if not exists public.boxes (
  id uuid primary key default gen_random_uuid(),
  id_box text unique not null,
  pemilik_id_box text unique not null,
  barcode_value text unique not null,
  box_name text not null,
  owner_id uuid not null references public.owners(id),
  source_type text not null check (source_type in ('custom', 'package', 'mixed')),
  package_id uuid references public.package_templates(id),
  package_qty numeric not null default 0 check (package_qty >= 0),
  expired_at date,
  location_code text,
  status text not null default 'active' check (status in ('active', 'partial', 'empty', 'taken', 'void')),
  created_by uuid references public.profiles(id),
  checked_out_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  checked_out_at timestamptz,
  notes text
);

create table if not exists public.box_items (
  id uuid primary key default gen_random_uuid(),
  box_id uuid not null references public.boxes(id) on delete cascade,
  product_id uuid not null references public.products(id),
  qty_initial numeric not null check (qty_initial >= 0),
  qty_available numeric not null check (qty_available >= 0),
  expired_at date,
  batch_no text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(box_id, product_id, expired_at, batch_no)
);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  movement_type text not null check (movement_type in ('in', 'out_full_box', 'out_partial_item', 'adjustment', 'void')),
  box_id uuid references public.boxes(id),
  owner_id uuid references public.owners(id),
  product_id uuid references public.products(id),
  qty numeric not null,
  before_qty numeric,
  after_qty numeric,
  actor_user_id uuid references public.profiles(id),
  scanned_barcode text,
  reason text,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.scan_logs (
  id uuid primary key default gen_random_uuid(),
  scan_type text not null check (scan_type in ('check_in', 'check_out', 'lookup')),
  raw_value text not null,
  box_id uuid references public.boxes(id),
  actor_user_id uuid references public.profiles(id),
  result text not null check (result in ('success', 'not_found', 'already_taken', 'invalid', 'error')),
  message text,
  created_at timestamptz not null default now()
);

create table if not exists public.import_batches (
  id uuid primary key default gen_random_uuid(),
  import_type text,
  file_name text,
  status text,
  total_rows integer default 0,
  success_rows integer default 0,
  failed_rows integer default 0,
  error_summary text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.profiles(id),
  action text,
  table_name text,
  record_id uuid,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_boxes_barcode_value on public.boxes(barcode_value);
create index if not exists idx_boxes_id_box on public.boxes(id_box);
create index if not exists idx_boxes_owner_id on public.boxes(owner_id);
create index if not exists idx_boxes_status on public.boxes(status);
create index if not exists idx_boxes_expired_at on public.boxes(expired_at);
create index if not exists idx_boxes_created_at on public.boxes(created_at);
create index if not exists idx_box_items_box_id on public.box_items(box_id);
create index if not exists idx_box_items_product_id on public.box_items(product_id);
create index if not exists idx_stock_movements_box_id on public.stock_movements(box_id);
create index if not exists idx_stock_movements_product_id on public.stock_movements(product_id);
create index if not exists idx_stock_movements_created_at on public.stock_movements(created_at);
create index if not exists idx_scan_logs_raw_value on public.scan_logs(raw_value);
create index if not exists idx_scan_logs_created_at on public.scan_logs(created_at);
create index if not exists idx_audit_logs_actor_user_id on public.audit_logs(actor_user_id);
create index if not exists idx_audit_logs_created_at on public.audit_logs(created_at);
create index if not exists idx_audit_logs_table_name on public.audit_logs(table_name);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_updated_at on public.profiles;
drop trigger if exists trg_owners_updated_at on public.owners;
drop trigger if exists trg_products_updated_at on public.products;
drop trigger if exists trg_package_templates_updated_at on public.package_templates;
drop trigger if exists trg_boxes_updated_at on public.boxes;
drop trigger if exists trg_box_items_updated_at on public.box_items;

create trigger trg_profiles_updated_at before update on public.profiles
  for each row execute function public.touch_updated_at();
create trigger trg_owners_updated_at before update on public.owners
  for each row execute function public.touch_updated_at();
create trigger trg_products_updated_at before update on public.products
  for each row execute function public.touch_updated_at();
create trigger trg_package_templates_updated_at before update on public.package_templates
  for each row execute function public.touch_updated_at();
create trigger trg_boxes_updated_at before update on public.boxes
  for each row execute function public.touch_updated_at();
create trigger trg_box_items_updated_at before update on public.box_items
  for each row execute function public.touch_updated_at();

create or replace function public.audit_row_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_record_id uuid;
begin
  if tg_op = 'INSERT' then
    v_record_id := new.id;
  else
    v_record_id := old.id;
  end if;

  insert into public.audit_logs(actor_user_id, action, table_name, record_id, old_data, new_data)
  values (
    v_actor,
    tg_op,
    tg_table_name,
    v_record_id,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
  );
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_audit_owners on public.owners;
drop trigger if exists trg_audit_products on public.products;
drop trigger if exists trg_audit_packages on public.package_templates;
drop trigger if exists trg_audit_boxes on public.boxes;
drop trigger if exists trg_audit_box_items on public.box_items;
drop trigger if exists trg_audit_profiles on public.profiles;
drop trigger if exists trg_audit_stock_movements on public.stock_movements;
drop trigger if exists trg_audit_scan_logs on public.scan_logs;
drop trigger if exists trg_audit_import_batches on public.import_batches;

create trigger trg_audit_profiles after insert or update or delete on public.profiles
  for each row execute function public.audit_row_changes();
create trigger trg_audit_owners after insert or update or delete on public.owners
  for each row execute function public.audit_row_changes();
create trigger trg_audit_products after insert or update or delete on public.products
  for each row execute function public.audit_row_changes();
create trigger trg_audit_packages after insert or update or delete on public.package_templates
  for each row execute function public.audit_row_changes();
create trigger trg_audit_boxes after insert or update or delete on public.boxes
  for each row execute function public.audit_row_changes();
create trigger trg_audit_box_items after insert or update or delete on public.box_items
  for each row execute function public.audit_row_changes();
create trigger trg_audit_stock_movements after insert or update or delete on public.stock_movements
  for each row execute function public.audit_row_changes();
create trigger trg_audit_scan_logs after insert or update or delete on public.scan_logs
  for each row execute function public.audit_row_changes();
create trigger trg_audit_import_batches after insert or update or delete on public.import_batches
  for each row execute function public.audit_row_changes();

create or replace function public.current_profile_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid()
    and p.is_active = true
  limit 1
$$;

create or replace function public.current_profile_is_active()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.is_active = true
  )
$$;

create or replace function public.is_gudang_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_profile_role() in ('super_admin', 'admin_gudang')
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_profile_role() = 'super_admin'
$$;

create or replace function public.generate_owner_code()
returns text
language sql
volatile
security definer
set search_path = public
as $$
  select 'OWN-' || lpad(nextval('public.owner_number_seq')::text, 6, '0')
$$;

create or replace function public.to_base36(p_value bigint)
returns text
language plpgsql
immutable
as $$
declare
  v_digits text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  v_value bigint := abs(p_value);
  v_result text := '';
  v_remainder int;
begin
  if v_value = 0 then
    return '0';
  end if;

  while v_value > 0 loop
    v_remainder := (v_value % 36)::int;
    v_result := substr(v_digits, v_remainder + 1, 1) || v_result;
    v_value := floor(v_value / 36);
  end loop;

  return v_result;
end;
$$;

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

  if p_barcode_value !~ '^ATMY_BOX:BOX-[0-9]{8}-[0-9]{6}:[A-Z0-9]{4}$' then
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

  if p_barcode_value !~ '^ATMY_BOX:BOX-[0-9]{8}-[0-9]{6}:[A-Z0-9]{4}$' then
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

create or replace view public.v_active_stock
with (security_invoker = true) as
select
  b.id as box_uuid,
  b.id_box,
  b.pemilik_id_box,
  b.box_name,
  b.status,
  o.owner_code,
  o.owner_name,
  p.sku,
  p.product_name,
  bi.qty_initial,
  bi.qty_available,
  coalesce(bi.expired_at, b.expired_at) as expired_at,
  b.location_code
from public.boxes b
join public.owners o on o.id = b.owner_id
join public.box_items bi on bi.box_id = b.id
join public.products p on p.id = bi.product_id
where b.status in ('active', 'partial')
  and bi.qty_available > 0;

create or replace view public.v_box_summary
with (security_invoker = true) as
select
  b.id,
  b.id_box,
  b.box_name,
  o.owner_name,
  b.status,
  count(bi.id) as total_product_types,
  coalesce(sum(bi.qty_available), 0) as total_qty_available,
  b.expired_at,
  b.location_code,
  b.created_at,
  b.checked_out_at
from public.boxes b
join public.owners o on o.id = b.owner_id
left join public.box_items bi on bi.box_id = b.id
group by b.id, o.owner_name;

create or replace view public.v_activity_logs
with (security_invoker = true) as
select
  al.id,
  al.created_at,
  al.actor_user_id,
  actor.full_name as actor_name,
  actor.email as actor_email,
  actor.role as actor_role,
  lower(coalesce(al.action, 'audit')) as action,
  al.table_name as entity_type,
  al.record_id,
  case upper(coalesce(al.action, ''))
    when 'INSERT' then 'Membuat data ' || al.table_name
    when 'UPDATE' then 'Mengubah data ' || al.table_name
    when 'DELETE' then 'Menghapus data ' || al.table_name
    else coalesce(al.action, 'Audit') || ' ' || coalesce(al.table_name, '-')
  end as summary,
  jsonb_build_object('old_data', al.old_data, 'new_data', al.new_data) as metadata
from public.audit_logs al
left join public.profiles actor on actor.id = al.actor_user_id
union all
select
  sl.id,
  sl.created_at,
  sl.actor_user_id,
  actor.full_name as actor_name,
  actor.email as actor_email,
  actor.role as actor_role,
  'scan_' || sl.scan_type as action,
  'scan_logs' as entity_type,
  sl.id as record_id,
  coalesce(sl.message, sl.result) as summary,
  jsonb_build_object(
    'raw_value', sl.raw_value,
    'result', sl.result,
    'box_id', sl.box_id
  ) as metadata
from public.scan_logs sl
left join public.profiles actor on actor.id = sl.actor_user_id
union all
select
  sm.id,
  sm.created_at,
  sm.actor_user_id,
  actor.full_name as actor_name,
  actor.email as actor_email,
  actor.role as actor_role,
  sm.movement_type as action,
  'stock_movements' as entity_type,
  sm.id as record_id,
  trim(concat(
    sm.movement_type,
    ' ',
    coalesce(products.product_name, 'produk'),
    ' qty ',
    sm.qty,
    case when boxes.id_box is null then '' else ' pada ' || boxes.id_box end
  )) as summary,
  jsonb_build_object(
    'id_box', boxes.id_box,
    'product_name', products.product_name,
    'qty', sm.qty,
    'before_qty', sm.before_qty,
    'after_qty', sm.after_qty,
    'reason', sm.reason,
    'notes', sm.notes
  ) as metadata
from public.stock_movements sm
left join public.profiles actor on actor.id = sm.actor_user_id
left join public.boxes boxes on boxes.id = sm.box_id
left join public.products products on products.id = sm.product_id
union all
select
  ib.id,
  ib.created_at,
  ib.created_by as actor_user_id,
  actor.full_name as actor_name,
  actor.email as actor_email,
  actor.role as actor_role,
  'import_' || coalesce(ib.status, 'unknown') as action,
  'import_batches' as entity_type,
  ib.id as record_id,
  trim(concat(
    'Import ',
    coalesce(ib.import_type, 'data'),
    ' dari ',
    coalesce(ib.file_name, '-'),
    ' (',
    coalesce(ib.success_rows, 0),
    '/',
    coalesce(ib.total_rows, 0),
    ' sukses)'
  )) as summary,
  jsonb_build_object(
    'status', ib.status,
    'total_rows', ib.total_rows,
    'success_rows', ib.success_rows,
    'failed_rows', ib.failed_rows,
    'error_summary', ib.error_summary
  ) as metadata
from public.import_batches ib
left join public.profiles actor on actor.id = ib.created_by;

alter table public.profiles enable row level security;
alter table public.owners enable row level security;
alter table public.products enable row level security;
alter table public.package_templates enable row level security;
alter table public.package_template_items enable row level security;
alter table public.boxes enable row level security;
alter table public.box_items enable row level security;
alter table public.stock_movements enable row level security;
alter table public.scan_logs enable row level security;
alter table public.import_batches enable row level security;
alter table public.audit_logs enable row level security;

drop policy if exists "profiles select own or admin" on public.profiles;
drop policy if exists "profiles insert super admin" on public.profiles;
drop policy if exists "profiles update super admin" on public.profiles;
drop policy if exists "main select active authenticated" on public.owners;
drop policy if exists "main insert gudang admin owners" on public.owners;
drop policy if exists "main update gudang admin owners" on public.owners;
drop policy if exists "main select products" on public.products;
drop policy if exists "main insert products" on public.products;
drop policy if exists "main update products" on public.products;
drop policy if exists "main select package templates" on public.package_templates;
drop policy if exists "main insert package templates" on public.package_templates;
drop policy if exists "main update package templates" on public.package_templates;
drop policy if exists "main select package items" on public.package_template_items;
drop policy if exists "main insert package items" on public.package_template_items;
drop policy if exists "main update package items" on public.package_template_items;
drop policy if exists "main delete package items" on public.package_template_items;
drop policy if exists "main select boxes" on public.boxes;
drop policy if exists "main insert boxes" on public.boxes;
drop policy if exists "main update boxes" on public.boxes;
drop policy if exists "main select box items" on public.box_items;
drop policy if exists "main insert box items" on public.box_items;
drop policy if exists "main update box items" on public.box_items;
drop policy if exists "main select stock movements" on public.stock_movements;
drop policy if exists "main insert stock movements" on public.stock_movements;
drop policy if exists "main select scan logs" on public.scan_logs;
drop policy if exists "main insert scan logs" on public.scan_logs;
drop policy if exists "main select import batches" on public.import_batches;
drop policy if exists "main insert import batches" on public.import_batches;
drop policy if exists "main update import batches" on public.import_batches;
drop policy if exists "main select audit logs" on public.audit_logs;
drop policy if exists "main insert audit logs" on public.audit_logs;

create policy "profiles select own or admin" on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.current_profile_role() in ('super_admin', 'admin_gudang'));
create policy "profiles insert super admin" on public.profiles
  for insert to authenticated
  with check (public.is_super_admin());
create policy "profiles update super admin" on public.profiles
  for update to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

create policy "main select active authenticated" on public.owners
  for select to authenticated using (public.current_profile_is_active());
create policy "main insert gudang admin owners" on public.owners
  for insert to authenticated with check (public.is_gudang_admin());
create policy "main update gudang admin owners" on public.owners
  for update to authenticated using (public.is_gudang_admin()) with check (public.is_gudang_admin());

create policy "main select products" on public.products
  for select to authenticated using (public.current_profile_is_active());
create policy "main insert products" on public.products
  for insert to authenticated with check (public.is_gudang_admin());
create policy "main update products" on public.products
  for update to authenticated using (public.is_gudang_admin()) with check (public.is_gudang_admin());

create policy "main select package templates" on public.package_templates
  for select to authenticated using (public.current_profile_is_active());
create policy "main insert package templates" on public.package_templates
  for insert to authenticated with check (public.is_gudang_admin());
create policy "main update package templates" on public.package_templates
  for update to authenticated using (public.is_gudang_admin()) with check (public.is_gudang_admin());

create policy "main select package items" on public.package_template_items
  for select to authenticated using (public.current_profile_is_active());
create policy "main insert package items" on public.package_template_items
  for insert to authenticated with check (public.is_gudang_admin());
create policy "main update package items" on public.package_template_items
  for update to authenticated using (public.is_gudang_admin()) with check (public.is_gudang_admin());
create policy "main delete package items" on public.package_template_items
  for delete to authenticated using (public.is_gudang_admin());

create policy "main select boxes" on public.boxes
  for select to authenticated using (public.current_profile_is_active());
create policy "main insert boxes" on public.boxes
  for insert to authenticated with check (public.is_gudang_admin());
create policy "main update boxes" on public.boxes
  for update to authenticated using (public.is_gudang_admin()) with check (public.is_gudang_admin());

create policy "main select box items" on public.box_items
  for select to authenticated using (public.current_profile_is_active());
create policy "main insert box items" on public.box_items
  for insert to authenticated with check (public.is_gudang_admin());
create policy "main update box items" on public.box_items
  for update to authenticated using (public.is_gudang_admin()) with check (public.is_gudang_admin());

create policy "main select stock movements" on public.stock_movements
  for select to authenticated using (public.current_profile_is_active());
create policy "main insert stock movements" on public.stock_movements
  for insert to authenticated with check (public.is_gudang_admin());

create policy "main select scan logs" on public.scan_logs
  for select to authenticated using (public.current_profile_is_active());
create policy "main insert scan logs" on public.scan_logs
  for insert to authenticated with check (public.is_gudang_admin());

create policy "main select import batches" on public.import_batches
  for select to authenticated using (public.current_profile_is_active());
create policy "main insert import batches" on public.import_batches
  for insert to authenticated with check (public.is_super_admin());
create policy "main update import batches" on public.import_batches
  for update to authenticated using (public.is_super_admin()) with check (public.is_super_admin());

create policy "main select audit logs" on public.audit_logs
  for select to authenticated using (public.is_super_admin());
create policy "main insert audit logs" on public.audit_logs
  for insert to authenticated with check (public.is_gudang_admin());

grant usage on schema public to authenticated;
grant select on public.v_active_stock to authenticated;
grant select on public.v_box_summary to authenticated;
grant select on public.v_activity_logs to authenticated;
grant execute on function public.generate_owner_code() to authenticated;
grant execute on function public.generate_box_identifiers(uuid) to authenticated;
grant execute on function public.checkout_full_box(text) to authenticated;
grant execute on function public.checkout_partial_item(text, uuid, numeric) to authenticated;


-- ============================================================
-- 2. Fix barcode checksum
-- ============================================================

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


-- ============================================================
-- 3. Sync user demo Super User + Admin
-- ============================================================

-- Siapkan user demo untuk login aplikasi.
-- Super User:
-- email: super@demo.local
-- password: super123
-- Admin:
-- email: admin@demo.local
-- password: admin123
do $$
declare
  v_seed record;
  v_user_id uuid;
begin
  for v_seed in
    select *
    from jsonb_to_recordset($seed$
      [
        {
          "id": "00000000-0000-4000-8000-000000000001",
          "email": "super@demo.local",
          "password": "super123",
          "full_name": "Super User Demo",
          "profile_role": "super_admin"
        },
        {
          "id": "00000000-0000-4000-8000-000000000002",
          "email": "admin@demo.local",
          "password": "admin123",
          "full_name": "Admin Demo",
          "profile_role": "admin_gudang"
        }
      ]
    $seed$::jsonb) as seed(id text, email text, password text, full_name text, profile_role text)
  loop
    select id into v_user_id
    from auth.users
    where lower(email) = lower(v_seed.email)
    limit 1;

    if v_user_id is null then
      v_user_id := v_seed.id::uuid;

      begin
        insert into auth.users(
          id,
          instance_id,
          aud,
          role,
          email,
          encrypted_password,
          email_confirmed_at,
          raw_app_meta_data,
          raw_user_meta_data,
          created_at,
          updated_at
        )
        values (
          v_user_id,
          '00000000-0000-0000-0000-000000000000',
          'authenticated',
          'authenticated',
          v_seed.email,
          crypt(v_seed.password, gen_salt('bf')),
          now(),
          '{"provider":"email","providers":["email"]}'::jsonb,
          jsonb_build_object('full_name', v_seed.full_name),
          now(),
          now()
        );
      exception
        when unique_violation then
          select id into v_user_id
          from auth.users
          where lower(email) = lower(v_seed.email)
          limit 1;
        when others then
          raise notice 'Auth user demo tidak dibuat otomatis untuk %: %', v_seed.email, sqlerrm;
          select id into v_user_id
          from auth.users
          where lower(email) = lower(v_seed.email)
          limit 1;
      end;
    else
      update auth.users
      set
        encrypted_password = crypt(v_seed.password, gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"provider":"email","providers":["email"]}'::jsonb,
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('full_name', v_seed.full_name),
        updated_at = now()
      where id = v_user_id;
    end if;

    if v_user_id is not null then
      begin
        insert into auth.identities(
          provider_id,
          user_id,
          identity_data,
          provider,
          last_sign_in_at,
          created_at,
          updated_at
        )
        values (
          v_user_id::text,
          v_user_id,
          jsonb_build_object('sub', v_user_id::text, 'email', v_seed.email),
          'email',
          now(),
          now(),
          now()
        )
        on conflict do nothing;
      exception
        when others then
          raise notice 'Auth identity demo dilewati untuk %: %', v_seed.email, sqlerrm;
      end;

      insert into public.profiles(id, full_name, email, role, is_active)
      values (v_user_id, v_seed.full_name, v_seed.email, v_seed.profile_role, true)
      on conflict (id) do update set
        full_name = excluded.full_name,
        email = excluded.email,
        role = excluded.role,
        is_active = true;
    end if;
  end loop;
end $$;

-- ============================================================
-- 4. Import data client GudangKu
-- ============================================================

-- Import full data client GudangKu: kardus + inventory produk asli + paket
-- Source kardus CSV: /home/joo/Downloads/GudangKu Database - kardus.csv
-- Source inventory CSV: /home/joo/Downloads/GudangKu Database - inventory.csv
-- Source paket CSV: /home/joo/Downloads/GudangKu Database - paket.csv
-- Generated by: scripts/convert-gudangku-full.mjs
-- Kardus rows: 658
-- Inventory rows: 534
-- Paket rows: 41
-- Paket skipped empty rows: 7
-- Owners: 644
-- Boxes: 345
-- Kardus boxes without inventory skipped from app boxes: 311
-- Products: 86
-- Box items: 499
-- Stock movements: 534
-- Package templates: 22
-- Package items: 41
--
-- Mapping:
-- - raw kardus tetap menyimpan semua baris CSV kardus.
-- - boxes aplikasi hanya dibuat dari id CSV kardus yang muncul sebagai kardus_id di inventory.
-- - boxes dibuat dari kolom id pada CSV kardus: GK-KARDUS-000001, dst.
-- - Jika id kardus sama, dianggap box yang sama.
-- - products dibuat dari product_name Google Sheet inventory, dedupe exact normalized name.
-- - package_templates dibuat dari Nama Paket Google Sheet paket.
-- - package_template_items dibuat dari Produk + Qty Google Sheet paket.
-- - box_items dibuat dari kardus_id + product_name, qty_initial dari total MASUK, qty_available dari MASUK - PENJUALAN.
-- - stock_movements dibuat dari semua baris inventory: MASUK -> in, PENJUALAN -> out_partial_item.

begin;

create extension if not exists pgcrypto;

-- DELETE block dihapus: tidak perlu untuk restore.
-- Semua INSERT di bawah pakai "on conflict ... do update" (upsert) dengan id/kode tetap,
-- jadi data ter-restore tanpa menghapus dulu. Ini juga menghindari error FK
-- (boxes_package_id_fkey) saat menghapus package_templates.

create table if not exists public.client_gudangku_kardus_raw (
  import_row_no integer primary key,
  client_id text,
  label text,
  nomor_pesanan text,
  nomor_id text,
  owner_name text,
  location text,
  type text,
  created_at timestamptz,
  created_by text,
  updated_at timestamptz,
  updated_by text,
  mapped_owner_code text,
  mapped_id_box text,
  imported_at timestamptz not null default now()
);

create table if not exists public.client_gudangku_inventory_raw (
  import_row_no integer primary key,
  client_id text,
  type text,
  date timestamptz,
  kardus_id text,
  mapped_id_box text,
  product_name text,
  mapped_sku text,
  qty numeric,
  price numeric,
  buyer_name text,
  transfer_to text,
  transfer_amount numeric,
  performed_by text,
  notes text,
  imported_at timestamptz not null default now()
);

create table if not exists public.client_gudangku_paket_raw (
  import_row_no integer primary key,
  package_no text,
  package_code text,
  package_name text,
  product_name text,
  mapped_sku text,
  source_qty text,
  qty_per_package numeric,
  unit text,
  imported_at timestamptz not null default now()
);

truncate table
  public.client_gudangku_kardus_raw,
  public.client_gudangku_inventory_raw,
  public.client_gudangku_paket_raw;

insert into public.client_gudangku_kardus_raw(
  import_row_no,
  client_id,
  label,
  nomor_pesanan,
  nomor_id,
  owner_name,
  location,
  type,
  created_at,
  created_by,
  updated_at,
  updated_by,
  mapped_owner_code,
  mapped_id_box
)
values
  (1, '1', '4400-7713-SAMUEL ANITA SAMUEL MALUMUS', '4400', '7713', 'SAMUEL ANITA SAMUEL MALUMUS', 'GUDANG ANITA', 'Titipan', '2026-04-29 07:43:00+07', 'Admin', '2026-04-29 07:43:00+07', 'Admin', 'GK-7713-E4F48B', 'GK-KARDUS-000001'),
  (2, '2', '9000-7886-YOGA ANITA YOGA BAGUS', '9000', '7886', 'YOGA ANITA YOGA BAGUS', 'GUDANG ANITA', 'Titipan', '2026-04-29 07:45:00+07', 'Admin', '2026-04-29 07:45:00+07', 'Admin', 'GK-7886-A34010', 'GK-KARDUS-000002'),
  (3, '3', '8500-9884-ANITA BINTANG JECCIE LITAN JECCIE LITAN', '8500', '9884', 'ANITA BINTANG JECCIE LITAN JECCIE LITAN', 'GUDANG ANITA', 'Titipan', '2026-04-29 07:46:00+07', 'Admin', '2026-04-29 07:46:00+07', 'Admin', 'GK-9884-636FDA', 'GK-KARDUS-000003'),
  (4, '4', '7800-6175-ANITA BINTANG DWI MEDLIN DWI MEDLINS', '7800', '6175', 'ANITA BINTANG DWI MEDLIN DWI MEDLINS', 'GUDANG ANITA', 'Titipan', '2026-04-29 07:47:00+07', 'Admin', '2026-04-29 07:47:00+07', 'Admin', 'GK-6175-53C04A', 'GK-KARDUS-000004'),
  (5, '5', '1500-6230-AMI ARUM SARI', '1500', '6230', 'AMI ARUM SARI', 'GUDANG AMI', 'Titipan', '2026-04-29 07:48:00+07', 'Admin', '2026-04-29 07:48:00+07', 'Admin', 'GK-6230-A3351D', 'GK-KARDUS-000005'),
  (6, '6', '0800-6230-DWI DWI SANTOSO', '0800', '6230', 'DWI DWI SANTOSO', 'GUDANG AMI', 'Titipan', '2026-04-29 07:48:00+07', 'Admin', '2026-04-29 07:48:00+07', 'Admin', 'GK-6230-1BE427', 'GK-KARDUS-000006'),
  (7, '7', '8800-7426-ATHI TEAM RINA ATHI BASTIANA MANIA WASI', '8800', '7426', 'ATHI TEAM RINA ATHI BASTIANA MANIA WASI', 'GUDANG RINA', 'Titipan', '2026-04-29 07:50:00+07', 'Admin', '2026-04-29 07:50:00+07', 'Admin', 'GK-7426-0A142D', 'GK-KARDUS-000007'),
  (8, '8', '8200-9891-DWI T AMI DWI SANTOSO', '8200', '9891', 'DWI T AMI DWI SANTOSO', 'GUDANG AMI', 'Titipan', '2026-04-29 07:51:00+07', 'Admin', '2026-04-29 07:51:00+07', 'Admin', 'GK-9891-BAE981', 'GK-KARDUS-000008'),
  (9, '9', '3000-9940-SURYANI ARABIS TIKOMAH', '3000', '9940', 'SURYANI ARABIS TIKOMAH', 'GUDANG SURYANI', 'Titipan', '2026-04-29 07:52:00+07', 'Admin', '2026-04-29 07:52:00+07', 'Admin', 'GK-9940-261550', 'GK-KARDUS-000009'),
  (10, '10', '7900-6194-AMI LISTIA ERLIN LUPIANI', '7900', '6194', 'AMI LISTIA ERLIN LUPIANI', 'GUDANG AMI', 'Titipan', '2026-04-29 07:54:00+07', 'Admin', '2026-04-29 07:54:00+07', 'Admin', 'GK-6194-540F0A', 'GK-KARDUS-000010'),
  (11, '11', '2500-7916-ALVIN ANITA ALVIN', '2500', '7916', 'ALVIN ANITA ALVIN', 'GUDANG ANITA', 'Titipan', '2026-04-29 07:55:00+07', 'Admin', '2026-04-29 07:55:00+07', 'Admin', 'GK-7916-B05F0F', 'GK-KARDUS-000011'),
  (12, '12', '0400-0028-SURYANI ARA NOVAL PUSPITA SARI', '0400', '0028', 'SURYANI ARA NOVAL PUSPITA SARI', 'GUDANG SURYANI', 'Titipan', '2026-04-29 07:56:00+07', 'Admin', '2026-04-29 07:56:00+07', 'Admin', 'GK-0028-1263DF', 'GK-KARDUS-000012'),
  (13, '13', '6900-9784-TJONG LI MI TJ AHJA LIAY', '6900', '9784', 'TJONG LI MI TJ AHJA LIAY', 'GUDANG AMI', 'Titipan', '2026-04-29 07:58:00+07', 'Admin', '2026-04-29 07:58:00+07', 'Admin', 'GK-9784-8CF0AC', 'GK-KARDUS-000013'),
  (14, '14', '9200-7802-DINDA ANITA DINDA SIMAUNG', '9200', '7802', 'DINDA ANITA DINDA SIMAUNG', 'GUDANG ANITA', 'Titipan', '2026-04-29 07:59:00+07', 'Admin', '2026-04-29 07:59:00+07', 'Admin', 'GK-7802-DD41DB', 'GK-KARDUS-000014'),
  (15, '15', '6100-9842-ANITA BINTANG GILANG MUHAMMAD GILANG', '6100', '9842', 'ANITA BINTANG GILANG MUHAMMAD GILANG', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:00:00+07', 'Admin', '2026-04-29 08:00:00+07', 'Admin', 'GK-9842-279DC7', 'GK-KARDUS-000015'),
  (16, '16', '3600-9197-FERRY ANITA FERRY SANTOSO', '3600', '9197', 'FERRY ANITA FERRY SANTOSO', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:05:00+07', 'Admin', '2026-04-29 08:05:00+07', 'Admin', 'GK-9197-438819', 'GK-KARDUS-000016'),
  (17, '17', '1900-7770-INTAN ANITA INTAN PERMATA', '1900', '7770', 'INTAN ANITA INTAN PERMATA', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:06:00+07', 'Admin', '2026-04-29 08:06:00+07', 'Admin', 'GK-7770-F5621F', 'GK-KARDUS-000017'),
  (18, '18', '1100-8317-AHMAD FAUZAN T ERLINA MAD FAUZAN', '1100', '8317', 'AHMAD FAUZAN T ERLINA MAD FAUZAN', 'GUDANG ERLINA', 'Titipan', '2026-04-29 08:07:00+07', 'Admin', '2026-04-29 08:07:00+07', 'Admin', 'GK-8317-40C734', 'GK-KARDUS-000018'),
  (19, '19', '6100-6146-ANITA BINTANG SITI NURHALIZ A SITI NURHALIZA', '6100', '6146', 'ANITA BINTANG SITI NURHALIZ A SITI NURHALIZA', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:09:00+07', 'Admin', '2026-04-29 08:09:00+07', 'Admin', 'GK-6146-15B92B', 'GK-KARDUS-000019'),
  (20, '20', '3700-1376-NENG KANAN T PAPUA SUNARSIH', '3700', '1376', 'NENG KANAN T PAPUA SUNARSIH', 'GUDANG NENG', 'Titipan', '2026-04-29 08:10:00+07', 'Admin', '2026-04-29 08:10:00+07', 'Admin', 'GK-1376-8E0DB1', 'GK-KARDUS-000020'),
  (21, '21', '4400-5034-SURYANI ARABA C HMAD TANTOWI', '4400', '5034', 'SURYANI ARABA C HMAD TANTOWI', 'GUDANG SURYANI', 'Titipan', '2026-04-29 08:11:00+07', 'Admin', '2026-04-29 08:11:00+07', 'Admin', 'GK-5034-43C1DD', 'GK-KARDUS-000021'),
  (22, '22', '1200-0353-ANITA BINTANG SARWENDAH SARWENDAH HALIM', '1200', '0353', 'ANITA BINTANG SARWENDAH SARWENDAH HALIM', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:13:00+07', 'Admin', '2026-04-29 08:13:00+07', 'Admin', 'GK-0353-4E1396', 'GK-KARDUS-000022'),
  (23, '23', '2800-7455-DENNY ANITA DENNY SETIAWAN', '2800', '7455', 'DENNY ANITA DENNY SETIAWAN', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:14:00+07', 'Admin', '2026-04-29 08:14:00+07', 'Admin', 'GK-7455-53E31A', 'GK-KARDUS-000023'),
  (24, '24', '4900-6177-ANITA BINTANG ZAKI MUBARAK ZAKI MUBARAK', '4900', '6177', 'ANITA BINTANG ZAKI MUBARAK ZAKI MUBARAK', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:15:00+07', 'Admin', '2026-04-29 08:15:00+07', 'Admin', 'GK-6177-D0F7F8', 'GK-KARDUS-000024'),
  (25, '25', '7500-9881-EKO T AMI EKO NUGROHO', '7500', '9881', 'EKO T AMI EKO NUGROHO', 'GUDANG AMI', 'Titipan', '2026-04-29 08:16:00+07', 'Admin', '2026-04-29 08:16:00+07', 'Admin', 'GK-9881-047ABC', 'GK-KARDUS-000025'),
  (26, '26', '8700-1272-NIRMA TEAM RINA NIRMA', '8700', '1272', 'NIRMA TEAM RINA NIRMA', 'GUDANG RINA', 'Titipan', '2026-04-29 08:18:00+07', 'Admin', '2026-04-29 08:18:00+07', 'Admin', 'GK-1272-7ABC75', 'GK-KARDUS-000026'),
  (27, '27', '8900-9889-AMELIA AMELIA BADUI', '8900', '9889', 'AMELIA AMELIA BADUI', 'GUDANG AMELIA', 'Titipan', '2026-04-29 08:19:00+07', 'Admin', '2026-04-29 08:19:00+07', 'Admin', 'GK-9889-D6EF8D', 'GK-KARDUS-000027'),
  (28, '28', '3300-0190-TJONG LI MI NABILA', '3300', '0190', 'TJONG LI MI NABILA', 'GUDANG AMI', 'Titipan', '2026-04-29 08:21:00+07', 'Admin', '2026-04-29 08:21:00+07', 'Admin', 'GK-0190-04EBA9', 'GK-KARDUS-000028'),
  (29, '29', '1400-6127-ANITA BINTANG SITI AULIA SITI AULIA', '1400', '6127', 'ANITA BINTANG SITI AULIA SITI AULIA', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:22:00+07', 'Admin', '2026-04-29 08:22:00+07', 'Admin', 'GK-6127-970BA2', 'GK-KARDUS-000029'),
  (30, '30', '1500-0491-AMI AMALIA PUTRI', '1500', '0491', 'AMI AMALIA PUTRI', 'GUDANG AMI', 'Titipan', '2026-04-29 08:22:00+07', 'Admin', '2026-04-29 08:22:00+07', 'Admin', 'GK-0491-A6683B', 'GK-KARDUS-000030'),
  (31, '31', '6800-6205-TAUFI TAUFIK', '6800', '6205', 'TAUFI TAUFIK', 'GUDANG TAUFIK', 'Titipan', '2026-04-29 08:23:00+07', 'Admin', '2026-04-29 08:23:00+07', 'Admin', 'GK-6205-9DF1CE', 'GK-KARDUS-000031'),
  (32, '32', '6500-0080-TJONG LI MI ASEP', '6500', '0080', 'TJONG LI MI ASEP', 'GUDANG AMI', 'Titipan', '2026-04-29 08:25:00+07', 'Admin', '2026-04-29 08:25:00+07', 'Admin', 'GK-0080-B7F529', 'GK-KARDUS-000032'),
  (33, '33', '3600-9813-SURYANI ARAB SILVIA', '3600', '9813', 'SURYANI ARAB SILVIA', 'GUDANG SURYANI', 'Titipan', '2026-04-29 08:26:00+07', 'Admin', '2026-04-29 08:26:00+07', 'Admin', 'GK-9813-9B5734', 'GK-KARDUS-000033'),
  (34, '34', '1000-3586-ANITA BINTANG WENDI SALIM WENDI SALIN', '1000', '3586', 'ANITA BINTANG WENDI SALIM WENDI SALIN', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:28:00+07', 'Admin', '2026-04-29 08:28:00+07', 'Admin', 'GK-3586-830929', 'GK-KARDUS-000034'),
  (35, '35', '7300-9736-TJONG LI MI HERLAN PERLANA', '7300', '9736', 'TJONG LI MI HERLAN PERLANA', 'GUDANG AMI', 'Titipan', '2026-04-29 08:29:00+07', 'Admin', '2026-04-29 08:29:00+07', 'Admin', 'GK-9736-337511', 'GK-KARDUS-000035'),
  (36, '36', '6600-0082-TJONG LI MI MICAHEL PRATAMA SOELI ES TYO', '6600', '0082', 'TJONG LI MI MICAHEL PRATAMA SOELI ES TYO', 'GUDANG AMI', 'Titipan', '2026-04-29 08:31:00+07', 'Admin', '2026-04-29 08:31:00+07', 'Admin', 'GK-0082-9B1E23', 'GK-KARDUS-000036'),
  (37, '37', '4000-6196-AMI MIRA RACHEL', '4000', '6196', 'AMI MIRA RACHEL', 'GUDANG AMI', 'Titipan', '2026-04-29 08:33:00+07', 'Admin', '2026-04-29 08:33:00+07', 'Admin', 'GK-6196-0D22E4', 'GK-KARDUS-000037'),
  (38, '38', '0800-6193-AMI ARUM SARI', '0800', '6193', 'AMI ARUM SARI', 'GUDANG AMI', 'Titipan', '2026-04-29 08:33:00+07', 'Admin', '2026-04-29 08:33:00+07', 'Admin', 'GK-6193-A3351D', 'GK-KARDUS-000038'),
  (39, '39', '8500-8282-AMI TEGUH PRAKOSO', '8500', '8282', 'AMI TEGUH PRAKOSO', 'GUDANG AMI', 'Titipan', '2026-04-29 08:34:00+07', 'Admin', '2026-04-29 08:34:00+07', 'Admin', 'GK-8282-72DB09', 'GK-KARDUS-000039'),
  (40, '40', '5500-9723-NENG KANAN T PAPUA SITI KHUSNUL', '5500', '9723', 'NENG KANAN T PAPUA SITI KHUSNUL', 'GUDANG NENG', 'Titipan', '2026-04-29 08:35:00+07', 'Admin', '2026-04-29 08:35:00+07', 'Admin', 'GK-9723-902F19', 'GK-KARDUS-000040'),
  (41, '41', '2100-9993-neng kanan t papua lina nurlina', '2100', '9993', 'neng kanan t papua lina nurlina', 'GUDANG NENG', 'Titipan', '2026-04-29 08:40:00+07', 'Admin', '2026-04-29 08:40:00+07', 'Admin', 'GK-9993-28045E', 'GK-KARDUS-000041'),
  (42, '42', '5200-7748-eka anita eka suptra', '5200', '7748', 'eka anita eka suptra', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:48:00+07', 'Admin', '2026-04-29 08:48:00+07', 'Admin', 'GK-7748-DAB0FB', 'GK-KARDUS-000042'),
  (43, '43', '6300-1382-DEVIN MULYONO T WIFA DEVIN MULYONO', '6300', '1382', 'DEVIN MULYONO T WIFA DEVIN MULYONO', 'GUDANG WIFA', 'Titipan', '2026-04-29 08:49:00+07', 'Admin', '2026-04-29 08:49:00+07', 'Admin', 'GK-1382-148E5E', 'GK-KARDUS-000043'),
  (44, '44', '9800-6147-ANITA BINTANG DIN BOENTARAN PIN BOENTARAN', '9800', '6147', 'ANITA BINTANG DIN BOENTARAN PIN BOENTARAN', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:50:00+07', 'Admin', '2026-04-29 08:50:00+07', 'Admin', 'GK-6147-0E960A', 'GK-KARDUS-000044'),
  (45, '45', '4300-0357-ANITA BINTANG DODHY DODHY ROHMAT', '4300', '0357', 'ANITA BINTANG DODHY DODHY ROHMAT', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:51:00+07', 'Admin', '2026-04-29 08:51:00+07', 'Admin', 'GK-0357-C1FA8A', 'GK-KARDUS-000045'),
  (46, '46', '9900-9766-TJONG LI MI NGATIAH', '9900', '9766', 'TJONG LI MI NGATIAH', 'GUDANG AMI', 'Titipan', '2026-04-29 08:51:00+07', 'Admin', '2026-04-29 08:51:00+07', 'Admin', 'GK-9766-54FA8A', 'GK-KARDUS-000046'),
  (47, '47', '9100-7620-NENG KANAN T PAPUA CICI SRIYANA', '9100', '7620', 'NENG KANAN T PAPUA CICI SRIYANA', 'GUDANG NENG', 'Titipan', '2026-04-29 08:53:00+07', 'Admin', '2026-04-29 08:53:00+07', 'Admin', 'GK-7620-F88A6D', 'GK-KARDUS-000047'),
  (48, '48', '5800-8255-WENDY SELVI WENDI CAGUR', '5800', '8255', 'WENDY SELVI WENDI CAGUR', 'GUDANG SELVI', 'Titipan', '2026-04-29 08:53:00+07', 'Admin', '2026-04-29 08:53:00+07', 'Admin', 'GK-8255-E7A7AA', 'GK-KARDUS-000048'),
  (49, '49', '0100-6149-ANITA BINTANG SARI SARI', '0100', '6149', 'ANITA BINTANG SARI SARI', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:54:00+07', 'Admin', '2026-04-29 08:54:00+07', 'Admin', 'GK-6149-637C80', 'GK-KARDUS-000049'),
  (50, '50', '2700-6126-ANITA BINTANG HAFSAH NABILA HAFSAH', '2700', '6126', 'ANITA BINTANG HAFSAH NABILA HAFSAH', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:55:00+07', 'Admin', '2026-04-29 08:55:00+07', 'Admin', 'GK-6126-11B62A', 'GK-KARDUS-000050'),
  (51, '51', '8600-6150-ANITA BINTANG NADIA NADIA', '8600', '6150', 'ANITA BINTANG NADIA NADIA', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:56:00+07', 'Admin', '2026-04-29 08:56:00+07', 'Admin', 'GK-6150-E5C412', 'GK-KARDUS-000051'),
  (52, '52', '7900-9816-NENG KANAN T PAPUA CANTIKA PUTRI', '7900', '9816', 'NENG KANAN T PAPUA CANTIKA PUTRI', 'GUDANG NENG', 'Titipan', '2026-04-29 08:56:00+07', 'Admin', '2026-04-29 08:56:00+07', 'Admin', 'GK-9816-1D8A39', 'GK-KARDUS-000052'),
  (53, '53', '7000-0085-TJONG LI MI KIKI RUHMAN', '7000', '0085', 'TJONG LI MI KIKI RUHMAN', 'GUDANG AMI', 'Titipan', '2026-04-29 08:57:00+07', 'Admin', '2026-04-29 08:57:00+07', 'Admin', 'GK-0085-50E873', 'GK-KARDUS-000053'),
  (54, '54', '3600-6152-ANITA BINTANG GITA MAHARANI GITA MAHARANI', '3600', '6152', 'ANITA BINTANG GITA MAHARANI GITA MAHARANI', 'GUDANG ANITA', 'Titipan', '2026-04-29 08:57:00+07', 'Admin', '2026-04-29 08:57:00+07', 'Admin', 'GK-6152-DD0C77', 'GK-KARDUS-000054'),
  (55, '55', '7800-8249-LESTARI HANDAYANI T ERLINE LESTARI', '7800', '8249', 'LESTARI HANDAYANI T ERLINE LESTARI', 'GUDANG ERLINE', 'Titipan', '2026-04-29 08:58:00+07', 'Admin', '2026-04-29 08:58:00+07', 'Admin', 'GK-8249-0AA66D', 'GK-KARDUS-000055'),
  (56, '56', '9300-9742-TJONG LI MI KRIS PINUS KAPITAN TENA NIRON', '9300', '9742', 'TJONG LI MI KRIS PINUS KAPITAN TENA NIRON', 'GUDANG TJONG LI MI', 'Titipan', '2026-04-29 08:58:00+07', 'Admin', '2026-04-29 08:58:00+07', 'Admin', 'GK-9742-5FE752', 'GK-KARDUS-000056'),
  (57, '57', '7900-8307-nofliana selvi NOFLIANA GRESCE MANU', '7900', '8307', 'nofliana selvi NOFLIANA GRESCE MANU', 'GUDANG SELVI', 'Titipan', '2026-04-29 09:00:00+07', 'Admin', '2026-04-29 09:00:00+07', 'Admin', 'GK-8307-07A775', 'GK-KARDUS-000057'),
  (58, '58', '6100-6171-ANITA BINTANG ALFAHRIALFAHRI', '6100', '6171', 'ANITA BINTANG ALFAHRIALFAHRI', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:01:00+07', 'Admin', '2026-04-29 09:01:00+07', 'Admin', 'GK-6171-7F213D', 'GK-KARDUS-000058'),
  (59, '59', '1600-0170-TJONG LI MI MANDIKA', '1600', '0170', 'TJONG LI MI MANDIKA', 'GUDANG AMI', 'Titipan', '2026-04-29 09:02:00+07', 'Admin', '2026-04-29 09:02:00+07', 'Admin', 'GK-0170-03DBCF', 'GK-KARDUS-000059'),
  (60, '60', '1000-6819-AJENG AJENG SUITA', '1000', '6819', 'AJENG AJENG SUITA', 'GUDANG AJENG', 'Titipan', '2026-04-29 09:02:00+07', 'Admin', '2026-04-29 09:02:00+07', 'Admin', 'GK-6819-F8058D', 'GK-KARDUS-000060'),
  (61, '61', '9000-8220-TINA MARIANA DMAMI', '9000', '8220', 'TINA MARIANA DMAMI', 'GUDANG TINA', 'Titipan', '2026-04-29 09:03:00+07', 'Admin', '2026-04-29 09:03:00+07', 'Admin', 'GK-8220-C33D07', 'GK-KARDUS-000061'),
  (62, '62', '9600-9809-TJONG LI MI ANITA KELOP', '9600', '9809', 'TJONG LI MI ANITA KELOP', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 09:04:00+07', 'Admin', '2026-04-29 09:04:00+07', 'Admin', 'GK-9809-899033', 'GK-KARDUS-000062'),
  (63, '63', '3400-0354-ANITA BINTANG BUDI EMAN BUDI EMAN', '3400', '0354', 'ANITA BINTANG BUDI EMAN BUDI EMAN', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:05:00+07', 'Admin', '2026-04-29 09:05:00+07', 'Admin', 'GK-0354-FECF58', 'GK-KARDUS-000063'),
  (64, '64', '2800-4819-SURYANI ARAB RINI YASLIANA SITOHAMG', '2800', '4819', 'SURYANI ARAB RINI YASLIANA SITOHAMG', 'GUDANG SURYANI', 'Titipan', '2026-04-29 09:06:00+07', 'Admin', '2026-04-29 09:06:00+07', 'Admin', 'GK-4819-544857', 'GK-KARDUS-000064'),
  (65, '65', '5600-7926-SUMANTO ANITA SUMANTO HALIM', '5600', '7926', 'SUMANTO ANITA SUMANTO HALIM', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:06:00+07', 'Admin', '2026-04-29 09:06:00+07', 'Admin', 'GK-7926-DCCEFB', 'GK-KARDUS-000065'),
  (66, '66', '8600-9894-SURYA T AMI SURYA MAHENDRA', '8600', '9894', 'SURYA T AMI SURYA MAHENDRA', 'GUDANG AMI', 'Titipan', '2026-04-29 09:08:00+07', 'Admin', '2026-04-29 09:08:00+07', 'Admin', 'GK-9894-810E33', 'GK-KARDUS-000066'),
  (67, '67', '5700-0291-TJONG LI MI NANDA BERMAHTA', '5700', '0291', 'TJONG LI MI NANDA BERMAHTA', 'GUDANG AMI', 'Titipan', '2026-04-29 09:10:00+07', 'Admin', '2026-04-29 09:10:00+07', 'Admin', 'GK-0291-684578', 'GK-KARDUS-000067'),
  (68, '68', '5900-0395-ESRA TEAM RINA ESRA RENDEN', '5900', '0395', 'ESRA TEAM RINA ESRA RENDEN', 'GUDANG RINA', 'Titipan', '2026-04-29 09:10:00+07', 'Admin', '2026-04-29 09:10:00+07', 'Admin', 'GK-0395-D3A1E9', 'GK-KARDUS-000068'),
  (69, '69', '1200-0360-ANITA BINTANG DONI DONI', '1200', '0360', 'ANITA BINTANG DONI DONI', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:11:00+07', 'Admin', '2026-04-29 09:11:00+07', 'Admin', 'GK-0360-165132', 'GK-KARDUS-000069'),
  (70, '70', '9100-9808-TJONG LI MI AGUS SEPTIAN', '9100', '9808', 'TJONG LI MI AGUS SEPTIAN', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 09:11:00+07', 'Admin', '2026-04-29 09:11:00+07', 'Admin', 'GK-9808-91FA6B', 'GK-KARDUS-000070'),
  (71, '71', '5600-0352-ANITA BINTANG GALIH GALIH SAPUTRO', '5600', '0352', 'ANITA BINTANG GALIH GALIH SAPUTRO', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:12:00+07', 'Admin', '2026-04-29 09:12:00+07', 'Admin', 'GK-0352-AA3E8F', 'GK-KARDUS-000071'),
  (72, '72', '3900-0290-TJONG LI MI LALA KIKI', '3900', '0290', 'TJONG LI MI LALA KIKI', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 09:13:00+07', 'Admin', '2026-04-29 09:13:00+07', 'Admin', 'GK-0290-25E319', 'GK-KARDUS-000072'),
  (73, '73', '8000-9884-TJONG LI MI DINDA PUTRI', '8000', '9884', 'TJONG LI MI DINDA PUTRI', 'GUDANG AMI', 'Titipan', '2026-04-29 09:14:00+07', 'Admin', '2026-04-29 09:14:00+07', 'Admin', 'GK-9884-466A96', 'GK-KARDUS-000073'),
  (74, '74', '4400-6197-AMIVINA AMELIA', '4400', '6197', 'AMIVINA AMELIA', 'GUDANG AMI', 'Titipan', '2026-04-29 09:15:00+07', 'Admin', '2026-04-29 09:15:00+07', 'Admin', 'GK-6197-7E380A', 'GK-KARDUS-000074'),
  (75, '75', '0700-6219-ADUL SELVI ABDUL AZIZ', '0700', '6219', 'ADUL SELVI ABDUL AZIZ', 'GUDANG SELVI', 'Titipan', '2026-04-29 09:15:00+07', 'Admin', '2026-04-29 09:15:00+07', 'Admin', 'GK-6219-E2E1A7', 'GK-KARDUS-000075'),
  (76, '76', '2500-9226-DERLY TEAM RINA DERLY APRILIANY', '2500', '9226', 'DERLY TEAM RINA DERLY APRILIANY', 'GUDANG RINA', 'Titipan', '2026-04-29 09:16:00+07', 'Admin', '2026-04-29 09:16:00+07', 'Admin', 'GK-9226-748A29', 'GK-KARDUS-000076'),
  (77, '77', '8000-6219-JANSEN HUTAPEA T MAWARNI JANSEN HUTAPEA', '8000', '6219', 'JANSEN HUTAPEA T MAWARNI JANSEN HUTAPEA', 'GUDANG SELVI', 'Titipan', '2026-04-29 09:17:00+07', 'Admin', '2026-04-29 09:17:00+07', 'Admin', 'GK-6219-AD2911', 'GK-KARDUS-000077'),
  (78, '78', '8000-9729-TJONG LI MI LALITA AGUSTIN', '8000', '9729', 'TJONG LI MI LALITA AGUSTIN', 'GUDNAG AMI', 'Milik Sendiri', '2026-04-29 09:18:00+07', 'Admin', '2026-04-29 09:18:00+07', 'Admin', 'GK-9729-439989', 'GK-KARDUS-000078'),
  (79, '79', '9900-9886-ANITA BINTANG DEVIN DEVIN', '9900', '9886', 'ANITA BINTANG DEVIN DEVIN', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:19:00+07', 'Admin', '2026-04-29 09:19:00+07', 'Admin', 'GK-9886-F2F2F8', 'GK-KARDUS-000079'),
  (80, '80', '8500-6131-ANITA BINTANG ANDREAS ANDREAS', '8500', '6131', 'ANITA BINTANG ANDREAS ANDREAS', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:20:00+07', 'Admin', '2026-04-29 09:20:00+07', 'Admin', 'GK-6131-0C39EA', 'GK-KARDUS-000080'),
  (81, '81', '3400-0359-ANITA BINTANG ARIF HIDAYAT', '3400', '0359', 'ANITA BINTANG ARIF HIDAYAT', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:20:00+07', 'Admin', '2026-04-29 09:20:00+07', 'Admin', 'GK-0359-76F222', 'GK-KARDUS-000081'),
  (82, '82', '1000-6204-HUSEN JAYA LAKSANA SELVI HUSEN JAYA', '1000', '6204', 'HUSEN JAYA LAKSANA SELVI HUSEN JAYA', 'GUDANG SELVI', 'Titipan', '2026-04-29 09:21:00+07', 'Admin', '2026-04-29 09:21:00+07', 'Admin', 'GK-6204-08EF5D', 'GK-KARDUS-000082'),
  (83, '83', '7100-0928-NENG KANAN T PAPUA HERI KUSWANTO', '7100', '0928', 'NENG KANAN T PAPUA HERI KUSWANTO', 'GUDANG NENG', 'Titipan', '2026-04-29 09:23:00+07', 'Admin', '2026-04-29 09:23:00+07', 'Admin', 'GK-0928-7800C6', 'GK-KARDUS-000083'),
  (84, '84', '1700-3482-AMI RAISA AFRA SAKILA', '1700', '3482', 'AMI RAISA AFRA SAKILA', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 09:24:00+07', 'Admin', '2026-04-29 09:24:00+07', 'Admin', 'GK-3482-85F02C', 'GK-KARDUS-000084'),
  (85, '85', '9700-9801-WULAN ANITA WULAN', '9700', '9801', 'WULAN ANITA WULAN', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:25:00+07', 'Admin', '2026-04-29 09:25:00+07', 'Admin', 'GK-9801-7C8F69', 'GK-KARDUS-000085'),
  (86, '86', '8600-4282-DODI IMANUEL ANITA DODI IMANUEL', '8600', '4282', 'DODI IMANUEL ANITA DODI IMANUEL', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:26:00+07', 'Admin', '2026-04-29 09:26:00+07', 'Admin', 'GK-4282-53768B', 'GK-KARDUS-000086'),
  (87, '87', '5000-9733-TJONG LI MI TIARA VINA', '5000', '9733', 'TJONG LI MI TIARA VINA', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 09:40:00+07', 'Admin', '2026-04-29 09:40:00+07', 'Admin', 'GK-9733-B786FE', 'GK-KARDUS-000087'),
  (88, '88', '1100-7632-YERIKHO ANITA YERIKHO RIDO HUTAHAEAN', '1100', '7632', 'YERIKHO ANITA YERIKHO RIDO HUTAHAEAN', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:42:00+07', 'Admin', '2026-04-29 09:42:00+07', 'Admin', 'GK-7632-BE3F0A', 'GK-KARDUS-000088'),
  (89, '89', '0400-6391-AMI ANGGA PRANATA', '0400', '6391', 'AMI ANGGA PRANATA', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 09:44:00+07', 'Admin', '2026-04-29 09:44:00+07', 'Admin', 'GK-6391-9B2A31', 'GK-KARDUS-000089'),
  (90, '90', '6500-6173-ANITA BINTANG DEDI MULYANTO DEDI MULYANTO', '6500', '6173', 'ANITA BINTANG DEDI MULYANTO DEDI MULYANTO', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:45:00+07', 'Admin', '2026-04-29 09:45:00+07', 'Admin', 'GK-6173-1554D7', 'GK-KARDUS-000090'),
  (91, '91', '1900-6170-ANITA BINTANG RAIHAN NUGRAHA RAIHAN', '1900', '6170', 'ANITA BINTANG RAIHAN NUGRAHA RAIHAN', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:47:00+07', 'Admin', '2026-04-29 09:47:00+07', 'Admin', 'GK-6170-5462BE', 'GK-KARDUS-000091'),
  (92, '92', '4100-0356-ANITA BINTANG RAMI RAMA ADITYA', '4100', '0356', 'ANITA BINTANG RAMI RAMA ADITYA', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:49:00+07', 'Admin', '2026-04-29 09:49:00+07', 'Admin', 'GK-0356-E3BAC3', 'GK-KARDUS-000092'),
  (93, '93', '1300-4807-ANITA BINTANG BAGAS BAGAS ADIPUTRA', '1300', '4807', 'ANITA BINTANG BAGAS BAGAS ADIPUTRA', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:50:00+07', 'Admin', '2026-04-29 09:50:00+07', 'Admin', 'GK-4807-4953AE', 'GK-KARDUS-000093'),
  (94, '94', '5700-1486-AMI VINA AMELIA', '5700', '1486', 'AMI VINA AMELIA', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 09:51:00+07', 'Admin', '2026-04-29 09:51:00+07', 'Admin', 'GK-1486-CF8F25', 'GK-KARDUS-000094'),
  (95, '95', '7800-6129-ANITA BINTANG VENDA HALIN VENDA HALIN', '7800', '6129', 'ANITA BINTANG VENDA HALIN VENDA HALIN', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:51:00+07', 'Admin', '2026-04-29 09:51:00+07', 'Admin', 'GK-6129-C9998E', 'GK-KARDUS-000095'),
  (96, '96', '3400-9855-NENG KANAN T PAPUA WIDURI', '3400', '9855', 'NENG KANAN T PAPUA WIDURI', 'GUDANG NENG', 'Titipan', '2026-04-29 09:53:00+07', 'Admin', '2026-04-29 09:53:00+07', 'Admin', 'GK-9855-68B36E', 'GK-KARDUS-000096'),
  (97, '97', '8700-7827-HERMANSYAH ANITA', '8700', '7827', 'HERMANSYAH ANITA', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:55:00+07', 'Admin', '2026-04-29 09:55:00+07', 'Admin', 'GK-7827-54C2BB', 'GK-KARDUS-000097'),
  (98, '98', '5200-7507-NENG KANAN T PAPUA YULLI', '5200', '7507', 'NENG KANAN T PAPUA YULLI', 'GUDANG NENG', 'Titipan', '2026-04-29 09:55:00+07', 'Admin', '2026-04-29 09:55:00+07', 'Admin', 'GK-7507-427FF3', 'GK-KARDUS-000098'),
  (99, '99', '9200-8243-AMI ABDUL RAHMAN', '9200', '8243', 'AMI ABDUL RAHMAN', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 09:57:00+07', 'Admin', '2026-04-29 09:57:00+07', 'Admin', 'GK-8243-793E7C', 'GK-KARDUS-000099'),
  (100, '100', '6200-4805-ANITA BINTANG KEYLA', '6200', '4805', 'ANITA BINTANG KEYLA', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:58:00+07', 'Admin', '2026-04-29 09:58:00+07', 'Admin', 'GK-4805-68086A', 'GK-KARDUS-000100'),
  (101, '101', '1900-6130-ANITA BINTANG IDAH IDAH', '1900', '6130', 'ANITA BINTANG IDAH IDAH', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:58:00+07', 'Admin', '2026-04-29 09:58:00+07', 'Admin', 'GK-6130-2915B7', 'GK-KARDUS-000101'),
  (102, '102', '5900-7850-FARHAN ANITA MAULANA', '5900', '7850', 'FARHAN ANITA MAULANA', 'GUDANG ANITA', 'Titipan', '2026-04-29 09:59:00+07', 'Admin', '2026-04-29 09:59:00+07', 'Admin', 'GK-7850-F7EE9F', 'GK-KARDUS-000102'),
  (103, '103', '8300-6179-ANITA BINTANG SOFIAH HUSNA SHOFIA', '8300', '6179', 'ANITA BINTANG SOFIAH HUSNA SHOFIA', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:00:00+07', 'Admin', '2026-04-29 10:00:00+07', 'Admin', 'GK-6179-294269', 'GK-KARDUS-000103'),
  (104, '104', '7700-7821-FADLI ANITA', '7700', '7821', 'FADLI ANITA', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:00:00+07', 'Admin', '2026-04-29 10:00:00+07', 'Admin', 'GK-7821-137F7A', 'GK-KARDUS-000104'),
  (105, '105', '1500-0041-NENG KANAN T PAPUA LIAM PUTRA', '1500', '0041', 'NENG KANAN T PAPUA LIAM PUTRA', 'GUDANG NENG', 'Titipan', '2026-04-29 10:01:00+07', 'Admin', '2026-04-29 10:01:00+07', 'Admin', 'GK-0041-889FD0', 'GK-KARDUS-000105'),
  (106, '106', '3400-6195-AMI T MAWARNI SARTIKA', '3400', '6195', 'AMI T MAWARNI SARTIKA', 'GUDANG AMI', 'Titipan', '2026-04-29 10:02:00+07', 'Admin', '2026-04-29 10:02:00+07', 'Admin', 'GK-6195-63CBA3', 'GK-KARDUS-000106'),
  (107, '107', '9700-0096-TJONG LI MI JANUAR HENDRATAMA', '9700', '0096', 'TJONG LI MI JANUAR HENDRATAMA', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 10:02:00+07', 'Admin', '2026-04-29 10:02:00+07', 'Admin', 'GK-0096-2EDE46', 'GK-KARDUS-000107'),
  (108, '108', '4000-7737-RAHMAD ANITA RAHMAD HIDAYAT', '4000', '7737', 'RAHMAD ANITA RAHMAD HIDAYAT', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:04:00+07', 'Admin', '2026-04-29 10:04:00+07', 'Admin', 'GK-7737-B72624', 'GK-KARDUS-000108'),
  (109, '109', '0700-6207-ABDUL SELVI ABDUL AZIZ', '0700', '6207', 'ABDUL SELVI ABDUL AZIZ', 'GUDANG SELVI', 'Titipan', '2026-04-29 10:05:00+07', 'Admin', '2026-04-29 10:05:00+07', 'Admin', 'GK-6207-FEB098', 'GK-KARDUS-000109'),
  (110, '110', '9200-9882-AMALIA AMALIA SAFIRA', '9200', '9882', 'AMALIA AMALIA SAFIRA', 'GUDANG AMALIA', 'Titipan', '2026-04-29 10:06:00+07', 'Admin', '2026-04-29 10:06:00+07', 'Admin', 'GK-9882-AAD4C1', 'GK-KARDUS-000110'),
  (111, '111', '7500-7736-MIRENDI ANITA MIRENDI SAMBO', '7500', '7736', 'MIRENDI ANITA MIRENDI SAMBO', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:07:00+07', 'Admin', '2026-04-29 10:07:00+07', 'Admin', 'GK-7736-D6B56B', 'GK-KARDUS-000111'),
  (112, '112', '7000-4216-TJONG LI MI KIKI RUHMAN', '7000', '4216', 'TJONG LI MI KIKI RUHMAN', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 10:07:00+07', 'Admin', '2026-04-29 10:07:00+07', 'Admin', 'GK-4216-50E873', 'GK-KARDUS-000112'),
  (113, '113', '8000-9965-NENG KANAN T PAPUA ARFATHAN MALIK RAZI', '8000', '9965', 'NENG KANAN T PAPUA ARFATHAN MALIK RAZI', 'GUDANG NENG', 'Titipan', '2026-04-29 10:09:00+07', 'Admin', '2026-04-29 10:09:00+07', 'Admin', 'GK-9965-C04674', 'GK-KARDUS-000113'),
  (114, '114', '5700-4219-TJONG LI MI NANDA BERMAHTA', '5700', '4219', 'TJONG LI MI NANDA BERMAHTA', 'GUDANG AMI', 'Titipan', '2026-04-29 10:09:00+07', 'Admin', '2026-04-29 10:09:00+07', 'Admin', 'GK-4219-684578', 'GK-KARDUS-000114'),
  (115, '115', '2400-7546-DENI ANITA DENI KURNIAWAN', '2400', '7546', 'DENI ANITA DENI KURNIAWAN', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:11:00+07', 'Admin', '2026-04-29 10:11:00+07', 'Admin', 'GK-7546-5A7792', 'GK-KARDUS-000115'),
  (116, '116', '3300-2215-NENG KANAN T PAPUA SUNARSIH', '3300', '2215', 'NENG KANAN T PAPUA SUNARSIH', 'GUDANG NENG', 'Titipan', '2026-04-29 10:13:00+07', 'Admin', '2026-04-29 10:13:00+07', 'Admin', 'GK-2215-8E0DB1', 'GK-KARDUS-000116'),
  (117, '117', '0900-4224-TJONG LI MI SUKIRNO', '0900', '4224', 'TJONG LI MI SUKIRNO', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 10:13:00+07', 'Admin', '2026-04-29 10:13:00+07', 'Admin', 'GK-4224-69E415', 'GK-KARDUS-000117'),
  (118, '118', '9200-6178-ANITA BINTANG WENNY', '9200', '6178', 'ANITA BINTANG WENNY', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:15:00+07', 'Admin', '2026-04-29 10:15:00+07', 'Admin', 'GK-6178-5364F7', 'GK-KARDUS-000118'),
  (119, '119', '1500-4228-AMI AMALIA PUTRI', '1500', '4228', 'AMI AMALIA PUTRI', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 10:15:00+07', 'Admin', '2026-04-29 10:15:00+07', 'Admin', 'GK-4228-A6683B', 'GK-KARDUS-000119'),
  (120, '120', '4000-3592-ANITA BINTAMG RIAN FIRMANSYAH', '4000', '3592', 'ANITA BINTAMG RIAN FIRMANSYAH', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:16:00+07', 'Admin', '2026-04-29 10:16:00+07', 'Admin', 'GK-3592-8CE143', 'GK-KARDUS-000120'),
  (121, '121', '5000-7592-TJONG LI MI TIARA VINA', '5000', '7592', 'TJONG LI MI TIARA VINA', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 10:17:00+07', 'Admin', '2026-04-29 10:17:00+07', 'Admin', 'GK-7592-B786FE', 'GK-KARDUS-000121'),
  (122, '122', '6600-4214-TJONG LI MI MICHAEL PRATAMA SOELIESTYO', '6600', '4214', 'TJONG LI MI MICHAEL PRATAMA SOELIESTYO', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 10:19:00+07', 'Admin', '2026-04-29 10:19:00+07', 'Admin', 'GK-4214-68D112', 'GK-KARDUS-000122'),
  (123, '123', '9400-3589-ANITA BINTANG ARDIANSYAH PUTRA', '9400', '3589', 'ANITA BINTANG ARDIANSYAH PUTRA', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:19:00+07', 'Admin', '2026-04-29 10:19:00+07', 'Admin', 'GK-3589-5DB3D7', 'GK-KARDUS-000123'),
  (124, '124', '3900-4222-TJONG LALA KIKI', '3900', '4222', 'TJONG LALA KIKI', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 10:19:00+07', 'Admin', '2026-04-29 10:19:00+07', 'Admin', 'GK-4222-2E05FC', 'GK-KARDUS-000124'),
  (125, '125', '2300-7581-ELLYS BYRALIMUDDIN DG NAI', '2300', '7581', 'ELLYS BYRALIMUDDIN DG NAI', 'GUDANG ELLYS', 'Titipan', '2026-04-29 10:20:00+07', 'Admin', '2026-04-29 10:20:00+07', 'Admin', 'GK-7581-704847', 'GK-KARDUS-000125'),
  (126, '126', '8600-0367-DODI IMANUEL ANITA DODI IMANUEL', '8600', '0367', 'DODI IMANUEL ANITA DODI IMANUEL', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:21:00+07', 'Admin', '2026-04-29 10:21:00+07', 'Admin', 'GK-0367-53768B', 'GK-KARDUS-000126'),
  (127, '127', '8600-3575-ANITA BINTANG MIRA RACHEL', '8600', '3575', 'ANITA BINTANG MIRA RACHEL', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:22:00+07', 'Admin', '2026-04-29 10:22:00+07', 'Admin', 'GK-3575-A1C36D', 'GK-KARDUS-000127'),
  (128, '128', '6700-8237-MARIANI SELVI PAKPAHAN', '6700', '8237', 'MARIANI SELVI PAKPAHAN', 'GUDANG SELVI', 'Titipan', '2026-04-29 10:24:00+07', 'Admin', '2026-04-29 10:24:00+07', 'Admin', 'GK-8237-D7E9CC', 'GK-KARDUS-000128'),
  (129, '129', '2700-0319-AMI ASNI PASARIBU', '2700', '0319', 'AMI ASNI PASARIBU', 'GUDANG AMI', 'Titipan', '2026-04-29 10:25:00+07', 'Admin', '2026-04-29 10:25:00+07', 'Admin', 'GK-0319-6E0B32', 'GK-KARDUS-000129'),
  (130, '130', '9900-9835-NENG KANAN T PAPUA ABDURAHMAN', '9900', '9835', 'NENG KANAN T PAPUA ABDURAHMAN', 'GUDANG NENG', 'Titipan', '2026-04-29 10:26:00+07', 'Admin', '2026-04-29 10:26:00+07', 'Admin', 'GK-9835-DD482A', 'GK-KARDUS-000130'),
  (131, '131', '1800-9740-NENG KANAN T PAPUA RINA HANDAYANI', '1800', '9740', 'NENG KANAN T PAPUA RINA HANDAYANI', 'GUDANG NENG', 'Titipan', '2026-04-29 10:28:00+07', 'Admin', '2026-04-29 10:28:00+07', 'Admin', 'GK-9740-B5547E', 'GK-KARDUS-000131'),
  (132, '132', '7700-9943-NABILA ANITA NABILA', '7700', '9943', 'NABILA ANITA NABILA', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:29:00+07', 'Admin', '2026-04-29 10:29:00+07', 'Admin', 'GK-9943-6F116C', 'GK-KARDUS-000132'),
  (133, '133', '1700-0587-AMI RAISHA AFRA SAKILA', '1700', '0587', 'AMI RAISHA AFRA SAKILA', 'GUDANG AMI', 'Titipan', '2026-04-29 10:29:00+07', 'Admin', '2026-04-29 10:29:00+07', 'Admin', 'GK-0587-067B0E', 'GK-KARDUS-000133'),
  (134, '134', '1600-7622-NENG KANAN T PAPUA ARUNA PUTRI', '1600', '7622', 'NENG KANAN T PAPUA ARUNA PUTRI', 'GUDANG NENG', 'Titipan', '2026-04-29 10:32:00+07', 'Admin', '2026-04-29 10:32:00+07', 'Admin', 'GK-7622-895F67', 'GK-KARDUS-000134'),
  (135, '135', '2200-9968-RUDIANTO TEAM RINA RUDIANTO', '2200', '9968', 'RUDIANTO TEAM RINA RUDIANTO', 'GUDANG RINA', 'Titipan', '2026-04-29 10:35:00+07', 'Admin', '2026-04-29 10:35:00+07', 'Admin', 'GK-9968-5F8860', 'GK-KARDUS-000135'),
  (136, '136', '1600-4208-TJONG LI MI ANDIKA', '1600', '4208', 'TJONG LI MI ANDIKA', 'GUDANG AMI', 'Titipan', '2026-04-29 10:37:00+07', 'Admin', '2026-04-29 10:37:00+07', 'Admin', 'GK-4208-5232D0', 'GK-KARDUS-000136'),
  (137, '137', '7000-1359-TJAHJA LIAY T WIFATJAHJA LIAY', '7000', '1359', 'TJAHJA LIAY T WIFATJAHJA LIAY', 'GUDANG WIFA', 'Titipan', '2026-04-29 10:37:00+07', 'Admin', '2026-04-29 10:37:00+07', 'Admin', 'GK-1359-355619', 'GK-KARDUS-000137'),
  (138, '138', '0500-6616-GINTING ANITA GINTING HAMATIR', '0500', '6616', 'GINTING ANITA GINTING HAMATIR', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:39:00+07', 'Admin', '2026-04-29 10:39:00+07', 'Admin', 'GK-6616-D001E7', 'GK-KARDUS-000138'),
  (139, '139', '2800-9754-NENG KANAN T PAPUA UUM SUPRIYADI', '2800', '9754', 'NENG KANAN T PAPUA UUM SUPRIYADI', 'GUDANG NENG', 'Titipan', '2026-04-29 10:39:00+07', 'Admin', '2026-04-29 10:39:00+07', 'Admin', 'GK-9754-D6C0C7', 'GK-KARDUS-000139'),
  (140, '140', '5200-9802-EVA ANITA EKA SAPUTRA', '5200', '9802', 'EVA ANITA EKA SAPUTRA', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:41:00+07', 'Admin', '2026-04-29 10:41:00+07', 'Admin', 'GK-9802-B441AB', 'GK-KARDUS-000140'),
  (141, '141', '6800-0000-MARCO ANITA MARCORIUS', '6800', '0000', 'MARCO ANITA MARCORIUS', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:44:00+07', 'Admin', '2026-04-29 10:44:00+07', 'Admin', 'GK-0000-615F28', 'GK-KARDUS-000141'),
  (142, '142', '4400-9781-SAMUEL ANITA SAMUEL MALUMUS', '4400', '9781', 'SAMUEL ANITA SAMUEL MALUMUS', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:46:00+07', 'Admin', '2026-04-29 10:46:00+07', 'Admin', 'GK-9781-E4F48B', 'GK-KARDUS-000142'),
  (143, '143', '0000-0236-JUMRIYEH ANITA JUMRIYEH', '0000', '0236', 'JUMRIYEH ANITA JUMRIYEH', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:46:00+07', 'Admin', '2026-04-29 10:46:00+07', 'Admin', 'GK-0236-8B7DA3', 'GK-KARDUS-000143'),
  (144, '144', '1000-6212-HUSEN JAYA LAKSANA SELVI HUSEN JAYA', '1000', '6212', 'HUSEN JAYA LAKSANA SELVI HUSEN JAYA', 'GUDANG SELVI', 'Titipan', '2026-04-29 10:47:00+07', 'Admin', '2026-04-29 10:47:00+07', 'Admin', 'GK-6212-08EF5D', 'GK-KARDUS-000144'),
  (145, '145', '6800-6212-TAUFI TAUFIK', '6800', '6212', 'TAUFI TAUFIK', 'GUDANG SELVI', 'Titipan', '2026-04-29 10:48:00+07', 'Admin', '2026-04-29 10:48:00+07', 'Admin', 'GK-6212-9DF1CE', 'GK-KARDUS-000145'),
  (146, '146', '8600-4895-TJONG LI MI ELIA FERNANDO PURBA', '8600', '4895', 'TJONG LI MI ELIA FERNANDO PURBA', 'GUDANG AMI', 'Titipan', '2026-04-29 10:48:00+07', 'Admin', '2026-04-29 10:48:00+07', 'Admin', 'GK-4895-FF3A86', 'GK-KARDUS-000146'),
  (147, '147', '6400-5035-TJONG LI MI ALOY HALIMUS', '6400', '5035', 'TJONG LI MI ALOY HALIMUS', 'GUDANG AMI', 'Titipan', '2026-04-29 10:49:00+07', 'Admin', '2026-04-29 10:49:00+07', 'Admin', 'GK-5035-B501E8', 'GK-KARDUS-000147'),
  (148, '148', '0200-9795-NENG KANAN T PAPUA KURNIA HIDAYAT', '0200', '9795', 'NENG KANAN T PAPUA KURNIA HIDAYAT', 'GUDANG NENG', 'Titipan', '2026-04-29 10:50:00+07', 'Admin', '2026-04-29 10:50:00+07', 'Admin', 'GK-9795-F312F0', 'GK-KARDUS-000148'),
  (149, '149', '9800-9709-NENG KANAN T PAPUA RAMDAN', '9800', '9709', 'NENG KANAN T PAPUA RAMDAN', 'GUDANG NENG', 'Titipan', '2026-04-29 10:53:00+07', 'Admin', '2026-04-29 10:53:00+07', 'Admin', 'GK-9709-5993C3', 'GK-KARDUS-000149'),
  (150, '150', '9600-8172-AMI BUYUNG TANJUNG', '9600', '8172', 'AMI BUYUNG TANJUNG', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 10:54:00+07', 'Admin', '2026-04-29 10:54:00+07', 'Admin', 'GK-8172-AA7BE3', 'GK-KARDUS-000150'),
  (151, '151', '7800-6274-ANITA BINTANG GILANG MUHAMMAD', '7800', '6274', 'ANITA BINTANG GILANG MUHAMMAD', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:54:00+07', 'Admin', '2026-04-29 10:54:00+07', 'Admin', 'GK-6274-465203', 'GK-KARDUS-000151'),
  (152, '152', '9000-7610-HERMIN TEAM RINA HERMIN PAKIDING', '9000', '7610', 'HERMIN TEAM RINA HERMIN PAKIDING', 'GUDANG RINA', 'Titipan', '2026-04-29 10:55:00+07', 'Admin', '2026-04-29 10:55:00+07', 'Admin', 'GK-7610-03E1AB', 'GK-KARDUS-000152'),
  (153, '153', '1200-8301-AMI ANGGA SAPUTERA', '1200', '8301', 'AMI ANGGA SAPUTERA', 'GUDANG AMI', 'Milik Sendiri', '2026-04-29 10:56:00+07', 'Admin', '2026-04-29 10:56:00+07', 'Admin', 'GK-8301-A95757', 'GK-KARDUS-000153'),
  (154, '154', '4100-7586-NENG KANAN T PAPUA AMMAR KHOLID', '4100', '7586', 'NENG KANAN T PAPUA AMMAR KHOLID', 'GUDANG NENG', 'Titipan', '2026-04-29 10:59:00+07', 'Admin', '2026-04-29 10:59:00+07', 'Admin', 'GK-7586-04B1C4', 'GK-KARDUS-000154'),
  (155, '155', '3800-9897-BOEN DM ANITA PIN BOENTARAN', '3800', '9897', 'BOEN DM ANITA PIN BOENTARAN', 'GUDANG ANITA', 'Titipan', '2026-04-29 10:59:00+07', 'Admin', '2026-04-29 10:59:00+07', 'Admin', 'GK-9897-B38A9C', 'GK-KARDUS-000155'),
  (156, '156', '0900-0387-TJONG LI MI SUKIRNO', '0900', '0387', 'TJONG LI MI SUKIRNO', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 05:55:00+07', 'Admin', '2026-04-30 05:55:00+07', 'Admin', 'GK-0387-69E415', 'GK-KARDUS-000156'),
  (157, '157', '8400-0351-ANITA BINTANG AMELIA AMELIA', '8400', '0351', 'ANITA BINTANG AMELIA AMELIA', 'GUDANG ANITA', 'Titipan', '2026-04-30 06:03:00+07', 'Admin', '2026-04-30 06:03:00+07', 'Admin', 'GK-0351-49B0DE', 'GK-KARDUS-000157'),
  (158, '158', '8600-1746-AMI T CHAELESS JULI SUJIANTO', '8600', '1746', 'AMI T CHAELESS JULI SUJIANTO', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 06:04:00+07', 'Admin', '2026-04-30 06:04:00+07', 'Admin', 'GK-1746-85C0E4', 'GK-KARDUS-000158'),
  (159, '159', '0600-3571-AMI ROPINDAH HASIBUAN', '0600', '3571', 'AMI ROPINDAH HASIBUAN', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 06:05:00+07', 'Admin', '2026-04-30 06:05:00+07', 'Admin', 'GK-3571-0AC2EE', 'GK-KARDUS-000159'),
  (160, '160', '3900-0101-TJONG LI MI LALA KLARA', '3900', '0101', 'TJONG LI MI LALA KLARA', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 06:06:00+07', 'Admin', '2026-04-30 06:06:00+07', 'Admin', 'GK-0101-0FFC02', 'GK-KARDUS-000160'),
  (161, '161', '3700-1381-AMI T WIFA ANDIKA', '3700', '1381', 'AMI T WIFA ANDIKA', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 06:08:00+07', 'Admin', '2026-04-30 06:08:00+07', 'Admin', 'GK-1381-07BBF1', 'GK-KARDUS-000161'),
  (162, '162', '8900-9790-SURYANI ARABROPINTA SIHITE', '8900', '9790', 'SURYANI ARABROPINTA SIHITE', 'GUDANG SURYANI', 'Titipan', '2026-04-30 06:11:00+07', 'Admin', '2026-04-30 06:11:00+07', 'Admin', 'GK-9790-AD21D6', 'GK-KARDUS-000162'),
  (163, '163', '8900-9790-SURYANI ARABROPINTA SIHITE', '8900', '9790', 'SURYANI ARABROPINTA SIHITE', 'GUDANG SURYANI', 'Titipan', '2026-04-30 06:44:00+07', 'Admin', '2026-04-30 06:44:00+07', 'Admin', 'GK-9790-AD21D6', 'GK-KARDUS-000163'),
  (164, '164', '2200-7754-RUDIANTO TEAM RINA', '2200', '7754', 'RUDIANTO TEAM RINA', 'GUDANG RINA', 'Titipan', '2026-04-30 06:45:00+07', 'Admin', '2026-04-30 06:45:00+07', 'Admin', 'GK-7754-D36E80', 'GK-KARDUS-000164'),
  (165, '165', '2200-7754-RUDIANTO TEAM RINA', '2200', '7754', 'RUDIANTO TEAM RINA', 'GUDANG RINA', 'Titipan', '2026-04-30 06:50:00+07', 'Admin', '2026-04-30 06:50:00+07', 'Admin', 'GK-7754-D36E80', 'GK-KARDUS-000165'),
  (166, '166', '8500-2804-NENG KANAN T PAPUA CANTIKA PUTRI', '8500', '2804', 'NENG KANAN T PAPUA CANTIKA PUTRI', 'GUDANG NENG', 'Titipan', '2026-04-30 06:53:00+07', 'Admin', '2026-04-30 06:53:00+07', 'Admin', 'GK-2804-1D8A39', 'GK-KARDUS-000166'),
  (167, '167', '2400-0211-RAISHA T WIFA AFRA SAKILA', '2400', '0211', 'RAISHA T WIFA AFRA SAKILA', 'GUDANG WIFA', 'Titipan', '2026-04-30 06:57:00+07', 'Admin', '2026-04-30 06:57:00+07', 'Admin', 'GK-0211-E87F75', 'GK-KARDUS-000167'),
  (168, '168', '7500-2957-AMELIA ANITA', '7500', '2957', 'AMELIA ANITA', 'GUDANG ANITA', 'Titipan', '2026-04-30 07:01:00+07', 'Admin', '2026-04-30 07:01:00+07', 'Admin', 'GK-2957-F40958', 'GK-KARDUS-000168'),
  (169, '169', '0900-9989-CONTOTUA SELVI MARBUN', '0900', '9989', 'CONTOTUA SELVI MARBUN', 'GUDANG SELVI', 'Titipan', '2026-04-30 07:03:00+07', 'Admin', '2026-04-30 07:03:00+07', 'Admin', 'GK-9989-DE76BA', 'GK-KARDUS-000169'),
  (170, '170', '0100-9769-PAJAR SELVI PAJAR RUDI', '0100', '9769', 'PAJAR SELVI PAJAR RUDI', 'GUDANG SELVI', 'Titipan', '2026-04-30 07:04:00+07', 'Admin', '2026-04-30 07:04:00+07', 'Admin', 'GK-9769-6BE1FF', 'GK-KARDUS-000170'),
  (171, '171', '6200-0641-NENG KANAN T PAPUA ADINDA ARISA', '6200', '0641', 'NENG KANAN T PAPUA ADINDA ARISA', 'GUDANG NENG', 'Titipan', '2026-04-30 07:07:00+07', 'Admin', '2026-04-30 07:07:00+07', 'Admin', 'GK-0641-2DBD9C', 'GK-KARDUS-000171'),
  (172, '172', '2800-9854-iqbal selvi iqbal fariski sinaga', '2800', '9854', 'iqbal selvi iqbal fariski sinaga', 'GUDANG SELVI', 'Titipan', '2026-04-30 09:32:00+07', 'Admin', '2026-04-30 09:32:00+07', 'Admin', 'GK-9854-384F21', 'GK-KARDUS-000172'),
  (173, '173', '7700-0035-NENG KANAN T PAPUA BULAN BAGASWARI', '7700', '0035', 'NENG KANAN T PAPUA BULAN BAGASWARI', 'GUDANG NENG', 'Titipan', '2026-04-30 09:33:00+07', 'Admin', '2026-04-30 09:33:00+07', 'Admin', 'GK-0035-4EFDA4', 'GK-KARDUS-000173'),
  (174, '174', '9800-7514-TUTIK TEAM RINA TUTIK RAHAYU', '9800', '7514', 'TUTIK TEAM RINA TUTIK RAHAYU', 'GUDANG RINA', 'Titipan', '2026-04-30 09:35:00+07', 'Admin', '2026-04-30 09:35:00+07', 'Admin', 'GK-7514-6A13C8', 'GK-KARDUS-000174'),
  (175, '175', '3000-4914-Tjong Li Mi rofinus laro', '3000', '4914', 'Tjong Li Mi rofinus laro', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 09:35:00+07', 'Admin', '2026-04-30 09:35:00+07', 'Admin', 'GK-4914-474A82', 'GK-KARDUS-000175'),
  (176, '176', '0400-6556-SAMSUL TEAM RINA SAMSUL ARIPIN', '0400', '6556', 'SAMSUL TEAM RINA SAMSUL ARIPIN', 'GUDANG RINA', 'Titipan', '2026-04-30 09:36:00+07', 'Admin', '2026-04-30 09:36:00+07', 'Admin', 'GK-6556-9B897A', 'GK-KARDUS-000176'),
  (177, '177', '7700-9696-FADLI ANITA FADLI', '7700', '9696', 'FADLI ANITA FADLI', 'GUDANG ANITA', 'Titipan', '2026-04-30 09:37:00+07', 'Admin', '2026-04-30 09:37:00+07', 'Admin', 'GK-9696-F38051', 'GK-KARDUS-000177'),
  (178, '178', '2500-7435-NENG KANAN T PAPUA ANDITA PUTRI', '2500', '7435', 'NENG KANAN T PAPUA ANDITA PUTRI', 'GUDANG NENG', 'Titipan', '2026-04-30 09:38:00+07', 'Admin', '2026-04-30 09:38:00+07', 'Admin', 'GK-7435-DCDA85', 'GK-KARDUS-000178'),
  (179, '179', '3600-5036-ferry anita ferry santoso', '3600', '5036', 'ferry anita ferry santoso', 'GUDANG ANITA', 'Titipan', '2026-04-30 09:38:00+07', 'Admin', '2026-04-30 09:38:00+07', 'Admin', 'GK-5036-438819', 'GK-KARDUS-000179'),
  (180, '180', '2000-7614-NENG KANAN T PAPUA ARFHATAN MALIK RAZI', '2000', '7614', 'NENG KANAN T PAPUA ARFHATAN MALIK RAZI', 'GUDANG NENG', 'Titipan', '2026-04-30 09:39:00+07', 'Admin', '2026-04-30 09:39:00+07', 'Admin', 'GK-7614-5D04F4', 'GK-KARDUS-000180'),
  (181, '181', '6000-0067-NENG KANAN T PAPUA OLIVIA KIMI', '6000', '0067', 'NENG KANAN T PAPUA OLIVIA KIMI', 'GUDANG NENG', 'Titipan', '2026-04-30 09:40:00+07', 'Admin', '2026-04-30 09:40:00+07', 'Admin', 'GK-0067-292595', 'GK-KARDUS-000181'),
  (182, '182', '6400-8222-chandra selvi chandra', '6400', '8222', 'chandra selvi chandra', 'GUDANG SELVI', 'Titipan', '2026-04-30 09:41:00+07', 'Admin', '2026-04-30 09:41:00+07', 'Admin', 'GK-8222-A7ABC3', 'GK-KARDUS-000182'),
  (183, '183', '4600-9837-NENG KANAN T PAPUA KAYLA PUTRI', '4600', '9837', 'NENG KANAN T PAPUA KAYLA PUTRI', 'GUDANG NENG', 'Titipan', '2026-04-30 09:41:00+07', 'Admin', '2026-04-30 09:41:00+07', 'Admin', 'GK-9837-3AF253', 'GK-KARDUS-000183'),
  (184, '184', '1100-9881-YERIKO ANITA YERIKO RIDHO HUTAHEAN', '1100', '9881', 'YERIKO ANITA YERIKO RIDHO HUTAHEAN', 'GUDANG ANITA', 'Titipan', '2026-04-30 09:42:00+07', 'Admin', '2026-04-30 09:42:00+07', 'Admin', 'GK-9881-080F5A', 'GK-KARDUS-000184'),
  (185, '185', '8000-6279-ami t mawarni lukman hakim', '8000', '6279', 'ami t mawarni lukman hakim', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 09:43:00+07', 'Admin', '2026-04-30 09:43:00+07', 'Admin', 'GK-6279-02E5F8', 'GK-KARDUS-000185'),
  (186, '186', '1300-5075-RAKA ANITA RAKA WIJAYA', '1300', '5075', 'RAKA ANITA RAKA WIJAYA', 'GUDANG ANITA', 'Titipan', '2026-04-30 09:43:00+07', 'Admin', '2026-04-30 09:43:00+07', 'Admin', 'GK-5075-95B698', 'GK-KARDUS-000186'),
  (187, '187', '7700-0062-tjong li mi eplin rutris sabuna', '7700', '0062', 'tjong li mi eplin rutris sabuna', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 09:44:00+07', 'Admin', '2026-04-30 09:44:00+07', 'Admin', 'GK-0062-0B0E15', 'GK-KARDUS-000187'),
  (188, '188', '4100-5024-TJONG LI MI ERLANG HAMUDI', '4100', '5024', 'TJONG LI MI ERLANG HAMUDI', 'GUDANG AMI', 'Titipan', '2026-04-30 09:45:00+07', 'Admin', '2026-04-30 09:45:00+07', 'Admin', 'GK-5024-F2B75B', 'GK-KARDUS-000188'),
  (189, '189', '4100-0336-ANITA BINTANG RAMI J RAMA ADITYA', '4100', '0336', 'ANITA BINTANG RAMI J RAMA ADITYA', 'GUDANG ANITA', 'Titipan', '2026-04-30 09:48:00+07', 'Admin', '2026-04-30 09:48:00+07', 'Admin', 'GK-0336-C5A565', 'GK-KARDUS-000189'),
  (190, '190', '6100-4106-ANITA BINTANG DIAN DIAN', '6100', '4106', 'ANITA BINTANG DIAN DIAN', 'GUDANG ANITA', 'Titipan', '2026-04-30 09:49:00+07', 'Admin', '2026-04-30 09:49:00+07', 'Admin', 'GK-4106-2A8555', 'GK-KARDUS-000190'),
  (191, '191', '4900-9920-neng kanan t papua bayu', '4900', '9920', 'neng kanan t papua bayu', 'GUDANG NENG', 'Titipan', '2026-04-30 09:50:00+07', 'Admin', '2026-04-30 09:50:00+07', 'Admin', 'GK-9920-5F39EA', 'GK-KARDUS-000191'),
  (192, '192', '5700-1493-AMI VINA AMELIA', '5700', '1493', 'AMI VINA AMELIA', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 09:50:00+07', 'Admin', '2026-04-30 09:50:00+07', 'Admin', 'GK-1493-CF8F25', 'GK-KARDUS-000192'),
  (193, '193', '4000-1493-AMI MIRA RACHELL', '4000', '1493', 'AMI MIRA RACHELL', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 09:50:00+07', 'Admin', '2026-04-30 09:50:00+07', 'Admin', 'GK-1493-D52327', 'GK-KARDUS-000193'),
  (194, '194', '2900-8261-AMI SARTIKA DEWI', '2900', '8261', 'AMI SARTIKA DEWI', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 09:51:00+07', 'Admin', '2026-04-30 09:51:00+07', 'Admin', 'GK-8261-4C7EA9', 'GK-KARDUS-000194'),
  (195, '195', '5700-8230-debora selvi debora parinding', '5700', '8230', 'debora selvi debora parinding', 'GUDANG SELVI', 'Titipan', '2026-04-30 09:52:00+07', 'Admin', '2026-04-30 09:52:00+07', 'Admin', 'GK-8230-BAA1C3', 'GK-KARDUS-000195'),
  (196, '196', '8700-0057-HERMANSYAH ANITA HERMANSYAH', '8700', '0057', 'HERMANSYAH ANITA HERMANSYAH', 'GUDANG ANITA', 'Titipan', '2026-04-30 09:52:00+07', 'Admin', '2026-04-30 09:52:00+07', 'Admin', 'GK-0057-0C0ACD', 'GK-KARDUS-000196'),
  (197, '197', '0800-9833-NENG KANAN T PAPUA MIMI AISYAH', '0800', '9833', 'NENG KANAN T PAPUA MIMI AISYAH', 'GUDANG NENG', 'Titipan', '2026-04-30 09:53:00+07', 'Admin', '2026-04-30 09:53:00+07', 'Admin', 'GK-9833-316895', 'GK-KARDUS-000197'),
  (198, '198', '9000-4840-YUSPIN TEAM RINA YUSPIN PARIMATA', '9000', '4840', 'YUSPIN TEAM RINA YUSPIN PARIMATA', 'GUDANG RINA', 'Titipan', '2026-04-30 09:54:00+07', 'Admin', '2026-04-30 09:54:00+07', 'Admin', 'GK-4840-7700F3', 'GK-KARDUS-000198'),
  (199, '199', '3800-7633-neng kanan t papua alvan', '3800', '7633', 'neng kanan t papua alvan', 'GUDANG NENG', 'Titipan', '2026-04-30 09:55:00+07', 'Admin', '2026-04-30 09:55:00+07', 'Admin', 'GK-7633-13025E', 'GK-KARDUS-000199'),
  (200, '200', '0300-4841-RIANTO TEAM RINA RIANTO KARURU', '0300', '4841', 'RIANTO TEAM RINA RIANTO KARURU', 'GUDANG RINA', 'Titipan', '2026-04-30 09:55:00+07', 'Admin', '2026-04-30 09:55:00+07', 'Admin', 'GK-4841-26E3F5', 'GK-KARDUS-000200'),
  (201, '201', '3300-3434-Tjong li mi nabila', '3300', '3434', 'Tjong li mi nabila', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 09:56:00+07', 'Admin', '2026-04-30 09:56:00+07', 'Admin', 'GK-3434-04EBA9', 'GK-KARDUS-000201'),
  (202, '202', '2900-0058-NENG KANAN T PAPUA IPIN HIDAYAT', '2900', '0058', 'NENG KANAN T PAPUA IPIN HIDAYAT', 'GUDANG NENG', 'Titipan', '2026-04-30 09:57:00+07', 'Admin', '2026-04-30 09:57:00+07', 'Admin', 'GK-0058-CAA8DF', 'GK-KARDUS-000202'),
  (203, '203', '2500-4980-DERLY TEAM RINA DERLY APRILIANI', '2500', '4980', 'DERLY TEAM RINA DERLY APRILIANI', 'GUDANG RINA', 'Titipan', '2026-04-30 09:58:00+07', 'Admin', '2026-04-30 09:58:00+07', 'Admin', 'GK-4980-8248DD', 'GK-KARDUS-000203'),
  (204, '204', '8500-8227-suryati selvi suryati', '8500', '8227', 'suryati selvi suryati', 'GUDANG SELVI', 'Titipan', '2026-04-30 10:00:00+07', 'Admin', '2026-04-30 10:00:00+07', 'Admin', 'GK-8227-4FAB30', 'GK-KARDUS-000204'),
  (205, '205', '9400-6264-ANITA BINTANG DWI TRI D WITRI', '9400', '6264', 'ANITA BINTANG DWI TRI D WITRI', 'GUDANG ANITA', 'Titipan', '2026-04-30 10:00:00+07', 'Admin', '2026-04-30 10:00:00+07', 'Admin', 'GK-6264-59C629', 'GK-KARDUS-000205'),
  (206, '206', '2300-7554-NENG KANAN T PAPUA NASIWA AZIZAH', '2300', '7554', 'NENG KANAN T PAPUA NASIWA AZIZAH', 'GUDANG NENG', 'Titipan', '2026-04-30 10:01:00+07', 'Admin', '2026-04-30 10:01:00+07', 'Admin', 'GK-7554-E76735', 'GK-KARDUS-000206'),
  (207, '207', '4800-3876-HERMIN TEAM RINA HERMIN PAKIDING', '4800', '3876', 'HERMIN TEAM RINA HERMIN PAKIDING', 'GUDANG RINA', 'Titipan', '2026-04-30 10:05:00+07', 'Admin', '2026-04-30 10:05:00+07', 'Admin', 'GK-3876-03E1AB', 'GK-KARDUS-000207'),
  (208, '208', '8100-0314-AMI MARSELINUS MALE', '8100', '0314', 'AMI MARSELINUS MALE', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 10:08:00+07', 'Admin', '2026-04-30 10:08:00+07', 'Admin', 'GK-0314-0F32B2', 'GK-KARDUS-000208'),
  (209, '209', '1400-3619-TINA MARIANA D MAMI', '1400', '3619', 'TINA MARIANA D MAMI', 'GUDANG TINA', 'Titipan', '2026-04-30 10:09:00+07', 'Admin', '2026-04-30 10:09:00+07', 'Admin', 'GK-3619-674523', 'GK-KARDUS-000209'),
  (210, '210', '4600-9882-NENG KANAN T PAPUA WELI', '4600', '9882', 'NENG KANAN T PAPUA WELI', 'GUDANG NENG', 'Titipan', '2026-04-30 10:12:00+07', 'Admin', '2026-04-30 10:12:00+07', 'Admin', 'GK-9882-FE1CC7', 'GK-KARDUS-000210'),
  (211, '211', '5100-8099-FARHAN ANITA FARHAN MAULANA', '5100', '8099', 'FARHAN ANITA FARHAN MAULANA', 'GUDANG ANITA', 'Titipan', '2026-04-30 10:12:00+07', 'Admin', '2026-04-30 10:12:00+07', 'Admin', 'GK-8099-1EC964', 'GK-KARDUS-000211'),
  (212, '212', '6200-8271-NURHADI SELVI NURHADI SETIAWAN', '6200', '8271', 'NURHADI SELVI NURHADI SETIAWAN', 'GUDANG SELVI', 'Titipan', '2026-04-30 10:13:00+07', 'Admin', '2026-04-30 10:13:00+07', 'Admin', 'GK-8271-6B684F', 'GK-KARDUS-000212'),
  (213, '213', '9000-9950-NENG KANAN T PAPUA DEVI AULIA', '9000', '9950', 'NENG KANAN T PAPUA DEVI AULIA', 'GUDANG NENG', 'Titipan', '2026-04-30 10:16:00+07', 'Admin', '2026-04-30 10:16:00+07', 'Admin', 'GK-9950-175BF2', 'GK-KARDUS-000213'),
  (214, '214', '2600-3991-NOVI HANDAYANI T MAWARNI NOVI HANDAYANI', '2600', '3991', 'NOVI HANDAYANI T MAWARNI NOVI HANDAYANI', 'GUDANG MAWARNI', 'Titipan', '2026-04-30 10:18:00+07', 'Admin', '2026-04-30 10:18:00+07', 'Admin', 'GK-3991-310102', 'GK-KARDUS-000214'),
  (215, '215', '0200-9858-ARUM ARUM WULANDARI', '0200', '9858', 'ARUM ARUM WULANDARI', 'GUDANG RANDOM', 'Titipan', '2026-04-30 10:19:00+07', 'Admin', '2026-04-30 10:19:00+07', 'Admin', 'GK-9858-1DF7A2', 'GK-KARDUS-000215'),
  (216, '216', '0900-3991-MARIA ERMELINDA T CARLES MARIA ERMELINDA INDA DEPA', '0900', '3991', 'MARIA ERMELINDA T CARLES MARIA ERMELINDA INDA DEPA', 'GUDANG MAWARNI', 'Titipan', '2026-04-30 10:19:00+07', 'Admin', '2026-04-30 10:19:00+07', 'Admin', 'GK-3991-6BF048', 'GK-KARDUS-000216'),
  (217, '217', '0800-9858-ARIL ARIEL JUMAINAH', '0800', '9858', 'ARIL ARIEL JUMAINAH', 'GUDANG RANDOM', 'Titipan', '2026-04-30 10:20:00+07', 'Admin', '2026-04-30 10:20:00+07', 'Admin', 'GK-9858-CB03EF', 'GK-KARDUS-000217'),
  (218, '218', '9500-6229-MIRNA TEAM RINA MIRNA SUMINDAR', '9500', '6229', 'MIRNA TEAM RINA MIRNA SUMINDAR', 'GUDANG RINA', 'Titipan', '2026-04-30 10:20:00+07', 'Admin', '2026-04-30 10:20:00+07', 'Admin', 'GK-6229-71FB01', 'GK-KARDUS-000218'),
  (219, '219', '0000-9858-KEISHA KEISHA KALLISTA', '0000', '9858', 'KEISHA KEISHA KALLISTA', 'GUDANG RANDOM', 'Titipan', '2026-04-30 10:21:00+07', 'Admin', '2026-04-30 10:21:00+07', 'Admin', 'GK-9858-757062', 'GK-KARDUS-000219'),
  (220, '220', '1200-3925-LESTARI HANDAYANI T ERLIN KIRI LESTARI HANDAYANI', '1200', '3925', 'LESTARI HANDAYANI T ERLIN KIRI LESTARI HANDAYANI', 'GUDANG ERLIN', 'Titipan', '2026-04-30 10:22:00+07', 'Admin', '2026-04-30 10:22:00+07', 'Admin', 'GK-3925-ED47AB', 'GK-KARDUS-000220'),
  (221, '221', '0800-3936-NISA MAHARANI T ERLINNISA MAHARANI', '0800', '3936', 'NISA MAHARANI T ERLINNISA MAHARANI', 'GUDANG RANDOM', 'Titipan', '2026-04-30 10:23:00+07', 'Admin', '2026-04-30 10:23:00+07', 'Admin', 'GK-3936-930B05', 'GK-KARDUS-000221'),
  (222, '222', '51O0-3776-KARTIKA SARI T MARTHA KARTIKA SARI', '51O0', '3776', 'KARTIKA SARI T MARTHA KARTIKA SARI', 'GUDANG MARTHA', 'Titipan', '2026-04-30 10:23:00+07', 'Admin', '2026-04-30 10:23:00+07', 'Admin', 'GK-3776-DCC445', 'GK-KARDUS-000222'),
  (223, '223', '1300-3787-ARIEL JUMAINAH T ERLIN ARIEL JUMAINAH', '1300', '3787', 'ARIEL JUMAINAH T ERLIN ARIEL JUMAINAH', 'GUDANG RANDOM', 'Titipan', '2026-04-30 10:25:00+07', 'Admin', '2026-04-30 10:25:00+07', 'Admin', 'GK-3787-B8AC33', 'GK-KARDUS-000223'),
  (224, '224', '8700-3869-RIKA HARTIKA WATI SM T SHOFIA KANARIKA HARTIKA', '8700', '3869', 'RIKA HARTIKA WATI SM T SHOFIA KANARIKA HARTIKA', 'GUDANG SHOFIA', 'Titipan', '2026-04-30 10:25:00+07', 'Admin', '2026-04-30 10:25:00+07', 'Admin', 'GK-3869-C245C8', 'GK-KARDUS-000224'),
  (225, '225', '7900-4065-AGNES THERESIA T BEND KIRI AGNES THERESIA', '7900', '4065', 'AGNES THERESIA T BEND KIRI AGNES THERESIA', 'GUDANG RANDOM', 'Titipan', '2026-04-30 10:27:00+07', 'Admin', '2026-04-30 10:27:00+07', 'Admin', 'GK-4065-FBD8AA', 'GK-KARDUS-000225'),
  (226, '226', '8400-3988-MANGATAS ARITONANG T SHOFIA', '8400', '3988', 'MANGATAS ARITONANG T SHOFIA', 'GUDANG SHOFIA', 'Titipan', '2026-04-30 10:35:00+07', 'Admin', '2026-04-30 10:35:00+07', 'Admin', 'GK-3988-310FFB', 'GK-KARDUS-000226'),
  (227, '227', '4800-3850-WOEN T LILY T BOEN KANAN WOEN LILY', '4800', '3850', 'WOEN T LILY T BOEN KANAN WOEN LILY', 'GUDANG RANDOM', 'Titipan', '2026-04-30 10:37:00+07', 'Admin', '2026-04-30 10:37:00+07', 'Admin', 'GK-3850-1E445B', 'GK-KARDUS-000227'),
  (228, '228', '9900-0395-NENG KANAN T PAPUA ANITA MARLITA', '9900', '0395', 'NENG KANAN T PAPUA ANITA MARLITA', 'GUDANG NENG', 'Titipan', '2026-04-30 10:37:00+07', 'Admin', '2026-04-30 10:37:00+07', 'Admin', 'GK-0395-3EEAC2', 'GK-KARDUS-000228'),
  (229, '229', '4200-3957-STANNY T BOEN KANAN STANNY NOVILITA PEEA', '4200', '3957', 'STANNY T BOEN KANAN STANNY NOVILITA PEEA', 'GUDANG RANDOM', 'Titipan', '2026-04-30 10:39:00+07', 'Admin', '2026-04-30 10:39:00+07', 'Admin', 'GK-3957-BB300D', 'GK-KARDUS-000229'),
  (230, '230', '8500-3960-LIHO T BENDLIHO', '8500', '3960', 'LIHO T BENDLIHO', 'GUDANG RANDOM', 'Titipan', '2026-04-30 10:40:00+07', 'Admin', '2026-04-30 10:40:00+07', 'Admin', 'GK-3960-4323AD', 'GK-KARDUS-000230'),
  (231, '231', '2600-4041-MESHA T BOEN KIRI MESHA', '2600', '4041', 'MESHA T BOEN KIRI MESHA', 'GUDANG RANDOM', 'Titipan', '2026-04-30 10:41:00+07', 'Admin', '2026-04-30 10:41:00+07', 'Admin', 'GK-4041-9A465B', 'GK-KARDUS-000231'),
  (232, '232', '4400-3975-DINDA T MAWARNI DINDA', '4400', '3975', 'DINDA T MAWARNI DINDA', 'GUDANG MAWARNI', 'Titipan', '2026-04-30 10:42:00+07', 'Admin', '2026-04-30 10:42:00+07', 'Admin', 'GK-3975-C84044', 'GK-KARDUS-000232'),
  (233, '233', '2300-4106-YOHANNES T MAWARNI YOHANES', '2300', '4106', 'YOHANNES T MAWARNI YOHANES', 'GUDANG MAWARNI', 'Titipan', '2026-04-30 10:43:00+07', 'Admin', '2026-04-30 10:43:00+07', 'Admin', 'GK-4106-436639', 'GK-KARDUS-000233'),
  (234, '234', '5600-4106-AMI SITKA CHRISTIE', '5600', '4106', 'AMI SITKA CHRISTIE', 'GUDANG AMI', 'Milik Sendiri', '2026-04-30 10:44:00+07', 'Admin', '2026-04-30 10:44:00+07', 'Admin', 'GK-4106-A2BE48', 'GK-KARDUS-000234'),
  (235, '235', '5100-3975-SUKAEMI T MAWARNI', '5100', '3975', 'SUKAEMI T MAWARNI', 'GUDANG MAWARNI', 'Titipan', '2026-04-30 10:45:00+07', 'Admin', '2026-04-30 10:45:00+07', 'Admin', 'GK-3975-263FF1', 'GK-KARDUS-000235'),
  (236, '236', '0600-6114-Ami amalia safira', '0600', '6114', 'Ami amalia safira', 'KANTOR', 'Milik Sendiri', '2026-05-02 07:45:00+07', 'Admin', '2026-05-02 07:45:00+07', 'Admin', 'GK-6114-D9AC31', 'GK-KARDUS-000236'),
  (237, '237', '7700-3564-ami januar hendratama', '7700', '3564', 'ami januar hendratama', 'KANTOR', 'Milik Sendiri', '2026-05-02 07:50:00+07', 'Admin', '2026-05-02 07:50:00+07', 'Admin', 'GK-3564-40191E', 'GK-KARDUS-000237'),
  (238, '238', '0600-5041-Tjong li mi dedi sulaeman', '0600', '5041', 'Tjong li mi dedi sulaeman', 'KANTOR', 'Milik Sendiri', '2026-05-02 07:55:00+07', 'Admin', '2026-05-02 07:55:00+07', 'Admin', 'GK-5041-57543B', 'GK-KARDUS-000238'),
  (239, '239', '7000-4017-LIU OI KIMLIU OI KIM', '7000', '4017', 'LIU OI KIMLIU OI KIM', 'GUDANG RANDOM', 'Titipan', '2026-05-02 07:55:00+07', 'Admin', '2026-05-02 07:55:00+07', 'Admin', 'GK-4017-397E40', 'GK-KARDUS-000239'),
  (240, '240', '5600-4135-ANITA BINTANG TASMI TASMI', '5600', '4135', 'ANITA BINTANG TASMI TASMI', 'GUDANG ANITA', 'Titipan', '2026-05-02 07:57:00+07', 'Admin', '2026-05-02 07:57:00+07', 'Admin', 'GK-4135-FD824C', 'GK-KARDUS-000240'),
  (241, '241', '8000-6238-ami t mawarni lukman hakim', '8000', '6238', 'ami t mawarni lukman hakim', 'KANTOR', 'Milik Sendiri', '2026-05-02 07:57:00+07', 'Admin', '2026-05-02 07:57:00+07', 'Admin', 'GK-6238-02E5F8', 'GK-KARDUS-000241'),
  (242, '242', '0800-3911-nisa maharani t erlin nisa maharani', '0800', '3911', 'nisa maharani t erlin nisa maharani', 'GUDANG ERLIN', 'Titipan', '2026-05-02 08:00:00+07', 'Admin', '2026-05-02 08:00:00+07', 'Admin', 'GK-3911-BC0DF0', 'GK-KARDUS-000242'),
  (243, '243', '3000-8372-NURUL ANITA NURUL KHOTIMAH', '3000', '8372', 'NURUL ANITA NURUL KHOTIMAH', 'GUDANG ANITA', 'Titipan', '2026-05-02 08:00:00+07', 'Admin', '2026-05-02 08:00:00+07', 'Admin', 'GK-8372-1CE7A2', 'GK-KARDUS-000243'),
  (244, '244', '9700-3911-prabowo adi t mawarni prabowo adi', '9700', '3911', 'prabowo adi t mawarni prabowo adi', 'GUDANG ERLIN', 'Titipan', '2026-05-02 08:01:00+07', 'Admin', '2026-05-02 08:01:00+07', 'Admin', 'GK-3911-E913C5', 'GK-KARDUS-000244'),
  (245, '245', '3100-3911-richmond t charles richmond', '3100', '3911', 'richmond t charles richmond', 'GUDANG ERLIN', 'Titipan', '2026-05-02 08:01:00+07', 'Admin', '2026-05-02 08:01:00+07', 'Admin', 'GK-3911-A507EF', 'GK-KARDUS-000245'),
  (246, '246', '2700-0358-ANITA BINTANG SARI SARI', '2700', '0358', 'ANITA BINTANG SARI SARI', 'GUDANG ANITA', 'Titipan', '2026-05-02 08:03:00+07', 'Admin', '2026-05-02 08:03:00+07', 'Admin', 'GK-0358-637C80', 'GK-KARDUS-000246'),
  (247, '247', '5900-4086-marselinus male dm marselinus male', '5900', '4086', 'marselinus male dm marselinus male', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:05:00+07', 'Admin', '2026-05-02 08:05:00+07', 'Admin', 'GK-4086-1093EB', 'GK-KARDUS-000247'),
  (248, '248', '5300-3894-STANNY NOVILITA PEEA T BOEN KANAN STANNY', '5300', '3894', 'STANNY NOVILITA PEEA T BOEN KANAN STANNY', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:05:00+07', 'Admin', '2026-05-02 08:05:00+07', 'Admin', 'GK-3894-682672', 'GK-KARDUS-000248'),
  (249, '249', '7400-3923-casi bt akmar t dwi kiri casi bt akmar', '7400', '3923', 'casi bt akmar t dwi kiri casi bt akmar', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:07:00+07', 'Admin', '2026-05-02 08:07:00+07', 'Admin', 'GK-3923-DF1DED', 'GK-KARDUS-000249'),
  (250, '250', '3300-3845-KEISHA KALLISTA T EELIN KEISHA KALLISTA', '3300', '3845', 'KEISHA KALLISTA T EELIN KEISHA KALLISTA', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:08:00+07', 'Admin', '2026-05-02 08:08:00+07', 'Admin', 'GK-3845-0E7C5A', 'GK-KARDUS-000250'),
  (251, '251', '6900-4037-Liu oi kim T dwi edyliu oi kim', '6900', '4037', 'Liu oi kim T dwi edyliu oi kim', 'GUDANG DWI', 'Titipan', '2026-05-02 08:08:00+07', 'Admin', '2026-05-02 08:08:00+07', 'Admin', 'GK-4037-C9F319', 'GK-KARDUS-000251'),
  (252, '252', '1900-3954-Anita bintang ngatiyono ngatiyono', '1900', '3954', 'Anita bintang ngatiyono ngatiyono', 'GUDANG ANITA', 'Titipan', '2026-05-02 08:09:00+07', 'Admin', '2026-05-02 08:09:00+07', 'Admin', 'GK-3954-211F54', 'GK-KARDUS-000252'),
  (253, '253', '2700-6492-NOVALIA TEAM RINA NOVALIA FALENTINA MARANI', '2700', '6492', 'NOVALIA TEAM RINA NOVALIA FALENTINA MARANI', 'GUDANG RINA', 'Titipan', '2026-05-02 08:10:00+07', 'Admin', '2026-05-02 08:10:00+07', 'Admin', 'GK-6492-FC43E4', 'GK-KARDUS-000253'),
  (254, '254', '0600-2328-Neng kanan T. Rina Handayani', '0600', '2328', 'Neng kanan T. Rina Handayani', 'GUDANG NENG', 'Titipan', '2026-05-02 08:11:00+07', 'Admin', '2026-05-02 08:11:00+07', 'Admin', 'GK-2328-5AC7FF', 'GK-KARDUS-000254'),
  (255, '255', '6900-3959-Aston Aston', '6900', '3959', 'Aston Aston', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:11:00+07', 'Admin', '2026-05-02 08:11:00+07', 'Admin', 'GK-3959-2D06BE', 'GK-KARDUS-000255'),
  (256, '256', '3600-3913-ESRA TEAM RINA ESRA RENDEN', '3600', '3913', 'ESRA TEAM RINA ESRA RENDEN', 'GUDANG RINA', 'Titipan', '2026-05-02 08:13:00+07', 'Admin', '2026-05-02 08:13:00+07', 'Admin', 'GK-3913-D3A1E9', 'GK-KARDUS-000256'),
  (257, '257', '9200-3992-alvin prakoso t benhard alvin prakoso', '9200', '3992', 'alvin prakoso t benhard alvin prakoso', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:14:00+07', 'Admin', '2026-05-02 08:14:00+07', 'Admin', 'GK-3992-5E6C98', 'GK-KARDUS-000257'),
  (258, '258', '9900-0431-Donald Anita Ronard', '9900', '0431', 'Donald Anita Ronard', 'GUDANG ANITA', 'Titipan', '2026-05-02 08:15:00+07', 'Admin', '2026-05-02 08:15:00+07', 'Admin', 'GK-0431-34D9BE', 'GK-KARDUS-000258'),
  (259, '259', '6500-3942-MARTHA SIMANGUNSONG T MAWARNI MARTHA', '6500', '3942', 'MARTHA SIMANGUNSONG T MAWARNI MARTHA', 'GUDANG MAWARNI', 'Titipan', '2026-05-02 08:16:00+07', 'Admin', '2026-05-02 08:16:00+07', 'Admin', 'GK-3942-7F32C9', 'GK-KARDUS-000259'),
  (260, '260', '3200-0877-Anisa Hari Sutanto', '3200', '0877', 'Anisa Hari Sutanto', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:16:00+07', 'Admin', '2026-05-02 08:16:00+07', 'Admin', 'GK-0877-614FE6', 'GK-KARDUS-000260'),
  (261, '261', '9700-3939-Prabowo Adi T Mawarni', '9700', '3939', 'Prabowo Adi T Mawarni', 'GUDANG MAWARNI', 'Titipan', '2026-05-02 08:17:00+07', 'Admin', '2026-05-02 08:17:00+07', 'Admin', 'GK-3939-795EB1', 'GK-KARDUS-000261'),
  (262, '262', '7100-0350-ANITA BINTANG NANI NANI NINGSIH', '7100', '0350', 'ANITA BINTANG NANI NANI NINGSIH', 'GUDANG ANITA', 'Titipan', '2026-05-02 08:17:00+07', 'Admin', '2026-05-02 08:17:00+07', 'Admin', 'GK-0350-2C6548', 'GK-KARDUS-000262'),
  (263, '263', '1600-4083-Djohan T boendjohan', '1600', '4083', 'Djohan T boendjohan', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:18:00+07', 'Admin', '2026-05-02 08:18:00+07', 'Admin', 'GK-4083-7EADD5', 'GK-KARDUS-000263'),
  (264, '264', '8700-1398-EKI Fadli Hutasuhut t marta eki fadli hutasuhut', '8700', '1398', 'EKI Fadli Hutasuhut t marta eki fadli hutasuhut', 'GUDANG MARTA', 'Titipan', '2026-05-02 08:21:00+07', 'Admin', '2026-05-02 08:21:00+07', 'Admin', 'GK-1398-BBD7D0', 'GK-KARDUS-000264'),
  (265, '265', '3300-3846-jessica thanita limor t boen kiri jessica', '3300', '3846', 'jessica thanita limor t boen kiri jessica', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:23:00+07', 'Admin', '2026-05-02 08:23:00+07', 'Admin', 'GK-3846-9966A1', 'GK-KARDUS-000265'),
  (266, '266', '3600-3820-ARUM WULANDARI T ERLIN ARUM WULANDARI', '3600', '3820', 'ARUM WULANDARI T ERLIN ARUM WULANDARI', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:23:00+07', 'Admin', '2026-05-02 08:23:00+07', 'Admin', 'GK-3820-C216C6', 'GK-KARDUS-000266'),
  (267, '267', '6800-7773-MARCO ANITA MARCORIUS', '6800', '7773', 'MARCO ANITA MARCORIUS', 'GUDANG ANITA', 'Titipan', '2026-05-02 08:24:00+07', 'Admin', '2026-05-02 08:24:00+07', 'Admin', 'GK-7773-615F28', 'GK-KARDUS-000267'),
  (268, '268', '0200-4039-Agnes Theresia T Bend Kiri', '0200', '4039', 'Agnes Theresia T Bend Kiri', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:24:00+07', 'Admin', '2026-05-02 08:24:00+07', 'Admin', 'GK-4039-09E1AC', 'GK-KARDUS-000268'),
  (269, '269', '6000-3986-Alvin T dwi edyalvin tandrio', '6000', '3986', 'Alvin T dwi edyalvin tandrio', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:25:00+07', 'Admin', '2026-05-02 08:25:00+07', 'Admin', 'GK-3986-982926', 'GK-KARDUS-000269'),
  (270, '270', '4200-3786-Arman hakim T eelinarman hakim', '4200', '3786', 'Arman hakim T eelinarman hakim', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:26:00+07', 'Admin', '2026-05-02 08:26:00+07', 'Admin', 'GK-3786-D0F7F8', 'GK-KARDUS-000270'),
  (271, '271', '0300-3902-SITKA CRISHTIE T ERLIN KIRI SITKA CHRISTIE', '0300', '3902', 'SITKA CRISHTIE T ERLIN KIRI SITKA CHRISTIE', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:27:00+07', 'Admin', '2026-05-02 08:27:00+07', 'Admin', 'GK-3902-5C3203', 'GK-KARDUS-000271'),
  (272, '272', '0900-2447-Juliyana T. RINA Naingoian.', '0900', '2447', 'Juliyana T. RINA Naingoian.', 'GUDANG RINA', 'Titipan', '2026-05-02 08:28:00+07', 'Admin', '2026-05-02 08:28:00+07', 'Admin', 'GK-2447-279A28', 'GK-KARDUS-000272'),
  (273, '273', '6000-0680-Neng Kanan T. Abel Putri', '6000', '0680', 'Neng Kanan T. Abel Putri', 'GUDANG NENG', 'Titipan', '2026-05-02 08:28:00+07', 'Admin', '2026-05-02 08:28:00+07', 'Admin', 'GK-0680-2CA30B', 'GK-KARDUS-000273'),
  (274, '274', '4600-3792-MUH SUKARNO T MARTA MUH SUKARNO', '4600', '3792', 'MUH SUKARNO T MARTA MUH SUKARNO', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:29:00+07', 'Admin', '2026-05-02 08:29:00+07', 'Admin', 'GK-3792-FE5CBD', 'GK-KARDUS-000274'),
  (275, '275', '8500-3892-Alfi Syahrin SM T Shoria kanan alfi syahrin', '8500', '3892', 'Alfi Syahrin SM T Shoria kanan alfi syahrin', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:30:00+07', 'Admin', '2026-05-02 08:30:00+07', 'Admin', 'GK-3892-1F3B20', 'GK-KARDUS-000275'),
  (276, '276', '1700-3928-Jessica Jessica thanita Limor', '1700', '3928', 'Jessica Jessica thanita Limor', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:31:00+07', 'Admin', '2026-05-02 08:31:00+07', 'Admin', 'GK-3928-262132', 'GK-KARDUS-000276'),
  (277, '277', '1800-1411-NENG KANAN T PAPUA KAYLA PUTRI', '1800', '1411', 'NENG KANAN T PAPUA KAYLA PUTRI', 'GUDANG NENG', 'Titipan', '2026-05-02 08:32:00+07', 'Admin', '2026-05-02 08:32:00+07', 'Admin', 'GK-1411-3AF253', 'GK-KARDUS-000277'),
  (278, '278', '8100-0881-Rofinus Laro T. Marta', '8100', '0881', 'Rofinus Laro T. Marta', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:33:00+07', 'Admin', '2026-05-02 08:33:00+07', 'Admin', 'GK-0881-E9656A', 'GK-KARDUS-000278'),
  (279, '279', '3300-2375-Ami Maria Valentina', '3300', '2375', 'Ami Maria Valentina', 'GUDANG AMI', 'Milik Sendiri', '2026-05-02 08:33:00+07', 'Admin', '2026-05-02 08:33:00+07', 'Admin', 'GK-2375-2F0DBF', 'GK-KARDUS-000279'),
  (280, '280', '4900-4068-Efendi T Boen Kanan', '4900', '4068', 'Efendi T Boen Kanan', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:34:00+07', 'Admin', '2026-05-02 08:34:00+07', 'Admin', 'GK-4068-7DF7D5', 'GK-KARDUS-000280'),
  (281, '281', '2900-4063-Andrew Kusashi T wenny andrew kusashi', '2900', '4063', 'Andrew Kusashi T wenny andrew kusashi', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:35:00+07', 'Admin', '2026-05-02 08:35:00+07', 'Admin', 'GK-4063-DB1E83', 'GK-KARDUS-000281'),
  (282, '282', '6700-4042-JOSHUA SETIAWAN T WENNY JOSHUA SETIAWAN', '6700', '4042', 'JOSHUA SETIAWAN T WENNY JOSHUA SETIAWAN', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:35:00+07', 'Admin', '2026-05-02 08:35:00+07', 'Admin', 'GK-4042-0F608B', 'GK-KARDUS-000282'),
  (283, '283', '9700-9862-Neng Kanan T Papua Citra Putri', '9700', '9862', 'Neng Kanan T Papua Citra Putri', 'GUDANG NENG', 'Titipan', '2026-05-02 08:37:00+07', 'Admin', '2026-05-02 08:37:00+07', 'Admin', 'GK-9862-946138', 'GK-KARDUS-000283'),
  (284, '284', '7000-2351-Neng Kanan T. Garet Putra', '7000', '2351', 'Neng Kanan T. Garet Putra', 'GUDANG NENG', 'Titipan', '2026-05-02 08:39:00+07', 'Admin', '2026-05-02 08:39:00+07', 'Admin', 'GK-2351-E00D5D', 'GK-KARDUS-000284'),
  (285, '285', '3000-0349-ANITA BINTANG DIMAS DIMAS', '3000', '0349', 'ANITA BINTANG DIMAS DIMAS', 'GUDANG ANITA', 'Titipan', '2026-05-02 08:39:00+07', 'Admin', '2026-05-02 08:39:00+07', 'Admin', 'GK-0349-94090E', 'GK-KARDUS-000285'),
  (286, '286', '1000-3995-Rani ottaviani T erlin kirir ani oktaviani', '1000', '3995', 'Rani ottaviani T erlin kirir ani oktaviani', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:43:00+07', 'Admin', '2026-05-02 08:43:00+07', 'Admin', 'GK-3995-BCA5AE', 'GK-KARDUS-000286'),
  (287, '287', '9000-1374-Neng kanan T. Billy Ciputra', '9000', '1374', 'Neng kanan T. Billy Ciputra', 'GUDANG NENG', 'Titipan', '2026-05-02 08:45:00+07', 'Admin', '2026-05-02 08:45:00+07', 'Admin', 'GK-1374-4D30BC', 'GK-KARDUS-000287'),
  (288, '288', '9400-2319-Neng Kanan Kanan T. Kartika', '9400', '2319', 'Neng Kanan Kanan T. Kartika', 'GUDANG NENG', 'Titipan', '2026-05-02 08:48:00+07', 'Admin', '2026-05-02 08:48:00+07', 'Admin', 'GK-2319-444018', 'GK-KARDUS-000288'),
  (289, '289', '1600-3810-Anjani Puspita T Erlin', '1600', '3810', 'Anjani Puspita T Erlin', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:56:00+07', 'Admin', '2026-05-02 08:56:00+07', 'Admin', 'GK-3810-620323', 'GK-KARDUS-000289'),
  (290, '290', '6600-3898-Alvin Tandrio T Dwi Kiri', '6600', '3898', 'Alvin Tandrio T Dwi Kiri', 'GUDANG RANDOM', 'Titipan', '2026-05-02 08:57:00+07', 'Admin', '2026-05-02 08:57:00+07', 'Admin', 'GK-3898-C7D4B2', 'GK-KARDUS-000290'),
  (291, '291', '3700-5073-Tjong Li mi marselinus male', '3700', '5073', 'Tjong Li mi marselinus male', 'GUDANG AMI', 'Milik Sendiri', '2026-05-02 08:59:00+07', 'Admin', '2026-05-02 08:59:00+07', 'Admin', 'GK-5073-334EA5', 'GK-KARDUS-000291'),
  (292, '292', '0700-9927-Neng Kanan T Papua Ammar Kholid', '0700', '9927', 'Neng Kanan T Papua Ammar Kholid', 'GUDANG NENG', 'Titipan', '2026-05-02 09:01:00+07', 'Admin', '2026-05-02 09:01:00+07', 'Admin', 'GK-9927-04B1C4', 'GK-KARDUS-000292'),
  (293, '293', '4000-3886-HALIM JULIANTO T MAWARNI HALIM JULIANTO', '4000', '3886', 'HALIM JULIANTO T MAWARNI HALIM JULIANTO', 'GUDANG MAWARNI', 'Titipan', '2026-05-02 09:04:00+07', 'Admin', '2026-05-02 09:04:00+07', 'Admin', 'GK-3886-92B6E1', 'GK-KARDUS-000293'),
  (294, '294', '7300-8262-Shofia Anita Shofia Husna', '7300', '8262', 'Shofia Anita Shofia Husna', 'GUDANG ANITA', 'Titipan', '2026-05-02 09:04:00+07', 'Admin', '2026-05-02 09:04:00+07', 'Admin', 'GK-8262-7DBA4C', 'GK-KARDUS-000294'),
  (295, '295', '3400-3886-WINDA T MAWARNI T WINDA', '3400', '3886', 'WINDA T MAWARNI T WINDA', 'GUDANG RANDOM', 'Titipan', '2026-05-02 09:05:00+07', 'Admin', '2026-05-02 09:05:00+07', 'Admin', 'GK-3886-07B734', 'GK-KARDUS-000295'),
  (296, '296', '6600-4024-Ana leo T Bend kiri Ana leo', '6600', '4024', 'Ana leo T Bend kiri Ana leo', 'GUDANG RANDOM', 'Titipan', '2026-05-02 09:07:00+07', 'Admin', '2026-05-02 09:07:00+07', 'Admin', 'GK-4024-BAB1EF', 'GK-KARDUS-000296'),
  (297, '297', '2100-4084-Natasya Tania T Bend', '2100', '4084', 'Natasya Tania T Bend', 'GUDANG RANDOM', 'Titipan', '2026-05-02 09:09:00+07', 'Admin', '2026-05-02 09:09:00+07', 'Admin', 'GK-4084-8F5EE2', 'GK-KARDUS-000297'),
  (298, '298', '5200-5120-TJONG LI MI MARIA CARINA METIKORES', '5200', '5120', 'TJONG LI MI MARIA CARINA METIKORES', 'GUDANG AMI', 'Titipan', '2026-05-02 09:09:00+07', 'Admin', '2026-05-02 09:09:00+07', 'Admin', 'GK-5120-2EE85F', 'GK-KARDUS-000298'),
  (299, '299', '1000-9905-Suryani Arab tiffani jocelyn loe', '1000', '9905', 'Suryani Arab tiffani jocelyn loe', 'GUDANG SURYANI', 'Titipan', '2026-05-02 09:11:00+07', 'Admin', '2026-05-02 09:11:00+07', 'Admin', 'GK-9905-1443B1', 'GK-KARDUS-000299'),
  (300, '300', '7200-4018-CASIH DWI EDY CASIH BT AKMAR', '7200', '4018', 'CASIH DWI EDY CASIH BT AKMAR', 'GUDANG RANDOM', 'Titipan', '2026-05-02 09:14:00+07', 'Admin', '2026-05-02 09:14:00+07', 'Admin', 'GK-4018-DA8EA8', 'GK-KARDUS-000300'),
  (301, '301', '0700-8291-ILHAM Anita Kurniawan', '0700', '8291', 'ILHAM Anita Kurniawan', 'GUDANG ANITA', 'Titipan', '2026-05-02 09:14:00+07', 'Admin', '2026-05-02 09:14:00+07', 'Admin', 'GK-8291-3F11EE', 'GK-KARDUS-000301'),
  (302, '302', '8900-4020-ANA LEOANA LEO', '8900', '4020', 'ANA LEOANA LEO', 'GUDANG RANDOM', 'Titipan', '2026-05-02 09:16:00+07', 'Admin', '2026-05-02 09:16:00+07', 'Admin', 'GK-4020-B6E00D', 'GK-KARDUS-000302'),
  (303, '303', '8800-1861-Neng Kanan T. Putri Ayu', '8800', '1861', 'Neng Kanan T. Putri Ayu', 'GUDANG NENG', 'Titipan', '2026-05-02 09:17:00+07', 'Admin', '2026-05-02 09:17:00+07', 'Admin', 'GK-1861-19F8F1', 'GK-KARDUS-000303'),
  (304, '304', '0300-1871-Neng Kanan T. Putri Ayu', '0300', '1871', 'Neng Kanan T. Putri Ayu', 'GUDANG NENG', 'Titipan', '2026-05-02 09:19:00+07', 'Admin', '2026-05-02 09:19:00+07', 'Admin', 'GK-1871-19F8F1', 'GK-KARDUS-000304'),
  (305, '305', '5800-3826-SUKAEMI T MAWARNI', '5800', '3826', 'SUKAEMI T MAWARNI', 'GUDANG MAWARNI', 'Titipan', '2026-05-02 09:20:00+07', 'Admin', '2026-05-02 09:20:00+07', 'Admin', 'GK-3826-263FF1', 'GK-KARDUS-000305'),
  (306, '306', '0300-1871-Neng Karan T. cici Sriyana', '0300', '1871', 'Neng Karan T. cici Sriyana', 'GUDANG NENG', 'Titipan', '2026-05-02 09:21:00+07', 'Admin', '2026-05-02 09:21:00+07', 'Admin', 'GK-1871-56EE5F', 'GK-KARDUS-000306'),
  (307, '307', '3700-2065-NENG KANAN T PAPUA DANIAH JASMANIAH', '3700', '2065', 'NENG KANAN T PAPUA DANIAH JASMANIAH', 'GUDANG NENG', 'Titipan', '2026-05-02 09:23:00+07', 'Admin', '2026-05-02 09:23:00+07', 'Admin', 'GK-2065-A7A53C', 'GK-KARDUS-000307'),
  (308, '308', '3000-2640-Nerg kanan T. Bashir', '3000', '2640', 'Nerg kanan T. Bashir', 'GUDANG NENG', 'Titipan', '2026-05-02 09:26:00+07', 'Admin', '2026-05-02 09:26:00+07', 'Admin', 'GK-2640-7A0853', 'GK-KARDUS-000308'),
  (309, '309', '1700-8465-Yunus Anita', '1700', '8465', 'Yunus Anita', 'GUDANG ANITA', 'Titipan', '2026-05-02 09:28:00+07', 'Admin', '2026-05-02 09:28:00+07', 'Admin', 'GK-8465-33439B', 'GK-KARDUS-000309'),
  (310, '310', '4900-8433-Ayunda Anita Axunda', '4900', '8433', 'Ayunda Anita Axunda', 'GUDANG ANITA', 'Titipan', '2026-05-02 09:29:00+07', 'Admin', '2026-05-02 09:29:00+07', 'Admin', 'GK-8433-98456D', 'GK-KARDUS-000310'),
  (311, '311', '1300-9288-Raka Anita raka Wijaya', '1300', '9288', 'Raka Anita raka Wijaya', 'GUDANG ANITA', 'Titipan', '2026-05-02 09:31:00+07', 'Admin', '2026-05-02 09:31:00+07', 'Admin', 'GK-9288-95B698', 'GK-KARDUS-000311'),
  (312, '312', '2300-3931-SEAN MURPHY MOEIS T ERLIN KANAN SEAN', '2300', '3931', 'SEAN MURPHY MOEIS T ERLIN KANAN SEAN', 'GUDANG RANDOM', 'Titipan', '2026-05-02 09:31:00+07', 'Admin', '2026-05-02 09:31:00+07', 'Admin', 'GK-3931-8539CC', 'GK-KARDUS-000312'),
  (313, '313', '5900-9945-tjong li mi eko Prasetiyo', '5900', '9945', 'tjong li mi eko Prasetiyo', 'GUDANG AMI', 'Milik Sendiri', '2026-05-02 09:32:00+07', 'Admin', '2026-05-02 09:32:00+07', 'Admin', 'GK-9945-85E489', 'GK-KARDUS-000313'),
  (314, '314', '1900-3848-DJOHAN SM T BOENDJHOHAN', '1900', '3848', 'DJOHAN SM T BOENDJHOHAN', 'GUDANG RANDOM', 'Titipan', '2026-05-02 09:34:00+07', 'Admin', '2026-05-02 09:34:00+07', 'Admin', 'GK-3848-7103F1', 'GK-KARDUS-000314'),
  (315, '315', '6900-8519-Tri Anitatri Wahyudi', '6900', '8519', 'Tri Anitatri Wahyudi', 'GUDANG ANITA', 'Titipan', '2026-05-02 09:35:00+07', 'Admin', '2026-05-02 09:35:00+07', 'Admin', 'GK-8519-232B74', 'GK-KARDUS-000315'),
  (316, '316', '7300-9901-Tiong li mi Suriyati', '7300', '9901', 'Tiong li mi Suriyati', 'GUDANG AMI', 'Milik Sendiri', '2026-05-02 09:36:00+07', 'Admin', '2026-05-02 09:36:00+07', 'Admin', 'GK-9901-3178D8', 'GK-KARDUS-000316'),
  (317, '317', '4500-2801-NENG KANAN T PAPUA HOTMARIA SINAGA', '4500', '2801', 'NENG KANAN T PAPUA HOTMARIA SINAGA', 'GUDANG NENG', 'Titipan', '2026-05-02 09:36:00+07', 'Admin', '2026-05-02 09:36:00+07', 'Admin', 'GK-2801-F68631', 'GK-KARDUS-000317'),
  (318, '318', '2500-4101-AMI DELILA BR HARIANJA', '2500', '4101', 'AMI DELILA BR HARIANJA', 'GUDANG AMI', 'Titipan', '2026-05-02 09:40:00+07', 'Admin', '2026-05-02 09:40:00+07', 'Admin', 'GK-4101-79BFD2', 'GK-KARDUS-000318'),
  (319, '319', '5000-1526-NENG KANAN T PAPUA DANIAH JASMANIAH', '5000', '1526', 'NENG KANAN T PAPUA DANIAH JASMANIAH', 'GUDANG NENG', 'Titipan', '2026-05-02 09:41:00+07', 'Admin', '2026-05-02 09:41:00+07', 'Admin', 'GK-1526-A7A53C', 'GK-KARDUS-000319'),
  (320, '320', '1600-4101-GO SU CHEN GO SU CHEN', '1600', '4101', 'GO SU CHEN GO SU CHEN', 'KANTOR', 'Titipan', '2026-05-02 09:41:00+07', 'Admin', '2026-05-02 09:41:00+07', 'Admin', 'GK-4101-A15E64', 'GK-KARDUS-000320'),
  (321, '321', '5000-4101-AMI T CHARLES KANAN YOHANA AFRA BABO RAKI', '5000', '4101', 'AMI T CHARLES KANAN YOHANA AFRA BABO RAKI', 'KANTOR', 'Titipan', '2026-05-02 09:43:00+07', 'Admin', '2026-05-02 09:43:00+07', 'Admin', 'GK-4101-005B16', 'GK-KARDUS-000321'),
  (322, '322', '5600-1157-NENG KANAN T PAPUA RUSMINI', '5600', '1157', 'NENG KANAN T PAPUA RUSMINI', 'GUDANG NENG', 'Titipan', '2026-05-02 09:45:00+07', 'Admin', '2026-05-02 09:45:00+07', 'Admin', 'GK-1157-0CE773', 'GK-KARDUS-000322'),
  (323, '323', '9600-4101-ANITA BINTANG HINTA SINTA SUSILAWATI', '9600', '4101', 'ANITA BINTANG HINTA SINTA SUSILAWATI', 'KANTOR', 'Titipan', '2026-05-02 09:46:00+07', 'Admin', '2026-05-02 09:46:00+07', 'Admin', 'GK-4101-25BC25', 'GK-KARDUS-000323'),
  (324, '324', '7100-6502-ANISAHARI SUSANTO', '7100', '6502', 'ANISAHARI SUSANTO', 'GUDANG RANDOM', 'Titipan', '2026-05-02 09:47:00+07', 'Admin', '2026-05-02 09:47:00+07', 'Admin', 'GK-6502-5E01C4', 'GK-KARDUS-000324'),
  (325, '325', '3700-1703-NENG KANAN T PAPUA CICI SRIYANA', '3700', '1703', 'NENG KANAN T PAPUA CICI SRIYANA', 'GUDANG NENG', 'Titipan', '2026-05-02 09:49:00+07', 'Admin', '2026-05-02 09:49:00+07', 'Admin', 'GK-1703-F88A6D', 'GK-KARDUS-000325'),
  (326, '326', '9600-4102-MIA AUDINA NAJ MIA', '9600', '4102', 'MIA AUDINA NAJ MIA', 'KANTOR', 'Titipan', '2026-05-02 09:50:00+07', 'Admin', '2026-05-02 09:50:00+07', 'Admin', 'GK-4102-529E9A', 'GK-KARDUS-000326'),
  (327, '327', '0000-4101-MAGDALENA TEAM ANISA EASTER YULI WESTERN YULI', '0000', '4101', 'MAGDALENA TEAM ANISA EASTER YULI WESTERN YULI', 'GUDANG ANISA', 'Titipan', '2026-05-02 09:53:00+07', 'Admin', '2026-05-02 09:53:00+07', 'Admin', 'GK-4101-48005C', 'GK-KARDUS-000327'),
  (328, '328', '8200-3979-SOFIA DM T EDY SOFIA HUSNA', '8200', '3979', 'SOFIA DM T EDY SOFIA HUSNA', 'GUDANG RANDOM', 'Titipan', '2026-05-02 09:59:00+07', 'Admin', '2026-05-02 09:59:00+07', 'Admin', 'GK-3979-794971', 'GK-KARDUS-000328'),
  (329, '329', '9500-4069-AMI HIKMAH SYAIFULLOH', '9500', '4069', 'AMI HIKMAH SYAIFULLOH', 'KANTOR', 'Milik Sendiri', '2026-05-02 09:59:00+07', 'Admin', '2026-05-02 09:59:00+07', 'Admin', 'GK-4069-291A22', 'GK-KARDUS-000329'),
  (330, '330', '3300-7532-NENG KANAN T PAPUA GARET PUTRA', '3300', '7532', 'NENG KANAN T PAPUA GARET PUTRA', 'GUDANG NENG', 'Titipan', '2026-05-02 10:01:00+07', 'Admin', '2026-05-02 10:01:00+07', 'Admin', 'GK-7532-6F088F', 'GK-KARDUS-000330'),
  (331, '331', '1900-4069-ANITA BINTANG NGATIYONONGATIY ONO', '1900', '4069', 'ANITA BINTANG NGATIYONONGATIY ONO', 'KANTOR', 'Titipan', '2026-05-02 10:01:00+07', 'Admin', '2026-05-02 10:01:00+07', 'Admin', 'GK-4069-3FB4BD', 'GK-KARDUS-000331'),
  (332, '332', '3600-4069-ESRA TEAM RINA ESRA RENDEN', '3600', '4069', 'ESRA TEAM RINA ESRA RENDEN', 'KANTOR', 'Titipan', '2026-05-02 10:02:00+07', 'Admin', '2026-05-02 10:02:00+07', 'Admin', 'GK-4069-D3A1E9', 'GK-KARDUS-000332'),
  (333, '333', '9900-4069-AMI ANDREAS PAIAN', '9900', '4069', 'AMI ANDREAS PAIAN', 'KANTOR', 'Milik Sendiri', '2026-05-02 10:02:00+07', 'Admin', '2026-05-02 10:02:00+07', 'Admin', 'GK-4069-09BDD2', 'GK-KARDUS-000333'),
  (334, '334', '4300-2742-SISKA YUNI T WIFA SISKA YUNI', '4300', '2742', 'SISKA YUNI T WIFA SISKA YUNI', 'GUDANG RANDOM', 'Titipan', '2026-05-02 10:03:00+07', 'Admin', '2026-05-02 10:03:00+07', 'Admin', 'GK-2742-76A481', 'GK-KARDUS-000334'),
  (335, '335', '2600-4114-AMI T ANDREW KUSASHI SMANDREW KUSASHI', '2600', '4114', 'AMI T ANDREW KUSASHI SMANDREW KUSASHI', 'KANTOR', 'Titipan', '2026-05-02 10:12:00+07', 'Admin', '2026-05-02 10:12:00+07', 'Admin', 'GK-4114-41C21B', 'GK-KARDUS-000335'),
  (336, '336', '1000-4168-MIA AUDINA NURSAIDAH', '1000', '4168', 'MIA AUDINA NURSAIDAH', 'KANTOR', 'Titipan', '2026-05-02 10:18:00+07', 'Admin', '2026-05-02 10:18:00+07', 'Admin', 'GK-4168-C5FF43', 'GK-KARDUS-000336'),
  (337, '337', '2200-4168-AMI AGNES JESSICA', '2200', '4168', 'AMI AGNES JESSICA', 'KANTOR', 'Titipan', '2026-05-02 10:18:00+07', 'Admin', '2026-05-02 10:18:00+07', 'Admin', 'GK-4168-0D4FC7', 'GK-KARDUS-000337'),
  (338, '338', '9600-4168-AMI ANDREW KUSASHI', '9600', '4168', 'AMI ANDREW KUSASHI', 'KANTOR', 'Titipan', '2026-05-02 10:19:00+07', 'Admin', '2026-05-02 10:19:00+07', 'Admin', 'GK-4168-36A0F1', 'GK-KARDUS-000338'),
  (339, '339', '6600-4154-ANITA BINTANG FELIXFELIX', '6600', '4154', 'ANITA BINTANG FELIXFELIX', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:26:00+07', 'Admin', '2026-05-02 10:26:00+07', 'Admin', 'GK-4154-29D7B1', 'GK-KARDUS-000339'),
  (340, '340', '0600-5041-TJONG LI MI EDI SULAEMAN', '0600', '5041', 'TJONG LI MI EDI SULAEMAN', 'GUDANG AMI', 'Milik Sendiri', '2026-05-02 10:27:00+07', 'Admin', '2026-05-02 10:27:00+07', 'Admin', 'GK-5041-58E566', 'GK-KARDUS-000340'),
  (341, '341', '5600-4154-ANITA BINTANG TASMI TASMI', '5600', '4154', 'ANITA BINTANG TASMI TASMI', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:27:00+07', 'Admin', '2026-05-02 10:27:00+07', 'Admin', 'GK-4154-FD824C', 'GK-KARDUS-000341'),
  (342, '342', '7700-3564-AMI JANUAR HENDRATAMA', '7700', '3564', 'AMI JANUAR HENDRATAMA', 'GUDANG AMI', 'Titipan', '2026-05-02 10:28:00+07', 'OWEN', '2026-05-02 10:28:00+07', 'OWEN', 'GK-3564-40191E', 'GK-KARDUS-000342'),
  (343, '343', '5800-3564-ANITA BINTANG DINDA DINDA', '5800', '3564', 'ANITA BINTANG DINDA DINDA', 'GUDANG AMI', 'Titipan', '2026-05-02 10:29:00+07', 'OWEN', '2026-05-02 10:29:00+07', 'OWEN', 'GK-3564-1BFA1B', 'GK-KARDUS-000343'),
  (344, '344', '2200-0275-ANITA BINTANG AULIA AULIA', '2200', '0275', 'ANITA BINTANG AULIA AULIA', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:29:00+07', 'Admin', '2026-05-02 10:29:00+07', 'Admin', 'GK-0275-D2D592', 'GK-KARDUS-000344'),
  (345, '345', '2200-0275-ANITA BINTANG GADING GADING MARTHIN', '2200', '0275', 'ANITA BINTANG GADING GADING MARTHIN', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:31:00+07', 'Oktavia', '2026-05-02 10:31:00+07', 'Oktavia', 'GK-0275-B284A3', 'GK-KARDUS-000345'),
  (346, '346', '3000-0275-ANITA BINTANG DIMAS DIMAS', '3000', '0275', 'ANITA BINTANG DIMAS DIMAS', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:32:00+07', 'Oktavia', '2026-05-02 10:32:00+07', 'Oktavia', 'GK-0275-94090E', 'GK-KARDUS-000346'),
  (347, '347', '7000-3496-ANITA BINTANG LUSI LUSIO NANTIKA', '7000', '3496', 'ANITA BINTANG LUSI LUSIO NANTIKA', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:33:00+07', 'Admin', '2026-05-02 10:33:00+07', 'Admin', 'GK-3496-EE2777', 'GK-KARDUS-000347'),
  (348, '348', '4000-3496-ANITA BINTANG RIAN FIRMANSYAH RIAN FFIRMANSYAH', '4000', '3496', 'ANITA BINTANG RIAN FIRMANSYAH RIAN FFIRMANSYAH', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:34:00+07', 'Admin', '2026-05-02 10:34:00+07', 'Admin', 'GK-3496-470D9B', 'GK-KARDUS-000348'),
  (349, '349', '9400-3496-ANITA BINTANG ARDIANSYAHARDIANSYAH PUTRA', '9400', '3496', 'ANITA BINTANG ARDIANSYAHARDIANSYAH PUTRA', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:35:00+07', 'Admin', '2026-05-02 10:35:00+07', 'Admin', 'GK-3496-B25FCD', 'GK-KARDUS-000349'),
  (350, '350', '4000-0635-neng kanan t papua asum sumiati', '4000', '0635', 'neng kanan t papua asum sumiati', 'GUDANG NENG', 'Titipan', '2026-05-02 10:35:00+07', 'Admin', '2026-05-02 10:35:00+07', 'Admin', 'GK-0635-31FCC1', 'GK-KARDUS-000350'),
  (351, '351', '8400-3496-ANITA BINTANG WENDAH ALISIA WENDAH', '8400', '3496', 'ANITA BINTANG WENDAH ALISIA WENDAH', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:36:00+07', 'Admin', '2026-05-02 10:36:00+07', 'Admin', 'GK-3496-362AD0', 'GK-KARDUS-000351'),
  (352, '352', '1000-3496-ANITA BINTANG WENDI SALIM WENDI SALIN', '1000', '3496', 'ANITA BINTANG WENDI SALIM WENDI SALIN', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:37:00+07', 'Admin', '2026-05-02 10:37:00+07', 'Admin', 'GK-3496-830929', 'GK-KARDUS-000352'),
  (353, '353', '1600-2791-jumriyeh anita jumriyeh', '1600', '2791', 'jumriyeh anita jumriyeh', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:37:00+07', 'Admin', '2026-05-02 10:37:00+07', 'Admin', 'GK-2791-8B7DA3', 'GK-KARDUS-000353'),
  (354, '354', '1400-6114-ANITA BINTANG SITI AULIA SITI AULIA', '1400', '6114', 'ANITA BINTANG SITI AULIA SITI AULIA', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:38:00+07', 'Admin', '2026-05-02 10:38:00+07', 'Admin', 'GK-6114-970BA2', 'GK-KARDUS-000354'),
  (355, '355', '2700-6114-ANITA BINTANG HAFSA NABILA HAFSA', '2700', '6114', 'ANITA BINTANG HAFSA NABILA HAFSA', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:39:00+07', 'Admin', '2026-05-02 10:39:00+07', 'Admin', 'GK-6114-F34CBD', 'GK-KARDUS-000355'),
  (356, '356', '0600-6114-AMI AMALIA SAFIRA', '0600', '6114', 'AMI AMALIA SAFIRA', 'GUDANG AMI', 'Titipan', '2026-05-02 10:39:00+07', 'Admin', '2026-05-02 10:39:00+07', 'Admin', 'GK-6114-D9AC31', 'GK-KARDUS-000356'),
  (357, '357', '6500-4124-ANITA BINTANG KENNY KENNY NG', '6500', '4124', 'ANITA BINTANG KENNY KENNY NG', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:42:00+07', 'Admin', '2026-05-02 10:42:00+07', 'Admin', 'GK-4124-46B257', 'GK-KARDUS-000357'),
  (358, '358', '0100-6097-ANITA BINTANG SARISARI', '0100', '6097', 'ANITA BINTANG SARISARI', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:43:00+07', 'Admin', '2026-05-02 10:43:00+07', 'Admin', 'GK-6097-6D273F', 'GK-KARDUS-000358'),
  (359, '359', '9800-6097-ANITA BINTANG PIN BOENTARAN PIN BOENTARAN', '9800', '6097', 'ANITA BINTANG PIN BOENTARAN PIN BOENTARAN', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:44:00+07', 'Admin', '2026-05-02 10:44:00+07', 'Admin', 'GK-6097-ECC3EC', 'GK-KARDUS-000359'),
  (360, '360', '6100-6097-ANITA BINTANG SITI NURHALIZA SITI NURHALIZA', '6100', '6097', 'ANITA BINTANG SITI NURHALIZA SITI NURHALIZA', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:45:00+07', 'Admin', '2026-05-02 10:45:00+07', 'Admin', 'GK-6097-BE09CE', 'GK-KARDUS-000360'),
  (361, '361', '8500-6097-ANITA BINTANG ANDREAS ANDREAS', '8500', '6097', 'ANITA BINTANG ANDREAS ANDREAS', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:45:00+07', 'Admin', '2026-05-02 10:45:00+07', 'Admin', 'GK-6097-0C39EA', 'GK-KARDUS-000361'),
  (362, '362', '1900-6097-ANITA BINTANG IDAH IDAH', '1900', '6097', 'ANITA BINTANG IDAH IDAH', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:46:00+07', 'Admin', '2026-05-02 10:46:00+07', 'Admin', 'GK-6097-2915B7', 'GK-KARDUS-000362'),
  (363, '363', '7800-6097-ANITA BINTANG VENDA HALIN VENDA HALIN', '7800', '6097', 'ANITA BINTANG VENDA HALIN VENDA HALIN', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:47:00+07', 'Admin', '2026-05-02 10:47:00+07', 'Admin', 'GK-6097-C9998E', 'GK-KARDUS-000363'),
  (364, '364', '5400-3540-anita bintang agnesagnes kewa padak', '5400', '3540', 'anita bintang agnesagnes kewa padak', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:47:00+07', 'Admin', '2026-05-02 10:47:00+07', 'Admin', 'GK-3540-DC6CF5', 'GK-KARDUS-000364'),
  (365, '365', '0500-0106-NENG KANAN T PAPUA LIVINA AYU', '0500', '0106', 'NENG KANAN T PAPUA LIVINA AYU', 'GUDANG NENG', 'Titipan', '2026-05-02 10:47:00+07', 'Admin', '2026-05-02 10:47:00+07', 'Admin', 'GK-0106-00131C', 'GK-KARDUS-000365'),
  (366, '366', '7800-6022-anita bintang dwi medlin dwi medlins', '7800', '6022', 'anita bintang dwi medlin dwi medlins', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:48:00+07', 'Admin', '2026-05-02 10:48:00+07', 'Admin', 'GK-6022-53C04A', 'GK-KARDUS-000366'),
  (367, '367', '1000-3562-anita bintang vincenciavinsensius neon basu', '1000', '3562', 'anita bintang vincenciavinsensius neon basu', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:49:00+07', 'Admin', '2026-05-02 10:49:00+07', 'Admin', 'GK-3562-283056', 'GK-KARDUS-000367'),
  (368, '368', '7800-3531-ANITA BINTANG JANUAR NEPA AMTIRAN JANUAR', '7800', '3531', 'ANITA BINTANG JANUAR NEPA AMTIRAN JANUAR', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:51:00+07', 'Admin', '2026-05-02 10:51:00+07', 'Admin', 'GK-3531-3E5BFF', 'GK-KARDUS-000368'),
  (369, '369', '5600-6474-sumanto anita sumanto halim', '5600', '6474', 'sumanto anita sumanto halim', 'LOKASI ANITA', 'Titipan', '2026-05-02 10:51:00+07', 'Admin', '2026-05-02 10:51:00+07', 'Admin', 'GK-6474-DCCEFB', 'GK-KARDUS-000369'),
  (370, '370', '8300-6036-ANITA BINTANG SOFIA HUSNA SHOFIA', '8300', '6036', 'ANITA BINTANG SOFIA HUSNA SHOFIA', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:52:00+07', 'Admin', '2026-05-02 10:52:00+07', 'Admin', 'GK-6036-436939', 'GK-KARDUS-000370'),
  (371, '371', '9200-6036-ANITA BINTANG ZAKI MUBARAK ZAKI MUBARAK', '9200', '6036', 'ANITA BINTANG ZAKI MUBARAK ZAKI MUBARAK', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:53:00+07', 'Admin', '2026-05-02 10:53:00+07', 'Admin', 'GK-6036-D0F7F8', 'GK-KARDUS-000371'),
  (372, '372', '6100-6065-ANITA BINTANG ALFAHRIALFAHRI', '6100', '6065', 'ANITA BINTANG ALFAHRIALFAHRI', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:55:00+07', 'Admin', '2026-05-02 10:55:00+07', 'Admin', 'GK-6065-7F213D', 'GK-KARDUS-000372'),
  (373, '373', '1900-6065-ANITA BINTANG RAIHAN NUGRAHARAIHAN', '1900', '6065', 'ANITA BINTANG RAIHAN NUGRAHARAIHAN', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:55:00+07', 'Admin', '2026-05-02 10:55:00+07', 'Admin', 'GK-6065-0DA3F7', 'GK-KARDUS-000373'),
  (374, '374', '8600-6065-ANITA BINTANG NADIA NADIA', '8600', '6065', 'ANITA BINTANG NADIA NADIA', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:56:00+07', 'Admin', '2026-05-02 10:56:00+07', 'Admin', 'GK-6065-E5C412', 'GK-KARDUS-000374'),
  (375, '375', '1600-6542-GADING ANITA GADING MARTHIN', '1600', '6542', 'GADING ANITA GADING MARTHIN', 'GUDANG ANITA', 'Titipan', '2026-05-02 10:57:00+07', 'Admin', '2026-05-02 10:57:00+07', 'Admin', 'GK-6542-3A9D84', 'GK-KARDUS-000375'),
  (376, '376', '2900-6837-DETRONI ANITA DETRONI WARUWU', '2900', '6837', 'DETRONI ANITA DETRONI WARUWU', 'GUDANG ANITA', 'Titipan', '2026-05-02 11:02:00+07', 'Admin', '2026-05-02 11:02:00+07', 'Admin', 'GK-6837-749A34', 'GK-KARDUS-000376'),
  (377, '377', '6500-6047-anita bintang dedi mulyanto dedi mulyanto', '6500', '6047', 'anita bintang dedi mulyanto dedi mulyanto', 'GUDANG ANITA', 'Titipan', '2026-05-02 11:03:00+07', 'Admin', '2026-05-02 11:03:00+07', 'Admin', 'GK-6047-1554D7', 'GK-KARDUS-000377'),
  (378, '378', '2800-0219-NENG KANAN T PAPUA IHAT SOLIHAT', '2800', '0219', 'NENG KANAN T PAPUA IHAT SOLIHAT', 'GUDANG NENG', 'Titipan', '2026-05-04 07:08:00+07', 'Admin', '2026-05-04 07:08:00+07', 'Admin', 'GK-0219-C1432F', 'GK-KARDUS-000378'),
  (379, '379', '1300-2058-AMI T NICOLAUS SM SURAMEN NICOLAUS NIA', '1300', '2058', 'AMI T NICOLAUS SM SURAMEN NICOLAUS NIA', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 07:13:00+07', 'Admin', '2026-05-04 07:13:00+07', 'Admin', 'GK-2058-896FB0', 'GK-KARDUS-000379'),
  (380, '380', '9100-3962-Ahmad Fauzan T bendhar dahmad Fauzan', '9100', '3962', 'Ahmad Fauzan T bendhar dahmad Fauzan', 'GUDANG BENDHAR', 'Titipan', '2026-05-04 07:18:00+07', 'Admin', '2026-05-04 07:18:00+07', 'Admin', 'GK-3962-57D652', 'GK-KARDUS-000380'),
  (381, '381', '8900-8923-Hafiz Anita', '8900', '8923', 'Hafiz Anita', 'GUDANG ANITA', 'Titipan', '2026-05-04 07:20:00+07', 'Admin', '2026-05-04 07:20:00+07', 'Admin', 'GK-8923-D6E556', 'GK-KARDUS-000381'),
  (382, '382', '2400-1756-DEWINTA SARI WIFA DEWINTA SARI', '2400', '1756', 'DEWINTA SARI WIFA DEWINTA SARI', 'GUDANG WIFA', 'Titipan', '2026-05-04 07:21:00+07', 'Oktavia', '2026-05-04 07:21:00+07', 'Oktavia', 'GK-1756-230DC3', 'GK-KARDUS-000382'),
  (383, '383', '9300-4045-Diyan T bend kiri diyan', '9300', '4045', 'Diyan T bend kiri diyan', 'GUDANG BEND', 'Titipan', '2026-05-04 07:24:00+07', 'Admin', '2026-05-04 07:24:00+07', 'Admin', 'GK-4045-546BAD', 'GK-KARDUS-000383'),
  (384, '384', '1800-1696-NENG KANAN T PAPUA KAYLA PUTRI', '1800', '1696', 'NENG KANAN T PAPUA KAYLA PUTRI', 'GUDANG NENG', 'Titipan', '2026-05-04 07:24:00+07', 'Oktavia', '2026-05-04 07:24:00+07', 'Oktavia', 'GK-1696-3AF253', 'GK-KARDUS-000384'),
  (385, '385', '2700-3932-ANISA RAHMAWATI T ERLIN KANAN ANISA RAHMAWATI', '2700', '3932', 'ANISA RAHMAWATI T ERLIN KANAN ANISA RAHMAWATI', 'GUDANG RANDOM', 'Titipan', '2026-05-04 07:29:00+07', 'Oktavia', '2026-05-04 07:29:00+07', 'Oktavia', 'GK-3932-94681B', 'GK-KARDUS-000385'),
  (386, '386', '9400-9681-Neng Kanan T Papua Puspita Lasm', '9400', '9681', 'Neng Kanan T Papua Puspita Lasm', 'GUDANG NENG', 'Titipan', '2026-05-04 07:29:00+07', 'Admin', '2026-05-04 07:29:00+07', 'Admin', 'GK-9681-D7B336', 'GK-KARDUS-000386'),
  (387, '387', '6300-2563-DEVIN MULYONO T TOMY KANAN DEVIN MULYONO', '6300', '2563', 'DEVIN MULYONO T TOMY KANAN DEVIN MULYONO', 'GUDANG RANDOM', 'Titipan', '2026-05-04 07:30:00+07', 'Oktavia', '2026-05-04 07:30:00+07', 'Oktavia', 'GK-2563-5E121E', 'GK-KARDUS-000387'),
  (388, '388', '8400-0272-Sambaru Team Rina', '8400', '0272', 'Sambaru Team Rina', 'GUDANG RINA', 'Titipan', '2026-05-04 07:31:00+07', 'Admin', '2026-05-04 07:31:00+07', 'Admin', 'GK-0272-492097', 'GK-KARDUS-000388'),
  (389, '389', '0200-0737-Neng Kanan T. Nabila', '0200', '0737', 'Neng Kanan T. Nabila', 'GUDANG NENG', 'Titipan', '2026-05-04 07:33:00+07', 'Admin', '2026-05-04 07:33:00+07', 'Admin', 'GK-0737-4544B6', 'GK-KARDUS-000389'),
  (390, '390', '1200-0325-ANITA BINTANG DONIDONI', '1200', '0325', 'ANITA BINTANG DONIDONI', 'GUDANG ANITA', 'Titipan', '2026-05-04 07:34:00+07', 'Admin', '2026-05-04 07:34:00+07', 'Admin', 'GK-0325-E7B8E4', 'GK-KARDUS-000390'),
  (391, '391', '1200-0325-ANITA BINTANG DONIDONI', '1200', '0325', 'ANITA BINTANG DONIDONI', 'GUDANG ANITA', 'Titipan', '2026-05-04 07:34:00+07', 'Admin', '2026-05-04 07:34:00+07', 'Admin', 'GK-0325-E7B8E4', 'GK-KARDUS-000391'),
  (392, '392', '0700-0760-NENG KANAN T PAPUA ILHAM PURNAMA', '0700', '0760', 'NENG KANAN T PAPUA ILHAM PURNAMA', 'GUDANG NENG', 'Titipan', '2026-05-04 07:35:00+07', 'Oktavia', '2026-05-04 07:35:00+07', 'Oktavia', 'GK-0760-8010E5', 'GK-KARDUS-000392'),
  (393, '393', '6700-2607-NENG KANAN T PAPUA PUSPITA LASMI', '6700', '2607', 'NENG KANAN T PAPUA PUSPITA LASMI', 'GUDANG NENG', 'Titipan', '2026-05-04 07:38:00+07', 'Admin', '2026-05-04 07:38:00+07', 'Admin', 'GK-2607-2446E5', 'GK-KARDUS-000393'),
  (394, '394', '5900-7585-TJONG LI MI', '5900', '7585', 'TJONG LI MI', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 07:38:00+07', 'Admin', '2026-05-04 07:38:00+07', 'Admin', 'GK-7585-0C47F4', 'GK-KARDUS-000394'),
  (395, '395', '4400-2188-Rika Nahami T. Wifa Rica', '4400', '2188', 'Rika Nahami T. Wifa Rica', 'GUDANG WIFA', 'Titipan', '2026-05-04 07:38:00+07', 'Admin', '2026-05-04 07:38:00+07', 'Admin', 'GK-2188-B8F629', 'GK-KARDUS-000395'),
  (396, '396', '7400-1397-AKBAR ANITA AKBAR', '7400', '1397', 'AKBAR ANITA AKBAR', 'GUDANG ANITA', 'Titipan', '2026-05-04 07:43:00+07', 'Oktavia', '2026-05-04 07:43:00+07', 'Oktavia', 'GK-1397-9EB307', 'GK-KARDUS-000396'),
  (397, '397', '0500-7552-NENG KANAN T PAPUA LIVINA AYU', '0500', '7552', 'NENG KANAN T PAPUA LIVINA AYU', 'GUDANG NENG', 'Titipan', '2026-05-04 07:44:00+07', 'Admin', '2026-05-04 07:44:00+07', 'Admin', 'GK-7552-00131C', 'GK-KARDUS-000397'),
  (398, '398', '9200-9713-NENG KANAN T PAPUA NURLIDA', '9200', '9713', 'NENG KANAN T PAPUA NURLIDA', 'GUDANG NENG', 'Titipan', '2026-05-04 07:45:00+07', 'Oktavia', '2026-05-04 07:45:00+07', 'Oktavia', 'GK-9713-F288F2', 'GK-KARDUS-000398'),
  (399, '399', '4900-1461-AMI T WIFA ASEP', '4900', '1461', 'AMI T WIFA ASEP', 'GUDANG AMI', 'Titipan', '2026-05-04 07:47:00+07', 'Admin', '2026-05-04 07:47:00+07', 'Admin', 'GK-1461-CA40B4', 'GK-KARDUS-000399'),
  (400, '400', '9100-7598-TJong li mi Agus Septian', '9100', '7598', 'TJong li mi Agus Septian', 'GUDANG AMI', 'Titipan', '2026-05-04 07:49:00+07', 'Admin', '2026-05-04 07:49:00+07', 'Admin', 'GK-7598-91FA6B', 'GK-KARDUS-000400'),
  (401, '401', '2700-0729-NENG KANAN T PAPUA ANISA NURAWWALIYAH', '2700', '0729', 'NENG KANAN T PAPUA ANISA NURAWWALIYAH', 'GUDANG NENG', 'Titipan', '2026-05-04 07:53:00+07', 'Admin', '2026-05-04 07:53:00+07', 'Admin', 'GK-0729-FA6F1F', 'GK-KARDUS-000401'),
  (402, '402', '8300-0688-Neng karan T. Nunu Nuhdin', '8300', '0688', 'Neng karan T. Nunu Nuhdin', 'GUDANG NENG', 'Titipan', '2026-05-04 07:54:00+07', 'Admin', '2026-05-04 07:54:00+07', 'Admin', 'GK-0688-EFA402', 'GK-KARDUS-000402'),
  (403, '403', '5800-0249-KEVIN T TOMY KANAN KEVIN', '5800', '0249', 'KEVIN T TOMY KANAN KEVIN', 'GUDANG RANDOM', 'Titipan', '2026-05-04 07:57:00+07', 'Oktavia', '2026-05-04 07:57:00+07', 'Oktavia', 'GK-0249-43D2B5', 'GK-KARDUS-000403'),
  (404, '404', '6600-4170-AMI JONATHAN KENZIRO SUWITO', '6600', '4170', 'AMI JONATHAN KENZIRO SUWITO', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 07:59:00+07', 'Admin', '2026-05-04 07:59:00+07', 'Admin', 'GK-4170-012C23', 'GK-KARDUS-000404'),
  (405, '405', '3400-3948-winda T mawarni winda', '3400', '3948', 'winda T mawarni winda', 'GUDANG MAWARNI', 'Titipan', '2026-05-04 08:04:00+07', 'Admin', '2026-05-04 08:04:00+07', 'Admin', 'GK-3948-2FD0FE', 'GK-KARDUS-000405'),
  (406, '406', '7200-1353-SANDRI ANITA SANDRIYANO KORNAMNE PAYARA', '7200', '1353', 'SANDRI ANITA SANDRIYANO KORNAMNE PAYARA', 'GUDANG RANDOM', 'Titipan', '2026-05-04 08:04:00+07', 'Admin', '2026-05-04 08:04:00+07', 'Admin', 'GK-1353-ECF5CE', 'GK-KARDUS-000406'),
  (407, '407', '5900-3984-Efendi kornamne T boen kanan efendi', '5900', '3984', 'Efendi kornamne T boen kanan efendi', 'GUDANG BOEN', 'Titipan', '2026-05-04 08:06:00+07', 'Admin', '2026-05-04 08:06:00+07', 'Admin', 'GK-3984-B1FB7A', 'GK-KARDUS-000407'),
  (408, '408', '7000-8262-NURUL HUDA ID T MAWARNI NURUL HUDA', '7000', '8262', 'NURUL HUDA ID T MAWARNI NURUL HUDA', 'GUDANG MAWARNI', 'Titipan', '2026-05-04 08:07:00+07', 'Admin', '2026-05-04 08:07:00+07', 'Admin', 'GK-8262-6E648C', 'GK-KARDUS-000408'),
  (409, '409', '7000-1140-NENG KANAN T PAPUA UNDANG SUKARSA', '7000', '1140', 'NENG KANAN T PAPUA UNDANG SUKARSA', 'GUDANG NENG', 'Titipan', '2026-05-04 08:07:00+07', 'Admin', '2026-05-04 08:07:00+07', 'Admin', 'GK-1140-BC5634', 'GK-KARDUS-000409'),
  (410, '410', '7900-9962-Meti Anita Meti Delsi', '7900', '9962', 'Meti Anita Meti Delsi', 'GUDANG ANITA', 'Titipan', '2026-05-04 08:09:00+07', 'Admin', '2026-05-04 08:09:00+07', 'Admin', 'GK-9962-F9584E', 'GK-KARDUS-000410'),
  (411, '411', '5200-9922-NENG KANAN T PAPUA IHSAN IFTIKAR', '5200', '9922', 'NENG KANAN T PAPUA IHSAN IFTIKAR', 'GUDANG NENG', 'Titipan', '2026-05-04 08:10:00+07', 'Admin', '2026-05-04 08:10:00+07', 'Admin', 'GK-9922-910D6C', 'GK-KARDUS-000411'),
  (412, '412', '9600-7566-Tjong Li Mi Anita kelop', '9600', '7566', 'Tjong Li Mi Anita kelop', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 08:11:00+07', 'Admin', '2026-05-04 08:11:00+07', 'Admin', 'GK-7566-899033', 'GK-KARDUS-000412'),
  (413, '413', '8000-7604-Tjong li mi Dinda putri', '8000', '7604', 'Tjong li mi Dinda putri', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 08:11:00+07', 'Admin', '2026-05-04 08:11:00+07', 'Admin', 'GK-7604-466A96', 'GK-KARDUS-000413'),
  (414, '414', '2800-0063-denny Anita denny setiawan', '2800', '0063', 'denny Anita denny setiawan', 'GUDANG ANITA', 'Titipan', '2026-05-04 08:14:00+07', 'Admin', '2026-05-04 08:14:00+07', 'Admin', 'GK-0063-53E31A', 'GK-KARDUS-000414'),
  (415, '415', '2900-1752-TEODORUS TEAM RINA TEODORUS BREYNOL', '2900', '1752', 'TEODORUS TEAM RINA TEODORUS BREYNOL', 'GUDANG RINA', 'Titipan', '2026-05-04 08:15:00+07', 'Admin', '2026-05-04 08:15:00+07', 'Admin', 'GK-1752-6E13D5', 'GK-KARDUS-000415'),
  (416, '416', '0800-7482-Neng Kanan T Papua Citra Cantika', '0800', '7482', 'Neng Kanan T Papua Citra Cantika', 'GUDANG NENG', 'Titipan', '2026-05-04 08:15:00+07', 'Admin', '2026-05-04 08:15:00+07', 'Admin', 'GK-7482-ED4BFA', 'GK-KARDUS-000416'),
  (417, '417', '1870-4162-Anita bintang sunarsih sunarsih', '1870', '4162', 'Anita bintang sunarsih sunarsih', 'GUDANG ANITA', 'Titipan', '2026-05-04 08:16:00+07', 'Admin', '2026-05-04 08:16:00+07', 'Admin', 'GK-4162-8DC0C5', 'GK-KARDUS-000417'),
  (418, '418', '3000-9860-Tjong li mi merina', '3000', '9860', 'Tjong li mi merina', 'GUDANG AMI', 'Titipan', '2026-05-04 08:17:00+07', 'Admin', '2026-05-04 08:17:00+07', 'Admin', 'GK-9860-C7FD6E', 'GK-KARDUS-000418'),
  (419, '419', '0900-4165-Nurhaini DM Nurhaini', '0900', '4165', 'Nurhaini DM Nurhaini', 'GUDANG RANDOM', 'Titipan', '2026-05-04 08:18:00+07', 'Admin', '2026-05-04 08:18:00+07', 'Admin', 'GK-4165-A0F795', 'GK-KARDUS-000419'),
  (420, '420', '7800-1372-PHILIPS ANITA PHILIPS FREIZENZ LOKWATY', '7800', '1372', 'PHILIPS ANITA PHILIPS FREIZENZ LOKWATY', 'GUDANG ANITA', 'Titipan', '2026-05-04 08:19:00+07', 'Admin', '2026-05-04 08:19:00+07', 'Admin', 'GK-1372-986689', 'GK-KARDUS-000420'),
  (421, '421', '8300-2054-Neng karan T. Nunu Nuhdini', '8300', '2054', 'Neng karan T. Nunu Nuhdini', 'GUDANG NENG', 'Titipan', '2026-05-04 08:20:00+07', 'Admin', '2026-05-04 08:20:00+07', 'Admin', 'GK-2054-22DE0E', 'GK-KARDUS-000421'),
  (422, '422', '6900-7781-Neng kanan T Papua widi', '6900', '7781', 'Neng kanan T Papua widi', 'GUDANG NENG', 'Titipan', '2026-05-04 08:21:00+07', 'Admin', '2026-05-04 08:21:00+07', 'Admin', 'GK-7781-E459CE', 'GK-KARDUS-000422'),
  (423, '423', '7300-1667-Neng Kanan T. Nining Yuningsih.', '7300', '1667', 'Neng Kanan T. Nining Yuningsih.', 'GUDANG NENG', 'Titipan', '2026-05-04 08:24:00+07', 'Admin', '2026-05-04 08:24:00+07', 'Admin', 'GK-1667-B307BE', 'GK-KARDUS-000423'),
  (424, '424', '8300-2615-NENG KANAN T PAPUA ROSMA ROSTIKA', '8300', '2615', 'NENG KANAN T PAPUA ROSMA ROSTIKA', 'GUDANG NENG', 'Titipan', '2026-05-04 08:24:00+07', 'Admin', '2026-05-04 08:24:00+07', 'Admin', 'GK-2615-A60B0C', 'GK-KARDUS-000424'),
  (425, '425', '1900-3789-Rafli Hidayat T Mawarni', '1900', '3789', 'Rafli Hidayat T Mawarni', 'GUDANG MAWARNI', 'Titipan', '2026-05-04 08:26:00+07', 'Admin', '2026-05-04 08:26:00+07', 'Admin', 'GK-3789-EDCD4F', 'GK-KARDUS-000425'),
  (426, '426', '6500-0465-Neng Kanan T. Riki suswanto', '6500', '0465', 'Neng Kanan T. Riki suswanto', 'GUDANG NENG', 'Titipan', '2026-05-04 08:27:00+07', 'Admin', '2026-05-04 08:27:00+07', 'Admin', 'GK-0465-1D80E2', 'GK-KARDUS-000426'),
  (427, '427', '1900-0096-Intan Anita Intan permata', '1900', '0096', 'Intan Anita Intan permata', 'GUDANG ANITA', 'Titipan', '2026-05-04 08:27:00+07', 'Admin', '2026-05-04 08:27:00+07', 'Admin', 'GK-0096-F5621F', 'GK-KARDUS-000427'),
  (428, '428', '4500-2624-AGIL KIRANA WIFA AGIL KIRANA', '4500', '2624', 'AGIL KIRANA WIFA AGIL KIRANA', 'GUDANG WIFA', 'Titipan', '2026-05-04 08:28:00+07', 'Admin', '2026-05-04 08:28:00+07', 'Admin', 'GK-2624-D80061', 'GK-KARDUS-000428'),
  (429, '429', '6500-2152-Fajar Permatasari T. WIFA', '6500', '2152', 'Fajar Permatasari T. WIFA', 'GUDANG WIFA', 'Titipan', '2026-05-04 08:29:00+07', 'Admin', '2026-05-04 08:29:00+07', 'Admin', 'GK-2152-DAB7E1', 'GK-KARDUS-000429'),
  (430, '430', '8700-0880-M DAME ANITA DAME SIHOMBING', '8700', '0880', 'M DAME ANITA DAME SIHOMBING', 'GUDANG ANITA', 'Titipan', '2026-05-04 08:30:00+07', 'Admin', '2026-05-04 08:30:00+07', 'Admin', 'GK-0880-57C704', 'GK-KARDUS-000430'),
  (431, '431', '4800-7625-Neng kanan T Papua wili Saputra', '4800', '7625', 'Neng kanan T Papua wili Saputra', 'GUDANG NENG', 'Titipan', '2026-05-04 08:30:00+07', 'Admin', '2026-05-04 08:30:00+07', 'Admin', 'GK-7625-9E9B86', 'GK-KARDUS-000431'),
  (432, '432', '2800-1027-Neng Kanan T. Marjono', '2800', '1027', 'Neng Kanan T. Marjono', 'GUDANG NENG', 'Titipan', '2026-05-04 08:31:00+07', 'Admin', '2026-05-04 08:31:00+07', 'Admin', 'GK-1027-2B1634', 'GK-KARDUS-000432'),
  (433, '433', '6913-5119-Tjoy li mi Agus tinus Ojara', '6913', '5119', 'Tjoy li mi Agus tinus Ojara', 'GUDANG AMI', 'Titipan', '2026-05-04 08:33:00+07', 'Admin', '2026-05-04 08:33:00+07', 'Admin', 'GK-5119-2ED76E', 'GK-KARDUS-000433'),
  (434, '434', '1900-2405-Neng Kanan T. asum sumiati', '1900', '2405', 'Neng Kanan T. asum sumiati', 'GUDANG NENG', 'Titipan', '2026-05-04 08:33:00+07', 'Admin', '2026-05-04 08:33:00+07', 'Admin', 'GK-2405-C0A53A', 'GK-KARDUS-000434'),
  (435, '435', '0220-0784-raisha afra sakila t wifa raisha afra sakila', '0220', '0784', 'raisha afra sakila t wifa raisha afra sakila', 'GUDANG WIFA', 'Titipan', '2026-05-04 08:34:00+07', 'Admin', '2026-05-04 08:34:00+07', 'Admin', 'GK-0784-BC9519', 'GK-KARDUS-000435'),
  (436, '436', '2800-0231-christal geraldine wifa christal geraldine kirsten', '2800', '0231', 'christal geraldine wifa christal geraldine kirsten', 'GUDANG WIFA', 'Titipan', '2026-05-04 08:37:00+07', 'Admin', '2026-05-04 08:37:00+07', 'Admin', 'GK-0231-BB6BD3', 'GK-KARDUS-000436'),
  (437, '437', '0100-2304-doni anita doni setia', '0100', '2304', 'doni anita doni setia', 'GUDANG ANITA', 'Titipan', '2026-05-04 08:40:00+07', 'Admin', '2026-05-04 08:40:00+07', 'Admin', 'GK-2304-827CDD', 'GK-KARDUS-000437'),
  (438, '438', '2400-8181-Ami Alvin PRAkOSO', '2400', '8181', 'Ami Alvin PRAkOSO', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 08:40:00+07', 'Admin', '2026-05-04 08:40:00+07', 'Admin', 'GK-8181-B9CFB4', 'GK-KARDUS-000438'),
  (439, '439', '5500-3874-Ami Fitri Aulia', '5500', '3874', 'Ami Fitri Aulia', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 08:40:00+07', 'Admin', '2026-05-04 08:40:00+07', 'Admin', 'GK-3874-7C9088', 'GK-KARDUS-000439'),
  (440, '440', '5200-8181-AMIPITRIADAMAYANTI', '5200', '8181', 'AMIPITRIADAMAYANTI', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 08:41:00+07', 'Admin', '2026-05-04 08:41:00+07', 'Admin', 'GK-8181-D66020', 'GK-KARDUS-000440'),
  (441, '441', '3700-2171-Neng Kanan T.Irfan', '3700', '2171', 'Neng Kanan T.Irfan', 'GUDANG NENG', 'Titipan', '2026-05-04 08:43:00+07', 'Admin', '2026-05-04 08:43:00+07', 'Admin', 'GK-2171-DB0466', 'GK-KARDUS-000441'),
  (442, '442', '9000-9805-Yoga Anita yoga bagus', '9000', '9805', 'Yoga Anita yoga bagus', 'GUDANG ANITA', 'Titipan', '2026-05-04 08:44:00+07', 'Admin', '2026-05-04 08:44:00+07', 'Admin', 'GK-9805-A34010', 'GK-KARDUS-000442'),
  (443, '443', '5200-4085-DWi DM edydwi medling', '5200', '4085', 'DWi DM edydwi medling', 'GUDANG DWI', 'Titipan', '2026-05-04 08:45:00+07', 'Admin', '2026-05-04 08:45:00+07', 'Admin', 'GK-4085-C1AACA', 'GK-KARDUS-000443'),
  (444, '444', '1500-3805-PRabowo Adi T mawarni Prabowo Adi', '1500', '3805', 'PRabowo Adi T mawarni Prabowo Adi', 'GUDANG MAWARNI', 'Titipan', '2026-05-04 08:46:00+07', 'Admin', '2026-05-04 08:46:00+07', 'Admin', 'GK-3805-E913C5', 'GK-KARDUS-000444'),
  (445, '445', '4500-4821-tjong li mi Maria bernadet bunga betan', '4500', '4821', 'tjong li mi Maria bernadet bunga betan', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 08:48:00+07', 'Admin', '2026-05-04 08:48:00+07', 'Admin', 'GK-4821-E3A44A', 'GK-KARDUS-000445'),
  (446, '446', '5200-4085-DWi DM edydwi medling', '5200', '4085', 'DWi DM edydwi medling', 'GUDANG DWI', 'Titipan', '2026-05-04 08:48:00+07', 'Admin', '2026-05-04 08:48:00+07', 'Admin', 'GK-4085-C1AACA', 'GK-KARDUS-000446'),
  (447, '447', '8200-7629-neng kanan t papua rajan akbar', '8200', '7629', 'neng kanan t papua rajan akbar', 'GUDANG NENG', 'Titipan', '2026-05-04 08:48:00+07', 'Admin', '2026-05-04 08:48:00+07', 'Admin', 'GK-7629-D1182F', 'GK-KARDUS-000447'),
  (448, '448', '5500-3788-Joko Susilo t marta joko Susilo', '5500', '3788', 'Joko Susilo t marta joko Susilo', 'GUDANG MARTA', 'Titipan', '2026-05-04 08:49:00+07', 'Admin', '2026-05-04 08:49:00+07', 'Admin', 'GK-3788-4FFA97', 'GK-KARDUS-000448'),
  (449, '449', '7600-1550-Setepen T. Dadang kanan', '7600', '1550', 'Setepen T. Dadang kanan', 'GUDANG RANDOM', 'Titipan', '2026-05-04 08:52:00+07', 'Admin', '2026-05-04 08:52:00+07', 'Admin', 'GK-1550-390A1D', 'GK-KARDUS-000449'),
  (450, '450', '8700-7619-Neng kanan T papua muhamad Riyas', '8700', '7619', 'Neng kanan T papua muhamad Riyas', 'GUDANG NENG', 'Titipan', '2026-05-04 08:52:00+07', 'Admin', '2026-05-04 08:52:00+07', 'Admin', 'GK-7619-0D0A77', 'GK-KARDUS-000450'),
  (451, '451', '2300-7798-NenG kanan I papua Lalita Surlina', '2300', '7798', 'NenG kanan I papua Lalita Surlina', 'GUDANG NENG', 'Titipan', '2026-05-04 08:54:00+07', 'Admin', '2026-05-04 08:54:00+07', 'Admin', 'GK-7798-7F03A6', 'GK-KARDUS-000451'),
  (452, '452', '7700-1646-Oki Seatiwan T. Raisa', '7700', '1646', 'Oki Seatiwan T. Raisa', 'GUDANG RANDOM', 'Titipan', '2026-05-04 08:57:00+07', 'Admin', '2026-05-04 08:57:00+07', 'Admin', 'GK-1646-2F6079', 'GK-KARDUS-000452'),
  (453, '453', '7700-3775-Nur efendi team Rina nur efendi', '7700', '3775', 'Nur efendi team Rina nur efendi', 'GUDANG RINA', 'Titipan', '2026-05-04 08:58:00+07', 'Admin', '2026-05-04 08:58:00+07', 'Admin', 'GK-3775-11D61E', 'GK-KARDUS-000453'),
  (454, '454', '3600-0047-tina mariana dm tina', '3600', '0047', 'tina mariana dm tina', 'GUDANG RANDOM', 'Titipan', '2026-05-04 08:58:00+07', 'Admin', '2026-05-04 08:58:00+07', 'Admin', 'GK-0047-7A20E6', 'GK-KARDUS-000454'),
  (455, '455', '5900-3893-Ami metta sutanto', '5900', '3893', 'Ami metta sutanto', 'GUDANG AMI', 'Titipan', '2026-05-04 09:00:00+07', 'Admin', '2026-05-04 09:00:00+07', 'Admin', 'GK-3893-DA0DD8', 'GK-KARDUS-000455'),
  (456, '456', '5700-2509-Neng Kanan T. ABDUL ADID', '5700', '2509', 'Neng Kanan T. ABDUL ADID', 'GUDANG NENG', 'Titipan', '2026-05-04 09:00:00+07', 'Admin', '2026-05-04 09:00:00+07', 'Admin', 'GK-2509-53AD0E', 'GK-KARDUS-000456'),
  (457, '457', '2500-3955-Angga Pranata T erlin kanan angga pranata', '2500', '3955', 'Angga Pranata T erlin kanan angga pranata', 'GUDANG ERLIN', 'Titipan', '2026-05-04 09:02:00+07', 'Admin', '2026-05-04 09:02:00+07', 'Admin', 'GK-3955-CAF4E8', 'GK-KARDUS-000457'),
  (458, '458', '7600-2338-Yuyun Jiman T Martha', '7600', '2338', 'Yuyun Jiman T Martha', 'GUDANG MARTHA', 'Titipan', '2026-05-04 09:04:00+07', 'Admin', '2026-05-04 09:04:00+07', 'Admin', 'GK-2338-664744', 'GK-KARDUS-000458'),
  (459, '459', '2500-3817-Intan Permatasari T Erlin Intan', '2500', '3817', 'Intan Permatasari T Erlin Intan', 'GUDANG ERLIN', 'Titipan', '2026-05-04 09:07:00+07', 'Admin', '2026-05-04 09:07:00+07', 'Admin', 'GK-3817-B8719A', 'GK-KARDUS-000459'),
  (460, '460', '0400-7592-Neng kanan T Papua Nita Lingga citra', '0400', '7592', 'Neng kanan T Papua Nita Lingga citra', 'GUDANG NENG', 'Titipan', '2026-05-04 09:07:00+07', 'Admin', '2026-05-04 09:07:00+07', 'Admin', 'GK-7592-73ED16', 'GK-KARDUS-000460'),
  (461, '461', '7300-1238-neng kanan t papua hotmaria sinaga', '7300', '1238', 'neng kanan t papua hotmaria sinaga', 'GUDANG NENG', 'Titipan', '2026-05-04 09:08:00+07', 'Admin', '2026-05-04 09:08:00+07', 'Admin', 'GK-1238-F68631', 'GK-KARDUS-000461'),
  (462, '462', '4900-2576-Tomy Effendy Sm T. Raisha', '4900', '2576', 'Tomy Effendy Sm T. Raisha', 'GUDANG RANDOM', 'Titipan', '2026-05-04 09:08:00+07', 'Admin', '2026-05-04 09:08:00+07', 'Admin', 'GK-2576-BF59D2', 'GK-KARDUS-000462'),
  (463, '463', '5400-1556-Neng kanan T. Novie Masayu', '5400', '1556', 'Neng kanan T. Novie Masayu', 'GUDANG NENG', 'Titipan', '2026-05-04 09:09:00+07', 'Admin', '2026-05-04 09:09:00+07', 'Admin', 'GK-1556-72B5E8', 'GK-KARDUS-000463'),
  (464, '464', '4200-1093-Ami T. Ichsan yarmi', '4200', '1093', 'Ami T. Ichsan yarmi', 'GUDANG AMI', 'Titipan', '2026-05-04 09:10:00+07', 'Admin', '2026-05-04 09:10:00+07', 'Admin', 'GK-1093-945980', 'GK-KARDUS-000464'),
  (465, '465', '2200-0348-Anita bintang gading gading marthin', '2200', '0348', 'Anita bintang gading gading marthin', 'GUDANG ANITA', 'Titipan', '2026-05-04 09:12:00+07', 'Admin', '2026-05-04 09:12:00+07', 'Admin', 'GK-0348-B284A3', 'GK-KARDUS-000465'),
  (466, '466', '4200-2560-neng kanan t papua widya vania', '4200', '2560', 'neng kanan t papua widya vania', 'GUDANG NENG', 'Titipan', '2026-05-04 09:12:00+07', 'Admin', '2026-05-04 09:12:00+07', 'Admin', 'GK-2560-459DD3', 'GK-KARDUS-000466'),
  (467, '467', '5800-5095-Tjong li mi niken lestari', '5800', '5095', 'Tjong li mi niken lestari', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 09:12:00+07', 'Admin', '2026-05-04 09:12:00+07', 'Admin', 'GK-5095-449698', 'GK-KARDUS-000467'),
  (468, '468', '4000-3946-Halim julianto t mawar nithalim Julianto', '4000', '3946', 'Halim julianto t mawar nithalim Julianto', 'GUDANG MAWARNI', 'Titipan', '2026-05-04 09:14:00+07', 'Admin', '2026-05-04 09:14:00+07', 'Admin', 'GK-3946-CBAAF1', 'GK-KARDUS-000468'),
  (469, '469', '0900-8176-edi anita edi saptono', '0900', '8176', 'edi anita edi saptono', 'GUDANG ANITA', 'Titipan', '2026-05-04 09:14:00+07', 'Admin', '2026-05-04 09:14:00+07', 'Admin', 'GK-8176-8A03D1', 'GK-KARDUS-000469'),
  (470, '470', '5600-7496-Neng kanan T Papua niko Lius', '5600', '7496', 'Neng kanan T Papua niko Lius', 'GUDANG NENG', 'Titipan', '2026-05-04 09:15:00+07', 'Admin', '2026-05-04 09:15:00+07', 'Admin', 'GK-7496-C42014', 'GK-KARDUS-000470'),
  (471, '471', '0200-9934-neng kanan t papua ujang mansur', '0200', '9934', 'neng kanan t papua ujang mansur', 'GUDANG NENG', 'Titipan', '2026-05-04 09:17:00+07', 'Admin', '2026-05-04 09:17:00+07', 'Admin', 'GK-9934-FE0501', 'GK-KARDUS-000471'),
  (472, '472', '0200-0260-Putri Maheshwara Kanan Dadang', '0200', '0260', 'Putri Maheshwara Kanan Dadang', 'GUDANG RANDOM', 'Titipan', '2026-05-04 09:17:00+07', 'Admin', '2026-05-04 09:17:00+07', 'Admin', 'GK-0260-B71C7A', 'GK-KARDUS-000472'),
  (473, '473', '5700-3852-Ami Diyan', '5700', '3852', 'Ami Diyan', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 09:19:00+07', 'Admin', '2026-05-04 09:19:00+07', 'Admin', 'GK-3852-B6AD22', 'GK-KARDUS-000473'),
  (474, '474', '4900-4112-ami sean murphy moeis', '4900', '4112', 'ami sean murphy moeis', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 09:20:00+07', 'Admin', '2026-05-04 09:20:00+07', 'Admin', 'GK-4112-D23476', 'GK-KARDUS-000474'),
  (475, '475', '1800-1264-Neng Kanan T Papua Abel Putri', '1800', '1264', 'Neng Kanan T Papua Abel Putri', 'GUDANG NENG', 'Titipan', '2026-05-04 09:20:00+07', 'Admin', '2026-05-04 09:20:00+07', 'Admin', 'GK-1264-87C613', 'GK-KARDUS-000475'),
  (476, '476', '0400-4112-dian kartika t erlin dian kartika', '0400', '4112', 'dian kartika t erlin dian kartika', 'GUDANG RANDOM', 'Titipan', '2026-05-04 09:21:00+07', 'Admin', '2026-05-04 09:21:00+07', 'Admin', 'GK-4112-FE1DAE', 'GK-KARDUS-000476'),
  (477, '477', '5100-1154-Neng Kanan T. Kartika', '5100', '1154', 'Neng Kanan T. Kartika', 'GUDANG NENG', 'Titipan', '2026-05-04 09:21:00+07', 'Admin', '2026-05-04 09:21:00+07', 'Admin', 'GK-1154-061A85', 'GK-KARDUS-000477'),
  (478, '478', '6300-2332-Neng Kanan T. Parva Fika Andira', '6300', '2332', 'Neng Kanan T. Parva Fika Andira', 'GUDANG NENG', 'Titipan', '2026-05-04 09:22:00+07', 'Admin', '2026-05-04 09:22:00+07', 'Admin', 'GK-2332-81457D', 'GK-KARDUS-000478'),
  (479, '479', '8900-8294-lena selvi lena arumi', '8900', '8294', 'lena selvi lena arumi', 'GUDANG SELVI', 'Titipan', '2026-05-04 09:23:00+07', 'Oktavia', '2026-05-04 09:23:00+07', 'Oktavia', 'GK-8294-F0223F', 'GK-KARDUS-000479'),
  (480, '480', '3400-4023-Woen lily ID T boen kanan woen lily', '3400', '4023', 'Woen lily ID T boen kanan woen lily', 'GUDANG RANDOM', 'Titipan', '2026-05-04 09:24:00+07', 'Admin', '2026-05-04 09:24:00+07', 'Admin', 'GK-4023-84B127', 'GK-KARDUS-000480'),
  (481, '481', '3000-1233-Neng Kanan T Papua Afika Andika', '3000', '1233', 'Neng Kanan T Papua Afika Andika', 'GUDANG NENG', 'Titipan', '2026-05-04 09:24:00+07', 'Admin', '2026-05-04 09:24:00+07', 'Admin', 'GK-1233-DADA95', 'GK-KARDUS-000481'),
  (482, '482', '3800-0732-Puput Kembang Wifa', '3800', '0732', 'Puput Kembang Wifa', 'GUDANG WIFA', 'Titipan', '2026-05-04 09:26:00+07', 'Admin', '2026-05-04 09:26:00+07', 'Admin', 'GK-0732-DBC479', 'GK-KARDUS-000482'),
  (483, '483', '9900-7401-Adriana Team Rina', '9900', '7401', 'Adriana Team Rina', 'GUDANG RINA', 'Titipan', '2026-05-04 09:26:00+07', 'Admin', '2026-05-04 09:26:00+07', 'Admin', 'GK-7401-FC54D6', 'GK-KARDUS-000483'),
  (484, '484', '3000-2342-Nurul Anita Khotimah', '3000', '2342', 'Nurul Anita Khotimah', 'GUDANG ANITA', 'Titipan', '2026-05-04 09:28:00+07', 'Admin', '2026-05-04 09:28:00+07', 'Admin', 'GK-2342-45E920', 'GK-KARDUS-000484'),
  (485, '485', '6400-8456-Yani Anita Yaniingsi', '6400', '8456', 'Yani Anita Yaniingsi', 'GUDANG ANITA', 'Titipan', '2026-05-04 09:31:00+07', 'Admin', '2026-05-04 09:31:00+07', 'Admin', 'GK-8456-E73EE7', 'GK-KARDUS-000485'),
  (486, '486', '0200-0079-dian anita dian', '0200', '0079', 'dian anita dian', 'GUDANG ANITA', 'Titipan', '2026-05-04 09:32:00+07', 'Admin', '2026-05-04 09:32:00+07', 'Admin', 'GK-0079-D9F943', 'GK-KARDUS-000486'),
  (487, '487', '8600-1406-Neng Kanan T Papua Ilham Purnama', '8600', '1406', 'Neng Kanan T Papua Ilham Purnama', 'GUDANG NENG', 'Titipan', '2026-05-04 09:32:00+07', 'Admin', '2026-05-04 09:32:00+07', 'Admin', 'GK-1406-8010E5', 'GK-KARDUS-000487'),
  (488, '488', '4800-8215-Jojor Selvi Jojor Simanjuntak', '4800', '8215', 'Jojor Selvi Jojor Simanjuntak', 'GUDANG SELVI', 'Titipan', '2026-05-04 09:34:00+07', 'Admin', '2026-05-04 09:34:00+07', 'Admin', 'GK-8215-DA51B6', 'GK-KARDUS-000488'),
  (489, '489', '6100-9849-Neng kanan T papua Syaifullah hidayat', '6100', '9849', 'Neng kanan T papua Syaifullah hidayat', 'GUDANG NENG', 'Titipan', '2026-05-04 09:35:00+07', 'Admin', '2026-05-04 09:35:00+07', 'Admin', 'GK-9849-61C56A', 'GK-KARDUS-000489'),
  (490, '490', '4200-0791-Neng kanan T. Papuakharisma Palupi', '4200', '0791', 'Neng kanan T. Papuakharisma Palupi', 'GUDANG NENG', 'Titipan', '2026-05-04 09:36:00+07', 'Admin', '2026-05-04 09:36:00+07', 'Admin', 'GK-0791-07A182', 'GK-KARDUS-000490'),
  (491, '491', '5000-2520-neng kanan t papua juliana', '5000', '2520', 'neng kanan t papua juliana', 'GUDANG ANITA', 'Titipan', '2026-05-04 09:38:00+07', 'Admin', '2026-05-04 09:38:00+07', 'Admin', 'GK-2520-78C1FF', 'GK-KARDUS-000491'),
  (492, '492', '0600-1586-Neng kanan T. Yati', '0600', '1586', 'Neng kanan T. Yati', 'GUDANG NENG', 'Titipan', '2026-05-04 09:38:00+07', 'Admin', '2026-05-04 09:38:00+07', 'Admin', 'GK-1586-468B25', 'GK-KARDUS-000492'),
  (493, '493', '5900-9743-Farhan Anita Farhan maulana', '5900', '9743', 'Farhan Anita Farhan maulana', 'GUDANG ANITA', 'Titipan', '2026-05-04 09:39:00+07', 'Admin', '2026-05-04 09:39:00+07', 'Admin', 'GK-9743-1EC964', 'GK-KARDUS-000493'),
  (494, '494', '1900-0037-neng kanan t papua tatan', '1900', '0037', 'neng kanan t papua tatan', 'GUDANG NENG', 'Titipan', '2026-05-04 09:40:00+07', 'Admin', '2026-05-04 09:40:00+07', 'Admin', 'GK-0037-C6DC16', 'GK-KARDUS-000494'),
  (495, '495', '2900-2600-Neng Kanan T. Ammar Kholid', '2900', '2600', 'Neng Kanan T. Ammar Kholid', 'GUDANG NENG', 'Titipan', '2026-05-04 09:40:00+07', 'Admin', '2026-05-04 09:40:00+07', 'Admin', 'GK-2600-09E172', 'GK-KARDUS-000495'),
  (496, '496', '9500-7630-Mirna team rina mirna sumindar', '9500', '7630', 'Mirna team rina mirna sumindar', 'GUDANG RINA', 'Titipan', '2026-05-04 09:41:00+07', 'Admin', '2026-05-04 09:41:00+07', 'Admin', 'GK-7630-71FB01', 'GK-KARDUS-000496'),
  (497, '497', '6300-3831-Ami Ahmad rifai', '6300', '3831', 'Ami Ahmad rifai', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 09:44:00+07', 'Admin', '2026-05-04 09:44:00+07', 'Admin', 'GK-3831-F4AC7F', 'GK-KARDUS-000497'),
  (498, '498', '7200-8195-boima silalahi t mawarni boima silalahi', '7200', '8195', 'boima silalahi t mawarni boima silalahi', 'GUDANG MAWARNI', 'Titipan', '2026-05-04 09:45:00+07', 'Admin', '2026-05-04 09:45:00+07', 'Admin', 'GK-8195-7FF8A5', 'GK-KARDUS-000498'),
  (499, '498', '6000-8557-Gilang Anita Gilang', '6000', '8557', 'Gilang Anita Gilang', 'GUDANG ANITA', 'Titipan', '2026-05-04 09:45:00+07', 'Admin', '2026-05-04 09:45:00+07', 'Admin', 'GK-8557-9A8C8A', 'GK-KARDUS-000498'),
  (500, '499', '9700-1940-Wilson by Ami Frendy Butar', '9700', '1940', 'Wilson by Ami Frendy Butar', 'GUDANG AMI', 'Milik Sendiri', '2026-05-04 09:46:00+07', 'Admin', '2026-05-04 09:46:00+07', 'Admin', 'GK-1940-137196', 'GK-KARDUS-000499'),
  (501, '500', '9100-1382-Neng kanan T papua muhamad Riyas', '9100', '1382', 'Neng kanan T papua muhamad Riyas', 'GUDANG NENG', 'Titipan', '2026-05-04 09:48:00+07', 'Admin', '2026-05-04 09:48:00+07', 'Admin', 'GK-1382-0D0A77', 'GK-KARDUS-000500'),
  (502, '501', '0200-1088-Gerad firmansya Kanan Dadang', '0200', '1088', 'Gerad firmansya Kanan Dadang', 'GUDANG RANDOM', 'Titipan', '2026-05-04 09:48:00+07', 'Admin', '2026-05-04 09:48:00+07', 'Admin', 'GK-1088-E485B5', 'GK-KARDUS-000501'),
  (503, '502', '8200-3871-Bagiono SM T Shofia kiri bagiono', '8200', '3871', 'Bagiono SM T Shofia kiri bagiono', 'GUDANG SHOFIA', 'Titipan', '2026-05-04 09:49:00+07', 'Admin', '2026-05-04 09:49:00+07', 'Admin', 'GK-3871-81F0DA', 'GK-KARDUS-000502'),
  (504, '503', '9700-7849-wulan anita wulan', '9700', '7849', 'wulan anita wulan', 'GUDANG ANITA', 'Titipan', '2026-05-04 09:52:00+07', 'Admin', '2026-05-04 09:52:00+07', 'Admin', 'GK-7849-7C8F69', 'GK-KARDUS-000503'),
  (505, '504', '8500-2139-Neng kanan T. Marjono', '8500', '2139', 'Neng kanan T. Marjono', 'GUDANG NENG', 'Titipan', '2026-05-04 09:53:00+07', 'Admin', '2026-05-04 09:53:00+07', 'Admin', 'GK-2139-2B1634', 'GK-KARDUS-000504'),
  (506, '505', '6900-2535-LIDIA Team Rinalidia', '6900', '2535', 'LIDIA Team Rinalidia', 'GUDANG RINA', 'Titipan', '2026-05-04 09:54:00+07', 'Admin', '2026-05-04 09:54:00+07', 'Admin', 'GK-2535-0ED9BF', 'GK-KARDUS-000505'),
  (507, '506', '7100-4005-Asnawi Hafel T Mawarni', '7100', '4005', 'Asnawi Hafel T Mawarni', 'GUDANG MAWARNI', 'Titipan', '2026-05-04 09:54:00+07', 'Admin', '2026-05-04 09:54:00+07', 'Admin', 'GK-4005-FF3B04', 'GK-KARDUS-000506'),
  (508, '507', '4300-4005-amiliho', '4300', '4005', 'amiliho', 'GUDANG MAWARNI', 'Titipan', '2026-05-04 09:55:00+07', 'Admin', '2026-05-04 09:55:00+07', 'Admin', 'GK-4005-07340C', 'GK-KARDUS-000507'),
  (509, '508', '9200-8890-Fahmi Anitafahmi', '9200', '8890', 'Fahmi Anitafahmi', 'GUDANG ANITA', 'Titipan', '2026-05-04 09:56:00+07', 'Admin', '2026-05-04 09:56:00+07', 'Admin', 'GK-8890-E34860', 'GK-KARDUS-000508'),
  (510, '509', '8300-2340-Wenny Anita', '8300', '2340', 'Wenny Anita', 'GUDANG ANITA', 'Titipan', '2026-05-04 09:58:00+07', 'Admin', '2026-05-04 09:58:00+07', 'Admin', 'GK-2340-4BC70A', 'GK-KARDUS-000509'),
  (511, '510', '7900-7576-Meti Anita meti Delsi', '7900', '7576', 'Meti Anita meti Delsi', 'GUDANG ANITA', 'Titipan', '2026-05-04 09:58:00+07', 'Admin', '2026-05-04 09:58:00+07', 'Admin', 'GK-7576-F9584E', 'GK-KARDUS-000510'),
  (512, '511', '2700-0301-Neng Kanan T. Papua IHSAN IFTIKAR', '2700', '0301', 'Neng Kanan T. Papua IHSAN IFTIKAR', 'GUDANG NENG', 'Titipan', '2026-05-04 10:00:00+07', 'Admin', '2026-05-04 10:00:00+07', 'Admin', 'GK-0301-DB4C10', 'GK-KARDUS-000511'),
  (513, '512', '1600-1594-juliyana team rina puji lestar', '1600', '1594', 'juliyana team rina puji lestar', 'GUDANG RINA', 'Titipan', '2026-05-04 10:00:00+07', 'Admin', '2026-05-04 10:00:00+07', 'Admin', 'GK-1594-4E9B17', 'GK-KARDUS-000512'),
  (514, '513', '4000-1863-samsul anita samsul sumitarya', '4000', '1863', 'samsul anita samsul sumitarya', 'GUDANG ANITA', 'Titipan', '2026-05-04 10:09:00+07', 'Admin', '2026-05-04 10:09:00+07', 'Admin', 'GK-1863-5D2EAE', 'GK-KARDUS-000513'),
  (515, '514', '8100-0735-neng kanan t papua heri kuswanto', '8100', '0735', 'neng kanan t papua heri kuswanto', 'GUDANG NENG', 'Titipan', '2026-05-04 10:13:00+07', 'Admin', '2026-05-04 10:13:00+07', 'Admin', 'GK-0735-7800C6', 'GK-KARDUS-000514'),
  (516, '515', '9900-1190-juliyana team rina julyana nainggolan', '9900', '1190', 'juliyana team rina julyana nainggolan', 'GUDANG RINA', 'Titipan', '2026-05-04 10:15:00+07', 'Admin', '2026-05-04 10:15:00+07', 'Admin', 'GK-1190-49CF88', 'GK-KARDUS-000515'),
  (517, '516', '2300-2668-Neng Kanan T. PAPUA AQILA', '2300', '2668', 'Neng Kanan T. PAPUA AQILA', 'GUDANG ANITA', 'Titipan', '2026-05-05 08:42:00+07', 'Admin', '2026-05-05 08:42:00+07', 'Admin', 'GK-2668-E0A1EC', 'GK-KARDUS-000516'),
  (518, '517', '8000-8497-Deni Anita Deni', '8000', '8497', 'Deni Anita Deni', 'GUDANG ANITA', 'Titipan', '2026-05-05 08:44:00+07', 'Admin', '2026-05-05 08:44:00+07', 'Admin', 'GK-8497-CDBEAA', 'GK-KARDUS-000517'),
  (519, '518', '4600-2199-Neng Kanan T Papua Ujang Mansur', '4600', '2199', 'Neng Kanan T Papua Ujang Mansur', 'GUDANG NENG', 'Titipan', '2026-05-05 08:46:00+07', 'Admin', '2026-05-05 08:46:00+07', 'Admin', 'GK-2199-FE0501', 'GK-KARDUS-000518'),
  (520, '519', '9000-0786-Neng Kanan T. Papua Daniah', '9000', '0786', 'Neng Kanan T. Papua Daniah', 'GUDANG NENG', 'Titipan', '2026-05-05 08:49:00+07', 'Admin', '2026-05-05 08:49:00+07', 'Admin', 'GK-0786-CC5671', 'GK-KARDUS-000519'),
  (521, '520', '4500-0639-Neng kanan T. Papua Darrel Lingga', '4500', '0639', 'Neng kanan T. Papua Darrel Lingga', 'GUDANG NENG', 'Titipan', '2026-05-05 08:50:00+07', 'Admin', '2026-05-05 08:50:00+07', 'Admin', 'GK-0639-7C0426', 'GK-KARDUS-000520'),
  (522, '521', '7600-1381-Nengkanan T. Papua Darrel', '7600', '1381', 'Nengkanan T. Papua Darrel', 'GUDANG NENG', 'Titipan', '2026-05-05 08:51:00+07', 'Admin', '2026-05-05 08:51:00+07', 'Admin', 'GK-1381-01E92F', 'GK-KARDUS-000521'),
  (523, '522', '3000-3808-Dian kartika T erlin dian kartika', '3000', '3808', 'Dian kartika T erlin dian kartika', 'GUDANG ERLIN', 'Titipan', '2026-05-05 08:52:00+07', 'Admin', '2026-05-05 08:52:00+07', 'Admin', 'GK-3808-FE1DAE', 'GK-KARDUS-000522'),
  (524, '523', '7400-1852-Neng kanan T. Widya Vania', '7400', '1852', 'Neng kanan T. Widya Vania', 'GUDANG NENG', 'Titipan', '2026-05-05 08:59:00+07', 'Admin', '2026-05-05 08:59:00+07', 'Admin', 'GK-1852-8E6843', 'GK-KARDUS-000523'),
  (525, '524', '9600-0906-Neng kanan, T. bianca', '9600', '0906', 'Neng kanan, T. bianca', 'GUDANG NENG', 'Titipan', '2026-05-05 09:00:00+07', 'Admin', '2026-05-05 09:00:00+07', 'Admin', 'GK-0906-4ECA0F', 'GK-KARDUS-000524'),
  (526, '525', '0400-2674-Neng Kanan t papua kartika', '0400', '2674', 'Neng Kanan t papua kartika', 'GUDANG NENG', 'Titipan', '2026-05-05 09:03:00+07', 'Admin', '2026-05-05 09:03:00+07', 'Admin', 'GK-2674-A23E22', 'GK-KARDUS-000525'),
  (527, '526', '2800-1273-Neng Kanan T. Papua Euis Indasiah,', '2800', '1273', 'Neng Kanan T. Papua Euis Indasiah,', 'GUDANG NENG', 'Titipan', '2026-05-05 09:05:00+07', 'Admin', '2026-05-05 09:05:00+07', 'Admin', 'GK-1273-508CDA', 'GK-KARDUS-000526'),
  (528, '527', '9600-3941-Anita bintang Sinta sinta Susilawati', '9600', '3941', 'Anita bintang Sinta sinta Susilawati', 'GUDANG ANITA', 'Titipan', '2026-05-05 09:05:00+07', 'Admin', '2026-05-05 09:05:00+07', 'Admin', 'GK-3941-E7A362', 'GK-KARDUS-000527'),
  (529, '528', '3700-3875-Mesha T boen kiri mesha', '3700', '3875', 'Mesha T boen kiri mesha', 'GUDANG BOEN', 'Titipan', '2026-05-05 09:07:00+07', 'Admin', '2026-05-05 09:07:00+07', 'Admin', 'GK-3875-9A465B', 'GK-KARDUS-000528'),
  (530, '529', '6400-0584-Tori Aldonso T Raisha', '6400', '0584', 'Tori Aldonso T Raisha', 'GUDANG RANDOM', 'Titipan', '2026-05-05 09:08:00+07', 'Admin', '2026-05-05 09:08:00+07', 'Admin', 'GK-0584-C774BA', 'GK-KARDUS-000529'),
  (531, '530', '6400-0584-Tori Aldonso T Raisha', '6400', '0584', 'Tori Aldonso T Raisha', 'GUDANG RANDOM', 'Titipan', '2026-05-05 09:08:00+07', 'Admin', '2026-05-05 09:08:00+07', 'Admin', 'GK-0584-C774BA', 'GK-KARDUS-000530'),
  (532, '531', '0100-2542-Tina Mariana DM Tina.', '0100', '2542', 'Tina Mariana DM Tina.', 'GUDANG TINA', 'Titipan', '2026-05-05 09:10:00+07', 'Admin', '2026-05-05 09:10:00+07', 'Admin', 'GK-2542-BCF765', 'GK-KARDUS-000531'),
  (533, '532', '9500-1625-Ami Yanuar Iskandar', '9500', '1625', 'Ami Yanuar Iskandar', 'GUDANG AMI', 'Titipan', '2026-05-05 09:14:00+07', 'Admin', '2026-05-05 09:14:00+07', 'Admin', 'GK-1625-8076E6', 'GK-KARDUS-000532'),
  (534, '533', '7800-2510-Neng Kanan T. Lisna Fadilah', '7800', '2510', 'Neng Kanan T. Lisna Fadilah', 'GUDANG NENG', 'Titipan', '2026-05-05 09:16:00+07', 'Admin', '2026-05-05 09:16:00+07', 'Admin', 'GK-2510-37AB36', 'GK-KARDUS-000533'),
  (535, '534', '9600-2797-Nengkanan T. Papua Herlina', '9600', '2797', 'Nengkanan T. Papua Herlina', 'GUDANG NENG', 'Titipan', '2026-05-05 09:22:00+07', 'Admin', '2026-05-05 09:22:00+07', 'Admin', 'GK-2797-F0979D', 'GK-KARDUS-000534'),
  (536, '535', '4700-1383-Neng kanan Т. Ека', '4700', '1383', 'Neng kanan Т. Ека', 'GUDANG NENG', 'Titipan', '2026-05-05 09:28:00+07', 'Admin', '2026-05-05 09:28:00+07', 'Admin', 'GK-1383-1D166E', 'GK-KARDUS-000535'),
  (537, '536', '2300-2313-Neng Kanan T. PAPUA AQILA', '2300', '2313', 'Neng Kanan T. PAPUA AQILA', 'GUDANG NENG', 'Titipan', '2026-05-05 09:28:00+07', 'Admin', '2026-05-05 09:28:00+07', 'Admin', 'GK-2313-E0A1EC', 'GK-KARDUS-000536'),
  (538, '537', '4200-0487-Tina Mariana DM Tina', '4200', '0487', 'Tina Mariana DM Tina', 'GUDANG RANDOM', 'Titipan', '2026-05-05 09:30:00+07', 'Admin', '2026-05-05 09:30:00+07', 'Admin', 'GK-0487-7A20E6', 'GK-KARDUS-000537'),
  (539, '538', '8800-0268-Sakilah Team Rina Sakilah', '8800', '0268', 'Sakilah Team Rina Sakilah', 'GUDANG RINA', 'Titipan', '2026-05-05 09:30:00+07', 'Admin', '2026-05-05 09:30:00+07', 'Admin', 'GK-0268-886987', 'GK-KARDUS-000538'),
  (540, '539', '1700-1819-Neng kanan T. Rusmini', '1700', '1819', 'Neng kanan T. Rusmini', 'GUDANG NEG', 'Titipan', '2026-05-05 09:31:00+07', 'Admin', '2026-05-05 09:31:00+07', 'Admin', 'GK-1819-868EDD', 'GK-KARDUS-000539'),
  (541, '540', '1700-1819-Neng kanan T. Rusmini', '1700', '1819', 'Neng kanan T. Rusmini', 'GUDANG NEG', 'Titipan', '2026-05-05 09:31:00+07', 'Admin', '2026-05-05 09:31:00+07', 'Admin', 'GK-1819-868EDD', 'GK-KARDUS-000540'),
  (542, '541', '9100-3813-zamas wiliam T Erlin zamas wiliam', '9100', '3813', 'zamas wiliam T Erlin zamas wiliam', 'GUDANG ERLIN', 'Titipan', '2026-05-05 09:33:00+07', 'Admin', '2026-05-05 09:33:00+07', 'Admin', 'GK-3813-CFEFE0', 'GK-KARDUS-000541'),
  (543, '542', '2000-0308-Suryani Arab lenny Fransiska', '2000', '0308', 'Suryani Arab lenny Fransiska', 'GUDANG RANDOM', 'Titipan', '2026-05-05 09:35:00+07', 'Admin', '2026-05-05 09:35:00+07', 'Admin', 'GK-0308-15EE10', 'GK-KARDUS-000542'),
  (544, '543', '1555-3791-bagus setiawan T erlin bagus setiawan', '1555', '3791', 'bagus setiawan T erlin bagus setiawan', 'GUDANG ERLIN', 'Titipan', '2026-05-05 09:37:00+07', 'Admin', '2026-05-05 09:37:00+07', 'Admin', 'GK-3791-66E4FA', 'GK-KARDUS-000543'),
  (545, '544', '1900-0103-Sambaru Team Rina', '1900', '0103', 'Sambaru Team Rina', 'GUDANG RINA', 'Titipan', '2026-05-05 09:37:00+07', 'Admin', '2026-05-05 09:37:00+07', 'Admin', 'GK-0103-492097', 'GK-KARDUS-000544'),
  (546, '545', '4100-1301-Neng kanan T. Papuaabdurahman', '4100', '1301', 'Neng kanan T. Papuaabdurahman', 'GUDANG NENG', 'Titipan', '2026-05-05 09:38:00+07', 'Admin', '2026-05-05 09:38:00+07', 'Admin', 'GK-1301-E76D78', 'GK-KARDUS-000545'),
  (547, '546', '2200-2354-Neng Kanan T. Hidayatuloh.', '2200', '2354', 'Neng Kanan T. Hidayatuloh.', 'GUDANG NENG', 'Titipan', '2026-05-05 09:39:00+07', 'Admin', '2026-05-05 09:39:00+07', 'Admin', 'GK-2354-73CCDF', 'GK-KARDUS-000546'),
  (548, '547', '0100-1265-Neng Kanan T Papua Widya Vania', '0100', '1265', 'Neng Kanan T Papua Widya Vania', 'GUDANG NENG', 'Titipan', '2026-05-05 09:40:00+07', 'Admin', '2026-05-05 09:40:00+07', 'Admin', 'GK-1265-459DD3', 'GK-KARDUS-000547'),
  (549, '548', '2800-3868-Ami T Djohan SM Boen', '2800', '3868', 'Ami T Djohan SM Boen', 'GUDANG AMI', 'Titipan', '2026-05-05 09:41:00+07', 'Admin', '2026-05-05 09:41:00+07', 'Admin', 'GK-3868-6AA393', 'GK-KARDUS-000548'),
  (550, '549', '7900-3900-Paudi Iskandar Hasibuan Shofia', '7900', '3900', 'Paudi Iskandar Hasibuan Shofia', 'GUDANG RANDOM', 'Titipan', '2026-05-05 09:44:00+07', 'Admin', '2026-05-05 09:44:00+07', 'Admin', 'GK-3900-A12E28', 'GK-KARDUS-000549'),
  (551, '550', '2300-3842-Wulan sari T Erlin wulan sari', '2300', '3842', 'Wulan sari T Erlin wulan sari', 'GUDANG ERLIN', 'Titipan', '2026-05-05 09:46:00+07', 'Admin', '2026-05-05 09:46:00+07', 'Admin', 'GK-3842-9590C1', 'GK-KARDUS-000550'),
  (552, '551', '1700-9874-dony anita dony eko janingrum', '1700', '9874', 'dony anita dony eko janingrum', 'GUDANG ANITA', 'Titipan', '2026-05-05 09:47:00+07', 'Admin', '2026-05-05 09:47:00+07', 'Admin', 'GK-9874-5D040E', 'GK-KARDUS-000551'),
  (553, '552', '9200-1218-Neng kanan T. Abdul Adid', '9200', '1218', 'Neng kanan T. Abdul Adid', 'GUDANG NENG', 'Titipan', '2026-05-05 09:48:00+07', 'Admin', '2026-05-05 09:48:00+07', 'Admin', 'GK-1218-53AD0E', 'GK-KARDUS-000552'),
  (554, '553', '0100-2089-Juliyana T. Rina Juliyana', '0100', '2089', 'Juliyana T. Rina Juliyana', 'GUDANG RINA', 'Titipan', '2026-05-05 09:50:00+07', 'Admin', '2026-05-05 09:50:00+07', 'Admin', 'GK-2089-E12695', 'GK-KARDUS-000553'),
  (555, '554', '2900-2478-Roney Steven T Wifa', '2900', '2478', 'Roney Steven T Wifa', 'GUDANG WIFA', 'Titipan', '2026-05-05 09:52:00+07', 'Admin', '2026-05-05 09:52:00+07', 'Admin', 'GK-2478-CA5C18', 'GK-KARDUS-000554'),
  (556, '555', '7200-4064-diyan T bend kiri diyan', '7200', '4064', 'diyan T bend kiri diyan', 'GUDANG', 'Titipan', '2026-05-05 09:52:00+07', 'Admin', '2026-05-05 09:52:00+07', 'Admin', 'GK-4064-546BAD', 'GK-KARDUS-000555'),
  (557, '556', '3200-0653-Neng Kanan T. Riki Suswanto', '3200', '0653', 'Neng Kanan T. Riki Suswanto', 'GUDANG NENG', 'Titipan', '2026-05-05 09:54:00+07', 'Admin', '2026-05-05 09:54:00+07', 'Admin', 'GK-0653-1D80E2', 'GK-KARDUS-000556'),
  (558, '557', '7000-2612-Neng Kanan T. Sunarsih', '7000', '2612', 'Neng Kanan T. Sunarsih', 'GUDANG NENG', 'Titipan', '2026-05-05 09:55:00+07', 'Admin', '2026-05-05 09:55:00+07', 'Admin', 'GK-2612-6D0080', 'GK-KARDUS-000557'),
  (559, '558', '9890-4120-Intan Permatasari T Erlin', '9890', '4120', 'Intan Permatasari T Erlin', 'GUDANG ERLIN', 'Titipan', '2026-05-05 09:56:00+07', 'Admin', '2026-05-05 09:56:00+07', 'Admin', 'GK-4120-529E07', 'GK-KARDUS-000558'),
  (560, '559', '2700-4120-IMMANUEL T CARLES IMMANUEL NATANAEL', '2700', '4120', 'IMMANUEL T CARLES IMMANUEL NATANAEL', 'GUDANG ERLIN', 'Titipan', '2026-05-05 09:57:00+07', 'Admin', '2026-05-05 09:57:00+07', 'Admin', 'GK-4120-FA40B6', 'GK-KARDUS-000559'),
  (561, '560', '8600-0143-AMI APUD GUSMAN S PD', '8600', '0143', 'AMI APUD GUSMAN S PD', 'GUDANG', 'Titipan', '2026-05-20 09:01:00+07', 'Admin', '2026-05-20 09:01:00+07', 'Admin', 'GK-0143-C8B8DA', 'GK-KARDUS-000560'),
  (562, '561', '3800-4813-NADIA AMI NADIA', '3800', '4813', 'NADIA AMI NADIA', 'GUDANG AMI', 'Titipan', '2026-05-20 09:02:00+07', 'Admin', '2026-05-20 09:02:00+07', 'Admin', 'GK-4813-42EF75', 'GK-KARDUS-000561'),
  (563, '562', '3000-4813-SUPARMAN AMI SUPARMAN', '3000', '4813', 'SUPARMAN AMI SUPARMAN', 'GUDANG AMI', 'Titipan', '2026-05-20 09:02:00+07', 'Admin', '2026-05-20 09:02:00+07', 'Admin', 'GK-4813-50DA17', 'GK-KARDUS-000562'),
  (564, '563', '7200-4827-AMI SEPTIAN', '7200', '4827', 'AMI SEPTIAN', 'GUDANG AMI', 'Titipan', '2026-05-20 09:03:00+07', 'Admin', '2026-05-20 09:03:00+07', 'Admin', 'GK-4827-61ABEC', 'GK-KARDUS-000563'),
  (565, '564', '9400-4826-AMI ZAHRA LESTARI', '9400', '4826', 'AMI ZAHRA LESTARI', 'GUDANG AMI', 'Titipan', '2026-05-20 09:04:00+07', 'Admin', '2026-05-20 09:04:00+07', 'Admin', 'GK-4826-8EA866', 'GK-KARDUS-000564'),
  (566, '565', '0000-4828-AMI MALLIKAH BILQIS', '0000', '4828', 'AMI MALLIKAH BILQIS', 'GUDANG AMI', 'Titipan', '2026-05-20 09:04:00+07', 'Admin', '2026-05-20 09:04:00+07', 'Admin', 'GK-4828-551FDD', 'GK-KARDUS-000565'),
  (567, '566', '7800-0740-AMI RASTINI', '7800', '0740', 'AMI RASTINI', 'GUDANG AMI', 'Titipan', '2026-05-20 09:05:00+07', 'Admin', '2026-05-20 09:05:00+07', 'Admin', 'GK-0740-43825A', 'GK-KARDUS-000566'),
  (568, '567', '3500-4404-AMI JENNY OKTAVIANI', '3500', '4404', 'AMI JENNY OKTAVIANI', 'GUDANG AMI', 'Titipan', '2026-05-20 09:07:00+07', 'Admin', '2026-05-20 09:07:00+07', 'Admin', 'GK-4404-071084', 'GK-KARDUS-000567'),
  (569, '568', '1100-4405-AMI HADI SUWITO', '1100', '4405', 'AMI HADI SUWITO', 'GUDANG AMI', 'Titipan', '2026-05-20 09:08:00+07', 'Admin', '2026-05-20 09:08:00+07', 'Admin', 'GK-4405-FD15D1', 'GK-KARDUS-000568'),
  (570, '569', '0500-0231-AMI SOPYAN', '0500', '0231', 'AMI SOPYAN', 'GUDANG AMI', 'Titipan', '2026-05-20 09:09:00+07', 'Admin', '2026-05-20 09:09:00+07', 'Admin', 'GK-0231-5431EA', 'GK-KARDUS-000569'),
  (571, '570', '5000-2779-PUTRI AMI PUTRI CINDY', '5000', '2779', 'PUTRI AMI PUTRI CINDY', 'GUDANG AMI', 'Titipan', '2026-05-20 09:11:00+07', 'Admin', '2026-05-20 09:11:00+07', 'Admin', 'GK-2779-2C8490', 'GK-KARDUS-000570'),
  (572, '571', '3300-4402-aminadia', '3300', '4402', 'aminadia', 'GUDANG AMI', 'Milik Sendiri', '2026-05-20 09:11:00+07', 'Admin', '2026-05-20 09:11:00+07', 'Admin', 'GK-4402-D5A043', 'GK-KARDUS-000571'),
  (573, '572', '2300-0492-AMI SUSANTI', '2300', '0492', 'AMI SUSANTI', 'GUDANG AMI', 'Titipan', '2026-05-20 09:12:00+07', 'Admin', '2026-05-20 09:12:00+07', 'Admin', 'GK-0492-7720B2', 'GK-KARDUS-000572'),
  (574, '573', '9500-4403-AMI SUWARJI', '9500', '4403', 'AMI SUWARJI', 'GUDANG AMI', 'Titipan', '2026-05-20 09:14:00+07', 'Admin', '2026-05-20 09:14:00+07', 'Admin', 'GK-4403-0266EE', 'GK-KARDUS-000573'),
  (575, '575', '3800-4375-ANITA BINTANG DANANG DANANG', '3800', '4375', 'ANITA BINTANG DANANG DANANG', 'GUDANG ANITA', 'Titipan', '2026-05-20 09:17:00+07', 'Admin', '2026-05-20 09:17:00+07', 'Admin', 'GK-4375-B2C04B', 'GK-KARDUS-000575'),
  (576, '576', '2300-4401-AMI SUPARMAN', '2300', '4401', 'AMI SUPARMAN', 'GUDANG AMI', 'Titipan', '2026-05-20 09:18:00+07', 'Admin', '2026-05-20 09:18:00+07', 'Admin', 'GK-4401-7A32E3', 'GK-KARDUS-000576'),
  (577, '577', '4800-0332-AMIKSAM', '4800', '0332', 'AMIKSAM', 'KANTOR', 'Titipan', '2026-05-20 09:19:00+07', 'Admin', '2026-05-20 09:19:00+07', 'Admin', 'GK-0332-990A1E', 'GK-KARDUS-000577'),
  (578, '578', '9100-2317-MIA AUDINA NURHIDAYAH', '9100', '2317', 'MIA AUDINA NURHIDAYAH', 'KANTOR', 'Titipan', '2026-05-20 09:22:00+07', 'Admin', '2026-05-20 09:22:00+07', 'Admin', 'GK-2317-7256F9', 'GK-KARDUS-000578'),
  (579, '579', '3500-0088-ami lina', '3500', '0088', 'ami lina', 'KANTOR', 'Titipan', '2026-05-20 09:23:00+07', 'Admin', '2026-05-20 09:23:00+07', 'Admin', 'GK-0088-F14911', 'GK-KARDUS-000579'),
  (580, '580', '8400-2318-amicevi', '8400', '2318', 'amicevi', 'KANTOR', 'Titipan', '2026-05-20 09:24:00+07', 'Admin', '2026-05-20 09:24:00+07', 'Admin', 'GK-2318-8036DD', 'GK-KARDUS-000580'),
  (581, '581', '5000-1014-PUTRI AMI PUTRI CINDY', '5000', '1014', 'PUTRI AMI PUTRI CINDY', 'GUDANG AMI', 'Titipan', '2026-05-20 09:25:00+07', 'Admin', '2026-05-20 09:25:00+07', 'Admin', 'GK-1014-2C8490', 'GK-KARDUS-000581'),
  (582, '582', '9000-2323-ami erick putra', '9000', '2323', 'ami erick putra', 'KANTOR', 'Milik Sendiri', '2026-05-20 09:25:00+07', 'Admin', '2026-05-20 09:25:00+07', 'Admin', 'GK-2323-FF1AD9', 'GK-KARDUS-000582'),
  (583, '583', '0600-2322-SEPTIAN AMI', '0600', '2322', 'SEPTIAN AMI', 'KANTOR', 'Titipan', '2026-05-20 09:27:00+07', 'Admin', '2026-05-20 09:27:00+07', 'Admin', 'GK-2322-38B157', 'GK-KARDUS-000583'),
  (584, '584', '5000-2316-achmad ami achmad suheli', '5000', '2316', 'achmad ami achmad suheli', 'KANTOR', 'Milik Sendiri', '2026-05-20 09:27:00+07', 'Admin', '2026-05-20 09:27:00+07', 'Admin', 'GK-2316-A31866', 'GK-KARDUS-000584'),
  (585, '585', '7700-0189-ami agung setiawan', '7700', '0189', 'ami agung setiawan', 'KANTOR', 'Titipan', '2026-05-20 09:30:00+07', 'Admin', '2026-05-20 09:30:00+07', 'Admin', 'GK-0189-FA22C4', 'GK-KARDUS-000585'),
  (586, '586', '3500-4793-ami antika sari', '3500', '4793', 'ami antika sari', 'KANTOR', 'Milik Sendiri', '2026-05-20 09:33:00+07', 'Admin', '2026-05-20 09:33:00+07', 'Admin', 'GK-4793-425C57', 'GK-KARDUS-000586'),
  (587, '587', '3400-8675-ANUNSIATA MBEOWAKE WARE', '3400', '8675', 'ANUNSIATA MBEOWAKE WARE', 'KANTOR', 'Titipan', '2026-05-20 09:34:00+07', 'Admin', '2026-05-20 09:34:00+07', 'Admin', 'GK-8675-6FA479', 'GK-KARDUS-000587'),
  (588, '588', '0800-8675-AMIMALIKAH BILQIS', '0800', '8675', 'AMIMALIKAH BILQIS', 'KANTOR', 'Titipan', '2026-05-20 09:35:00+07', 'Admin', '2026-05-20 09:35:00+07', 'Admin', 'GK-8675-F4E056', 'GK-KARDUS-000588'),
  (589, '589', '4600-4931-tjong li mi ratnasari', '4600', '4931', 'tjong li mi ratnasari', 'KANTOR', 'Milik Sendiri', '2026-05-20 09:35:00+07', 'Admin', '2026-05-20 09:35:00+07', 'Admin', 'GK-4931-7AFA01', 'GK-KARDUS-000589'),
  (590, '590', '6500-8696-ami sahirin', '6500', '8696', 'ami sahirin', 'KANTOR', 'Milik Sendiri', '2026-05-20 09:37:00+07', 'Admin', '2026-05-20 09:37:00+07', 'Admin', 'GK-8696-CA23D0', 'GK-KARDUS-000590'),
  (591, '591', '7200-0935-AMIYULIA', '7200', '0935', 'AMIYULIA', 'KANTOR', 'Titipan', '2026-05-20 09:38:00+07', 'Admin', '2026-05-20 09:38:00+07', 'Admin', 'GK-0935-CA1C86', 'GK-KARDUS-000591'),
  (592, '592', '8500-4678-ami kisam', '8500', '4678', 'ami kisam', 'KANTOR', 'Titipan', '2026-05-20 09:38:00+07', 'Admin', '2026-05-20 09:38:00+07', 'Admin', 'GK-4678-82C3CE', 'GK-KARDUS-000592'),
  (593, '593', '1900-0898-ami susanti', '1900', '0898', 'ami susanti', 'KANTOR', 'Milik Sendiri', '2026-05-20 09:45:00+07', 'Admin', '2026-05-20 09:45:00+07', 'Admin', 'GK-0898-7720B2', 'GK-KARDUS-000593'),
  (594, '594', '8300-0886-rasto by ami rasto hartono', '8300', '0886', 'rasto by ami rasto hartono', 'KANTOR', 'Titipan', '2026-05-20 09:47:00+07', 'Admin', '2026-05-20 09:47:00+07', 'Admin', 'GK-0886-E1C3F9', 'GK-KARDUS-000594'),
  (595, '595', '3500-8186-AMI ANTIKA SARI', '3500', '8186', 'AMI ANTIKA SARI', 'GUDANG AMI', 'Titipan', '2026-05-20 09:47:00+07', 'Admin', '2026-05-20 09:47:00+07', 'Admin', 'GK-8186-425C57', 'GK-KARDUS-000595'),
  (596, '596', '7132-1741-Mita T WIFA AMita karya', '7132', '1741', 'Mita T WIFA AMita karya', 'GUDANG', 'Titipan', '2026-05-28 11:36:00+07', 'Admin', '2026-05-28 11:36:00+07', 'Admin', 'GK-1741-5EDFB0', 'GK-KARDUS-000596'),
  (597, '597', '1000-1678-jeffry dwi a', '1000', '1678', 'jeffry dwi a', 'GUDANG JEFFRY', 'Titipan', '2026-05-30 09:13:00+07', 'Admin', '2026-05-30 09:13:00+07', 'Admin', 'GK-1678-7B370D', 'GK-KARDUS-000597'),
  (598, '598', '2500-1661-jeffry bshofia husna', '2500', '1661', 'jeffry bshofia husna', 'GUDANG JEFFRY', 'Titipan', '2026-05-30 09:15:00+07', 'Admin', '2026-05-30 09:15:00+07', 'Admin', 'GK-1661-953F17', 'GK-KARDUS-000598'),
  (599, '599', '0700-2802-ilham anita ilham kurniawan', '0700', '2802', 'ilham anita ilham kurniawan', 'GUDANG ANITA', 'Titipan', '2026-05-30 09:16:00+07', 'Admin', '2026-05-30 09:16:00+07', 'Admin', 'GK-2802-60FB37', 'GK-KARDUS-000599'),
  (600, '600', '3400-0012-stevannystevani y peea', '3400', '0012', 'stevannystevani y peea', 'GUDANG STEVANI', 'Titipan', '2026-05-30 09:17:00+07', 'Admin', '2026-05-30 09:17:00+07', 'Admin', 'GK-0012-F8DB76', 'GK-KARDUS-000600'),
  (601, '601', '1000-9383-Neng Kanan T PAPUA UNDANG SUKARSA', '1000', '9383', 'Neng Kanan T PAPUA UNDANG SUKARSA', 'GUDANG NENG', 'Titipan', '2026-05-30 09:18:00+07', 'Admin', '2026-05-30 09:18:00+07', 'Admin', 'GK-9383-BC5634', 'GK-KARDUS-000601'),
  (602, '602', '2700-9521-NENG KANAN T PAPUA NUNU NUHDIN', '2700', '9521', 'NENG KANAN T PAPUA NUNU NUHDIN', 'GUDANG NENG', 'Titipan', '2026-05-30 09:21:00+07', 'Admin', '2026-05-30 09:21:00+07', 'Admin', 'GK-9521-2C772F', 'GK-KARDUS-000602'),
  (603, '603', '8600-0827-NENG KANNA T PAPUA IYAH SOPIYAH', '8600', '0827', 'NENG KANNA T PAPUA IYAH SOPIYAH', 'GUDANG NENG', 'Titipan', '2026-05-30 09:22:00+07', 'Admin', '2026-05-30 09:22:00+07', 'Admin', 'GK-0827-0255C1', 'GK-KARDUS-000603'),
  (604, '604', '5700-1396-indra anita indra lesmana', '5700', '1396', 'indra anita indra lesmana', 'GUDANG ANITA', 'Titipan', '2026-05-30 09:23:00+07', 'Admin', '2026-05-30 09:23:00+07', 'Admin', 'GK-1396-2B4366', 'GK-KARDUS-000604'),
  (605, '605', '3000-9407-ABDUL TEAM NENG ABDUL ADID', '3000', '9407', 'ABDUL TEAM NENG ABDUL ADID', 'GUDANG NENG', 'Titipan', '2026-05-30 09:24:00+07', 'Admin', '2026-05-30 09:24:00+07', 'Admin', 'GK-9407-2BAB65', 'GK-KARDUS-000605'),
  (606, '606', '8600-9608-neng kanan t papua iyah sopiyah', '8600', '9608', 'neng kanan t papua iyah sopiyah', 'GUDANG NENG', 'Titipan', '2026-05-30 09:25:00+07', 'Admin', '2026-05-30 09:25:00+07', 'Admin', 'GK-9608-1A781B', 'GK-KARDUS-000606'),
  (607, '607', '2000-9457-NENG KANAN T PAPUA RIKI ARIYANTO', '2000', '9457', 'NENG KANAN T PAPUA RIKI ARIYANTO', 'GUDANG NENG', 'Titipan', '2026-05-30 09:26:00+07', 'Admin', '2026-05-30 09:26:00+07', 'Admin', 'GK-9457-6369D3', 'GK-KARDUS-000607'),
  (608, '608', '9200-0025-dinda anita dinda simaung', '9200', '0025', 'dinda anita dinda simaung', 'GUDANG ANITA', 'Titipan', '2026-05-30 09:28:00+07', 'Admin', '2026-05-30 09:28:00+07', 'Admin', 'GK-0025-DD41DB', 'GK-KARDUS-000608'),
  (609, '609', '3500-9342-NENG KANAN T PAPUA NOVIE MASAYU AZAN', '3500', '9342', 'NENG KANAN T PAPUA NOVIE MASAYU AZAN', 'GUDANG NENG', 'Titipan', '2026-05-30 09:34:00+07', 'Admin', '2026-05-30 09:34:00+07', 'Admin', 'GK-9342-089C94', 'GK-KARDUS-000609'),
  (610, '610', '2400-9598-NENG KANAN T PAPUA LISNA FADILAH YUSTIANI', '2400', '9598', 'NENG KANAN T PAPUA LISNA FADILAH YUSTIANI', 'GUDANG NENG', 'Titipan', '2026-05-30 09:35:00+07', 'Admin', '2026-05-30 09:35:00+07', 'Admin', 'GK-9598-7FFFEE', 'GK-KARDUS-000610'),
  (611, '611', '2900-9409-NENG KANAN T PAPUA NINING YUNINGSIH', '2900', '9409', 'NENG KANAN T PAPUA NINING YUNINGSIH', 'GUDANG NENG', 'Titipan', '2026-05-30 09:36:00+07', 'Admin', '2026-05-30 09:36:00+07', 'Admin', 'GK-9409-003785', 'GK-KARDUS-000611'),
  (612, '612', '4500-9573-NENG KANAN T PAPUA EVA MIRAWATI', '4500', '9573', 'NENG KANAN T PAPUA EVA MIRAWATI', 'GUDANG NENG', 'Titipan', '2026-05-30 09:37:00+07', 'Admin', '2026-05-30 09:37:00+07', 'Admin', 'GK-9573-A9464E', 'GK-KARDUS-000612'),
  (613, '613', '3000-9407-ABDUL TEAM NENG ABDUL ADID', '3000', '9407', 'ABDUL TEAM NENG ABDUL ADID', 'GUDANG NENG', 'Titipan', '2026-05-30 09:40:00+07', 'Admin', '2026-05-30 09:40:00+07', 'Admin', 'GK-9407-2BAB65', 'GK-KARDUS-000613'),
  (614, '614', '1800-9350-NENG KANAN T PAPUA ASTUTI DEWI', '1800', '9350', 'NENG KANAN T PAPUA ASTUTI DEWI', 'GUDANG NENG', 'Titipan', '2026-05-30 09:40:00+07', 'Admin', '2026-05-30 09:40:00+07', 'Admin', 'GK-9350-950F0D', 'GK-KARDUS-000614'),
  (615, '615', '7100-7663-NENG KANNA T PAPUA HERI KUSWANTO', '7100', '7663', 'NENG KANNA T PAPUA HERI KUSWANTO', 'GUDANG NENG', 'Titipan', '2026-05-30 09:41:00+07', 'Admin', '2026-05-30 09:41:00+07', 'Admin', 'GK-7663-3536D6', 'GK-KARDUS-000615'),
  (616, '616', '1400-9505-NENG KANAN T PAPUA SARIPAH', '1400', '9505', 'NENG KANAN T PAPUA SARIPAH', 'GUDANG NENG', 'Titipan', '2026-05-30 09:42:00+07', 'Admin', '2026-05-30 09:42:00+07', 'Admin', 'GK-9505-A83F1A', 'GK-KARDUS-000616'),
  (617, '617', '4000-9421-NENG KANAN T PAPUA RUSMINI', '4000', '9421', 'NENG KANAN T PAPUA RUSMINI', 'GUDANG NENG', 'Titipan', '2026-05-30 09:44:00+07', 'Admin', '2026-05-30 09:44:00+07', 'Admin', 'GK-9421-0CE773', 'GK-KARDUS-000617'),
  (618, '618', '9800-9595-NENG KANAN T PAPUA BIRIN', '9800', '9595', 'NENG KANAN T PAPUA BIRIN', 'GUDANG NENG', 'Titipan', '2026-05-30 09:45:00+07', 'Admin', '2026-05-30 09:45:00+07', 'Admin', 'GK-9595-009A4F', 'GK-KARDUS-000618'),
  (619, '619', '8600-9608-NENG KANAN T PAPUA IYAH SOPIYAH', '8600', '9608', 'NENG KANAN T PAPUA IYAH SOPIYAH', 'GUDANG NENG', 'Titipan', '2026-05-30 09:45:00+07', 'Admin', '2026-05-30 09:45:00+07', 'Admin', 'GK-9608-1A781B', 'GK-KARDUS-000619'),
  (620, '620', '3000-1186-NENG KANAN T PAPUA ROSMA ROSTIKA', '3000', '1186', 'NENG KANAN T PAPUA ROSMA ROSTIKA', 'GUDANG NENG', 'Titipan', '2026-06-07 13:28:00+07', 'Admin', '2026-06-07 13:28:00+07', 'Admin', 'GK-1186-A60B0C', 'GK-KARDUS-000620'),
  (621, '621', '1700-2796-YUNUS ANITA YUNUS', '1700', '2796', 'YUNUS ANITA YUNUS', 'GUDANG ANITA', 'Titipan', '2026-06-07 13:31:00+07', 'Admin', '2026-06-07 13:31:00+07', 'Admin', 'GK-2796-AD0DD8', 'GK-KARDUS-000621'),
  (622, '622', '1400-1092-NENG KANAN T PAPUA YATI', '1400', '1092', 'NENG KANAN T PAPUA YATI', 'GUDANG NENG', 'Titipan', '2026-06-07 13:31:00+07', 'Admin', '2026-06-07 13:31:00+07', 'Admin', 'GK-1092-9FD7C9', 'GK-KARDUS-000622'),
  (623, '623', '4900-0973-NENG KANAN T PAPUA AYU LESTARI', '4900', '0973', 'NENG KANAN T PAPUA AYU LESTARI', 'GUDANG NENG', 'Titipan', '2026-06-07 13:32:00+07', 'Admin', '2026-06-07 13:32:00+07', 'Admin', 'GK-0973-3DAD12', 'GK-KARDUS-000623'),
  (624, '624', '9000-0017-NENG KANAN T PAPUA ADIT SURYA', '9000', '0017', 'NENG KANAN T PAPUA ADIT SURYA', 'GUDANG NENG', 'Titipan', '2026-06-07 13:32:00+07', 'Admin', '2026-06-07 13:32:00+07', 'Admin', 'GK-0017-B000AC', 'GK-KARDUS-000624'),
  (625, '625', '2100-0031-NENG KANAN T PAPUA ANNISA NURAWWALIYAH', '2100', '0031', 'NENG KANAN T PAPUA ANNISA NURAWWALIYAH', 'GUDANG NENG', 'Titipan', '2026-06-07 13:33:00+07', 'Admin', '2026-06-07 13:33:00+07', 'Admin', 'GK-0031-C759BA', 'GK-KARDUS-000625'),
  (626, '626', '2100-0031-NENG KANAN T PAPUA ANNISA NURAWWALIYAH', '2100', '0031', 'NENG KANAN T PAPUA ANNISA NURAWWALIYAH', 'GUDANG NENG', 'Titipan', '2026-06-07 13:33:00+07', 'Admin', '2026-06-07 13:33:00+07', 'Admin', 'GK-0031-C759BA', 'GK-KARDUS-000626'),
  (627, '626', '2100-0031-NENG KANAN T PAPUA ANNISA NURAWWALIYAH', '2100', '0031', 'NENG KANAN T PAPUA ANNISA NURAWWALIYAH', 'GUDANG NENG', 'Titipan', '2026-06-07 13:33:00+07', 'Admin', '2026-06-07 13:33:00+07', 'Admin', 'GK-0031-C759BA', 'GK-KARDUS-000626'),
  (628, '627', '2100-0031-NENG KANAN T PAPUA ANNISA NURAWWALIYAH', '2100', '0031', 'NENG KANAN T PAPUA ANNISA NURAWWALIYAH', 'GUDANG NENG', 'Titipan', '2026-06-07 13:34:00+07', 'Admin', '2026-06-07 13:34:00+07', 'Admin', 'GK-0031-C759BA', 'GK-KARDUS-000627'),
  (629, '628', '4600-2012-NENG KANNA T PAPUA ANNISA NURAWWALIYAH', '4600', '2012', 'NENG KANNA T PAPUA ANNISA NURAWWALIYAH', 'GUDANG NENG', 'Titipan', '2026-06-07 13:34:00+07', 'Admin', '2026-06-07 13:34:00+07', 'Admin', 'GK-2012-E6F220', 'GK-KARDUS-000628'),
  (630, '629', '4200-1664-NENG KANAN T PAPUA BADRIAH', '4200', '1664', 'NENG KANAN T PAPUA BADRIAH', 'GUDANG NENG', 'Titipan', '2026-06-07 13:35:00+07', 'Admin', '2026-06-07 13:35:00+07', 'Admin', 'GK-1664-98B68B', 'GK-KARDUS-000629'),
  (631, '630', '8600-1939-NENG KANAN T PAPUA HERI KUSWANTO', '8600', '1939', 'NENG KANAN T PAPUA HERI KUSWANTO', 'GUDANG NENG', 'Titipan', '2026-06-07 13:35:00+07', 'Admin', '2026-06-07 13:35:00+07', 'Admin', 'GK-1939-7800C6', 'GK-KARDUS-000630'),
  (632, '631', '4800-1207-NENG KANAN T PAPUA ARUNI HIDAYAT SURYA', '4800', '1207', 'NENG KANAN T PAPUA ARUNI HIDAYAT SURYA', 'GUDANG NENG', 'Titipan', '2026-06-07 13:36:00+07', 'Admin', '2026-06-07 13:36:00+07', 'Admin', 'GK-1207-4B53CE', 'GK-KARDUS-000631'),
  (633, '632', '0900-1407-EDI ANITAEDI SAPTONO', '0900', '1407', 'EDI ANITAEDI SAPTONO', 'GUDANG ANITA', 'Titipan', '2026-06-07 13:37:00+07', 'Admin', '2026-06-07 13:37:00+07', 'Admin', 'GK-1407-0C2909', 'GK-KARDUS-000632'),
  (634, '633', '5100-0046-NENG KANAN T PAPUA IHAT SOLIHAT', '5100', '0046', 'NENG KANAN T PAPUA IHAT SOLIHAT', 'GUDANG NENG', 'Titipan', '2026-06-07 13:37:00+07', 'Admin', '2026-06-07 13:37:00+07', 'Admin', 'GK-0046-C1432F', 'GK-KARDUS-000633'),
  (635, '634', '4400-1705-SETEPEN T WIFASETEPEN', '4400', '1705', 'SETEPEN T WIFASETEPEN', 'GUDANG WIFA', 'Titipan', '2026-06-07 13:38:00+07', 'Admin', '2026-06-07 13:38:00+07', 'Admin', 'GK-1705-CA0F89', 'GK-KARDUS-000634'),
  (636, '635', '6000-0903-GILANG ANITA GILANG RAMADHAN', '6000', '0903', 'GILANG ANITA GILANG RAMADHAN', 'GUDANG ANITA', 'Titipan', '2026-06-07 13:38:00+07', 'Admin', '2026-06-07 13:38:00+07', 'Admin', 'GK-0903-F70AAF', 'GK-KARDUS-000635'),
  (637, '636', '1200-1193-NENG KANAN T P--APUA RATU PERMATA SARI', '1200', '1193', 'NENG KANAN T P--APUA RATU PERMATA SARI', 'GUDANG NENG', 'Titipan', '2026-06-07 13:39:00+07', 'Admin', '2026-06-07 13:39:00+07', 'Admin', 'GK-1193-38BA47', 'GK-KARDUS-000636'),
  (638, '637', '8300-0886-RASTO BY AMI RASTO BUDI', '8300', '0886', 'RASTO BY AMI RASTO BUDI', 'KANTOR', 'Titipan', '2026-06-07 13:40:00+07', 'Admin', '2026-06-07 13:40:00+07', 'Admin', 'GK-0886-FFA435', 'GK-KARDUS-000637'),
  (639, '638', '4300-0236-HERIYANTO WIFA HERIYANTO', '4300', '0236', 'HERIYANTO WIFA HERIYANTO', 'GUDANG WIFA', 'Titipan', '2026-06-07 13:41:00+07', 'Admin', '2026-06-07 13:41:00+07', 'Admin', 'GK-0236-37654F', 'GK-KARDUS-000638'),
  (640, '639', '7200-0935-AMI YULIA', '7200', '0935', 'AMI YULIA', 'KANTOR', 'Titipan', '2026-06-07 13:41:00+07', 'Admin', '2026-06-07 13:41:00+07', 'Admin', 'GK-0935-7AED5F', 'GK-KARDUS-000639'),
  (641, '640', '3900-0649-NENG KANAN T PAPUA EVA MIRAWATI', '3900', '0649', 'NENG KANAN T PAPUA EVA MIRAWATI', 'GUDANG NENG', 'Titipan', '2026-06-07 13:42:00+07', 'Admin', '2026-06-07 13:42:00+07', 'Admin', 'GK-0649-A9464E', 'GK-KARDUS-000640'),
  (642, '641', '6300-1597-NENG KANAN T PAPUA IPAH SARIPAH', '6300', '1597', 'NENG KANAN T PAPUA IPAH SARIPAH', 'GUDANG NENG', 'Titipan', '2026-06-07 13:43:00+07', 'Admin', '2026-06-07 13:43:00+07', 'Admin', 'GK-1597-1AF885', 'GK-KARDUS-000641'),
  (643, '642', '6400-1428-NENG KANAN T PAPUA IHSAN IFTIKAR', '6400', '1428', 'NENG KANAN T PAPUA IHSAN IFTIKAR', 'GUDANG NENG', 'Titipan', '2026-06-07 13:43:00+07', 'Admin', '2026-06-07 13:43:00+07', 'Admin', 'GK-1428-910D6C', 'GK-KARDUS-000642'),
  (644, '643', '9400-1242-NENG KANAN T PAPUA NOVIE MASAYU', '9400', '1242', 'NENG KANAN T PAPUA NOVIE MASAYU', 'GUDANG NENG', 'Titipan', '2026-06-07 13:44:00+07', 'Admin', '2026-06-07 13:44:00+07', 'Admin', 'GK-1242-D35AD4', 'GK-KARDUS-000643'),
  (645, '644', '9400-1242-NENG KANAN T PAPUA NOVIE MASAYU', '9400', '1242', 'NENG KANAN T PAPUA NOVIE MASAYU', 'GUDANG NENG', 'Titipan', '2026-06-07 13:44:00+07', 'Admin', '2026-06-07 13:44:00+07', 'Admin', 'GK-1242-D35AD4', 'GK-KARDUS-000644'),
  (646, '645', '0000-0042-NENG KANAN T PAPUA UNDANG SUKARSA', '0000', '0042', 'NENG KANAN T PAPUA UNDANG SUKARSA', 'GUDANG NENG', 'Titipan', '2026-06-07 13:44:00+07', 'Admin', '2026-06-07 13:44:00+07', 'Admin', 'GK-0042-BC5634', 'GK-KARDUS-000645'),
  (647, '646', '8000-2391-NENG KANAN T PAPUA ASTUTI DEWI', '8000', '2391', 'NENG KANAN T PAPUA ASTUTI DEWI', 'GUDANG NENG', 'Titipan', '2026-06-07 13:45:00+07', 'Admin', '2026-06-07 13:45:00+07', 'Admin', 'GK-2391-950F0D', 'GK-KARDUS-000646'),
  (648, '647', '8000-0917-DENI ANITA DENI', '8000', '0917', 'DENI ANITA DENI', 'GUDANG ANITA', 'Titipan', '2026-06-07 13:45:00+07', 'Admin', '2026-06-07 13:45:00+07', 'Admin', 'GK-0917-CDBEAA', 'GK-KARDUS-000647'),
  (649, '648', '0900-0686-NENG KANAN T PAPUA EUIS INDASIAH', '0900', '0686', 'NENG KANAN T PAPUA EUIS INDASIAH', 'GUDANG NENG', 'Titipan', '2026-06-07 13:46:00+07', 'Admin', '2026-06-07 13:46:00+07', 'Admin', 'GK-0686-19916D', 'GK-KARDUS-000648'),
  (650, '649', '3500-1679-YOHANES WIFA YOHANES', '3500', '1679', 'YOHANES WIFA YOHANES', 'GUDANG WIFA', 'Titipan', '2026-06-07 13:47:00+07', 'Admin', '2026-06-07 13:47:00+07', 'Admin', 'GK-1679-51580A', 'GK-KARDUS-000649'),
  (651, '650', '3100-0215-NENG KANAN T PAPUA ASUM SUMIIATI', '3100', '0215', 'NENG KANAN T PAPUA ASUM SUMIIATI', 'GUDANG NENG', 'Titipan', '2026-06-07 13:47:00+07', 'Admin', '2026-06-07 13:47:00+07', 'Admin', 'GK-0215-386871', 'GK-KARDUS-000650'),
  (652, '651', '0600-1036-NENG KANAN T PAPUA RIKI ARIYANTO', '0600', '1036', 'NENG KANAN T PAPUA RIKI ARIYANTO', 'GUDANG NENG', 'Titipan', '2026-06-07 13:48:00+07', 'Admin', '2026-06-07 13:48:00+07', 'Admin', 'GK-1036-6369D3', 'GK-KARDUS-000651'),
  (653, '652', '4500-1977-NENG KANAN T PAPUA EVA MIRAWATI', '4500', '1977', 'NENG KANAN T PAPUA EVA MIRAWATI', 'GUDANG NENG', 'Titipan', '2026-06-07 13:48:00+07', 'Admin', '2026-06-07 13:48:00+07', 'Admin', 'GK-1977-A9464E', 'GK-KARDUS-000652'),
  (654, '653', '3500-1504-NENG KANAN T PAPUA ASTUTI DEWI', '3500', '1504', 'NENG KANAN T PAPUA ASTUTI DEWI', 'GUDANG NENG', 'Titipan', '2026-06-07 13:49:00+07', 'Admin', '2026-06-07 13:49:00+07', 'Admin', 'GK-1504-950F0D', 'GK-KARDUS-000653'),
  (655, '654', '5300-2527-NENG KANAN T PAPUA IRFAN', '5300', '2527', 'NENG KANAN T PAPUA IRFAN', 'GUDANG NENG', 'Titipan', '2026-06-07 13:49:00+07', 'Admin', '2026-06-07 13:49:00+07', 'Admin', 'GK-2527-483DEF', 'GK-KARDUS-000654'),
  (656, '655', '8200-9820-NENG KANAN T PAPUA ARFATHAN MALIK', '8200', '9820', 'NENG KANAN T PAPUA ARFATHAN MALIK', 'GUDANG NENG', 'Titipan', '2026-06-07 13:50:00+07', 'Admin', '2026-06-07 13:50:00+07', 'Admin', 'GK-9820-7E705B', 'GK-KARDUS-000655'),
  (657, '656', '6300-1385-SILWANUS TABANA T MARTAWANUS TABANA', '6300', '1385', 'SILWANUS TABANA T MARTAWANUS TABANA', 'GUDANG RANDOM', 'Titipan', '2026-06-07 13:50:00+07', 'Admin', '2026-06-07 13:50:00+07', 'Admin', 'GK-1385-4D3FBC', 'GK-KARDUS-000656'),
  (658, '657', '6900-0201-INIEDWATI T KANNA RAISHA INIEDWATI', '6900', '0201', 'INIEDWATI T KANNA RAISHA INIEDWATI', 'GUDANG NENG', 'Titipan', '2026-06-07 13:51:00+07', 'Admin', '2026-06-07 13:51:00+07', 'Admin', 'GK-0201-14140F', 'GK-KARDUS-000657')
on conflict (import_row_no) do update set
  client_id = excluded.client_id,
  label = excluded.label,
  nomor_pesanan = excluded.nomor_pesanan,
  nomor_id = excluded.nomor_id,
  owner_name = excluded.owner_name,
  location = excluded.location,
  type = excluded.type,
  created_at = excluded.created_at,
  created_by = excluded.created_by,
  updated_at = excluded.updated_at,
  updated_by = excluded.updated_by,
  mapped_owner_code = excluded.mapped_owner_code,
  mapped_id_box = excluded.mapped_id_box,
  imported_at = now();

insert into public.client_gudangku_inventory_raw(
  import_row_no,
  client_id,
  type,
  date,
  kardus_id,
  mapped_id_box,
  product_name,
  mapped_sku,
  qty,
  price,
  buyer_name,
  transfer_to,
  transfer_amount,
  performed_by,
  notes
)
values
  (1, '1', 'MASUK', '2026-04-29 07:43:00+07', '1', 'GK-KARDUS-000001', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (2, '2', 'MASUK', '2026-04-29 07:45:00+07', '2', 'GK-KARDUS-000002', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (3, '3', 'MASUK', '2026-04-29 07:50:00+07', '7', 'GK-KARDUS-000007', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (4, '4', 'MASUK', '2026-04-29 07:52:00+07', '9', 'GK-KARDUS-000009', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (5, '5', 'MASUK', '2026-04-29 07:55:00+07', '11', 'GK-KARDUS-000011', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (6, '6', 'MASUK', '2026-04-29 07:56:00+07', '12', 'GK-KARDUS-000012', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (7, '7', 'MASUK', '2026-04-29 07:58:00+07', '13', 'GK-KARDUS-000013', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (8, '8', 'MASUK', '2026-04-29 08:00:00+07', '14', 'GK-KARDUS-000014', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (9, '9', 'MASUK', '2026-04-29 08:05:00+07', '16', 'GK-KARDUS-000016', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (10, '10', 'MASUK', '2026-04-29 08:06:00+07', '17', 'GK-KARDUS-000017', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (11, '11', 'MASUK', '2026-04-29 08:10:00+07', '20', 'GK-KARDUS-000020', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (12, '12', 'MASUK', '2026-04-29 08:12:00+07', '21', 'GK-KARDUS-000021', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (13, '13', 'MASUK', '2026-04-29 08:14:00+07', '23', 'GK-KARDUS-000023', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (14, '14', 'MASUK', '2026-04-29 08:18:00+07', '26', 'GK-KARDUS-000026', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (15, '15', 'MASUK', '2026-04-29 08:21:00+07', '28', 'GK-KARDUS-000028', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (16, '16', 'MASUK', '2026-04-29 08:22:00+07', '29', 'GK-KARDUS-000029', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (17, '17', 'MASUK', '2026-04-29 08:25:00+07', '32', 'GK-KARDUS-000032', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (18, '18', 'MASUK', '2026-04-29 08:27:00+07', '33', 'GK-KARDUS-000033', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (19, '19', 'MASUK', '2026-04-29 08:29:00+07', '35', 'GK-KARDUS-000035', 'Atomy Hongsamdan Red Ginseng', 'ATOMY-HONGSAMDAN-RED-GINSENG', 1, 0, '', '', 0, 'Admin', ''),
  (20, '20', 'MASUK', '2026-04-29 08:29:00+07', '35', 'GK-KARDUS-000035', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (21, '21', 'MASUK', '2026-04-29 08:29:00+07', '35', 'GK-KARDUS-000035', 'Atomy Probiotics 10+', 'ATOMY-PROBIOTICS-10', 1, 0, '', '', 0, 'Admin', ''),
  (22, '22', 'MASUK', '2026-04-29 08:29:00+07', '35', 'GK-KARDUS-000035', 'Atomy Color Food Vitamin C', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 0, '', '', 0, 'Admin', ''),
  (23, '23', 'MASUK', '2026-04-29 08:31:00+07', '36', 'GK-KARDUS-000036', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (24, '24', 'MASUK', '2026-04-29 08:36:00+07', '40', 'GK-KARDUS-000040', 'Atomy Paket Ramadhan Care', 'ATOMY-PAKET-RAMADHAN-CARE', 1, 0, '', '', 0, 'Admin', ''),
  (25, '25', 'MASUK', '2026-04-29 08:49:00+07', '43', 'GK-KARDUS-000043', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (26, '26', 'MASUK', '2026-04-29 08:49:00+07', '43', 'GK-KARDUS-000043', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (27, '27', 'MASUK', '2026-04-29 08:52:00+07', '46', 'GK-KARDUS-000046', 'Atomy Paket Ramadhan Care', 'ATOMY-PAKET-RAMADHAN-CARE', 1, 0, '', '', 0, 'Admin', ''),
  (28, '28', 'MASUK', '2026-04-29 08:57:00+07', '53', 'GK-KARDUS-000053', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (29, '29', 'MASUK', '2026-04-29 08:59:00+07', '56', 'GK-KARDUS-000056', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (30, '30', 'MASUK', '2026-04-29 09:02:00+07', '59', 'GK-KARDUS-000059', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (31, '31', 'MASUK', '2026-04-29 09:03:00+07', '60', 'GK-KARDUS-000060', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (32, '32', 'MASUK', '2026-04-29 09:04:00+07', '62', 'GK-KARDUS-000062', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (33, '33', 'MASUK', '2026-04-29 09:06:00+07', '64', 'GK-KARDUS-000064', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (34, '34', 'MASUK', '2026-04-29 09:06:00+07', '65', 'GK-KARDUS-000065', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (35, '35', 'MASUK', '2026-04-29 09:10:00+07', '68', 'GK-KARDUS-000068', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (36, '36', 'MASUK', '2026-04-29 09:11:00+07', '67', 'GK-KARDUS-000067', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (37, '37', 'MASUK', '2026-04-29 09:12:00+07', '70', 'GK-KARDUS-000070', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (38, '38', 'MASUK', '2026-04-29 09:13:00+07', '72', 'GK-KARDUS-000072', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (39, '39', 'MASUK', '2026-04-29 09:14:00+07', '73', 'GK-KARDUS-000073', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (40, '40', 'MASUK', '2026-04-29 09:17:00+07', '77', 'GK-KARDUS-000077', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (41, '41', 'MASUK', '2026-04-29 09:18:00+07', '78', 'GK-KARDUS-000078', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (42, '42', 'MASUK', '2026-04-29 09:24:00+07', '84', 'GK-KARDUS-000084', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (43, '43', 'MASUK', '2026-04-29 09:25:00+07', '85', 'GK-KARDUS-000085', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (44, '44', 'MASUK', '2026-04-29 09:25:00+07', '85', 'GK-KARDUS-000085', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (45, '45', 'MASUK', '2026-04-29 09:26:00+07', '85', 'GK-KARDUS-000085', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 2, 0, '', '', 0, 'Admin', ''),
  (46, '46', 'MASUK', '2026-04-29 09:26:00+07', '85', 'GK-KARDUS-000085', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 2, 0, '', '', 0, 'Admin', ''),
  (47, '47', 'MASUK', '2026-04-29 09:26:00+07', '86', 'GK-KARDUS-000086', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (48, '48', 'MASUK', '2026-04-29 09:40:00+07', '87', 'GK-KARDUS-000087', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (49, '49', 'MASUK', '2026-04-29 09:43:00+07', '88', 'GK-KARDUS-000088', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (50, '50', 'MASUK', '2026-04-29 09:54:00+07', '96', 'GK-KARDUS-000096', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (51, '51', 'MASUK', '2026-04-29 09:55:00+07', '97', 'GK-KARDUS-000097', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (52, '52', 'MASUK', '2026-04-29 09:56:00+07', '98', 'GK-KARDUS-000098', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (53, '53', 'MASUK', '2026-04-29 09:59:00+07', '102', 'GK-KARDUS-000102', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (54, '54', 'MASUK', '2026-04-29 10:00:00+07', '103', 'GK-KARDUS-000103', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (55, '55', 'MASUK', '2026-04-29 10:01:00+07', '105', 'GK-KARDUS-000105', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (56, '56', 'MASUK', '2026-04-29 10:04:00+07', '108', 'GK-KARDUS-000108', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (57, '57', 'MASUK', '2026-04-29 10:04:00+07', '108', 'GK-KARDUS-000108', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (58, '58', 'MASUK', '2026-04-29 10:05:00+07', '109', 'GK-KARDUS-000109', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (59, '59', 'MASUK', '2026-04-29 10:07:00+07', '111', 'GK-KARDUS-000111', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (60, '60', 'MASUK', '2026-04-29 10:08:00+07', '112', 'GK-KARDUS-000112', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (61, '61', 'MASUK', '2026-04-29 10:09:00+07', '113', 'GK-KARDUS-000113', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (62, '62', 'MASUK', '2026-04-29 10:10:00+07', '114', 'GK-KARDUS-000114', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (63, '63', 'MASUK', '2026-04-29 10:12:00+07', '115', 'GK-KARDUS-000115', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (64, '64', 'MASUK', '2026-04-29 10:13:00+07', '117', 'GK-KARDUS-000117', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (65, '65', 'MASUK', '2026-04-29 10:16:00+07', '119', 'GK-KARDUS-000119', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (66, '66', 'MASUK', '2026-04-29 10:17:00+07', '121', 'GK-KARDUS-000121', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (67, '67', 'MASUK', '2026-04-29 10:19:00+07', '122', 'GK-KARDUS-000122', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (68, '68', 'MASUK', '2026-04-29 10:20:00+07', '122', 'GK-KARDUS-000122', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (69, '69', 'MASUK', '2026-04-29 10:20:00+07', '124', 'GK-KARDUS-000124', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (70, '70', 'MASUK', '2026-04-29 10:20:00+07', '125', 'GK-KARDUS-000125', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (71, '71', 'MASUK', '2026-04-29 10:22:00+07', '127', 'GK-KARDUS-000127', 'Atomy Absolute Lotion', 'ATOMY-ABSOLUTE-LOTION', 1, 0, '', '', 0, 'Admin', ''),
  (72, '72', 'MASUK', '2026-04-29 10:25:00+07', '129', 'GK-KARDUS-000129', 'Atomy Absolute Lotion', 'ATOMY-ABSOLUTE-LOTION', 1, 0, '', '', 0, 'Admin', ''),
  (73, '73', 'MASUK', '2026-04-29 10:25:00+07', '126', 'GK-KARDUS-000126', 'Atomy Sunscreen White', 'ATOMY-SUNSCREEN-WHITE', 1, 0, '', '', 0, 'Admin', ''),
  (74, '74', 'MASUK', '2026-04-29 10:26:00+07', '130', 'GK-KARDUS-000130', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (75, '75', 'MASUK', '2026-04-29 10:27:00+07', '130', 'GK-KARDUS-000130', 'Atomy Absolute Eye-complex', 'ATOMY-ABSOLUTE-EYE-COMPLEX', 1, 0, '', '', 0, 'Admin', ''),
  (76, '76', 'MASUK', '2026-04-29 10:27:00+07', '126', 'GK-KARDUS-000126', 'Atomy Cafe Arabica', 'ATOMY-CAFE-ARABICA', 1, 0, '', '', 0, 'Admin', ''),
  (77, '77', 'MASUK', '2026-04-29 10:28:00+07', '131', 'GK-KARDUS-000131', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (78, '78', 'MASUK', '2026-04-29 10:29:00+07', '132', 'GK-KARDUS-000132', 'Atomy Herbal Hair Conditioner', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 0, '', '', 0, 'Admin', ''),
  (79, '79', 'MASUK', '2026-04-29 10:30:00+07', '132', 'GK-KARDUS-000132', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (80, '80', 'MASUK', '2026-04-29 10:30:00+07', '132', 'GK-KARDUS-000132', 'Atomy Herbal Hair Conditioner', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 0, '', '', 0, 'Admin', ''),
  (81, '81', 'MASUK', '2026-04-29 10:31:00+07', '132', 'GK-KARDUS-000132', 'Atomy Herbal Hair Tonic', 'ATOMY-HERBAL-HAIR-TONIC', 2, 0, '', '', 0, 'Admin', ''),
  (82, '82', 'MASUK', '2026-04-29 10:31:00+07', '132', 'GK-KARDUS-000132', 'Atomy Herbal Hair Shampoo', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 0, '', '', 0, 'Admin', ''),
  (83, '83', 'MASUK', '2026-04-29 10:32:00+07', '132', 'GK-KARDUS-000132', 'Atomy Probiotics 10+', 'ATOMY-PROBIOTICS-10', 2, 0, '', '', 0, 'Admin', ''),
  (84, '84', 'MASUK', '2026-04-29 10:32:00+07', '132', 'GK-KARDUS-000132', 'Atomy Color Food Vitamin C', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 0, '', '', 0, 'Admin', ''),
  (85, '85', 'MASUK', '2026-04-29 10:32:00+07', '134', 'GK-KARDUS-000134', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (86, '86', 'MASUK', '2026-04-29 10:32:00+07', '134', 'GK-KARDUS-000134', 'Atomy Herbal Hair Tonic', 'ATOMY-HERBAL-HAIR-TONIC', 2, 0, '', '', 0, 'Admin', ''),
  (87, '87', 'MASUK', '2026-04-29 10:35:00+07', '135', 'GK-KARDUS-000135', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (88, '88', 'MASUK', '2026-04-29 10:35:00+07', '135', 'GK-KARDUS-000135', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (89, '89', 'MASUK', '2026-04-29 10:35:00+07', '135', 'GK-KARDUS-000135', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 2, 0, '', '', 0, 'Admin', ''),
  (90, '90', 'MASUK', '2026-04-29 10:36:00+07', '135', 'GK-KARDUS-000135', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 2, 0, '', '', 0, 'Admin', ''),
  (91, '91', 'MASUK', '2026-04-29 10:37:00+07', '136', 'GK-KARDUS-000136', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (92, '92', 'MASUK', '2026-04-29 10:38:00+07', '137', 'GK-KARDUS-000137', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (93, '93', 'MASUK', '2026-04-29 10:39:00+07', '138', 'GK-KARDUS-000138', 'Atomy Herbal Hair Conditioner', 'ATOMY-HERBAL-HAIR-CONDITIONER', 2, 0, '', '', 0, 'Admin', ''),
  (94, '94', 'MASUK', '2026-04-29 10:39:00+07', '138', 'GK-KARDUS-000138', 'Atomy Absolute Ampoule', 'ATOMY-ABSOLUTE-AMPOULE', 1, 0, '', '', 0, 'Admin', ''),
  (95, '95', 'MASUK', '2026-04-29 10:39:00+07', '139', 'GK-KARDUS-000139', 'Atomy Absolute CellActive Skincare Set', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, '', '', 0, 'Admin', ''),
  (96, '96', 'MASUK', '2026-04-29 10:40:00+07', '138', 'GK-KARDUS-000138', 'Atomy Herbal Hair Tonic', 'ATOMY-HERBAL-HAIR-TONIC', 2, 0, '', '', 0, 'Admin', ''),
  (97, '97', 'MASUK', '2026-04-29 10:42:00+07', '140', 'GK-KARDUS-000140', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (98, '98', 'MASUK', '2026-04-29 10:42:00+07', '140', 'GK-KARDUS-000140', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (99, '99', 'MASUK', '2026-04-29 10:42:00+07', '140', 'GK-KARDUS-000140', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 1, 0, '', '', 0, 'Admin', ''),
  (100, '100', 'MASUK', '2026-04-29 10:42:00+07', '140', 'GK-KARDUS-000140', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 1, 0, '', '', 0, 'Admin', ''),
  (101, '101', 'MASUK', '2026-04-29 10:43:00+07', '140', 'GK-KARDUS-000140', 'Atomy Probiotics 10+', 'ATOMY-PROBIOTICS-10', 1, 0, '', '', 0, 'Admin', ''),
  (102, '102', 'MASUK', '2026-04-29 10:43:00+07', '138', 'GK-KARDUS-000138', 'Atomy Herbal Hair Tonic', 'ATOMY-HERBAL-HAIR-TONIC', 2, 0, '', '', 0, 'Admin', ''),
  (103, '103', 'MASUK', '2026-04-29 10:44:00+07', '141', 'GK-KARDUS-000141', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (104, '104', 'MASUK', '2026-04-29 10:44:00+07', '141', 'GK-KARDUS-000141', 'Atomy Herbal Hair Shampoo', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 0, '', '', 0, 'Admin', ''),
  (105, '105', 'MASUK', '2026-04-29 10:44:00+07', '141', 'GK-KARDUS-000141', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (106, '106', 'MASUK', '2026-04-29 10:44:00+07', '141', 'GK-KARDUS-000141', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 1, 0, '', '', 0, 'Admin', ''),
  (107, '107', 'MASUK', '2026-04-29 10:44:00+07', '141', 'GK-KARDUS-000141', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 1, 0, '', '', 0, 'Admin', ''),
  (108, '108', 'MASUK', '2026-04-29 10:46:00+07', '142', 'GK-KARDUS-000142', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (109, '109', 'MASUK', '2026-04-29 10:46:00+07', '142', 'GK-KARDUS-000142', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (110, '110', 'MASUK', '2026-04-29 10:46:00+07', '142', 'GK-KARDUS-000142', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 1, 0, '', '', 0, 'Admin', ''),
  (111, '111', 'MASUK', '2026-04-29 10:46:00+07', '142', 'GK-KARDUS-000142', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 1, 0, '', '', 0, 'Admin', ''),
  (112, '112', 'MASUK', '2026-04-29 10:47:00+07', '143', 'GK-KARDUS-000143', 'Atomy Travel Kit', 'ATOMY-TRAVEL-KIT', 4, 0, '', '', 0, 'Admin', ''),
  (113, '113', 'MASUK', '2026-04-29 10:49:00+07', '147', 'GK-KARDUS-000147', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (114, '114', 'MASUK', '2026-04-29 10:50:00+07', '147', 'GK-KARDUS-000147', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 2, 0, '', '', 0, 'Admin', ''),
  (115, '115', 'MASUK', '2026-04-29 10:51:00+07', '148', 'GK-KARDUS-000148', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (116, '116', 'MASUK', '2026-04-29 10:51:00+07', '148', 'GK-KARDUS-000148', 'Atomy Vitamin B-Complex', 'ATOMY-VITAMIN-B-COMPLEX', 1, 0, '', '', 0, 'Admin', ''),
  (117, '117', 'MASUK', '2026-04-29 10:53:00+07', '149', 'GK-KARDUS-000149', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (118, '118', 'MASUK', '2026-04-29 10:54:00+07', '150', 'GK-KARDUS-000150', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (119, '119', 'MASUK', '2026-04-29 10:54:00+07', '150', 'GK-KARDUS-000150', 'Atomy Travel Kit', 'ATOMY-TRAVEL-KIT', 1, 0, '', '', 0, 'Admin', ''),
  (120, '120', 'MASUK', '2026-04-29 10:56:00+07', '152', 'GK-KARDUS-000152', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (121, '121', 'MASUK', '2026-04-29 10:56:00+07', '152', 'GK-KARDUS-000152', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 1, 0, '', '', 0, 'Admin', ''),
  (122, '122', 'MASUK', '2026-04-29 10:56:00+07', '152', 'GK-KARDUS-000152', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 1, 0, '', '', 0, 'Admin', ''),
  (123, '123', 'MASUK', '2026-04-29 10:56:00+07', '152', 'GK-KARDUS-000152', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (124, '124', 'MASUK', '2026-04-29 10:59:00+07', '155', 'GK-KARDUS-000155', 'Atomy Herbal Hair Conditioner', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 0, '', '', 0, 'Admin', ''),
  (125, '125', 'MASUK', '2026-04-29 10:59:00+07', '154', 'GK-KARDUS-000154', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (126, '126', 'MASUK', '2026-04-29 10:59:00+07', '154', 'GK-KARDUS-000154', 'Atomy Herbal Hair Tonic', 'ATOMY-HERBAL-HAIR-TONIC', 1, 0, '', '', 0, 'Admin', ''),
  (127, '127', 'MASUK', '2026-04-29 11:00:00+07', '154', 'GK-KARDUS-000154', 'Atomy Herbal Hair Tonic', 'ATOMY-HERBAL-HAIR-TONIC', 1, 0, '', '', 0, 'Admin', ''),
  (128, '128', 'MASUK', '2026-04-29 11:00:00+07', '154', 'GK-KARDUS-000154', 'Atomy Herbal Hair Shampoo', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 0, '', '', 0, 'Admin', ''),
  (129, '129', 'MASUK', '2026-04-29 11:00:00+07', '154', 'GK-KARDUS-000154', 'Atomy Herbal Hair Shampoo', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 0, '', '', 0, 'Admin', ''),
  (130, '130', 'MASUK', '2026-04-29 11:00:00+07', '154', 'GK-KARDUS-000154', 'Atomy Probiotics 10+', 'ATOMY-PROBIOTICS-10', 1, 0, '', '', 0, 'Admin', ''),
  (131, '131', 'MASUK', '2026-04-29 11:00:00+07', '154', 'GK-KARDUS-000154', 'Atomy Probiotics 10+', 'ATOMY-PROBIOTICS-10', 1, 0, '', '', 0, 'Admin', ''),
  (132, '132', 'MASUK', '2026-04-29 11:00:00+07', '154', 'GK-KARDUS-000154', 'Atomy Color Food Vitamin C', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 0, '', '', 0, 'Admin', ''),
  (133, '133', 'MASUK', '2026-04-29 11:00:00+07', '154', 'GK-KARDUS-000154', 'Atomy Herbal Hair Tonic', 'ATOMY-HERBAL-HAIR-TONIC', 1, 0, '', '', 0, 'Admin', ''),
  (134, '134', 'MASUK', '2026-04-30 05:55:00+07', '156', 'GK-KARDUS-000156', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (135, '135', 'MASUK', '2026-04-30 06:03:00+07', '157', 'GK-KARDUS-000157', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (136, '136', 'MASUK', '2026-04-30 06:04:00+07', '158', 'GK-KARDUS-000158', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (137, '137', 'MASUK', '2026-04-30 06:06:00+07', '159', 'GK-KARDUS-000159', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (138, '138', 'MASUK', '2026-04-30 06:07:00+07', '160', 'GK-KARDUS-000160', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (139, '139', 'MASUK', '2026-04-30 06:09:00+07', '161', 'GK-KARDUS-000161', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 2, 0, '', '', 0, 'Admin', ''),
  (140, '140', 'MASUK', '2026-04-30 06:12:00+07', '162', 'GK-KARDUS-000162', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (141, '141', 'MASUK', '2026-04-30 06:45:00+07', '163', 'GK-KARDUS-000163', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (142, '142', 'MASUK', '2026-04-30 06:46:00+07', '164', 'GK-KARDUS-000164', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (143, '143', 'MASUK', '2026-04-30 06:51:00+07', '165', 'GK-KARDUS-000165', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (144, '144', 'MASUK', '2026-04-30 06:53:00+07', '166', 'GK-KARDUS-000166', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (145, '145', 'MASUK', '2026-04-30 06:57:00+07', '167', 'GK-KARDUS-000167', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (146, '146', 'MASUK', '2026-04-30 07:02:00+07', '168', 'GK-KARDUS-000168', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (147, '147', 'MASUK', '2026-04-30 07:03:00+07', '169', 'GK-KARDUS-000169', 'Atomy Paket Ramadhan Care', 'ATOMY-PAKET-RAMADHAN-CARE', 1, 0, '', '', 0, 'Admin', ''),
  (148, '148', 'MASUK', '2026-04-30 07:04:00+07', '170', 'GK-KARDUS-000170', 'Atomy Color Food Vitamin C', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 0, '', '', 0, 'Admin', ''),
  (149, '149', 'MASUK', '2026-04-30 07:05:00+07', '170', 'GK-KARDUS-000170', 'Atomy Probiotics 10+', 'ATOMY-PROBIOTICS-10', 1, 0, '', '', 0, 'Admin', ''),
  (150, '150', 'MASUK', '2026-04-30 07:05:00+07', '170', 'GK-KARDUS-000170', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (151, '151', 'MASUK', '2026-04-30 07:07:00+07', '171', 'GK-KARDUS-000171', 'Atomy Hongsamdan Red Ginseng', 'ATOMY-HONGSAMDAN-RED-GINSENG', 2, 0, '', '', 0, 'Admin', ''),
  (152, '152', 'MASUK', '2026-04-30 09:33:00+07', '172', 'GK-KARDUS-000172', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (153, '153', 'MASUK', '2026-04-30 09:33:00+07', '173', 'GK-KARDUS-000173', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (154, '154', 'MASUK', '2026-04-30 09:35:00+07', '174', 'GK-KARDUS-000174', 'Atomy Paket Bingkisan Lebaran', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 0, '', '', 0, 'Admin', ''),
  (155, '155', 'MASUK', '2026-04-30 09:36:00+07', '176', 'GK-KARDUS-000176', 'Atomy Paket Bingkisan Lebaran', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 0, '', '', 0, 'Admin', ''),
  (156, '156', 'MASUK', '2026-04-30 09:37:00+07', '177', 'GK-KARDUS-000177', 'Atomy Paket Bingkisan Lebaran', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 0, '', '', 0, 'Admin', ''),
  (157, '157', 'MASUK', '2026-04-30 09:37:00+07', '177', 'GK-KARDUS-000177', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (158, '158', 'MASUK', '2026-04-30 09:38:00+07', '178', 'GK-KARDUS-000178', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (159, '159', 'MASUK', '2026-04-30 09:39:00+07', '180', 'GK-KARDUS-000180', 'Atomy Travel Kit', 'ATOMY-TRAVEL-KIT', 4, 0, '', '', 0, 'Admin', ''),
  (160, '160', 'MASUK', '2026-04-30 09:39:00+07', '180', 'GK-KARDUS-000180', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (161, '161', 'MASUK', '2026-04-30 09:40:00+07', '181', 'GK-KARDUS-000181', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (162, '162', 'MASUK', '2026-04-30 09:41:00+07', '183', 'GK-KARDUS-000183', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (163, '163', 'MASUK', '2026-04-30 09:42:00+07', '184', 'GK-KARDUS-000184', 'Atomy Paket Bingkisan Lebaran', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 0, '', '', 0, 'Admin', ''),
  (164, '164', 'MASUK', '2026-04-30 09:43:00+07', '186', 'GK-KARDUS-000186', 'Atomy Travel Kit', 'ATOMY-TRAVEL-KIT', 1, 0, '', '', 0, 'Admin', ''),
  (165, '165', 'MASUK', '2026-04-30 09:45:00+07', '188', 'GK-KARDUS-000188', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (166, '166', 'MASUK', '2026-04-30 09:46:00+07', '188', 'GK-KARDUS-000188', 'Atomy Toothbrush', 'ATOMY-TOOTHBRUSH', 4, 0, '', '', 0, 'Admin', ''),
  (167, '167', 'MASUK', '2026-04-30 09:46:00+07', '188', 'GK-KARDUS-000188', 'Atomy Absolute CellActive Skincare Set', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, '', '', 0, 'Admin', ''),
  (168, '168', 'MASUK', '2026-04-30 09:47:00+07', '187', 'GK-KARDUS-000187', 'Atomy BB Cream', 'ATOMY-BB-CREAM', 1, 0, '', '', 0, 'Admin', ''),
  (169, '169', 'MASUK', '2026-04-30 09:47:00+07', '187', 'GK-KARDUS-000187', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (170, '170', 'MASUK', '2026-04-30 09:50:00+07', '191', 'GK-KARDUS-000191', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (171, '171', 'MASUK', '2026-04-30 09:51:00+07', '194', 'GK-KARDUS-000194', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (172, '172', 'MASUK', '2026-04-30 09:53:00+07', '196', 'GK-KARDUS-000196', 'Atomy Travel Kit', 'ATOMY-TRAVEL-KIT', 1, 0, '', '', 0, 'Admin', ''),
  (173, '173', 'MASUK', '2026-04-30 09:53:00+07', '197', 'GK-KARDUS-000197', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (174, '174', 'MASUK', '2026-04-30 09:54:00+07', '198', 'GK-KARDUS-000198', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (175, '175', 'MASUK', '2026-04-30 09:55:00+07', '199', 'GK-KARDUS-000199', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (176, '176', 'MASUK', '2026-04-30 09:56:00+07', '200', 'GK-KARDUS-000200', 'Atomy Paket Berkah Ramadan B', 'ATOMY-PAKET-BERKAH-RAMADAN-B', 1, 0, '', '', 0, 'Admin', ''),
  (177, '177', 'MASUK', '2026-04-30 09:56:00+07', '201', 'GK-KARDUS-000201', 'Atomy Toothpaste 50g', 'ATOMY-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Admin', ''),
  (178, '178', 'MASUK', '2026-04-30 09:57:00+07', '201', 'GK-KARDUS-000201', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (179, '179', 'MASUK', '2026-04-30 09:57:00+07', '201', 'GK-KARDUS-000201', 'Atomy Toothbrush', 'ATOMY-TOOTHBRUSH', 1, 0, '', '', 0, 'Admin', ''),
  (180, '180', 'MASUK', '2026-04-30 09:58:00+07', '202', 'GK-KARDUS-000202', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (181, '181', 'MASUK', '2026-04-30 09:59:00+07', '203', 'GK-KARDUS-000203', 'Atomy Aidam Cleanser', 'ATOMY-AIDAM-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (182, '182', 'MASUK', '2026-04-30 09:59:00+07', '203', 'GK-KARDUS-000203', 'Atomy Toothpaste 50g', 'ATOMY-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Admin', ''),
  (183, '183', 'MASUK', '2026-04-30 09:59:00+07', '203', 'GK-KARDUS-000203', 'Atomy Travel Kit', 'ATOMY-TRAVEL-KIT', 1, 0, '', '', 0, 'Admin', ''),
  (184, '184', 'MASUK', '2026-04-30 10:01:00+07', '206', 'GK-KARDUS-000206', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (185, '185', 'MASUK', '2026-04-30 10:06:00+07', '207', 'GK-KARDUS-000207', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (186, '186', 'MASUK', '2026-04-30 10:11:00+07', '209', 'GK-KARDUS-000209', 'Atomy Paket Bingkisan Lebaran', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 0, '', '', 0, 'Admin', ''),
  (187, '187', 'MASUK', '2026-04-30 10:11:00+07', '209', 'GK-KARDUS-000209', 'Atomy Hydra Brightening Care Set', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 1, 0, '', '', 0, 'Admin', ''),
  (188, '188', 'MASUK', '2026-04-30 10:12:00+07', '210', 'GK-KARDUS-000210', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (189, '189', 'MASUK', '2026-04-30 10:12:00+07', '211', 'GK-KARDUS-000211', 'Atomy Stainless Steel Scrubber', 'ATOMY-STAINLESS-STEEL-SCRUBBER', 1, 0, '', '', 0, 'Admin', ''),
  (190, '190', 'MASUK', '2026-04-30 10:13:00+07', '210', 'GK-KARDUS-000210', 'Atomy Deep Cleanser 150ml', 'ATOMY-DEEP-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (191, '191', 'MASUK', '2026-04-30 10:13:00+07', '211', 'GK-KARDUS-000211', 'Atomy Color Food Vitamin C', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 0, '', '', 0, 'Admin', ''),
  (192, '192', 'MASUK', '2026-04-30 10:13:00+07', '210', 'GK-KARDUS-000210', 'Atomy Color Food Vitamin C', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 0, '', '', 0, 'Admin', ''),
  (193, '193', 'MASUK', '2026-04-30 10:16:00+07', '213', 'GK-KARDUS-000213', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (194, '194', 'MASUK', '2026-04-30 10:21:00+07', '218', 'GK-KARDUS-000218', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (195, '195', 'MASUK', '2026-04-30 10:37:00+07', '228', 'GK-KARDUS-000228', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (196, '196', 'MASUK', '2026-04-30 10:40:00+07', '230', 'GK-KARDUS-000230', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (197, '197', 'MASUK', '2026-05-02 07:48:00+07', '236', 'GK-KARDUS-000236', 'Atomy Absolute CellActive Skincare Set', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, '', '', 0, 'Admin', ''),
  (198, '198', 'MASUK', '2026-05-02 07:48:00+07', '236', 'GK-KARDUS-000236', 'Atomy Herbal Hair Shampoo', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 0, '', '', 0, 'Admin', ''),
  (199, '199', 'MASUK', '2026-05-02 07:51:00+07', '237', 'GK-KARDUS-000237', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (200, '200', 'MASUK', '2026-05-02 07:56:00+07', '235', 'GK-KARDUS-000235', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (201, '201', 'MASUK', '2026-05-02 07:58:00+07', '241', 'GK-KARDUS-000241', 'Atomy Cafe Arabica', 'ATOMY-CAFE-ARABICA', 1, 0, '', '', 0, 'Admin', ''),
  (202, '202', 'MASUK', '2026-05-02 08:11:00+07', '235', 'GK-KARDUS-000235', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (203, '203', 'MASUK', '2026-05-02 08:21:00+07', '264', 'GK-KARDUS-000264', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (204, '204', 'MASUK', '2026-05-02 08:25:00+07', '235', 'GK-KARDUS-000235', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (205, '205', 'MASUK', '2026-05-02 08:28:00+07', '272', 'GK-KARDUS-000272', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (206, '206', 'MASUK', '2026-05-02 08:29:00+07', '235', 'GK-KARDUS-000235', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (207, '207', 'MASUK', '2026-05-02 08:32:00+07', '277', 'GK-KARDUS-000277', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (208, '208', 'MASUK', '2026-05-02 08:37:00+07', '283', 'GK-KARDUS-000283', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (209, '209', 'MASUK', '2026-05-02 08:40:00+07', '235', 'GK-KARDUS-000235', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (210, '210', 'MASUK', '2026-05-02 08:46:00+07', '287', 'GK-KARDUS-000287', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (211, '211', 'MASUK', '2026-05-02 08:48:00+07', '288', 'GK-KARDUS-000288', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (212, '212', 'MASUK', '2026-05-02 08:59:00+07', '291', 'GK-KARDUS-000291', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (213, '213', 'MASUK', '2026-05-02 09:02:00+07', '292', 'GK-KARDUS-000292', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (214, '214', 'MASUK', '2026-05-02 09:06:00+07', '235', 'GK-KARDUS-000235', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (215, '215', 'MASUK', '2026-05-02 09:10:00+07', '298', 'GK-KARDUS-000298', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (216, '216', 'MASUK', '2026-05-02 09:11:00+07', '299', 'GK-KARDUS-000299', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (217, '217', 'MASUK', '2026-05-02 09:14:00+07', '301', 'GK-KARDUS-000301', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (218, '218', 'MASUK', '2026-05-02 09:17:00+07', '303', 'GK-KARDUS-000303', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (219, '219', 'MASUK', '2026-05-02 09:22:00+07', '306', 'GK-KARDUS-000306', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (220, '220', 'MASUK', '2026-05-02 09:23:00+07', '307', 'GK-KARDUS-000307', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (221, '221', 'MASUK', '2026-05-02 09:26:00+07', '308', 'GK-KARDUS-000308', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (222, '222', 'MASUK', '2026-05-02 09:36:00+07', '317', 'GK-KARDUS-000317', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (223, '223', 'MASUK', '2026-05-02 09:40:00+07', '318', 'GK-KARDUS-000318', 'Atomy Toothpaste 50g', 'ATOMY-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Admin', ''),
  (224, '224', 'MASUK', '2026-05-02 09:41:00+07', '235', 'GK-KARDUS-000235', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (225, '225', 'MASUK', '2026-05-02 09:42:00+07', '320', 'GK-KARDUS-000320', 'Atomy Stainless Steel Scrubber', 'ATOMY-STAINLESS-STEEL-SCRUBBER', 1, 0, '', '', 0, 'Admin', ''),
  (226, '226', 'MASUK', '2026-05-02 09:43:00+07', '321', 'GK-KARDUS-000321', 'Atomy Absolute CellActive Skincare Set', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, '', '', 0, 'Admin', ''),
  (227, '227', 'MASUK', '2026-05-02 09:44:00+07', '321', 'GK-KARDUS-000321', 'Atomy Absolute Ampoule', 'ATOMY-ABSOLUTE-AMPOULE', 1, 0, '', '', 0, 'Admin', ''),
  (228, '228', 'MASUK', '2026-05-02 09:44:00+07', '321', 'GK-KARDUS-000321', 'Atomy Travel Kit', 'ATOMY-TRAVEL-KIT', 1, 0, '', '', 0, 'Admin', ''),
  (229, '229', 'MASUK', '2026-05-02 09:45:00+07', '322', 'GK-KARDUS-000322', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (230, '230', 'MASUK', '2026-05-02 09:46:00+07', '323', 'GK-KARDUS-000323', 'Atomy Toothpaste 200g', 'ATOMY-TOOTHPASTE-200G', 1, 0, '', '', 0, 'Admin', ''),
  (231, '231', 'MASUK', '2026-05-02 09:47:00+07', '235', 'GK-KARDUS-000235', 'Atomy Sunscreen White', 'ATOMY-SUNSCREEN-WHITE', 1, 0, '', '', 0, 'Admin', ''),
  (232, '232', 'MASUK', '2026-05-02 09:47:00+07', '323', 'GK-KARDUS-000323', 'Atomy Herbal Hair Shampoo', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 0, '', '', 0, 'Admin', ''),
  (233, '233', 'MASUK', '2026-05-02 09:48:00+07', '324', 'GK-KARDUS-000324', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (234, '234', 'MASUK', '2026-05-02 09:48:00+07', '323', 'GK-KARDUS-000323', 'Atomy Sunscreen Beige', 'ATOMY-SUNSCREEN-BEIGE', 1, 0, '', '', 0, 'Admin', ''),
  (235, '235', 'MASUK', '2026-05-02 09:48:00+07', '323', 'GK-KARDUS-000323', 'Atomy Sunscreen Beige', 'ATOMY-SUNSCREEN-BEIGE', 1, 0, '', '', 0, 'Admin', ''),
  (236, '236', 'MASUK', '2026-05-02 09:49:00+07', '323', 'GK-KARDUS-000323', 'Atomy Toothbrush', 'ATOMY-TOOTHBRUSH', 1, 0, '', '', 0, 'Admin', ''),
  (237, '237', 'MASUK', '2026-05-02 09:50:00+07', '325', 'GK-KARDUS-000325', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (238, '238', 'MASUK', '2026-05-02 09:55:00+07', '327', 'GK-KARDUS-000327', 'Atomy Baby Lotion', 'ATOMY-BABY-LOTION', 1, 0, '', '', 0, 'Admin', ''),
  (239, '239', 'MASUK', '2026-05-02 10:01:00+07', '235', 'GK-KARDUS-000235', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (240, '240', 'MASUK', '2026-05-02 10:04:00+07', '235', 'GK-KARDUS-000235', 'Atomy Slim Body Shake 2.0', 'ATOMY-SLIM-BODY-SHAKE-2-0', 1, 0, '', '', 0, 'Admin', ''),
  (241, '241', 'MASUK', '2026-05-02 10:04:00+07', '334', 'GK-KARDUS-000334', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (242, '242', 'MASUK', '2026-05-02 10:04:00+07', '332', 'GK-KARDUS-000332', 'Atomy Cafe Arabica', 'ATOMY-CAFE-ARABICA', 1, 0, '', '', 0, 'Admin', ''),
  (243, '243', 'MASUK', '2026-05-02 10:04:00+07', '333', 'GK-KARDUS-000333', 'Atomy BB Cream', 'ATOMY-BB-CREAM', 1, 0, '', '', 0, 'Admin', ''),
  (244, '244', 'MASUK', '2026-05-02 10:05:00+07', '329', 'GK-KARDUS-000329', 'Atomy Slim Body Shake 2.0', 'ATOMY-SLIM-BODY-SHAKE-2-0', 1, 0, '', '', 0, 'Admin', ''),
  (245, '245', 'MASUK', '2026-05-02 10:05:00+07', '329', 'GK-KARDUS-000329', 'Atomy Toothpaste 50g', 'ATOMY-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Admin', ''),
  (246, '246', 'MASUK', '2026-05-02 10:06:00+07', '331', 'GK-KARDUS-000331', 'Atomy Toothpaste 50g', 'ATOMY-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Admin', ''),
  (247, '247', 'MASUK', '2026-05-02 10:08:00+07', '331', 'GK-KARDUS-000331', 'Atomy Toothpaste 200g', 'ATOMY-TOOTHPASTE-200G', 1, 0, '', '', 0, 'Admin', ''),
  (248, '248', 'MASUK', '2026-05-02 10:08:00+07', '331', 'GK-KARDUS-000331', 'Atomy Sunscreen White', 'ATOMY-SUNSCREEN-WHITE', 1, 0, '', '', 0, 'Admin', ''),
  (249, '249', 'MASUK', '2026-05-02 10:09:00+07', '331', 'GK-KARDUS-000331', 'Atomy Herbal Hair Shampoo', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 0, '', '', 0, 'Admin', ''),
  (250, '250', 'MASUK', '2026-05-02 10:09:00+07', '331', 'GK-KARDUS-000331', 'Atomy Sunscreen Beige', 'ATOMY-SUNSCREEN-BEIGE', 1, 0, '', '', 0, 'Admin', ''),
  (251, '251', 'MASUK', '2026-05-02 10:09:00+07', '331', 'GK-KARDUS-000331', 'Atomy Toothbrush', 'ATOMY-TOOTHBRUSH', 1, 0, '', '', 0, 'Admin', ''),
  (252, '252', 'MASUK', '2026-05-02 10:13:00+07', '335', 'GK-KARDUS-000335', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (253, '253', 'MASUK', '2026-05-02 10:14:00+07', '335', 'GK-KARDUS-000335', 'Atomy Toothpaste 200g', 'ATOMY-TOOTHPASTE-200G', 1, 0, '', '', 0, 'Admin', ''),
  (254, '254', 'MASUK', '2026-05-02 10:14:00+07', '335', 'GK-KARDUS-000335', 'Atomy Sunscreen White', 'ATOMY-SUNSCREEN-WHITE', 1, 0, '', '', 0, 'Admin', ''),
  (255, '255', 'MASUK', '2026-05-02 10:14:00+07', '335', 'GK-KARDUS-000335', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 1, 0, '', '', 0, 'Admin', ''),
  (256, '256', 'MASUK', '2026-05-02 10:14:00+07', '335', 'GK-KARDUS-000335', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 1, 0, '', '', 0, 'Admin', ''),
  (257, '257', 'MASUK', '2026-05-02 10:14:00+07', '335', 'GK-KARDUS-000335', 'Atomy Sunscreen Beige', 'ATOMY-SUNSCREEN-BEIGE', 1, 0, '', '', 0, 'Admin', ''),
  (258, '258', 'MASUK', '2026-05-02 10:15:00+07', '335', 'GK-KARDUS-000335', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (259, '259', 'MASUK', '2026-05-02 10:15:00+07', '335', 'GK-KARDUS-000335', 'Atomy Toothbrush', 'ATOMY-TOOTHBRUSH', 1, 0, '', '', 0, 'Admin', ''),
  (260, '260', 'MASUK', '2026-05-02 10:19:00+07', '336', 'GK-KARDUS-000336', 'Atomy Pure Spirulina', 'ATOMY-PURE-SPIRULINA', 1, 0, '', '', 0, 'Admin', ''),
  (261, '261', 'MASUK', '2026-05-02 10:20:00+07', '337', 'GK-KARDUS-000337', 'Atomy Absolute CellActive Skincare Set', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, '', '', 0, 'Admin', ''),
  (262, '262', 'MASUK', '2026-05-02 10:20:00+07', '337', 'GK-KARDUS-000337', 'Atomy Absolute Ampoule', 'ATOMY-ABSOLUTE-AMPOULE', 1, 0, '', '', 0, 'Admin', ''),
  (263, '263', 'MASUK', '2026-05-02 10:20:00+07', '337', 'GK-KARDUS-000337', 'Atomy Hydra Brightening Care Set', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 1, 0, '', '', 0, 'Admin', ''),
  (264, '264', 'MASUK', '2026-05-02 10:20:00+07', '338', 'GK-KARDUS-000338', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (265, '265', 'MASUK', '2026-05-02 10:20:00+07', '338', 'GK-KARDUS-000338', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 1, 0, '', '', 0, 'Admin', ''),
  (266, '266', 'MASUK', '2026-05-02 10:21:00+07', '338', 'GK-KARDUS-000338', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 1, 0, '', '', 0, 'Admin', ''),
  (267, '267', 'MASUK', '2026-05-02 10:21:00+07', '338', 'GK-KARDUS-000338', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (268, '268', 'MASUK', '2026-05-02 10:30:00+07', '235', 'GK-KARDUS-000235', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'OWEN', ''),
  (269, '269', 'MASUK', '2026-05-02 10:31:00+07', '238', 'GK-KARDUS-000238', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'OWEN', ''),
  (270, '270', 'MASUK', '2026-05-02 10:39:00+07', '235', 'GK-KARDUS-000235', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (271, '271', 'MASUK', '2026-05-02 10:40:00+07', '235', 'GK-KARDUS-000235', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 2, 0, '', '', 0, 'Admin', ''),
  (272, '272', 'MASUK', '2026-05-02 10:42:00+07', '353', 'GK-KARDUS-000353', 'Atomy Sunscreen White', 'ATOMY-SUNSCREEN-WHITE', 2, 0, '', '', 0, 'Admin', ''),
  (273, '273', 'MASUK', '2026-05-02 10:42:00+07', '235', 'GK-KARDUS-000235', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 2, 0, '', '', 0, 'Admin', ''),
  (274, '274', 'MASUK', '2026-05-02 10:43:00+07', '235', 'GK-KARDUS-000235', 'Atomy Toothpaste 200g', 'ATOMY-TOOTHPASTE-200G', 2, 0, '', '', 0, 'Admin', ''),
  (275, '275', 'MASUK', '2026-05-02 10:44:00+07', '235', 'GK-KARDUS-000235', 'Atomy Sunscreen Beige', 'ATOMY-SUNSCREEN-BEIGE', 2, 0, '', '', 0, 'Admin', ''),
  (276, '276', 'MASUK', '2026-05-02 10:45:00+07', '235', 'GK-KARDUS-000235', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (277, '277', 'MASUK', '2026-05-02 10:45:00+07', '235', 'GK-KARDUS-000235', 'Atomy Toothbrush', 'ATOMY-TOOTHBRUSH', 2, 0, '', '', 0, 'Admin', ''),
  (278, '278', 'MASUK', '2026-05-02 10:48:00+07', '235', 'GK-KARDUS-000235', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (279, '279', 'MASUK', '2026-05-02 10:48:00+07', '365', 'GK-KARDUS-000365', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (280, '280', 'MASUK', '2026-05-02 10:48:00+07', '365', 'GK-KARDUS-000365', 'Atomy Hongsamdan Red Ginseng', 'ATOMY-HONGSAMDAN-RED-GINSENG', 1, 0, '', '', 0, 'Admin', ''),
  (281, '281', 'MASUK', '2026-05-02 10:49:00+07', '235', 'GK-KARDUS-000235', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 1, 0, '', '', 0, 'Admin', ''),
  (282, '282', 'MASUK', '2026-05-02 10:49:00+07', '365', 'GK-KARDUS-000365', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 1, 0, '', '', 0, 'Admin', ''),
  (283, '283', 'MASUK', '2026-05-02 10:49:00+07', '365', 'GK-KARDUS-000365', 'Atomy Probiotics 10+', 'ATOMY-PROBIOTICS-10', 1, 0, '', '', 0, 'Admin', ''),
  (284, '284', 'MASUK', '2026-05-02 10:49:00+07', '365', 'GK-KARDUS-000365', 'Atomy Color Food Vitamin C', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 0, '', '', 0, 'Admin', ''),
  (285, '285', 'MASUK', '2026-05-02 10:52:00+07', '235', 'GK-KARDUS-000235', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 2, 0, '', '', 0, 'Admin', ''),
  (286, '286', 'MASUK', '2026-05-02 10:54:00+07', '235', 'GK-KARDUS-000235', 'Atomy Herbal Hair Tonic', 'ATOMY-HERBAL-HAIR-TONIC', 2, 0, '', '', 0, 'Admin', ''),
  (287, '287', 'MASUK', '2026-05-02 10:55:00+07', '369', 'GK-KARDUS-000369', 'Atomy Deep Cleanser 150ml', 'ATOMY-DEEP-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (288, '288', 'MASUK', '2026-05-02 10:56:00+07', '235', 'GK-KARDUS-000235', 'Atomy Toothpaste 50g', 'ATOMY-TOOTHPASTE-50G', 3, 0, '', '', 0, 'Admin', ''),
  (289, '289', 'MASUK', '2026-05-02 10:57:00+07', '235', 'GK-KARDUS-000235', 'Atomy Herbal Hair Tonic', 'ATOMY-HERBAL-HAIR-TONIC', 2, 0, '', '', 0, 'Admin', ''),
  (290, '290', 'MASUK', '2026-05-02 10:57:00+07', '235', 'GK-KARDUS-000235', 'Atomy Absolute Toner', 'ATOMY-ABSOLUTE-TONER', 2, 0, '', '', 0, 'Admin', ''),
  (291, '291', 'MASUK', '2026-05-02 10:58:00+07', '369', 'GK-KARDUS-000369', 'Atomy Herbal Hair Shampoo', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 0, '', '', 0, 'Admin', ''),
  (292, '292', 'MASUK', '2026-05-02 10:58:00+07', '375', 'GK-KARDUS-000375', 'Atomy Herbal Hair Tonic', 'ATOMY-HERBAL-HAIR-TONIC', 1, 0, '', '', 0, 'Admin', ''),
  (293, '293', 'MASUK', '2026-05-02 10:58:00+07', '235', 'GK-KARDUS-000235', 'Atomy Herbal Hair Shampoo', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 0, '', '', 0, 'Admin', ''),
  (294, '294', 'MASUK', '2026-05-02 10:58:00+07', '369', 'GK-KARDUS-000369', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (295, '295', 'MASUK', '2026-05-02 10:58:00+07', '375', 'GK-KARDUS-000375', 'Atomy Cafe Arabica', 'ATOMY-CAFE-ARABICA', 1, 0, '', '', 0, 'Admin', ''),
  (296, '296', 'MASUK', '2026-05-02 10:59:00+07', '375', 'GK-KARDUS-000375', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (297, '297', 'MASUK', '2026-05-02 10:59:00+07', '369', 'GK-KARDUS-000369', 'Atomy Herbal Hair Conditioner', 'ATOMY-HERBAL-HAIR-CONDITIONER', 2, 0, '', '', 0, 'Admin', ''),
  (298, '298', 'MASUK', '2026-05-02 10:59:00+07', '375', 'GK-KARDUS-000375', 'Atomy Herbal Hair Conditioner', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 0, '', '', 0, 'Admin', ''),
  (299, '299', 'MASUK', '2026-05-02 10:59:00+07', '375', 'GK-KARDUS-000375', 'Atomy Absolute Ampoule', 'ATOMY-ABSOLUTE-AMPOULE', 1, 0, '', '', 0, 'Admin', ''),
  (300, '300', 'MASUK', '2026-05-02 10:59:00+07', '375', 'GK-KARDUS-000375', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (301, '301', 'MASUK', '2026-05-02 10:59:00+07', '369', 'GK-KARDUS-000369', 'Atomy Absolute Lotion', 'ATOMY-ABSOLUTE-LOTION', 2, 0, '', '', 0, 'Admin', ''),
  (302, '302', 'MASUK', '2026-05-02 10:59:00+07', '375', 'GK-KARDUS-000375', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 1, 0, '', '', 0, 'Admin', ''),
  (303, '303', 'MASUK', '2026-05-02 11:00:00+07', '375', 'GK-KARDUS-000375', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 1, 0, '', '', 0, 'Admin', ''),
  (304, '304', 'MASUK', '2026-05-02 11:00:00+07', '369', 'GK-KARDUS-000369', 'Atomy Absolute Ampoule', 'ATOMY-ABSOLUTE-AMPOULE', 1, 0, '', '', 0, 'Admin', ''),
  (305, '305', 'MASUK', '2026-05-02 11:00:00+07', '375', 'GK-KARDUS-000375', 'Atomy Herbal Hair Tonic', 'ATOMY-HERBAL-HAIR-TONIC', 1, 0, '', '', 0, 'Admin', ''),
  (306, '306', 'MASUK', '2026-05-02 11:00:00+07', '369', 'GK-KARDUS-000369', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (307, '307', 'MASUK', '2026-05-02 11:01:00+07', '369', 'GK-KARDUS-000369', 'Atomy Sunscreen White', 'ATOMY-SUNSCREEN-WHITE', 2, 0, '', '', 0, 'Admin', ''),
  (308, '308', 'MASUK', '2026-05-02 11:02:00+07', '369', 'GK-KARDUS-000369', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 2, 0, '', '', 0, 'Admin', ''),
  (309, '309', 'MASUK', '2026-05-02 11:03:00+07', '376', 'GK-KARDUS-000376', 'Atomy Body Cleanser', 'ATOMY-BODY-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (310, '310', 'MASUK', '2026-05-02 11:03:00+07', '376', 'GK-KARDUS-000376', 'Atomy Herbal Hair Conditioner', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 0, '', '', 0, 'Admin', ''),
  (311, '311', 'MASUK', '2026-05-02 11:03:00+07', '376', 'GK-KARDUS-000376', 'Atomy Foam Cleanser 150ml', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, '', '', 0, 'Admin', ''),
  (312, '312', 'MASUK', '2026-05-02 11:03:00+07', '235', 'GK-KARDUS-000235', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 1, 0, '', '', 0, 'Admin', ''),
  (313, '313', 'MASUK', '2026-05-02 11:03:00+07', '376', 'GK-KARDUS-000376', 'Atomy Body Lotion', 'ATOMY-BODY-LOTION', 1, 0, '', '', 0, 'Admin', ''),
  (314, '314', 'MASUK', '2026-05-02 11:04:00+07', '376', 'GK-KARDUS-000376', 'Atomy Herbal Hair Tonic', 'ATOMY-HERBAL-HAIR-TONIC', 1, 0, '', '', 0, 'Admin', ''),
  (315, '315', 'MASUK', '2026-05-02 11:04:00+07', '376', 'GK-KARDUS-000376', 'Atomy Toothpaste 50g', 'ATOMY-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Admin', ''),
  (316, '316', 'MASUK', '2026-05-04 07:08:00+07', '378', 'GK-KARDUS-000378', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (317, '317', 'MASUK', '2026-05-04 07:23:00+07', '382', 'GK-KARDUS-000382', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Oktavia', ''),
  (318, '318', 'MASUK', '2026-05-04 07:26:00+07', '384', 'GK-KARDUS-000384', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Oktavia', ''),
  (319, '319', 'MASUK', '2026-05-04 07:31:00+07', '387', 'GK-KARDUS-000387', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Oktavia', ''),
  (320, '320', 'MASUK', '2026-05-04 07:35:00+07', '389', 'GK-KARDUS-000389', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (321, '321', 'MASUK', '2026-05-04 07:36:00+07', '392', 'GK-KARDUS-000392', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Oktavia', ''),
  (322, '322', 'MASUK', '2026-05-04 07:38:00+07', '393', 'GK-KARDUS-000393', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Oktavia', ''),
  (323, '323', 'MASUK', '2026-05-04 07:39:00+07', '394', 'GK-KARDUS-000394', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (324, '324', 'MASUK', '2026-05-04 07:39:00+07', '395', 'GK-KARDUS-000395', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (325, '325', 'MASUK', '2026-05-04 07:44:00+07', '396', 'GK-KARDUS-000396', 'Atomy Promo Ramadhan 2', 'ATOMY-PROMO-RAMADHAN-2', 1, 0, '', '', 0, 'Oktavia', ''),
  (326, '326', 'MASUK', '2026-05-04 07:44:00+07', '396', 'GK-KARDUS-000396', 'Atomy Propolis Toothpaste 50g', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Oktavia', ''),
  (327, '327', 'MASUK', '2026-05-04 07:45:00+07', '397', 'GK-KARDUS-000397', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (328, '328', 'MASUK', '2026-05-04 07:46:00+07', '398', 'GK-KARDUS-000398', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Oktavia', ''),
  (329, '329', 'MASUK', '2026-05-04 07:48:00+07', '399', 'GK-KARDUS-000399', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (330, '330', 'MASUK', '2026-05-04 07:53:00+07', '400', 'GK-KARDUS-000400', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (331, '331', 'MASUK', '2026-05-04 07:54:00+07', '401', 'GK-KARDUS-000401', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Oktavia', ''),
  (332, '332', 'MASUK', '2026-05-04 07:55:00+07', '402', 'GK-KARDUS-000402', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (333, '333', 'MASUK', '2026-05-04 07:58:00+07', '403', 'GK-KARDUS-000403', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Oktavia', ''),
  (334, '334', 'MASUK', '2026-05-04 08:01:00+07', '404', 'GK-KARDUS-000404', 'Atomy Absolute CellActive Ampoule', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 1, 0, '', '', 0, 'Admin', ''),
  (335, '335', 'MASUK', '2026-05-04 08:01:00+07', '404', 'GK-KARDUS-000404', 'Atomy Absolute CellActive Skincare Set', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, '', '', 0, 'Admin', ''),
  (336, '336', 'MASUK', '2026-05-04 08:06:00+07', '406', 'GK-KARDUS-000406', 'Atomy Paket Lebaran A (Health Care)', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, '', '', 0, 'Admin', ''),
  (337, '337', 'MASUK', '2026-05-04 08:08:00+07', '409', 'GK-KARDUS-000409', 'Atomy Absolute CellActive Skincare Set', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, '', '', 0, 'Admin', ''),
  (338, '338', 'MASUK', '2026-05-04 08:08:00+07', '409', 'GK-KARDUS-000409', 'Atomy Absolute CellActive Ampoule', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 1, 0, '', '', 0, 'Admin', ''),
  (339, '339', 'MASUK', '2026-05-04 08:10:00+07', '410', 'GK-KARDUS-000410', 'Atomy Hydra Brightening Care Set', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 1, 0, '', '', 0, 'Admin', ''),
  (340, '340', 'MASUK', '2026-05-04 08:11:00+07', '411', 'GK-KARDUS-000411', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Oktavia', ''),
  (341, '341', 'MASUK', '2026-05-04 08:12:00+07', '412', 'GK-KARDUS-000412', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (342, '342', 'MASUK', '2026-05-04 08:12:00+07', '413', 'GK-KARDUS-000413', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (343, '343', 'MASUK', '2026-05-04 08:15:00+07', '414', 'GK-KARDUS-000414', 'Atomy Hydra Brightening Care Set', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 2, 0, '', '', 0, 'Admin', ''),
  (344, '344', 'MASUK', '2026-05-04 08:15:00+07', '415', 'GK-KARDUS-000415', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Oktavia', ''),
  (345, '345', 'MASUK', '2026-05-04 08:16:00+07', '416', 'GK-KARDUS-000416', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (346, '346', 'MASUK', '2026-05-04 08:20:00+07', '418', 'GK-KARDUS-000418', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (347, '347', 'MASUK', '2026-05-04 08:20:00+07', '420', 'GK-KARDUS-000420', 'Atomy Paket Lebaran A (Health Care)', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, '', '', 0, 'Oktavia', ''),
  (348, '348', 'MASUK', '2026-05-04 08:22:00+07', '422', 'GK-KARDUS-000422', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (349, '349', 'MASUK', '2026-05-04 08:23:00+07', '421', 'GK-KARDUS-000421', 'Atomy Hongsamdan Red Ginseng', 'ATOMY-HONGSAMDAN-RED-GINSENG', 2, 0, '', '', 0, 'Admin', ''),
  (350, '350', 'MASUK', '2026-05-04 08:23:00+07', '421', 'GK-KARDUS-000421', 'Atomy Sunscreen White', 'ATOMY-SUNSCREEN-WHITE', 2, 0, '', '', 0, 'Admin', ''),
  (351, '351', 'MASUK', '2026-05-04 08:23:00+07', '421', 'GK-KARDUS-000421', 'Atomy Propolis Toothpaste 200g', 'ATOMY-PROPOLIS-TOOTHPASTE-200G', 2, 0, '', '', 0, 'Admin', ''),
  (352, '352', 'MASUK', '2026-05-04 08:23:00+07', '421', 'GK-KARDUS-000421', 'Atomy Finezyme', 'ATOMY-FINEZYME', 2, 0, '', '', 0, 'Admin', ''),
  (353, '353', 'MASUK', '2026-05-04 08:23:00+07', '421', 'GK-KARDUS-000421', 'Atomy Sunscreen Beige', 'ATOMY-SUNSCREEN-BEIGE', 2, 0, '', '', 0, 'Admin', ''),
  (354, '354', 'MASUK', '2026-05-04 08:23:00+07', '421', 'GK-KARDUS-000421', 'Atomy Toothbrush', 'ATOMY-TOOTHBRUSH', 2, 0, '', '', 0, 'Admin', ''),
  (355, '355', 'MASUK', '2026-05-04 08:23:00+07', '421', 'GK-KARDUS-000421', 'Atomy Color Food Vitamin C', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 0, '', '', 0, 'Admin', ''),
  (356, '356', 'MASUK', '2026-05-04 08:24:00+07', '423', 'GK-KARDUS-000423', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (357, '357', 'MASUK', '2026-05-04 08:25:00+07', '424', 'GK-KARDUS-000424', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Oktavia', ''),
  (358, '358', 'MASUK', '2026-05-04 08:28:00+07', '426', 'GK-KARDUS-000426', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (359, '359', 'MASUK', '2026-05-04 08:28:00+07', '428', 'GK-KARDUS-000428', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Oktavia', ''),
  (360, '360', 'MASUK', '2026-05-04 08:30:00+07', '429', 'GK-KARDUS-000429', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (361, '361', 'MASUK', '2026-05-04 08:30:00+07', '430', 'GK-KARDUS-000430', 'Atomy Paket Lebaran A (Health Care)', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, '', '', 0, 'Oktavia', ''),
  (362, '362', 'MASUK', '2026-05-04 08:31:00+07', '431', 'GK-KARDUS-000431', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (363, '363', 'MASUK', '2026-05-04 08:32:00+07', '432', 'GK-KARDUS-000432', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (364, '364', 'MASUK', '2026-05-04 08:34:00+07', '434', 'GK-KARDUS-000434', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (365, '365', 'MASUK', '2026-05-04 08:35:00+07', '435', 'GK-KARDUS-000435', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Oktavia', ''),
  (366, '366', 'MASUK', '2026-05-04 08:35:00+07', '433', 'GK-KARDUS-000433', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (367, '367', 'MASUK', '2026-05-04 08:37:00+07', '436', 'GK-KARDUS-000436', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Oktavia', ''),
  (368, '368', 'MASUK', '2026-05-04 08:40:00+07', '437', 'GK-KARDUS-000437', 'Atomy Paket Lebaran A (Health Care)', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, '', '', 0, 'Oktavia', ''),
  (369, '369', 'MASUK', '2026-05-04 08:44:00+07', '441', 'GK-KARDUS-000441', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (370, '370', 'MASUK', '2026-05-04 08:45:00+07', '442', 'GK-KARDUS-000442', 'Atomy Paket Lebaran A (Health Care)', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, '', '', 0, 'Admin', ''),
  (371, '371', 'MASUK', '2026-05-04 08:49:00+07', '447', 'GK-KARDUS-000447', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (372, '372', 'MASUK', '2026-05-04 08:49:00+07', '447', 'GK-KARDUS-000447', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (373, '373', 'MASUK', '2026-05-04 08:52:00+07', '449', 'GK-KARDUS-000449', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (374, '374', 'MASUK', '2026-05-04 08:53:00+07', '450', 'GK-KARDUS-000450', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (375, '375', 'MASUK', '2026-05-04 08:53:00+07', '447', 'GK-KARDUS-000447', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (376, '376', 'MASUK', '2026-05-04 08:55:00+07', '451', 'GK-KARDUS-000451', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (377, '377', 'MASUK', '2026-05-04 08:57:00+07', '452', 'GK-KARDUS-000452', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (378, '378', 'MASUK', '2026-05-04 08:59:00+07', '454', 'GK-KARDUS-000454', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (379, '379', 'MASUK', '2026-05-04 09:01:00+07', '456', 'GK-KARDUS-000456', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (380, '380', 'MASUK', '2026-05-04 09:05:00+07', '458', 'GK-KARDUS-000458', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 2, 0, '', '', 0, 'Admin', ''),
  (381, '381', 'MASUK', '2026-05-04 09:07:00+07', '460', 'GK-KARDUS-000460', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 2, 0, '', '', 0, 'Admin', ''),
  (382, '382', 'MASUK', '2026-05-04 09:09:00+07', '462', 'GK-KARDUS-000462', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (383, '383', 'MASUK', '2026-05-04 09:09:00+07', '463', 'GK-KARDUS-000463', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 2, 0, '', '', 0, 'Admin', ''),
  (384, '384', 'MASUK', '2026-05-04 09:10:00+07', '461', 'GK-KARDUS-000461', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (385, '385', 'MASUK', '2026-05-04 09:11:00+07', '464', 'GK-KARDUS-000464', 'Atomy Paket Lebaran A (Health Care)', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, '', '', 0, 'Admin', ''),
  (386, '386', 'MASUK', '2026-05-04 09:13:00+07', '466', 'GK-KARDUS-000466', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (387, '387', 'MASUK', '2026-05-04 09:13:00+07', '467', 'GK-KARDUS-000467', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 2, 0, '', '', 0, 'Admin', ''),
  (388, '388', 'MASUK', '2026-05-04 09:15:00+07', '469', 'GK-KARDUS-000469', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Oktavia', ''),
  (389, '389', 'MASUK', '2026-05-04 09:15:00+07', '469', 'GK-KARDUS-000469', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Oktavia', ''),
  (390, '390', 'MASUK', '2026-05-04 09:15:00+07', '470', 'GK-KARDUS-000470', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 2, 0, '', '', 0, 'Admin', ''),
  (391, '391', 'MASUK', '2026-05-04 09:17:00+07', '471', 'GK-KARDUS-000471', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Oktavia', ''),
  (392, '392', 'MASUK', '2026-05-04 09:17:00+07', '472', 'GK-KARDUS-000472', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 2, 0, '', '', 0, 'Admin', ''),
  (393, '393', 'MASUK', '2026-05-04 09:21:00+07', '475', 'GK-KARDUS-000475', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (394, '394', 'MASUK', '2026-05-04 09:22:00+07', '477', 'GK-KARDUS-000477', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (395, '395', 'MASUK', '2026-05-04 09:23:00+07', '478', 'GK-KARDUS-000478', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (396, '396', 'MASUK', '2026-05-04 09:24:00+07', '481', 'GK-KARDUS-000481', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (397, '397', 'MASUK', '2026-05-04 09:26:00+07', '482', 'GK-KARDUS-000482', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (398, '398', 'MASUK', '2026-05-04 09:29:00+07', '483', 'GK-KARDUS-000483', 'Atomy Promo Ramadhan 2', 'ATOMY-PROMO-RAMADHAN-2', 1, 0, '', '', 0, 'Admin', ''),
  (399, '399', 'MASUK', '2026-05-04 09:29:00+07', '483', 'GK-KARDUS-000483', 'Atomy Sunscreen White', 'ATOMY-SUNSCREEN-WHITE', 2, 0, '', '', 0, 'Admin', ''),
  (400, '400', 'MASUK', '2026-05-04 09:29:00+07', '483', 'GK-KARDUS-000483', 'Atomy Sunscreen Beige', 'ATOMY-SUNSCREEN-BEIGE', 2, 0, '', '', 0, 'Admin', ''),
  (401, '401', 'MASUK', '2026-05-04 09:29:00+07', '483', 'GK-KARDUS-000483', 'Atomy Healthy Glow Base', 'ATOMY-HEALTHY-GLOW-BASE', 1, 0, '', '', 0, 'Admin', ''),
  (402, '402', 'MASUK', '2026-05-04 09:31:00+07', '484', 'GK-KARDUS-000484', 'Atomy Promo Ramadhan 2', 'ATOMY-PROMO-RAMADHAN-2', 1, 0, '', '', 0, 'Admin', ''),
  (403, '403', 'MASUK', '2026-05-04 09:31:00+07', '484', 'GK-KARDUS-000484', 'Atomy Propolis Toothpaste 50g', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Admin', ''),
  (404, '404', 'MASUK', '2026-05-04 09:31:00+07', '485', 'GK-KARDUS-000485', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (405, '405', 'MASUK', '2026-05-04 09:33:00+07', '487', 'GK-KARDUS-000487', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (406, '406', 'MASUK', '2026-05-04 09:33:00+07', '487', 'GK-KARDUS-000487', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (407, '407', 'MASUK', '2026-05-04 09:36:00+07', '489', 'GK-KARDUS-000489', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (408, '408', 'MASUK', '2026-05-04 09:36:00+07', '486', 'GK-KARDUS-000486', 'Atomy Paket Berkah Ramadan C', 'ATOMY-PAKET-BERKAH-RAMADAN-C', 1, 0, '', '', 0, 'Admin', ''),
  (409, '409', 'MASUK', '2026-05-04 09:36:00+07', '486', 'GK-KARDUS-000486', 'Atomy Color Food Vitamin C', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 0, '', '', 0, 'Admin', ''),
  (410, '410', 'MASUK', '2026-05-04 09:36:00+07', '486', 'GK-KARDUS-000486', 'Atomy Finezyme', 'ATOMY-FINEZYME', 2, 0, '', '', 0, 'Admin', ''),
  (411, '411', 'MASUK', '2026-05-04 09:37:00+07', '490', 'GK-KARDUS-000490', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (412, '412', 'MASUK', '2026-05-04 09:38:00+07', '492', 'GK-KARDUS-000492', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (413, '413', 'MASUK', '2026-05-04 09:39:00+07', '491', 'GK-KARDUS-000491', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (414, '414', 'MASUK', '2026-05-04 09:40:00+07', '493', 'GK-KARDUS-000493', 'Atomy Paket Lebaran A (Health Care)', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, '', '', 0, 'Admin', ''),
  (415, '415', 'MASUK', '2026-05-04 09:41:00+07', '494', 'GK-KARDUS-000494', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (416, '416', 'MASUK', '2026-05-04 09:41:00+07', '495', 'GK-KARDUS-000495', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (417, '417', 'MASUK', '2026-05-04 09:44:00+07', '496', 'GK-KARDUS-000496', 'Atomy Promo Ramadhan 2', 'ATOMY-PROMO-RAMADHAN-2', 1, 0, '', '', 0, 'Admin', ''),
  (418, '418', 'MASUK', '2026-05-04 09:44:00+07', '496', 'GK-KARDUS-000496', 'Atomy Propolis Toothpaste 50g', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 2, 0, '', '', 0, 'Admin', ''),
  (419, '419', 'MASUK', '2026-05-04 09:46:00+07', '498', 'GK-KARDUS-000498', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (420, '420', 'MASUK', '2026-05-04 09:46:00+07', '499', 'GK-KARDUS-000499', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (421, '421', 'MASUK', '2026-05-04 09:48:00+07', '500', 'GK-KARDUS-000500', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (422, '422', 'MASUK', '2026-05-04 09:48:00+07', '501', 'GK-KARDUS-000501', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (423, '423', 'MASUK', '2026-05-04 09:53:00+07', '504', 'GK-KARDUS-000504', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (424, '424', 'MASUK', '2026-05-04 09:54:00+07', '503', 'GK-KARDUS-000503', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (425, '425', 'MASUK', '2026-05-04 09:55:00+07', '505', 'GK-KARDUS-000505', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (426, '426', 'MASUK', '2026-05-04 09:57:00+07', '508', 'GK-KARDUS-000508', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (427, '427', 'MASUK', '2026-05-04 09:58:00+07', '510', 'GK-KARDUS-000510', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (428, '428', 'MASUK', '2026-05-04 09:59:00+07', '504', 'GK-KARDUS-000504', 'Atomy Paket Berkah Ramadan C', 'ATOMY-PAKET-BERKAH-RAMADAN-C', 1, 0, '', '', 0, 'Admin', ''),
  (429, '429', 'MASUK', '2026-05-04 09:59:00+07', '504', 'GK-KARDUS-000504', 'Atomy Finezyme', 'ATOMY-FINEZYME', 2, 0, '', '', 0, 'Admin', ''),
  (430, '430', 'MASUK', '2026-05-04 09:59:00+07', '504', 'GK-KARDUS-000504', 'Atomy Color Food Vitamin C', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 0, '', '', 0, 'Admin', ''),
  (431, '431', 'MASUK', '2026-05-04 10:00:00+07', '511', 'GK-KARDUS-000511', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (432, '432', 'MASUK', '2026-05-04 10:01:00+07', '512', 'GK-KARDUS-000512', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (433, '433', 'MASUK', '2026-05-04 10:12:00+07', '513', 'GK-KARDUS-000513', 'Atomy Paket Lebaran A (Health Care)', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, '', '', 0, 'Admin', ''),
  (434, '434', 'MASUK', '2026-05-04 10:13:00+07', '514', 'GK-KARDUS-000514', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (435, '435', 'MASUK', '2026-05-04 10:16:00+07', '515', 'GK-KARDUS-000515', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (436, '436', 'MASUK', '2026-05-05 08:42:00+07', '516', 'GK-KARDUS-000516', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (437, '437', 'MASUK', '2026-05-05 08:44:00+07', '517', 'GK-KARDUS-000517', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (438, '438', 'MASUK', '2026-05-05 08:46:00+07', '518', 'GK-KARDUS-000518', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (439, '439', 'MASUK', '2026-05-05 08:50:00+07', '519', 'GK-KARDUS-000519', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (440, '440', 'MASUK', '2026-05-05 08:51:00+07', '520', 'GK-KARDUS-000520', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (441, '441', 'MASUK', '2026-05-05 08:51:00+07', '521', 'GK-KARDUS-000521', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (442, '442', 'MASUK', '2026-05-05 09:00:00+07', '523', 'GK-KARDUS-000523', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (443, '443', 'MASUK', '2026-05-05 09:00:00+07', '524', 'GK-KARDUS-000524', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (444, '444', 'MASUK', '2026-05-05 09:03:00+07', '525', 'GK-KARDUS-000525', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (445, '445', 'MASUK', '2026-05-05 09:11:00+07', '531', 'GK-KARDUS-000531', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (446, '446', 'MASUK', '2026-05-05 09:14:00+07', '530', 'GK-KARDUS-000530', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (447, '447', 'MASUK', '2026-05-05 09:15:00+07', '532', 'GK-KARDUS-000532', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (448, '448', 'MASUK', '2026-05-05 09:19:00+07', '533', 'GK-KARDUS-000533', 'Atomy Hongsamdan Red Ginseng', 'ATOMY-HONGSAMDAN-RED-GINSENG', 2, 0, '', '', 0, 'Admin', ''),
  (449, '449', 'MASUK', '2026-05-05 09:19:00+07', '533', 'GK-KARDUS-000533', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 1, 0, '', '', 0, 'Admin', ''),
  (450, '450', 'MASUK', '2026-05-05 09:19:00+07', '533', 'GK-KARDUS-000533', 'Atomy Evening Care 4 Set', 'ATOMY-EVENING-CARE-4-SET', 2, 0, '', '', 0, 'Admin', ''),
  (451, '451', 'MASUK', '2026-05-05 09:19:00+07', '533', 'GK-KARDUS-000533', 'Atomy Finezyme', 'ATOMY-FINEZYME', 2, 0, '', '', 0, 'Admin', ''),
  (452, '452', 'MASUK', '2026-05-05 09:19:00+07', '533', 'GK-KARDUS-000533', 'Atomy Evening Care Foam Cleanser', 'ATOMY-EVENING-CARE-FOAM-CLEANSER', 1, 0, '', '', 0, 'Admin', ''),
  (453, '453', 'MASUK', '2026-05-05 09:23:00+07', '534', 'GK-KARDUS-000534', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (454, '454', 'MASUK', '2026-05-05 09:28:00+07', '535', 'GK-KARDUS-000535', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (455, '455', 'MASUK', '2026-05-05 09:29:00+07', '536', 'GK-KARDUS-000536', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (456, '456', 'MASUK', '2026-05-05 09:30:00+07', '537', 'GK-KARDUS-000537', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (457, '457', 'MASUK', '2026-05-05 09:32:00+07', '540', 'GK-KARDUS-000540', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (458, '458', 'MASUK', '2026-05-05 09:33:00+07', '541', 'GK-KARDUS-000541', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (459, '459', 'MASUK', '2026-05-05 09:33:00+07', '538', 'GK-KARDUS-000538', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (460, '460', 'MASUK', '2026-05-05 09:35:00+07', '542', 'GK-KARDUS-000542', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (461, '461', 'MASUK', '2026-05-05 09:37:00+07', '543', 'GK-KARDUS-000543', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (462, '462', 'MASUK', '2026-05-05 09:38:00+07', '544', 'GK-KARDUS-000544', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (463, '463', 'MASUK', '2026-05-05 09:40:00+07', '546', 'GK-KARDUS-000546', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (464, '464', 'MASUK', '2026-05-05 09:40:00+07', '546', 'GK-KARDUS-000546', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (465, '465', 'MASUK', '2026-05-05 09:40:00+07', '547', 'GK-KARDUS-000547', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (466, '466', 'MASUK', '2026-05-05 09:42:00+07', '548', 'GK-KARDUS-000548', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (467, '467', 'MASUK', '2026-05-05 09:47:00+07', '551', 'GK-KARDUS-000551', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (468, '468', 'MASUK', '2026-05-05 09:49:00+07', '552', 'GK-KARDUS-000552', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (469, '469', 'MASUK', '2026-05-05 09:50:00+07', '553', 'GK-KARDUS-000553', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (470, '470', 'MASUK', '2026-05-05 09:52:00+07', '554', 'GK-KARDUS-000554', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 4, 0, '', '', 0, 'Admin', ''),
  (471, '471', 'MASUK', '2026-05-05 09:55:00+07', '556', 'GK-KARDUS-000556', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (472, '472', 'MASUK', '2026-05-05 09:56:00+07', '557', 'GK-KARDUS-000557', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (473, '473', 'MASUK', '2026-05-20 09:06:00+07', '566', 'GK-KARDUS-000566', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (474, '474', 'MASUK', '2026-05-20 09:07:00+07', '567', 'GK-KARDUS-000567', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (475, '475', 'MASUK', '2026-05-20 09:08:00+07', '568', 'GK-KARDUS-000568', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (476, '476', 'MASUK', '2026-05-20 09:09:00+07', '569', 'GK-KARDUS-000569', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (477, '477', 'MASUK', '2026-05-20 09:11:00+07', '570', 'GK-KARDUS-000570', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (478, '478', 'MASUK', '2026-05-20 09:12:00+07', '572', 'GK-KARDUS-000572', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (479, '479', 'MASUK', '2026-05-20 09:14:00+07', '573', 'GK-KARDUS-000573', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (480, '480', 'MASUK', '2026-05-20 09:19:00+07', '577', 'GK-KARDUS-000577', 'Atomy Psyllium Husk', 'ATOMY-PSYLLIUM-HUSK', 1, 0, '', '', 0, 'Admin', ''),
  (481, '481', 'MASUK', '2026-05-20 09:23:00+07', '578', 'GK-KARDUS-000578', 'Atomy Propolis Toothpaste 50g', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Admin', ''),
  (482, '482', 'MASUK', '2026-05-20 09:23:00+07', '578', 'GK-KARDUS-000578', 'Atomy Propolis Toothpaste 50g', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Admin', ''),
  (483, '483', 'MASUK', '2026-05-20 09:24:00+07', '580', 'GK-KARDUS-000580', 'Atomy Psyllium Husk', 'ATOMY-PSYLLIUM-HUSK', 1, 0, '', '', 0, 'Admin', ''),
  (484, '484', 'MASUK', '2026-05-20 09:26:00+07', '581', 'GK-KARDUS-000581', 'Atomy Hydra Brightening Care Set', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 1, 0, '', '', 0, 'Admin', ''),
  (485, '485', 'MASUK', '2026-05-20 09:26:00+07', '582', 'GK-KARDUS-000582', 'Atomy Psyllium Husk', 'ATOMY-PSYLLIUM-HUSK', 2, 0, '', '', 0, 'Admin', ''),
  (486, '486', 'MASUK', '2026-05-20 09:26:00+07', '582', 'GK-KARDUS-000582', 'Atomy Toothbrush', 'ATOMY-TOOTHBRUSH', 2, 0, '', '', 0, 'Admin', ''),
  (487, '487', 'MASUK', '2026-05-20 09:27:00+07', '583', 'GK-KARDUS-000583', 'Atomy Absolute CellActive Ampoule', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 2, 0, '', '', 0, 'Admin', ''),
  (488, '488', 'MASUK', '2026-05-20 09:28:00+07', '584', 'GK-KARDUS-000584', 'Atomy Absolute CellActive Skincare Set', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 2, 0, '', '', 0, 'Admin', ''),
  (489, '489', 'MASUK', '2026-05-20 09:31:00+07', '585', 'GK-KARDUS-000585', 'Atomy Absolute CellActive Skincare Set', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 2, 0, '', '', 0, 'Admin', ''),
  (490, '490', 'MASUK', '2026-05-20 09:31:00+07', '585', 'GK-KARDUS-000585', 'Atomy Propolis Toothpaste 50g', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Admin', ''),
  (491, '491', 'MASUK', '2026-05-20 09:32:00+07', '585', 'GK-KARDUS-000585', 'Atomy Propolis Toothpaste 50g', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Admin', ''),
  (492, '492', 'MASUK', '2026-05-20 09:32:00+07', '585', 'GK-KARDUS-000585', 'Atomy Pu''er Tea', 'ATOMY-PU-ER-TEA', 1, 0, '', '', 0, 'Admin', ''),
  (493, '493', 'MASUK', '2026-05-20 09:33:00+07', '586', 'GK-KARDUS-000586', 'Atomy Pu''er Tea', 'ATOMY-PU-ER-TEA', 1, 0, '', '', 0, 'Admin', ''),
  (494, '494', 'MASUK', '2026-05-20 09:36:00+07', '589', 'GK-KARDUS-000589', 'Atomy HemoHim', 'ATOMY-HEMOHIM', 2, 0, '', '', 0, 'Admin', ''),
  (495, '495', 'MASUK', '2026-05-20 09:36:00+07', '587', 'GK-KARDUS-000587', 'Atomy Propolis Toothpaste 50g', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 0, '', '', 0, 'Admin', ''),
  (496, '496', 'MASUK', '2026-05-20 09:37:00+07', '588', 'GK-KARDUS-000588', 'Atomy Psyllium Husk', 'ATOMY-PSYLLIUM-HUSK', 2, 0, '', '', 0, 'Admin', ''),
  (497, '496', 'MASUK', '2026-05-20 09:37:00+07', '588', 'GK-KARDUS-000588', 'Atomy Psyllium Husk', 'ATOMY-PSYLLIUM-HUSK', 2, 0, '', '', 0, 'Admin', ''),
  (498, '497', 'MASUK', '2026-05-20 09:37:00+07', '588', 'GK-KARDUS-000588', 'Atomy Psyllium Husk', 'ATOMY-PSYLLIUM-HUSK', 2, 0, '', '', 0, 'Admin', ''),
  (499, '498', 'MASUK', '2026-05-20 09:39:00+07', '591', 'GK-KARDUS-000591', 'Atomy Ethereal Oil Patch', 'ATOMY-ETHEREAL-OIL-PATCH', 5, 0, '', '', 0, 'Admin', ''),
  (500, '499', 'MASUK', '2026-05-20 09:39:00+07', '592', 'GK-KARDUS-000592', 'Atomy HemoHim 4 Sets', 'ATOMY-HEMOHIM-4-SETS', 1, 0, '', '', 0, 'Admin', ''),
  (501, '500', 'MASUK', '2026-05-20 09:45:00+07', '592', 'GK-KARDUS-000592', 'Atomy Ethereal Oil Patch', 'ATOMY-ETHEREAL-OIL-PATCH', 5, 0, '', '', 0, 'Admin', ''),
  (502, '501', 'MASUK', '2026-05-20 09:48:00+07', '594', 'GK-KARDUS-000594', 'Atomy Ethereal Oil Patch', 'ATOMY-ETHEREAL-OIL-PATCH', 5, 0, '', '', 0, 'Admin', ''),
  (503, '502', 'MASUK', '2026-05-20 09:48:00+07', '594', 'GK-KARDUS-000594', 'Atomy Ethereal Oil Patch', 'ATOMY-ETHEREAL-OIL-PATCH', 5, 0, '', '', 0, 'Admin', ''),
  (504, '503', 'MASUK', '2026-05-20 09:48:00+07', '595', 'GK-KARDUS-000595', 'Atomy HemoHim Set 4', 'ATOMY-HEMOHIM-SET-4', 1, 0, '', '', 0, 'Admin', ''),
  (505, '504', 'PENJUALAN', '2026-05-27 11:11:00+07', '584', 'GK-KARDUS-000584', 'Atomy Absolute CellActive Skincare Set', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, 'johnson', 'AMI ANTIKA SARI', 0, 'Admin', ''),
  (506, '505', 'MASUK', '2026-05-28 11:36:00+07', '596', 'GK-KARDUS-000596', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (507, '506', 'MASUK', '2026-05-30 09:17:00+07', '301', 'GK-KARDUS-000301', 'Atomy Promo Ramadhan 2', 'ATOMY-PROMO-RAMADHAN-2', 1, 0, '', '', 0, 'Admin', ''),
  (508, '507', 'MASUK', '2026-05-30 09:17:00+07', '301', 'GK-KARDUS-000301', 'Atomy Propolis Toothpaste 50g', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 2, 0, '', '', 0, 'Admin', ''),
  (509, '508', 'MASUK', '2026-05-30 09:19:00+07', '601', 'GK-KARDUS-000601', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (510, '509', 'MASUK', '2026-05-30 09:21:00+07', '602', 'GK-KARDUS-000602', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (511, '510', 'MASUK', '2026-05-30 09:21:00+07', '602', 'GK-KARDUS-000602', 'Atomy Psyllium Husk', 'ATOMY-PSYLLIUM-HUSK', 1, 0, '', '', 0, 'Admin', ''),
  (512, '511', 'MASUK', '2026-05-30 09:22:00+07', '600', 'GK-KARDUS-000600', 'Atomy Herbal Hair Conditioner', 'ATOMY-HERBAL-HAIR-CONDITIONER', 2, 0, '', '', 0, 'Admin', ''),
  (513, '512', 'MASUK', '2026-05-30 09:22:00+07', '600', 'GK-KARDUS-000600', 'Atomy Saengmodan Hair Tonic', 'ATOMY-SAENGMODAN-HAIR-TONIC', 2, 0, '', '', 0, 'Admin', ''),
  (514, '513', 'MASUK', '2026-05-30 09:22:00+07', '600', 'GK-KARDUS-000600', 'Atomy Herbal Hair Shampoo', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 0, '', '', 0, 'Admin', ''),
  (515, '514', 'MASUK', '2026-05-30 09:22:00+07', '600', 'GK-KARDUS-000600', 'Atomy Finezyme', 'ATOMY-FINEZYME', 2, 0, '', '', 0, 'Admin', ''),
  (516, '515', 'MASUK', '2026-05-30 09:22:00+07', '600', 'GK-KARDUS-000600', 'Atomy Color Food Vitamin C', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 0, '', '', 0, 'Admin', ''),
  (517, '516', 'MASUK', '2026-05-30 09:22:00+07', '600', 'GK-KARDUS-000600', 'Atomy Hair Essential Oil', 'ATOMY-HAIR-ESSENTIAL-OIL', 2, 0, '', '', 0, 'Admin', ''),
  (518, '517', 'MASUK', '2026-05-30 09:26:00+07', '605', 'GK-KARDUS-000605', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (519, '518', 'MASUK', '2026-05-30 09:26:00+07', '604', 'GK-KARDUS-000604', 'Atomy Paket Lebaran A (Health Care)', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, '', '', 0, 'Admin', ''),
  (520, '519', 'MASUK', '2026-05-30 09:27:00+07', '607', 'GK-KARDUS-000607', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (521, '520', 'MASUK', '2026-05-30 09:29:00+07', '604', 'GK-KARDUS-000604', 'Atomy Ethereal Oil Patch', 'ATOMY-ETHEREAL-OIL-PATCH', 4, 0, '', '', 0, 'Admin', ''),
  (522, '521', 'MASUK', '2026-05-30 09:34:00+07', '609', 'GK-KARDUS-000609', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (523, '522', 'MASUK', '2026-05-30 09:36:00+07', '610', 'GK-KARDUS-000610', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (524, '523', 'MASUK', '2026-05-30 09:38:00+07', '611', 'GK-KARDUS-000611', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (525, '524', 'MASUK', '2026-05-30 09:39:00+07', '610', 'GK-KARDUS-000610', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (526, '525', 'MASUK', '2026-05-30 09:39:00+07', '612', 'GK-KARDUS-000612', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (527, '526', 'MASUK', '2026-05-30 09:40:00+07', '613', 'GK-KARDUS-000613', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (528, '527', 'MASUK', '2026-05-30 09:41:00+07', '614', 'GK-KARDUS-000614', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (529, '528', 'MASUK', '2026-05-30 09:42:00+07', '615', 'GK-KARDUS-000615', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (530, '529', 'MASUK', '2026-05-30 09:42:00+07', '616', 'GK-KARDUS-000616', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (531, '530', 'MASUK', '2026-05-30 09:44:00+07', '617', 'GK-KARDUS-000617', 'Atomy Promo Ramadhan 1', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, '', '', 0, 'Admin', ''),
  (532, '531', 'MASUK', '2026-05-30 09:45:00+07', '618', 'GK-KARDUS-000618', 'Atomy Paket Berkah Ramadan A', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, '', '', 0, 'Admin', ''),
  (533, '532', 'MASUK', '2026-05-30 09:46:00+07', '619', 'GK-KARDUS-000619', 'Atomy Absolute CellActive Ampoule', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 1, 0, '', '', 0, 'Admin', ''),
  (534, '533', 'MASUK', '2026-05-30 09:46:00+07', '619', 'GK-KARDUS-000619', 'Atomy Absolute CellActive Skincare Set', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, '', '', 0, 'Admin', '')
on conflict (import_row_no) do update set
  client_id = excluded.client_id,
  type = excluded.type,
  date = excluded.date,
  kardus_id = excluded.kardus_id,
  mapped_id_box = excluded.mapped_id_box,
  product_name = excluded.product_name,
  mapped_sku = excluded.mapped_sku,
  qty = excluded.qty,
  price = excluded.price,
  buyer_name = excluded.buyer_name,
  transfer_to = excluded.transfer_to,
  transfer_amount = excluded.transfer_amount,
  performed_by = excluded.performed_by,
  notes = excluded.notes,
  imported_at = now();

insert into public.client_gudangku_paket_raw(
  import_row_no,
  package_no,
  package_code,
  package_name,
  product_name,
  mapped_sku,
  source_qty,
  qty_per_package,
  unit
)
values
  (1, '1', 'GKP-001', 'HemoHIM 1 Set', 'HemoHIM', 'HEMOHIM', '1 Set', 1, 'set'),
  (2, '2', 'GKP-002', 'HemoHIM 4 Set', 'HemoHIM', 'HEMOHIM', '4 Set', 4, 'set'),
  (3, '3', 'GKP-003', 'PV Up HemoHIM 4 Sets', 'HemoHIM', 'HEMOHIM', '4 Set', 4, 'set'),
  (4, '4', 'GKP-004', 'HemoHIM 4+1 Promo', 'HemoHIM', 'HEMOHIM', '5 Set', 5, 'set'),
  (5, '5', 'GKP-005', 'Hydra Brightening Care Set', 'Hydra Brightening Capsule Essence', 'HYDRA-BRIGHTENING-CAPSULE-ESSENCE', '1', 1, 'pcs'),
  (6, '5', 'GKP-005', 'Hydra Brightening Care Set', 'Hydra Brightening Cream', 'HYDRA-BRIGHTENING-CREAM', '1', 1, 'pcs'),
  (7, '6', 'GKP-006', 'Evening Care 4 Set', 'Deep Cleanser', 'DEEP-CLEANSER', '1', 1, 'pcs'),
  (8, '6', 'GKP-006', 'Evening Care 4 Set', 'Foam Cleanser', 'FOAM-CLEANSER', '1', 1, 'pcs'),
  (9, '6', 'GKP-006', 'Evening Care 4 Set', 'Peeling Gel', 'PEELING-GEL', '1', 1, 'pcs'),
  (10, '6', 'GKP-006', 'Evening Care 4 Set', 'Peel-Off Mask', 'PEEL-OFF-MASK', '1', 1, 'pcs'),
  (11, '7', 'GKP-007', 'Absolute CellActive Skincare Set', 'Toner', 'TONER', '1', 1, 'pcs'),
  (12, '7', 'GKP-007', 'Absolute CellActive Skincare Set', 'Ampoule', 'AMPOULE', '1', 1, 'pcs'),
  (13, '7', 'GKP-007', 'Absolute CellActive Skincare Set', 'Serum', 'SERUM', '1', 1, 'pcs'),
  (14, '7', 'GKP-007', 'Absolute CellActive Skincare Set', 'Lotion', 'LOTION', '1', 1, 'pcs'),
  (15, '7', 'GKP-007', 'Absolute CellActive Skincare Set', 'Eye Complex', 'EYE-COMPLEX', '1', 1, 'pcs'),
  (16, '7', 'GKP-007', 'Absolute CellActive Skincare Set', 'Nutrition Cream', 'NUTRITION-CREAM', '1', 1, 'pcs'),
  (17, '8', 'GKP-008', 'Derma Real Cica Set', 'Derma Real Cica Series Components', 'DERMA-REAL-CICA-SERIES-COMPONENTS', '1 Set', 1, 'set'),
  (18, '9', 'GKP-009', 'Synergy Ampoule Set', 'Synergy Ampoule', 'SYNERGY-AMPOULE', '1 Set', 1, 'set'),
  (19, '10', 'GKP-010', 'Cleansing Travel Kit', 'Travel Kit Components', 'TRAVEL-KIT-COMPONENTS', '1 Set', 1, 'set'),
  (20, '11', 'GKP-011', 'Oral Care System Set', 'Toothpaste + Toothbrush', 'TOOTHPASTE-TOOTHBRUSH', '1 Set', 1, 'set'),
  (21, '12', 'GKP-012', 'Toothpaste Set', 'Toothpaste', 'TOOTHPASTE', '5 pcs', 5, 'pcs'),
  (22, '13', 'GKP-013', 'Toothbrush Set', 'Toothbrush', 'TOOTHBRUSH', '8 pcs', 8, 'pcs'),
  (23, '14', 'GKP-014', 'Promo Ramadan 2026 Paket A', 'HemoHIM', 'HEMOHIM', '1', 1, 'pcs'),
  (24, '14', 'GKP-014', 'Promo Ramadan 2026 Paket A', 'Color Food Vitamin C', 'COLOR-FOOD-VITAMIN-C', '2', 2, 'pcs'),
  (25, '14', 'GKP-014', 'Promo Ramadan 2026 Paket A', 'Hongsamdan', 'HONGSAMDAN', '2', 2, 'pcs'),
  (26, '14', 'GKP-014', 'Promo Ramadan 2026 Paket A', 'Finezyme', 'FINEZYME', '2', 2, 'pcs'),
  (27, '15', 'GKP-015', 'Promo Ramadan 2026 Paket B', 'Toothpaste Set', 'TOOTHPASTE-SET', '2', 2, 'pcs'),
  (28, '15', 'GKP-015', 'Promo Ramadan 2026 Paket B', 'Toothbrush', 'TOOTHBRUSH', '2', 2, 'pcs'),
  (29, '15', 'GKP-015', 'Promo Ramadan 2026 Paket B', 'Sunscreen Beige', 'SUNSCREEN-BEIGE', '2', 2, 'pcs'),
  (30, '15', 'GKP-015', 'Promo Ramadan 2026 Paket B', 'Sunscreen White', 'SUNSCREEN-WHITE', '2', 2, 'pcs'),
  (31, '16', 'GKP-016', 'Promo Ramadan 2026 Paket C', 'Herbal Hair Shampoo', 'HERBAL-HAIR-SHAMPOO', '2', 2, 'pcs'),
  (32, '16', 'GKP-016', 'Promo Ramadan 2026 Paket C', 'Saengmodan Hair Tonic', 'SAENGMODAN-HAIR-TONIC', '2', 2, 'pcs'),
  (33, '16', 'GKP-016', 'Promo Ramadan 2026 Paket C', 'Herbal Hair Conditioner', 'HERBAL-HAIR-CONDITIONER', '2', 2, 'pcs'),
  (34, '16', 'GKP-016', 'Promo Ramadan 2026 Paket C', 'Hairessential Oil', 'HAIRESSENTIAL-OIL', '2', 2, 'pcs'),
  (35, '17', 'GKP-017', 'Promo Ramadan 2026 Paket D', 'Psyllium Husk', 'PSYLLIUM-HUSK', '2', 2, 'pcs'),
  (36, '18', 'GKP-018', 'Promo Ramadan 2026 Paket E', 'Easy Clean Water Filter Pitcher', 'EASY-CLEAN-WATER-FILTER-PITCHER', '2', 2, 'pcs'),
  (37, '19', 'GKP-019', 'Promotion PV Up Januari 2026', 'HemoHIM', 'HEMOHIM', '4 Set', 4, 'set'),
  (38, '20', 'GKP-020', 'Promo PV Up Mei 2025', 'HemoHIM', 'HEMOHIM', '4 Set', 4, 'set'),
  (39, '21', 'GKP-021', 'HemoHIM Spesial Promo 4 Gratis 1 April 2025', 'HemoHIM', 'HEMOHIM', '5 Set', 5, 'set'),
  (40, '22', 'GKP-022', 'Promotion PV Up November 2025', 'Puer Tea', 'PUER-TEA', '2', 2, 'pcs'),
  (41, '22', 'GKP-022', 'Promotion PV Up November 2025', 'Eye Health Luaxanthin', 'EYE-HEALTH-LUAXANTHIN', '1', 1, 'pcs')
on conflict (import_row_no) do update set
  package_no = excluded.package_no,
  package_code = excluded.package_code,
  package_name = excluded.package_name,
  product_name = excluded.product_name,
  mapped_sku = excluded.mapped_sku,
  source_qty = excluded.source_qty,
  qty_per_package = excluded.qty_per_package,
  unit = excluded.unit,
  imported_at = now();

insert into public.owners(id, owner_code, owner_name, atomy_member_id, notes, is_active)
values
  ('7782a13f-6a86-30ce-83e9-ee4fa368af1a', 'GK-7713-E4F48B', 'SAMUEL ANITA SAMUEL MALUMUS', '7713', 'Import GudangKu kardus. nomor_id=7713.', true),
  ('7e2e9e82-097a-3f0b-b072-949fa4cf8656', 'GK-7886-A34010', 'YOGA ANITA YOGA BAGUS', '7886', 'Import GudangKu kardus. nomor_id=7886.', true),
  ('c59d271a-dd18-3a82-895b-67212bf9f478', 'GK-9884-636FDA', 'ANITA BINTANG JECCIE LITAN JECCIE LITAN', '9884', 'Import GudangKu kardus. nomor_id=9884.', true),
  ('fa9f17d5-7e92-3a7b-b2c1-124761006c63', 'GK-6175-53C04A', 'ANITA BINTANG DWI MEDLIN DWI MEDLINS', '6175', 'Import GudangKu kardus. nomor_id=6175.', true),
  ('c4aaeaaa-7560-3a81-b5bd-d615b7306cf3', 'GK-6230-A3351D', 'AMI ARUM SARI', '6230', 'Import GudangKu kardus. nomor_id=6230.', true),
  ('73f3f2d6-b598-3418-a504-e43e8ba658f2', 'GK-6230-1BE427', 'DWI DWI SANTOSO', '6230', 'Import GudangKu kardus. nomor_id=6230.', true),
  ('528f5b13-45ba-3da6-b819-976a0dfdada8', 'GK-7426-0A142D', 'ATHI TEAM RINA ATHI BASTIANA MANIA WASI', '7426', 'Import GudangKu kardus. nomor_id=7426.', true),
  ('85ed0c8e-24bb-3b35-8ee2-6d3f80131753', 'GK-9891-BAE981', 'DWI T AMI DWI SANTOSO', '9891', 'Import GudangKu kardus. nomor_id=9891.', true),
  ('a3a2f521-ea69-339e-af14-dc85a6df0c0e', 'GK-9940-261550', 'SURYANI ARABIS TIKOMAH', '9940', 'Import GudangKu kardus. nomor_id=9940.', true),
  ('a8fb3580-6356-30f6-9b66-c4f17527ca14', 'GK-6194-540F0A', 'AMI LISTIA ERLIN LUPIANI', '6194', 'Import GudangKu kardus. nomor_id=6194.', true),
  ('76ca63da-82f3-374b-a767-24dce0cd7df9', 'GK-7916-B05F0F', 'ALVIN ANITA ALVIN', '7916', 'Import GudangKu kardus. nomor_id=7916.', true),
  ('9f557893-5121-3ed4-bd19-a881c722772b', 'GK-0028-1263DF', 'SURYANI ARA NOVAL PUSPITA SARI', '0028', 'Import GudangKu kardus. nomor_id=0028.', true),
  ('ce25201a-4867-34c9-a95f-055014efada3', 'GK-9784-8CF0AC', 'TJONG LI MI TJ AHJA LIAY', '9784', 'Import GudangKu kardus. nomor_id=9784.', true),
  ('19024175-e3aa-39b3-a419-01d63941ada8', 'GK-7802-DD41DB', 'DINDA ANITA DINDA SIMAUNG', '7802', 'Import GudangKu kardus. nomor_id=7802.', true),
  ('e1320d0c-babd-3a96-805a-c1031c6b6237', 'GK-9842-279DC7', 'ANITA BINTANG GILANG MUHAMMAD GILANG', '9842', 'Import GudangKu kardus. nomor_id=9842.', true),
  ('700603c9-51d4-3557-a6d1-bf2410df41b2', 'GK-9197-438819', 'FERRY ANITA FERRY SANTOSO', '9197', 'Import GudangKu kardus. nomor_id=9197.', true),
  ('d08a5167-a9b2-39d9-9896-73c7da93d062', 'GK-7770-F5621F', 'INTAN ANITA INTAN PERMATA', '7770', 'Import GudangKu kardus. nomor_id=7770.', true),
  ('19743c9b-8d10-3b4c-b1e3-fd82e73193a4', 'GK-8317-40C734', 'AHMAD FAUZAN T ERLINA MAD FAUZAN', '8317', 'Import GudangKu kardus. nomor_id=8317.', true),
  ('2a798915-8824-3201-9798-8d1c27fec0a2', 'GK-6146-15B92B', 'ANITA BINTANG SITI NURHALIZ A SITI NURHALIZA', '6146', 'Import GudangKu kardus. nomor_id=6146.', true),
  ('a4582259-489e-38a2-8c4f-9837c4c4d652', 'GK-1376-8E0DB1', 'NENG KANAN T PAPUA SUNARSIH', '1376', 'Import GudangKu kardus. nomor_id=1376.', true),
  ('d3cc94c1-f9e9-363c-9f89-afbad9b4a69a', 'GK-5034-43C1DD', 'SURYANI ARABA C HMAD TANTOWI', '5034', 'Import GudangKu kardus. nomor_id=5034.', true),
  ('b8011c30-05fc-30d8-84bf-e943c33838f6', 'GK-0353-4E1396', 'ANITA BINTANG SARWENDAH SARWENDAH HALIM', '0353', 'Import GudangKu kardus. nomor_id=0353.', true),
  ('2cdcf10e-7e6c-3390-9fdc-28d7ae29b498', 'GK-7455-53E31A', 'DENNY ANITA DENNY SETIAWAN', '7455', 'Import GudangKu kardus. nomor_id=7455.', true),
  ('4b82e92a-1777-3104-8f29-f151403b0dda', 'GK-6177-D0F7F8', 'ANITA BINTANG ZAKI MUBARAK ZAKI MUBARAK', '6177', 'Import GudangKu kardus. nomor_id=6177.', true),
  ('9c9994ff-62ba-35f2-890c-29e44e690aef', 'GK-9881-047ABC', 'EKO T AMI EKO NUGROHO', '9881', 'Import GudangKu kardus. nomor_id=9881.', true),
  ('9a220225-0af4-3bb5-ad00-73997642a122', 'GK-1272-7ABC75', 'NIRMA TEAM RINA NIRMA', '1272', 'Import GudangKu kardus. nomor_id=1272.', true),
  ('4ffcfb53-f03e-3f28-8b88-17ba83760293', 'GK-9889-D6EF8D', 'AMELIA AMELIA BADUI', '9889', 'Import GudangKu kardus. nomor_id=9889.', true),
  ('8236253b-69dd-3a3c-8342-442c2044d2c9', 'GK-0190-04EBA9', 'TJONG LI MI NABILA', '0190', 'Import GudangKu kardus. nomor_id=0190.', true),
  ('f7328cf5-a463-31b9-bc0a-a433d14c46f9', 'GK-6127-970BA2', 'ANITA BINTANG SITI AULIA SITI AULIA', '6127', 'Import GudangKu kardus. nomor_id=6127.', true),
  ('b63a495b-e6d1-388e-860c-803cc78f120d', 'GK-0491-A6683B', 'AMI AMALIA PUTRI', '0491', 'Import GudangKu kardus. nomor_id=0491.', true),
  ('e7f9ab05-73c9-38bb-859a-cbdf307268f3', 'GK-6205-9DF1CE', 'TAUFI TAUFIK', '6205', 'Import GudangKu kardus. nomor_id=6205.', true),
  ('be45d6e9-8540-3b6e-b63d-65b43f070b75', 'GK-0080-B7F529', 'TJONG LI MI ASEP', '0080', 'Import GudangKu kardus. nomor_id=0080.', true),
  ('20490f58-c74e-31e6-99b4-531927f075e1', 'GK-9813-9B5734', 'SURYANI ARAB SILVIA', '9813', 'Import GudangKu kardus. nomor_id=9813.', true),
  ('89a03df5-cfca-328b-99c5-eed76abf6aef', 'GK-3586-830929', 'ANITA BINTANG WENDI SALIM WENDI SALIN', '3586', 'Import GudangKu kardus. nomor_id=3586.', true),
  ('92e02264-de12-3835-a475-d8f04ee3a32d', 'GK-9736-337511', 'TJONG LI MI HERLAN PERLANA', '9736', 'Import GudangKu kardus. nomor_id=9736.', true),
  ('48d6477e-b752-3f93-881c-8ed255786a94', 'GK-0082-9B1E23', 'TJONG LI MI MICAHEL PRATAMA SOELI ES TYO', '0082', 'Import GudangKu kardus. nomor_id=0082.', true),
  ('c775846a-ee6b-3e8c-93df-ddb90a25d924', 'GK-6196-0D22E4', 'AMI MIRA RACHEL', '6196', 'Import GudangKu kardus. nomor_id=6196.', true),
  ('b1428850-d152-31e1-add1-51f861f26a48', 'GK-6193-A3351D', 'AMI ARUM SARI', '6193', 'Import GudangKu kardus. nomor_id=6193.', true),
  ('fd94dfad-01c2-3cd7-aa3d-b1ba5b7402e4', 'GK-8282-72DB09', 'AMI TEGUH PRAKOSO', '8282', 'Import GudangKu kardus. nomor_id=8282.', true),
  ('314a2d48-7e6f-3019-9006-ddd725fdc36d', 'GK-9723-902F19', 'NENG KANAN T PAPUA SITI KHUSNUL', '9723', 'Import GudangKu kardus. nomor_id=9723.', true),
  ('ea883bbd-eff0-33c4-9b33-b0a8e075c124', 'GK-9993-28045E', 'neng kanan t papua lina nurlina', '9993', 'Import GudangKu kardus. nomor_id=9993.', true),
  ('f08ab001-2970-3cae-a1e0-67cb145a9a29', 'GK-7748-DAB0FB', 'eka anita eka suptra', '7748', 'Import GudangKu kardus. nomor_id=7748.', true),
  ('0725e484-7dfe-3318-871f-4b00450e9462', 'GK-1382-148E5E', 'DEVIN MULYONO T WIFA DEVIN MULYONO', '1382', 'Import GudangKu kardus. nomor_id=1382.', true),
  ('ac8f506e-21a5-3767-9cb3-7f558f2adb7b', 'GK-6147-0E960A', 'ANITA BINTANG DIN BOENTARAN PIN BOENTARAN', '6147', 'Import GudangKu kardus. nomor_id=6147.', true),
  ('36e7614e-2d90-3744-984f-73fc84f861f2', 'GK-0357-C1FA8A', 'ANITA BINTANG DODHY DODHY ROHMAT', '0357', 'Import GudangKu kardus. nomor_id=0357.', true),
  ('bf684616-3e6d-3306-93a9-0aaf929e05af', 'GK-9766-54FA8A', 'TJONG LI MI NGATIAH', '9766', 'Import GudangKu kardus. nomor_id=9766.', true),
  ('a63ff46b-71c0-3b77-8fa4-ee0172cd0568', 'GK-7620-F88A6D', 'NENG KANAN T PAPUA CICI SRIYANA', '7620', 'Import GudangKu kardus. nomor_id=7620.', true),
  ('76078f41-a668-313c-b2ec-4040451d0667', 'GK-8255-E7A7AA', 'WENDY SELVI WENDI CAGUR', '8255', 'Import GudangKu kardus. nomor_id=8255.', true),
  ('3164272f-cf61-3b04-8873-8c7630853fde', 'GK-6149-637C80', 'ANITA BINTANG SARI SARI', '6149', 'Import GudangKu kardus. nomor_id=6149.', true),
  ('29a93f1f-e066-3e87-a243-2df5493c372c', 'GK-6126-11B62A', 'ANITA BINTANG HAFSAH NABILA HAFSAH', '6126', 'Import GudangKu kardus. nomor_id=6126.', true),
  ('1d96428d-f7ce-3fe3-80d3-57cb3f8ad064', 'GK-6150-E5C412', 'ANITA BINTANG NADIA NADIA', '6150', 'Import GudangKu kardus. nomor_id=6150.', true),
  ('5fd38880-8b9e-3544-a469-a071b5866400', 'GK-9816-1D8A39', 'NENG KANAN T PAPUA CANTIKA PUTRI', '9816', 'Import GudangKu kardus. nomor_id=9816.', true),
  ('29bd73cc-a93d-3520-bea7-f8161dc858fe', 'GK-0085-50E873', 'TJONG LI MI KIKI RUHMAN', '0085', 'Import GudangKu kardus. nomor_id=0085.', true),
  ('0e94c8e5-a643-3da3-a738-920fe90e2e53', 'GK-6152-DD0C77', 'ANITA BINTANG GITA MAHARANI GITA MAHARANI', '6152', 'Import GudangKu kardus. nomor_id=6152.', true),
  ('6378fb42-d3a9-307c-917f-1df0b41ab884', 'GK-8249-0AA66D', 'LESTARI HANDAYANI T ERLINE LESTARI', '8249', 'Import GudangKu kardus. nomor_id=8249.', true),
  ('9cd908de-b6ed-3399-a025-4060c4cce74f', 'GK-9742-5FE752', 'TJONG LI MI KRIS PINUS KAPITAN TENA NIRON', '9742', 'Import GudangKu kardus. nomor_id=9742.', true),
  ('73f5ff64-42fe-3307-a6e7-296d82de5cc0', 'GK-8307-07A775', 'nofliana selvi NOFLIANA GRESCE MANU', '8307', 'Import GudangKu kardus. nomor_id=8307.', true),
  ('1b4e8880-3987-3dde-af6d-a092a0610414', 'GK-6171-7F213D', 'ANITA BINTANG ALFAHRIALFAHRI', '6171', 'Import GudangKu kardus. nomor_id=6171.', true),
  ('f3de32bf-a33c-3c79-8452-a38c373724d8', 'GK-0170-03DBCF', 'TJONG LI MI MANDIKA', '0170', 'Import GudangKu kardus. nomor_id=0170.', true),
  ('eeccc26a-f953-3f47-be38-e4058016bee4', 'GK-6819-F8058D', 'AJENG AJENG SUITA', '6819', 'Import GudangKu kardus. nomor_id=6819.', true),
  ('5bdc5402-57cd-3307-a0af-30e825a2b0e4', 'GK-8220-C33D07', 'TINA MARIANA DMAMI', '8220', 'Import GudangKu kardus. nomor_id=8220.', true),
  ('c34741eb-ff3e-33a7-b3b6-c776da7918e2', 'GK-9809-899033', 'TJONG LI MI ANITA KELOP', '9809', 'Import GudangKu kardus. nomor_id=9809.', true),
  ('6dab80d9-6e52-3344-aef6-184e8f721c47', 'GK-0354-FECF58', 'ANITA BINTANG BUDI EMAN BUDI EMAN', '0354', 'Import GudangKu kardus. nomor_id=0354.', true),
  ('48e03172-ed6b-3527-8e45-d47c656da540', 'GK-4819-544857', 'SURYANI ARAB RINI YASLIANA SITOHAMG', '4819', 'Import GudangKu kardus. nomor_id=4819.', true),
  ('18cf868e-fd52-30bf-9efd-5bf5e073775e', 'GK-7926-DCCEFB', 'SUMANTO ANITA SUMANTO HALIM', '7926', 'Import GudangKu kardus. nomor_id=7926.', true),
  ('847e43c9-f597-370a-b22d-96ead5c6271e', 'GK-9894-810E33', 'SURYA T AMI SURYA MAHENDRA', '9894', 'Import GudangKu kardus. nomor_id=9894.', true),
  ('d7d67e97-f98f-3cff-9e9f-4c6cec145f64', 'GK-0291-684578', 'TJONG LI MI NANDA BERMAHTA', '0291', 'Import GudangKu kardus. nomor_id=0291.', true),
  ('a1a699ac-c997-361e-8c62-5a72d7bd3c34', 'GK-0395-D3A1E9', 'ESRA TEAM RINA ESRA RENDEN', '0395', 'Import GudangKu kardus. nomor_id=0395.', true),
  ('ff9097fe-44fd-348f-8a01-8f7d7409edeb', 'GK-0360-165132', 'ANITA BINTANG DONI DONI', '0360', 'Import GudangKu kardus. nomor_id=0360.', true),
  ('70c52bdd-ac0c-3895-be17-b331ae6a13b1', 'GK-9808-91FA6B', 'TJONG LI MI AGUS SEPTIAN', '9808', 'Import GudangKu kardus. nomor_id=9808.', true),
  ('c1562dcc-41d4-377c-b9a5-39768627d1f8', 'GK-0352-AA3E8F', 'ANITA BINTANG GALIH GALIH SAPUTRO', '0352', 'Import GudangKu kardus. nomor_id=0352.', true),
  ('7c7874db-fd17-37c2-8c36-734acbe906cf', 'GK-0290-25E319', 'TJONG LI MI LALA KIKI', '0290', 'Import GudangKu kardus. nomor_id=0290.', true),
  ('0757f7ff-abc0-31aa-a7c7-e3a529dbfd77', 'GK-9884-466A96', 'TJONG LI MI DINDA PUTRI', '9884', 'Import GudangKu kardus. nomor_id=9884.', true),
  ('ab29ac83-e638-323e-b662-c65e72c4b9ee', 'GK-6197-7E380A', 'AMIVINA AMELIA', '6197', 'Import GudangKu kardus. nomor_id=6197.', true),
  ('2eba17e2-9edc-36d3-b03f-04a68d003831', 'GK-6219-E2E1A7', 'ADUL SELVI ABDUL AZIZ', '6219', 'Import GudangKu kardus. nomor_id=6219.', true),
  ('0396d25b-a7e2-3fb4-9bc8-a9fdb0c661d5', 'GK-9226-748A29', 'DERLY TEAM RINA DERLY APRILIANY', '9226', 'Import GudangKu kardus. nomor_id=9226.', true),
  ('3639b306-abb3-3dd8-8763-18013f41e5d4', 'GK-6219-AD2911', 'JANSEN HUTAPEA T MAWARNI JANSEN HUTAPEA', '6219', 'Import GudangKu kardus. nomor_id=6219.', true),
  ('9a906a1b-d278-366d-80bf-2c74ef496f9d', 'GK-9729-439989', 'TJONG LI MI LALITA AGUSTIN', '9729', 'Import GudangKu kardus. nomor_id=9729.', true),
  ('1f45c20d-47d4-3f8a-9ed4-00d14db8895c', 'GK-9886-F2F2F8', 'ANITA BINTANG DEVIN DEVIN', '9886', 'Import GudangKu kardus. nomor_id=9886.', true),
  ('6dc7acaa-49c3-3d19-ba2e-ce265ad1fc05', 'GK-6131-0C39EA', 'ANITA BINTANG ANDREAS ANDREAS', '6131', 'Import GudangKu kardus. nomor_id=6131.', true),
  ('ed766795-6515-3542-9ee2-c666335def42', 'GK-0359-76F222', 'ANITA BINTANG ARIF HIDAYAT', '0359', 'Import GudangKu kardus. nomor_id=0359.', true),
  ('d8e6cafe-429a-3d2d-bc68-f670550a9c62', 'GK-6204-08EF5D', 'HUSEN JAYA LAKSANA SELVI HUSEN JAYA', '6204', 'Import GudangKu kardus. nomor_id=6204.', true),
  ('9fc39710-09e5-3657-ac45-3b882344381f', 'GK-0928-7800C6', 'NENG KANAN T PAPUA HERI KUSWANTO', '0928', 'Import GudangKu kardus. nomor_id=0928.', true),
  ('e88a8a94-36e3-3724-8424-aad99a6e088c', 'GK-3482-85F02C', 'AMI RAISA AFRA SAKILA', '3482', 'Import GudangKu kardus. nomor_id=3482.', true),
  ('1b78a26e-384f-345c-b47d-87f5ccf9172e', 'GK-9801-7C8F69', 'WULAN ANITA WULAN', '9801', 'Import GudangKu kardus. nomor_id=9801.', true),
  ('928f2e9c-7b88-3a2c-b813-e69825f8b673', 'GK-4282-53768B', 'DODI IMANUEL ANITA DODI IMANUEL', '4282', 'Import GudangKu kardus. nomor_id=4282.', true),
  ('88a4e2c6-214b-3109-b6f7-af2d37260ae6', 'GK-9733-B786FE', 'TJONG LI MI TIARA VINA', '9733', 'Import GudangKu kardus. nomor_id=9733.', true),
  ('4f8514b5-13c7-380c-bd09-65ba79da0210', 'GK-7632-BE3F0A', 'YERIKHO ANITA YERIKHO RIDO HUTAHAEAN', '7632', 'Import GudangKu kardus. nomor_id=7632.', true),
  ('e0845995-98a8-3dce-af9c-4d372b430588', 'GK-6391-9B2A31', 'AMI ANGGA PRANATA', '6391', 'Import GudangKu kardus. nomor_id=6391.', true),
  ('18d66855-3eab-3b46-954d-5e863ce0aef9', 'GK-6173-1554D7', 'ANITA BINTANG DEDI MULYANTO DEDI MULYANTO', '6173', 'Import GudangKu kardus. nomor_id=6173.', true),
  ('3b215ab6-423d-39b5-a1a1-a4736bd7ca9d', 'GK-6170-5462BE', 'ANITA BINTANG RAIHAN NUGRAHA RAIHAN', '6170', 'Import GudangKu kardus. nomor_id=6170.', true),
  ('9940a891-a41e-3850-a7f7-976b169e3216', 'GK-0356-E3BAC3', 'ANITA BINTANG RAMI RAMA ADITYA', '0356', 'Import GudangKu kardus. nomor_id=0356.', true),
  ('459c6645-b4b9-398e-9f57-bb198a3b2152', 'GK-4807-4953AE', 'ANITA BINTANG BAGAS BAGAS ADIPUTRA', '4807', 'Import GudangKu kardus. nomor_id=4807.', true),
  ('a10a70b6-4d22-3514-b331-48d0f8886d59', 'GK-1486-CF8F25', 'AMI VINA AMELIA', '1486', 'Import GudangKu kardus. nomor_id=1486.', true),
  ('86bb07cf-9b79-38fd-8f75-0e6225e049a4', 'GK-6129-C9998E', 'ANITA BINTANG VENDA HALIN VENDA HALIN', '6129', 'Import GudangKu kardus. nomor_id=6129.', true),
  ('5681905b-9793-3dde-930b-4150c9156267', 'GK-9855-68B36E', 'NENG KANAN T PAPUA WIDURI', '9855', 'Import GudangKu kardus. nomor_id=9855.', true),
  ('07bc0fe0-38c1-35f8-8540-0afd91a6fbdb', 'GK-7827-54C2BB', 'HERMANSYAH ANITA', '7827', 'Import GudangKu kardus. nomor_id=7827.', true),
  ('fbdf90cc-7049-35a7-944f-7a11d91c7bd6', 'GK-7507-427FF3', 'NENG KANAN T PAPUA YULLI', '7507', 'Import GudangKu kardus. nomor_id=7507.', true),
  ('ef366289-e74d-3c47-b55a-5f4d5f060d89', 'GK-8243-793E7C', 'AMI ABDUL RAHMAN', '8243', 'Import GudangKu kardus. nomor_id=8243.', true),
  ('38fa826d-644d-3d9f-b422-2401c3bc3ce7', 'GK-4805-68086A', 'ANITA BINTANG KEYLA', '4805', 'Import GudangKu kardus. nomor_id=4805.', true),
  ('23ead638-f871-3a86-b36a-c85601703a4b', 'GK-6130-2915B7', 'ANITA BINTANG IDAH IDAH', '6130', 'Import GudangKu kardus. nomor_id=6130.', true),
  ('9beae500-112d-339d-aa2f-98aed175affc', 'GK-7850-F7EE9F', 'FARHAN ANITA MAULANA', '7850', 'Import GudangKu kardus. nomor_id=7850.', true),
  ('b8eb2fc5-5268-3af9-ae9b-a078c38a3e00', 'GK-6179-294269', 'ANITA BINTANG SOFIAH HUSNA SHOFIA', '6179', 'Import GudangKu kardus. nomor_id=6179.', true),
  ('a13011eb-587b-3d75-805b-fe000147c779', 'GK-7821-137F7A', 'FADLI ANITA', '7821', 'Import GudangKu kardus. nomor_id=7821.', true),
  ('a39851a8-f451-3b8d-9f07-09d7e53b4edd', 'GK-0041-889FD0', 'NENG KANAN T PAPUA LIAM PUTRA', '0041', 'Import GudangKu kardus. nomor_id=0041.', true),
  ('2bfeca56-29b9-3e7c-b4ef-6f95aefb5fee', 'GK-6195-63CBA3', 'AMI T MAWARNI SARTIKA', '6195', 'Import GudangKu kardus. nomor_id=6195.', true),
  ('527067f4-de9d-392e-8acc-add575b24dfe', 'GK-0096-2EDE46', 'TJONG LI MI JANUAR HENDRATAMA', '0096', 'Import GudangKu kardus. nomor_id=0096.', true),
  ('bc7c029c-8d15-3716-9e3e-3336c3a5fdbd', 'GK-7737-B72624', 'RAHMAD ANITA RAHMAD HIDAYAT', '7737', 'Import GudangKu kardus. nomor_id=7737.', true),
  ('906cbacf-caba-3a82-baff-97366248aa2c', 'GK-6207-FEB098', 'ABDUL SELVI ABDUL AZIZ', '6207', 'Import GudangKu kardus. nomor_id=6207.', true),
  ('1a772fe9-ab15-34e9-8045-33a8c4608753', 'GK-9882-AAD4C1', 'AMALIA AMALIA SAFIRA', '9882', 'Import GudangKu kardus. nomor_id=9882.', true),
  ('6f34c8ad-d96a-3e31-99b9-eca6a4902a60', 'GK-7736-D6B56B', 'MIRENDI ANITA MIRENDI SAMBO', '7736', 'Import GudangKu kardus. nomor_id=7736.', true),
  ('7b2bc19d-af4a-3845-bd23-c635bf5f7c1e', 'GK-4216-50E873', 'TJONG LI MI KIKI RUHMAN', '4216', 'Import GudangKu kardus. nomor_id=4216.', true),
  ('f0d5d998-943d-31ce-8b5f-872ba2841272', 'GK-9965-C04674', 'NENG KANAN T PAPUA ARFATHAN MALIK RAZI', '9965', 'Import GudangKu kardus. nomor_id=9965.', true),
  ('dea3424f-0677-3f5a-9d20-7f4a57a78abe', 'GK-4219-684578', 'TJONG LI MI NANDA BERMAHTA', '4219', 'Import GudangKu kardus. nomor_id=4219.', true),
  ('87d537d3-a98b-3504-963c-c3191983e482', 'GK-7546-5A7792', 'DENI ANITA DENI KURNIAWAN', '7546', 'Import GudangKu kardus. nomor_id=7546.', true),
  ('2aefffae-7e02-31fe-b3d0-bf01ac925e86', 'GK-2215-8E0DB1', 'NENG KANAN T PAPUA SUNARSIH', '2215', 'Import GudangKu kardus. nomor_id=2215.', true),
  ('79fbc7de-30ac-398b-8439-f17416346909', 'GK-4224-69E415', 'TJONG LI MI SUKIRNO', '4224', 'Import GudangKu kardus. nomor_id=4224.', true),
  ('a4def46d-729c-3bd7-b74f-2157584c8ce2', 'GK-6178-5364F7', 'ANITA BINTANG WENNY', '6178', 'Import GudangKu kardus. nomor_id=6178.', true),
  ('94357601-8530-315a-8b06-60f24e3b5d6d', 'GK-4228-A6683B', 'AMI AMALIA PUTRI', '4228', 'Import GudangKu kardus. nomor_id=4228.', true),
  ('eb9d9736-3ea5-355a-aa14-28520101c521', 'GK-3592-8CE143', 'ANITA BINTAMG RIAN FIRMANSYAH', '3592', 'Import GudangKu kardus. nomor_id=3592.', true),
  ('6c3ad998-c711-309e-b1d7-cbcf0610b54e', 'GK-7592-B786FE', 'TJONG LI MI TIARA VINA', '7592', 'Import GudangKu kardus. nomor_id=7592.', true),
  ('8523b989-3640-3c3a-b707-9640f5a8a606', 'GK-4214-68D112', 'TJONG LI MI MICHAEL PRATAMA SOELIESTYO', '4214', 'Import GudangKu kardus. nomor_id=4214.', true),
  ('7cf5975d-a969-30b3-9778-1c4f5c269250', 'GK-3589-5DB3D7', 'ANITA BINTANG ARDIANSYAH PUTRA', '3589', 'Import GudangKu kardus. nomor_id=3589.', true),
  ('fa300f52-53bc-320d-b40d-9aeadd9eb487', 'GK-4222-2E05FC', 'TJONG LALA KIKI', '4222', 'Import GudangKu kardus. nomor_id=4222.', true),
  ('b1307f15-64ae-3924-89c7-a3870f5cd176', 'GK-7581-704847', 'ELLYS BYRALIMUDDIN DG NAI', '7581', 'Import GudangKu kardus. nomor_id=7581.', true),
  ('ffba52d1-e74c-3522-8c58-7d7d2632c2e1', 'GK-0367-53768B', 'DODI IMANUEL ANITA DODI IMANUEL', '0367', 'Import GudangKu kardus. nomor_id=0367.', true),
  ('14e72ef0-4d5b-3e84-b9ff-0208d4dfdc1d', 'GK-3575-A1C36D', 'ANITA BINTANG MIRA RACHEL', '3575', 'Import GudangKu kardus. nomor_id=3575.', true),
  ('6edf4e4b-d14d-3b27-b31f-088d23663ae3', 'GK-8237-D7E9CC', 'MARIANI SELVI PAKPAHAN', '8237', 'Import GudangKu kardus. nomor_id=8237.', true),
  ('3ea27847-6992-3cc7-8351-cbdef1dbc231', 'GK-0319-6E0B32', 'AMI ASNI PASARIBU', '0319', 'Import GudangKu kardus. nomor_id=0319.', true),
  ('52fa9da8-a39e-3143-b081-f76b5bd55310', 'GK-9835-DD482A', 'NENG KANAN T PAPUA ABDURAHMAN', '9835', 'Import GudangKu kardus. nomor_id=9835.', true),
  ('53d2e963-6d76-3128-99c9-323d3b4be46e', 'GK-9740-B5547E', 'NENG KANAN T PAPUA RINA HANDAYANI', '9740', 'Import GudangKu kardus. nomor_id=9740.', true),
  ('b9f9febe-aa93-3698-ac07-4d4f1541c0f7', 'GK-9943-6F116C', 'NABILA ANITA NABILA', '9943', 'Import GudangKu kardus. nomor_id=9943.', true),
  ('1c083f83-3eac-39a3-902e-8fd3bd65e8c8', 'GK-0587-067B0E', 'AMI RAISHA AFRA SAKILA', '0587', 'Import GudangKu kardus. nomor_id=0587.', true),
  ('7b2b35b3-ee0d-3a93-b521-623381f2be26', 'GK-7622-895F67', 'NENG KANAN T PAPUA ARUNA PUTRI', '7622', 'Import GudangKu kardus. nomor_id=7622.', true),
  ('1c0f9733-766d-349f-a701-37532ed43db4', 'GK-9968-5F8860', 'RUDIANTO TEAM RINA RUDIANTO', '9968', 'Import GudangKu kardus. nomor_id=9968.', true),
  ('86da45b0-ca4f-3299-991e-19eb68c23f9f', 'GK-4208-5232D0', 'TJONG LI MI ANDIKA', '4208', 'Import GudangKu kardus. nomor_id=4208.', true),
  ('15920407-df39-31eb-8049-e6db99bb259e', 'GK-1359-355619', 'TJAHJA LIAY T WIFATJAHJA LIAY', '1359', 'Import GudangKu kardus. nomor_id=1359.', true),
  ('a5510f0b-4216-3427-a452-e620715490ba', 'GK-6616-D001E7', 'GINTING ANITA GINTING HAMATIR', '6616', 'Import GudangKu kardus. nomor_id=6616.', true),
  ('47333066-9a9a-3398-9411-6eb3051180bb', 'GK-9754-D6C0C7', 'NENG KANAN T PAPUA UUM SUPRIYADI', '9754', 'Import GudangKu kardus. nomor_id=9754.', true),
  ('90180cfa-9066-3cf5-a98b-8b655c39f0e1', 'GK-9802-B441AB', 'EVA ANITA EKA SAPUTRA', '9802', 'Import GudangKu kardus. nomor_id=9802.', true),
  ('a6c7d1a1-a0d3-32c9-95d7-854adf24345b', 'GK-0000-615F28', 'MARCO ANITA MARCORIUS', '0000', 'Import GudangKu kardus. nomor_id=0000.', true),
  ('b9a32991-6568-3247-b8e7-fac58ecb2f09', 'GK-9781-E4F48B', 'SAMUEL ANITA SAMUEL MALUMUS', '9781', 'Import GudangKu kardus. nomor_id=9781.', true),
  ('3e04d9f7-549d-3e1c-b0bf-81145946d2ac', 'GK-0236-8B7DA3', 'JUMRIYEH ANITA JUMRIYEH', '0236', 'Import GudangKu kardus. nomor_id=0236.', true),
  ('f5c02823-1625-3c5d-8254-7449dc96593d', 'GK-6212-08EF5D', 'HUSEN JAYA LAKSANA SELVI HUSEN JAYA', '6212', 'Import GudangKu kardus. nomor_id=6212.', true),
  ('691f2953-2e7f-36c8-be26-8afc2845a511', 'GK-6212-9DF1CE', 'TAUFI TAUFIK', '6212', 'Import GudangKu kardus. nomor_id=6212.', true),
  ('638000f4-3ffd-382c-a9c8-14af3368aef6', 'GK-4895-FF3A86', 'TJONG LI MI ELIA FERNANDO PURBA', '4895', 'Import GudangKu kardus. nomor_id=4895.', true),
  ('d40b5e52-e47b-3f8d-b89e-6ea4582c319c', 'GK-5035-B501E8', 'TJONG LI MI ALOY HALIMUS', '5035', 'Import GudangKu kardus. nomor_id=5035.', true),
  ('88b7631c-5f36-35e4-a99f-b552cc6df473', 'GK-9795-F312F0', 'NENG KANAN T PAPUA KURNIA HIDAYAT', '9795', 'Import GudangKu kardus. nomor_id=9795.', true),
  ('06d96f8d-1ad6-31b3-9611-534a97297174', 'GK-9709-5993C3', 'NENG KANAN T PAPUA RAMDAN', '9709', 'Import GudangKu kardus. nomor_id=9709.', true),
  ('657e4cac-b60a-393f-a9d2-6017c627071d', 'GK-8172-AA7BE3', 'AMI BUYUNG TANJUNG', '8172', 'Import GudangKu kardus. nomor_id=8172.', true),
  ('6a286141-35c3-33d4-af8a-fe55770c06ef', 'GK-6274-465203', 'ANITA BINTANG GILANG MUHAMMAD', '6274', 'Import GudangKu kardus. nomor_id=6274.', true),
  ('a5f6225d-d2ad-3407-af7a-253587916831', 'GK-7610-03E1AB', 'HERMIN TEAM RINA HERMIN PAKIDING', '7610', 'Import GudangKu kardus. nomor_id=7610.', true),
  ('d34d45e3-325d-3834-b03c-68e7f27f73a6', 'GK-8301-A95757', 'AMI ANGGA SAPUTERA', '8301', 'Import GudangKu kardus. nomor_id=8301.', true),
  ('ce78c6dc-5c8d-3d8e-96fa-c9a197c6e0d9', 'GK-7586-04B1C4', 'NENG KANAN T PAPUA AMMAR KHOLID', '7586', 'Import GudangKu kardus. nomor_id=7586.', true),
  ('272bf9f4-fe25-3519-a580-2de1a3d4d464', 'GK-9897-B38A9C', 'BOEN DM ANITA PIN BOENTARAN', '9897', 'Import GudangKu kardus. nomor_id=9897.', true),
  ('6d23d945-ec90-342d-8596-fd39fcfafb53', 'GK-0387-69E415', 'TJONG LI MI SUKIRNO', '0387', 'Import GudangKu kardus. nomor_id=0387.', true),
  ('21822ad6-3650-3326-a287-d627b3fa50eb', 'GK-0351-49B0DE', 'ANITA BINTANG AMELIA AMELIA', '0351', 'Import GudangKu kardus. nomor_id=0351.', true),
  ('455afa44-1020-3d3c-90e3-bfa478f90039', 'GK-1746-85C0E4', 'AMI T CHAELESS JULI SUJIANTO', '1746', 'Import GudangKu kardus. nomor_id=1746.', true),
  ('09063c7f-c264-3791-928a-d3cb2a8006e0', 'GK-3571-0AC2EE', 'AMI ROPINDAH HASIBUAN', '3571', 'Import GudangKu kardus. nomor_id=3571.', true),
  ('8b2ef050-5b42-3b01-8b4a-585f33e863c0', 'GK-0101-0FFC02', 'TJONG LI MI LALA KLARA', '0101', 'Import GudangKu kardus. nomor_id=0101.', true),
  ('712d193b-f0f2-3077-8f37-2224fc6918d5', 'GK-1381-07BBF1', 'AMI T WIFA ANDIKA', '1381', 'Import GudangKu kardus. nomor_id=1381.', true),
  ('706ac6a2-29af-36bf-8e23-64766d3f44bc', 'GK-9790-AD21D6', 'SURYANI ARABROPINTA SIHITE', '9790', 'Import GudangKu kardus. nomor_id=9790.', true),
  ('71e45f52-5884-318a-a9ba-37b84ace312e', 'GK-7754-D36E80', 'RUDIANTO TEAM RINA', '7754', 'Import GudangKu kardus. nomor_id=7754.', true),
  ('8653931c-797b-37ad-badd-4373e6300ccc', 'GK-2804-1D8A39', 'NENG KANAN T PAPUA CANTIKA PUTRI', '2804', 'Import GudangKu kardus. nomor_id=2804.', true),
  ('763f0dbc-7d93-339e-842d-f7df302717d9', 'GK-0211-E87F75', 'RAISHA T WIFA AFRA SAKILA', '0211', 'Import GudangKu kardus. nomor_id=0211.', true),
  ('8c53259d-b4ca-3599-886b-e475ee1d341e', 'GK-2957-F40958', 'AMELIA ANITA', '2957', 'Import GudangKu kardus. nomor_id=2957.', true),
  ('3d15dd48-1fff-3b14-8421-fa13c64addcb', 'GK-9989-DE76BA', 'CONTOTUA SELVI MARBUN', '9989', 'Import GudangKu kardus. nomor_id=9989.', true),
  ('7dad9341-7926-3113-a4a7-a2be2c377f34', 'GK-9769-6BE1FF', 'PAJAR SELVI PAJAR RUDI', '9769', 'Import GudangKu kardus. nomor_id=9769.', true),
  ('d40ab8ed-e0d5-3dd2-9049-2c227cb7a1e1', 'GK-0641-2DBD9C', 'NENG KANAN T PAPUA ADINDA ARISA', '0641', 'Import GudangKu kardus. nomor_id=0641.', true),
  ('2980cd67-d723-3f1b-bfc0-0c2099a2704c', 'GK-9854-384F21', 'iqbal selvi iqbal fariski sinaga', '9854', 'Import GudangKu kardus. nomor_id=9854.', true),
  ('ec69eada-7c3c-382a-92be-103fb8acdcee', 'GK-0035-4EFDA4', 'NENG KANAN T PAPUA BULAN BAGASWARI', '0035', 'Import GudangKu kardus. nomor_id=0035.', true),
  ('847dfef8-e200-3faa-a46a-ca0c9805b267', 'GK-7514-6A13C8', 'TUTIK TEAM RINA TUTIK RAHAYU', '7514', 'Import GudangKu kardus. nomor_id=7514.', true),
  ('d10ed79f-10b6-3c42-a2aa-f0d9adf77607', 'GK-4914-474A82', 'Tjong Li Mi rofinus laro', '4914', 'Import GudangKu kardus. nomor_id=4914.', true),
  ('1458b70e-a3d7-3602-8bf6-d95207bbb237', 'GK-6556-9B897A', 'SAMSUL TEAM RINA SAMSUL ARIPIN', '6556', 'Import GudangKu kardus. nomor_id=6556.', true),
  ('b33d5d5d-a093-328a-b8eb-dbc40b252de0', 'GK-9696-F38051', 'FADLI ANITA FADLI', '9696', 'Import GudangKu kardus. nomor_id=9696.', true),
  ('645584b6-ef25-39f5-82ea-69dd51040699', 'GK-7435-DCDA85', 'NENG KANAN T PAPUA ANDITA PUTRI', '7435', 'Import GudangKu kardus. nomor_id=7435.', true),
  ('557a035b-3138-32c6-8f41-841dbbfdf7b8', 'GK-5036-438819', 'ferry anita ferry santoso', '5036', 'Import GudangKu kardus. nomor_id=5036.', true),
  ('e612ccc3-3f80-3375-b9a4-978d962096c9', 'GK-7614-5D04F4', 'NENG KANAN T PAPUA ARFHATAN MALIK RAZI', '7614', 'Import GudangKu kardus. nomor_id=7614.', true),
  ('cb2fa4f0-5eda-3eaa-b61a-a54a90aaf4a2', 'GK-0067-292595', 'NENG KANAN T PAPUA OLIVIA KIMI', '0067', 'Import GudangKu kardus. nomor_id=0067.', true),
  ('46cb8ffb-7518-3d9c-809e-094ae6c7df14', 'GK-8222-A7ABC3', 'chandra selvi chandra', '8222', 'Import GudangKu kardus. nomor_id=8222.', true),
  ('44551669-0869-3e6b-8138-58fb80569b51', 'GK-9837-3AF253', 'NENG KANAN T PAPUA KAYLA PUTRI', '9837', 'Import GudangKu kardus. nomor_id=9837.', true),
  ('36a04770-1fbf-36f7-b321-46546c65c48d', 'GK-9881-080F5A', 'YERIKO ANITA YERIKO RIDHO HUTAHEAN', '9881', 'Import GudangKu kardus. nomor_id=9881.', true),
  ('e0ca19fd-0143-3954-b06f-63eca6c25aa3', 'GK-6279-02E5F8', 'ami t mawarni lukman hakim', '6279', 'Import GudangKu kardus. nomor_id=6279.', true),
  ('d29b837a-cba6-3928-8d71-06f2adf1baed', 'GK-5075-95B698', 'RAKA ANITA RAKA WIJAYA', '5075', 'Import GudangKu kardus. nomor_id=5075.', true),
  ('3246ec15-bde5-358f-98ec-7e342af13472', 'GK-0062-0B0E15', 'tjong li mi eplin rutris sabuna', '0062', 'Import GudangKu kardus. nomor_id=0062.', true),
  ('d05f2dd0-664e-3129-b244-8e79dbfcce24', 'GK-5024-F2B75B', 'TJONG LI MI ERLANG HAMUDI', '5024', 'Import GudangKu kardus. nomor_id=5024.', true),
  ('d3cff1b8-7049-3c43-908d-5c1843fa9869', 'GK-0336-C5A565', 'ANITA BINTANG RAMI J RAMA ADITYA', '0336', 'Import GudangKu kardus. nomor_id=0336.', true),
  ('cc56b4ee-9710-3dc8-9958-8d46e6e80003', 'GK-4106-2A8555', 'ANITA BINTANG DIAN DIAN', '4106', 'Import GudangKu kardus. nomor_id=4106.', true),
  ('b7a696df-7173-3da6-9c79-755fbf61bb79', 'GK-9920-5F39EA', 'neng kanan t papua bayu', '9920', 'Import GudangKu kardus. nomor_id=9920.', true),
  ('f8077c6a-a8ed-3b6c-83ae-90035d48df19', 'GK-1493-CF8F25', 'AMI VINA AMELIA', '1493', 'Import GudangKu kardus. nomor_id=1493.', true),
  ('ab6afb5a-d593-365c-b78e-65cfc5977241', 'GK-1493-D52327', 'AMI MIRA RACHELL', '1493', 'Import GudangKu kardus. nomor_id=1493.', true),
  ('f33b41c3-a75c-32f8-9940-624bf39d6b27', 'GK-8261-4C7EA9', 'AMI SARTIKA DEWI', '8261', 'Import GudangKu kardus. nomor_id=8261.', true),
  ('883c60dc-2ad1-3b35-9cac-655f3e01273a', 'GK-8230-BAA1C3', 'debora selvi debora parinding', '8230', 'Import GudangKu kardus. nomor_id=8230.', true),
  ('740da4ac-dc41-363f-8e43-2cff39f3e708', 'GK-0057-0C0ACD', 'HERMANSYAH ANITA HERMANSYAH', '0057', 'Import GudangKu kardus. nomor_id=0057.', true),
  ('53e02dc8-10cf-373d-87b6-197b4c6dc5b2', 'GK-9833-316895', 'NENG KANAN T PAPUA MIMI AISYAH', '9833', 'Import GudangKu kardus. nomor_id=9833.', true),
  ('ff83963f-2223-3e4a-aeba-4adbaa2a4a5d', 'GK-4840-7700F3', 'YUSPIN TEAM RINA YUSPIN PARIMATA', '4840', 'Import GudangKu kardus. nomor_id=4840.', true),
  ('621a0c59-1e34-3079-8b2c-c79f4baa7c50', 'GK-7633-13025E', 'neng kanan t papua alvan', '7633', 'Import GudangKu kardus. nomor_id=7633.', true),
  ('dbf625ef-25b4-331c-9db0-9d4f4d2cb6d8', 'GK-4841-26E3F5', 'RIANTO TEAM RINA RIANTO KARURU', '4841', 'Import GudangKu kardus. nomor_id=4841.', true),
  ('8b6b4d80-84f0-3f89-9de4-0aefb6a7a691', 'GK-3434-04EBA9', 'Tjong li mi nabila', '3434', 'Import GudangKu kardus. nomor_id=3434.', true),
  ('085264cf-67ce-3097-96d6-6592f5c0c06f', 'GK-0058-CAA8DF', 'NENG KANAN T PAPUA IPIN HIDAYAT', '0058', 'Import GudangKu kardus. nomor_id=0058.', true),
  ('a9bd1f9d-4e0a-3236-809e-87759a56e9dd', 'GK-4980-8248DD', 'DERLY TEAM RINA DERLY APRILIANI', '4980', 'Import GudangKu kardus. nomor_id=4980.', true),
  ('95a9b147-3e42-32e4-9691-a45af63eb8ec', 'GK-8227-4FAB30', 'suryati selvi suryati', '8227', 'Import GudangKu kardus. nomor_id=8227.', true),
  ('36297b6b-ab34-3215-b996-5506eddbdad4', 'GK-6264-59C629', 'ANITA BINTANG DWI TRI D WITRI', '6264', 'Import GudangKu kardus. nomor_id=6264.', true),
  ('9710db83-2f1d-3912-80f6-452d209961a8', 'GK-7554-E76735', 'NENG KANAN T PAPUA NASIWA AZIZAH', '7554', 'Import GudangKu kardus. nomor_id=7554.', true),
  ('68353ea0-b91b-3489-a3fb-fced9d9db524', 'GK-3876-03E1AB', 'HERMIN TEAM RINA HERMIN PAKIDING', '3876', 'Import GudangKu kardus. nomor_id=3876.', true),
  ('9f3ec94f-d53a-34d6-a038-bbb832696080', 'GK-0314-0F32B2', 'AMI MARSELINUS MALE', '0314', 'Import GudangKu kardus. nomor_id=0314.', true),
  ('367fd8e6-9444-3e08-b137-39aeddea36d0', 'GK-3619-674523', 'TINA MARIANA D MAMI', '3619', 'Import GudangKu kardus. nomor_id=3619.', true),
  ('0a9fea90-ab14-3672-ac37-9d2017a1c9ad', 'GK-9882-FE1CC7', 'NENG KANAN T PAPUA WELI', '9882', 'Import GudangKu kardus. nomor_id=9882.', true),
  ('e03cad27-79a8-37fa-b3fd-27ce09091caa', 'GK-8099-1EC964', 'FARHAN ANITA FARHAN MAULANA', '8099', 'Import GudangKu kardus. nomor_id=8099.', true),
  ('31e74ccf-8ff8-3c1b-a933-68b58944815e', 'GK-8271-6B684F', 'NURHADI SELVI NURHADI SETIAWAN', '8271', 'Import GudangKu kardus. nomor_id=8271.', true),
  ('4232d008-2670-3c5e-8854-bac6c1936314', 'GK-9950-175BF2', 'NENG KANAN T PAPUA DEVI AULIA', '9950', 'Import GudangKu kardus. nomor_id=9950.', true),
  ('6b8b5435-1b6b-3181-a274-f2c0af138ee3', 'GK-3991-310102', 'NOVI HANDAYANI T MAWARNI NOVI HANDAYANI', '3991', 'Import GudangKu kardus. nomor_id=3991.', true),
  ('caf993ce-0520-31d0-8726-7e64b67e3679', 'GK-9858-1DF7A2', 'ARUM ARUM WULANDARI', '9858', 'Import GudangKu kardus. nomor_id=9858.', true),
  ('a63a2393-85a4-37fe-a5a8-2a965ba6b8b4', 'GK-3991-6BF048', 'MARIA ERMELINDA T CARLES MARIA ERMELINDA INDA DEPA', '3991', 'Import GudangKu kardus. nomor_id=3991.', true),
  ('031dd476-775b-3d0f-adaf-151a1be8d9de', 'GK-9858-CB03EF', 'ARIL ARIEL JUMAINAH', '9858', 'Import GudangKu kardus. nomor_id=9858.', true),
  ('697efad4-ceea-325f-bab9-7e2ffe4f8537', 'GK-6229-71FB01', 'MIRNA TEAM RINA MIRNA SUMINDAR', '6229', 'Import GudangKu kardus. nomor_id=6229.', true),
  ('b3d29b9c-dbc2-391f-848f-d7c063812be0', 'GK-9858-757062', 'KEISHA KEISHA KALLISTA', '9858', 'Import GudangKu kardus. nomor_id=9858.', true),
  ('bcdaf750-c207-35f4-ab20-07b221734177', 'GK-3925-ED47AB', 'LESTARI HANDAYANI T ERLIN KIRI LESTARI HANDAYANI', '3925', 'Import GudangKu kardus. nomor_id=3925.', true),
  ('00e391c6-2e6a-3643-a300-11e982ec00fd', 'GK-3936-930B05', 'NISA MAHARANI T ERLINNISA MAHARANI', '3936', 'Import GudangKu kardus. nomor_id=3936.', true),
  ('3f28e639-cf67-3321-88fd-914adf319264', 'GK-3776-DCC445', 'KARTIKA SARI T MARTHA KARTIKA SARI', '3776', 'Import GudangKu kardus. nomor_id=3776.', true),
  ('9d6328c1-5840-340c-b41d-82662ebef8c0', 'GK-3787-B8AC33', 'ARIEL JUMAINAH T ERLIN ARIEL JUMAINAH', '3787', 'Import GudangKu kardus. nomor_id=3787.', true),
  ('ae51849e-9053-3d8c-a54e-5493f0e4fdfb', 'GK-3869-C245C8', 'RIKA HARTIKA WATI SM T SHOFIA KANARIKA HARTIKA', '3869', 'Import GudangKu kardus. nomor_id=3869.', true),
  ('3a62cc45-6582-3012-bae0-72d13ee6bc9f', 'GK-4065-FBD8AA', 'AGNES THERESIA T BEND KIRI AGNES THERESIA', '4065', 'Import GudangKu kardus. nomor_id=4065.', true),
  ('1dab98db-ae69-392f-8c1a-ccf15f42f55c', 'GK-3988-310FFB', 'MANGATAS ARITONANG T SHOFIA', '3988', 'Import GudangKu kardus. nomor_id=3988.', true),
  ('e8524f6e-681a-3bc9-8e8e-01e96060f9f0', 'GK-3850-1E445B', 'WOEN T LILY T BOEN KANAN WOEN LILY', '3850', 'Import GudangKu kardus. nomor_id=3850.', true),
  ('532c37b2-dc51-37cd-ade6-d3be05024a55', 'GK-0395-3EEAC2', 'NENG KANAN T PAPUA ANITA MARLITA', '0395', 'Import GudangKu kardus. nomor_id=0395.', true),
  ('c6e49650-3f9b-3da9-9cf0-57aec937e92f', 'GK-3957-BB300D', 'STANNY T BOEN KANAN STANNY NOVILITA PEEA', '3957', 'Import GudangKu kardus. nomor_id=3957.', true),
  ('290ca253-a781-39b5-88d7-37a7a8c30908', 'GK-3960-4323AD', 'LIHO T BENDLIHO', '3960', 'Import GudangKu kardus. nomor_id=3960.', true),
  ('33bd0ff0-1ecd-3607-aad7-386063654897', 'GK-4041-9A465B', 'MESHA T BOEN KIRI MESHA', '4041', 'Import GudangKu kardus. nomor_id=4041.', true),
  ('f17f3bb6-4b53-3726-8a60-206efb93f267', 'GK-3975-C84044', 'DINDA T MAWARNI DINDA', '3975', 'Import GudangKu kardus. nomor_id=3975.', true),
  ('a1a021c1-221a-33d2-b679-9ab10924a4d4', 'GK-4106-436639', 'YOHANNES T MAWARNI YOHANES', '4106', 'Import GudangKu kardus. nomor_id=4106.', true),
  ('c49d2d73-613c-3eb3-be52-68bf96d57595', 'GK-4106-A2BE48', 'AMI SITKA CHRISTIE', '4106', 'Import GudangKu kardus. nomor_id=4106.', true),
  ('ac95436c-0cc4-37be-a68f-fab2fdbca3d2', 'GK-3975-263FF1', 'SUKAEMI T MAWARNI', '3975', 'Import GudangKu kardus. nomor_id=3975.', true),
  ('394af448-2802-38f5-9b19-3aa765ad852e', 'GK-6114-D9AC31', 'Ami amalia safira', '6114', 'Import GudangKu kardus. nomor_id=6114.', true),
  ('44adaa1b-4cca-3e46-bf24-44497fd0580f', 'GK-3564-40191E', 'ami januar hendratama', '3564', 'Import GudangKu kardus. nomor_id=3564.', true),
  ('822bac95-306f-3446-9b76-aeb3c88c7a3e', 'GK-5041-57543B', 'Tjong li mi dedi sulaeman', '5041', 'Import GudangKu kardus. nomor_id=5041.', true),
  ('7f88559f-b815-3189-bbbf-dbfb7bf13dab', 'GK-4017-397E40', 'LIU OI KIMLIU OI KIM', '4017', 'Import GudangKu kardus. nomor_id=4017.', true),
  ('dddf20dd-2129-377d-97bb-8c65c0dd3b09', 'GK-4135-FD824C', 'ANITA BINTANG TASMI TASMI', '4135', 'Import GudangKu kardus. nomor_id=4135.', true),
  ('c5f6603b-d5e5-3713-abb4-0421190e57be', 'GK-6238-02E5F8', 'ami t mawarni lukman hakim', '6238', 'Import GudangKu kardus. nomor_id=6238.', true),
  ('1dc91c75-e223-371e-892b-316d45730aa0', 'GK-3911-BC0DF0', 'nisa maharani t erlin nisa maharani', '3911', 'Import GudangKu kardus. nomor_id=3911.', true),
  ('e7e883e6-add0-37fa-bd58-f6c5ebebdf9b', 'GK-8372-1CE7A2', 'NURUL ANITA NURUL KHOTIMAH', '8372', 'Import GudangKu kardus. nomor_id=8372.', true),
  ('4f945db5-05b2-3fe6-a258-100ced002f94', 'GK-3911-E913C5', 'prabowo adi t mawarni prabowo adi', '3911', 'Import GudangKu kardus. nomor_id=3911.', true),
  ('dc7bd928-e954-31dd-99ad-f145e988a49d', 'GK-3911-A507EF', 'richmond t charles richmond', '3911', 'Import GudangKu kardus. nomor_id=3911.', true),
  ('47a74276-7e60-360b-9149-dc2c3c5d6039', 'GK-0358-637C80', 'ANITA BINTANG SARI SARI', '0358', 'Import GudangKu kardus. nomor_id=0358.', true),
  ('764f5be3-e5ca-3901-9c7b-0e788fcfcc9f', 'GK-4086-1093EB', 'marselinus male dm marselinus male', '4086', 'Import GudangKu kardus. nomor_id=4086.', true),
  ('6eb06da7-e12e-38fa-9cf3-baa1e4ef0d79', 'GK-3894-682672', 'STANNY NOVILITA PEEA T BOEN KANAN STANNY', '3894', 'Import GudangKu kardus. nomor_id=3894.', true),
  ('3f7cea8c-f454-3b4a-97a6-3f6c36cdcbaf', 'GK-3923-DF1DED', 'casi bt akmar t dwi kiri casi bt akmar', '3923', 'Import GudangKu kardus. nomor_id=3923.', true),
  ('c420f4c2-1f4a-3f68-a793-60e7f9e961b5', 'GK-3845-0E7C5A', 'KEISHA KALLISTA T EELIN KEISHA KALLISTA', '3845', 'Import GudangKu kardus. nomor_id=3845.', true),
  ('3d6d1609-debb-36ba-941e-d48ebd38ef6d', 'GK-4037-C9F319', 'Liu oi kim T dwi edyliu oi kim', '4037', 'Import GudangKu kardus. nomor_id=4037.', true),
  ('39c95c06-c731-3c76-a41a-5679d44914c9', 'GK-3954-211F54', 'Anita bintang ngatiyono ngatiyono', '3954', 'Import GudangKu kardus. nomor_id=3954.', true),
  ('0eebc47c-b50c-3fa5-9ef6-1029b2cf4fd7', 'GK-6492-FC43E4', 'NOVALIA TEAM RINA NOVALIA FALENTINA MARANI', '6492', 'Import GudangKu kardus. nomor_id=6492.', true),
  ('2671c359-06c7-3f25-88a9-dcf5d8d19f13', 'GK-2328-5AC7FF', 'Neng kanan T. Rina Handayani', '2328', 'Import GudangKu kardus. nomor_id=2328.', true),
  ('7258dc8f-e304-332c-8d40-303cd224c95f', 'GK-3959-2D06BE', 'Aston Aston', '3959', 'Import GudangKu kardus. nomor_id=3959.', true),
  ('162ba742-942a-3ffd-b262-5a1017c05d59', 'GK-3913-D3A1E9', 'ESRA TEAM RINA ESRA RENDEN', '3913', 'Import GudangKu kardus. nomor_id=3913.', true),
  ('dc3d58b2-aa5c-3a6b-bd0a-c47fabfb70ea', 'GK-3992-5E6C98', 'alvin prakoso t benhard alvin prakoso', '3992', 'Import GudangKu kardus. nomor_id=3992.', true),
  ('22cbb5bf-0317-32cb-b35d-8275b7397423', 'GK-0431-34D9BE', 'Donald Anita Ronard', '0431', 'Import GudangKu kardus. nomor_id=0431.', true),
  ('be536d8a-21be-352c-b856-8cea7e790b3b', 'GK-3942-7F32C9', 'MARTHA SIMANGUNSONG T MAWARNI MARTHA', '3942', 'Import GudangKu kardus. nomor_id=3942.', true),
  ('a23526f4-6471-3600-b946-7469c0d371f5', 'GK-0877-614FE6', 'Anisa Hari Sutanto', '0877', 'Import GudangKu kardus. nomor_id=0877.', true),
  ('d00f6ab4-669b-3645-ab9f-31e190535ee4', 'GK-3939-795EB1', 'Prabowo Adi T Mawarni', '3939', 'Import GudangKu kardus. nomor_id=3939.', true),
  ('29e82380-b073-3639-9d02-2601401080b5', 'GK-0350-2C6548', 'ANITA BINTANG NANI NANI NINGSIH', '0350', 'Import GudangKu kardus. nomor_id=0350.', true),
  ('ff237d7a-8c69-3453-a85f-c1f2e86e77ff', 'GK-4083-7EADD5', 'Djohan T boendjohan', '4083', 'Import GudangKu kardus. nomor_id=4083.', true),
  ('0251cb58-fd15-33e2-ab64-a349e7227936', 'GK-1398-BBD7D0', 'EKI Fadli Hutasuhut t marta eki fadli hutasuhut', '1398', 'Import GudangKu kardus. nomor_id=1398.', true),
  ('56f7591e-a215-3e6b-ba05-f3aa7d9a8799', 'GK-3846-9966A1', 'jessica thanita limor t boen kiri jessica', '3846', 'Import GudangKu kardus. nomor_id=3846.', true),
  ('ed58ed04-2695-3c44-8427-3ad71964fc01', 'GK-3820-C216C6', 'ARUM WULANDARI T ERLIN ARUM WULANDARI', '3820', 'Import GudangKu kardus. nomor_id=3820.', true),
  ('53d864ce-aeac-3965-b5f6-f3c3fb1e788c', 'GK-7773-615F28', 'MARCO ANITA MARCORIUS', '7773', 'Import GudangKu kardus. nomor_id=7773.', true),
  ('4445f390-901f-3eb2-8d9e-17cad71479b2', 'GK-4039-09E1AC', 'Agnes Theresia T Bend Kiri', '4039', 'Import GudangKu kardus. nomor_id=4039.', true),
  ('3cc9bd50-ab7b-3ea9-b6a6-59ff20a3d128', 'GK-3986-982926', 'Alvin T dwi edyalvin tandrio', '3986', 'Import GudangKu kardus. nomor_id=3986.', true),
  ('9383d42a-841c-3756-9f02-b1c136e3cd7e', 'GK-3786-D0F7F8', 'Arman hakim T eelinarman hakim', '3786', 'Import GudangKu kardus. nomor_id=3786.', true),
  ('6076eb04-f421-38dc-9faf-a8a914843cea', 'GK-3902-5C3203', 'SITKA CRISHTIE T ERLIN KIRI SITKA CHRISTIE', '3902', 'Import GudangKu kardus. nomor_id=3902.', true),
  ('feb686a5-e43d-32e9-b561-5b6f33cda8cb', 'GK-2447-279A28', 'Juliyana T. RINA Naingoian.', '2447', 'Import GudangKu kardus. nomor_id=2447.', true),
  ('303e522f-9e87-3b36-b0c4-83da8d2a0393', 'GK-0680-2CA30B', 'Neng Kanan T. Abel Putri', '0680', 'Import GudangKu kardus. nomor_id=0680.', true),
  ('ed1a7415-8352-377d-8517-abb675424622', 'GK-3792-FE5CBD', 'MUH SUKARNO T MARTA MUH SUKARNO', '3792', 'Import GudangKu kardus. nomor_id=3792.', true),
  ('bbd4aff3-e157-3f81-931d-fda96f0dadcb', 'GK-3892-1F3B20', 'Alfi Syahrin SM T Shoria kanan alfi syahrin', '3892', 'Import GudangKu kardus. nomor_id=3892.', true),
  ('6225df0d-3839-3dd9-88f8-3f6008330f5f', 'GK-3928-262132', 'Jessica Jessica thanita Limor', '3928', 'Import GudangKu kardus. nomor_id=3928.', true),
  ('9ce3798e-7c55-3a42-86dd-42877d1b543e', 'GK-1411-3AF253', 'NENG KANAN T PAPUA KAYLA PUTRI', '1411', 'Import GudangKu kardus. nomor_id=1411.', true),
  ('cf174844-6a35-3161-8642-b4dfaf44cdbb', 'GK-0881-E9656A', 'Rofinus Laro T. Marta', '0881', 'Import GudangKu kardus. nomor_id=0881.', true),
  ('1d18e9f0-cf31-3974-ab37-2db2977a288a', 'GK-2375-2F0DBF', 'Ami Maria Valentina', '2375', 'Import GudangKu kardus. nomor_id=2375.', true),
  ('26a8431d-c4fa-3d4d-a6ae-f1952447b51d', 'GK-4068-7DF7D5', 'Efendi T Boen Kanan', '4068', 'Import GudangKu kardus. nomor_id=4068.', true),
  ('6af095cc-51dd-3aed-bbee-eaf4fdadf024', 'GK-4063-DB1E83', 'Andrew Kusashi T wenny andrew kusashi', '4063', 'Import GudangKu kardus. nomor_id=4063.', true),
  ('7d39212f-2cc5-395f-b604-e25527319ebc', 'GK-4042-0F608B', 'JOSHUA SETIAWAN T WENNY JOSHUA SETIAWAN', '4042', 'Import GudangKu kardus. nomor_id=4042.', true),
  ('e80d3e83-3906-3f50-bce2-70023f702a87', 'GK-9862-946138', 'Neng Kanan T Papua Citra Putri', '9862', 'Import GudangKu kardus. nomor_id=9862.', true),
  ('1e05185e-bf4b-3032-ae63-430792752763', 'GK-2351-E00D5D', 'Neng Kanan T. Garet Putra', '2351', 'Import GudangKu kardus. nomor_id=2351.', true),
  ('f93b1a61-aac7-3e53-9210-0ba1b3588852', 'GK-0349-94090E', 'ANITA BINTANG DIMAS DIMAS', '0349', 'Import GudangKu kardus. nomor_id=0349.', true),
  ('53287c42-5d83-3252-b7fa-85dae22f19b3', 'GK-3995-BCA5AE', 'Rani ottaviani T erlin kirir ani oktaviani', '3995', 'Import GudangKu kardus. nomor_id=3995.', true),
  ('dae24ff5-ad0a-3058-a118-00a5f5b4b44e', 'GK-1374-4D30BC', 'Neng kanan T. Billy Ciputra', '1374', 'Import GudangKu kardus. nomor_id=1374.', true),
  ('43190b00-0e3f-36bb-8ca3-02b933575a12', 'GK-2319-444018', 'Neng Kanan Kanan T. Kartika', '2319', 'Import GudangKu kardus. nomor_id=2319.', true),
  ('24e473f1-7ac3-3ac5-be68-39f6e22d941f', 'GK-3810-620323', 'Anjani Puspita T Erlin', '3810', 'Import GudangKu kardus. nomor_id=3810.', true),
  ('1098f392-9e46-3b27-91a1-d0c08a11cd73', 'GK-3898-C7D4B2', 'Alvin Tandrio T Dwi Kiri', '3898', 'Import GudangKu kardus. nomor_id=3898.', true),
  ('6a8d3328-ee52-3468-b730-2a8ce543095c', 'GK-5073-334EA5', 'Tjong Li mi marselinus male', '5073', 'Import GudangKu kardus. nomor_id=5073.', true),
  ('60dc07e1-02ad-363e-b5e5-e843988fd050', 'GK-9927-04B1C4', 'Neng Kanan T Papua Ammar Kholid', '9927', 'Import GudangKu kardus. nomor_id=9927.', true),
  ('fd1afccb-c7b6-3999-9eeb-891c55b2ebec', 'GK-3886-92B6E1', 'HALIM JULIANTO T MAWARNI HALIM JULIANTO', '3886', 'Import GudangKu kardus. nomor_id=3886.', true),
  ('a4891bab-3f6e-39d2-800d-33958b3d847b', 'GK-8262-7DBA4C', 'Shofia Anita Shofia Husna', '8262', 'Import GudangKu kardus. nomor_id=8262.', true),
  ('f53faa58-5499-38c0-afa7-0e33676e68b0', 'GK-3886-07B734', 'WINDA T MAWARNI T WINDA', '3886', 'Import GudangKu kardus. nomor_id=3886.', true),
  ('6566ea8b-bc5e-3c3c-a2b1-97b7c3048ee9', 'GK-4024-BAB1EF', 'Ana leo T Bend kiri Ana leo', '4024', 'Import GudangKu kardus. nomor_id=4024.', true),
  ('070b6efb-837c-3ae6-b801-12322650dd43', 'GK-4084-8F5EE2', 'Natasya Tania T Bend', '4084', 'Import GudangKu kardus. nomor_id=4084.', true),
  ('8cf6b095-9ef0-3b22-8571-05ccc03fe267', 'GK-5120-2EE85F', 'TJONG LI MI MARIA CARINA METIKORES', '5120', 'Import GudangKu kardus. nomor_id=5120.', true),
  ('ccd6d76d-d8a7-37c0-afe1-4621f776813b', 'GK-9905-1443B1', 'Suryani Arab tiffani jocelyn loe', '9905', 'Import GudangKu kardus. nomor_id=9905.', true),
  ('a32527fa-0c02-3591-af77-3ee56f27b2ad', 'GK-4018-DA8EA8', 'CASIH DWI EDY CASIH BT AKMAR', '4018', 'Import GudangKu kardus. nomor_id=4018.', true),
  ('cb3a9c06-3e14-3d3e-a347-ac43a21b8411', 'GK-8291-3F11EE', 'ILHAM Anita Kurniawan', '8291', 'Import GudangKu kardus. nomor_id=8291.', true),
  ('6bd754a2-69e1-3284-9fc7-36965c4fabbc', 'GK-4020-B6E00D', 'ANA LEOANA LEO', '4020', 'Import GudangKu kardus. nomor_id=4020.', true),
  ('f04fef0e-f378-3a84-91b6-1375cc3b691a', 'GK-1861-19F8F1', 'Neng Kanan T. Putri Ayu', '1861', 'Import GudangKu kardus. nomor_id=1861.', true),
  ('ad429e13-1cf5-3a45-9066-cc1fe18f3247', 'GK-1871-19F8F1', 'Neng Kanan T. Putri Ayu', '1871', 'Import GudangKu kardus. nomor_id=1871.', true),
  ('3cbf24a5-cdcf-3742-8bbe-a6774c428f96', 'GK-3826-263FF1', 'SUKAEMI T MAWARNI', '3826', 'Import GudangKu kardus. nomor_id=3826.', true),
  ('2a930132-6985-3e04-9ab8-3fbf3ba37e02', 'GK-1871-56EE5F', 'Neng Karan T. cici Sriyana', '1871', 'Import GudangKu kardus. nomor_id=1871.', true),
  ('487ee617-a705-3758-ba3a-e5a526b4ba93', 'GK-2065-A7A53C', 'NENG KANAN T PAPUA DANIAH JASMANIAH', '2065', 'Import GudangKu kardus. nomor_id=2065.', true),
  ('34655230-0102-32d2-b741-7776244af344', 'GK-2640-7A0853', 'Nerg kanan T. Bashir', '2640', 'Import GudangKu kardus. nomor_id=2640.', true),
  ('95fdc3d2-06ee-31a3-900d-d48413d24085', 'GK-8465-33439B', 'Yunus Anita', '8465', 'Import GudangKu kardus. nomor_id=8465.', true),
  ('1b0d673a-a2ea-3e40-aacc-ed675cdf4501', 'GK-8433-98456D', 'Ayunda Anita Axunda', '8433', 'Import GudangKu kardus. nomor_id=8433.', true),
  ('3433b634-c970-3783-a434-50912e329309', 'GK-9288-95B698', 'Raka Anita raka Wijaya', '9288', 'Import GudangKu kardus. nomor_id=9288.', true),
  ('918129d3-e195-3e5d-a7a9-0b02f7763ef8', 'GK-3931-8539CC', 'SEAN MURPHY MOEIS T ERLIN KANAN SEAN', '3931', 'Import GudangKu kardus. nomor_id=3931.', true),
  ('6a8bf93d-f249-3976-b2bd-e5d9a6ab91ba', 'GK-9945-85E489', 'tjong li mi eko Prasetiyo', '9945', 'Import GudangKu kardus. nomor_id=9945.', true),
  ('5100764e-c57a-3d93-923b-7a27fa23e7d3', 'GK-3848-7103F1', 'DJOHAN SM T BOENDJHOHAN', '3848', 'Import GudangKu kardus. nomor_id=3848.', true),
  ('b6c9660f-7822-3514-935d-a2ff014ec632', 'GK-8519-232B74', 'Tri Anitatri Wahyudi', '8519', 'Import GudangKu kardus. nomor_id=8519.', true),
  ('72543b4d-db1e-3c86-a856-84d244fbb9b6', 'GK-9901-3178D8', 'Tiong li mi Suriyati', '9901', 'Import GudangKu kardus. nomor_id=9901.', true),
  ('e932c9d5-26ec-35d1-b6c7-a6aa351093cb', 'GK-2801-F68631', 'NENG KANAN T PAPUA HOTMARIA SINAGA', '2801', 'Import GudangKu kardus. nomor_id=2801.', true),
  ('8bf1cde2-256e-3ece-a4e1-14b32c479679', 'GK-4101-79BFD2', 'AMI DELILA BR HARIANJA', '4101', 'Import GudangKu kardus. nomor_id=4101.', true),
  ('32b8899f-8f04-33cd-bce3-eb5f836b10ae', 'GK-1526-A7A53C', 'NENG KANAN T PAPUA DANIAH JASMANIAH', '1526', 'Import GudangKu kardus. nomor_id=1526.', true),
  ('142ce1ad-fd70-3115-83e4-5fb0b368bab4', 'GK-4101-A15E64', 'GO SU CHEN GO SU CHEN', '4101', 'Import GudangKu kardus. nomor_id=4101.', true),
  ('54551f3a-8965-32a0-9d0f-930047a75959', 'GK-4101-005B16', 'AMI T CHARLES KANAN YOHANA AFRA BABO RAKI', '4101', 'Import GudangKu kardus. nomor_id=4101.', true),
  ('bcf17a25-3d51-3e18-9f05-f170bede3f3c', 'GK-1157-0CE773', 'NENG KANAN T PAPUA RUSMINI', '1157', 'Import GudangKu kardus. nomor_id=1157.', true),
  ('f45fb01d-ccc8-36c7-9929-d9ae1dd56172', 'GK-4101-25BC25', 'ANITA BINTANG HINTA SINTA SUSILAWATI', '4101', 'Import GudangKu kardus. nomor_id=4101.', true),
  ('a34d6d68-5f1a-3f7b-88c5-4f83ddc5c0f1', 'GK-6502-5E01C4', 'ANISAHARI SUSANTO', '6502', 'Import GudangKu kardus. nomor_id=6502.', true),
  ('564305c1-7871-3717-b6ce-6e7bebe30953', 'GK-1703-F88A6D', 'NENG KANAN T PAPUA CICI SRIYANA', '1703', 'Import GudangKu kardus. nomor_id=1703.', true),
  ('0bac235e-c9f9-329b-bd39-821b39e4e8db', 'GK-4102-529E9A', 'MIA AUDINA NAJ MIA', '4102', 'Import GudangKu kardus. nomor_id=4102.', true),
  ('4f31c1e8-2716-36af-9649-80029ad27ae2', 'GK-4101-48005C', 'MAGDALENA TEAM ANISA EASTER YULI WESTERN YULI', '4101', 'Import GudangKu kardus. nomor_id=4101.', true),
  ('68468763-e056-3d0a-90b8-2fcc3fc61a6b', 'GK-3979-794971', 'SOFIA DM T EDY SOFIA HUSNA', '3979', 'Import GudangKu kardus. nomor_id=3979.', true),
  ('9010a6d9-e200-3016-a198-da446441f05a', 'GK-4069-291A22', 'AMI HIKMAH SYAIFULLOH', '4069', 'Import GudangKu kardus. nomor_id=4069.', true),
  ('35356d9a-a317-30b0-a26c-f2ab7087183a', 'GK-7532-6F088F', 'NENG KANAN T PAPUA GARET PUTRA', '7532', 'Import GudangKu kardus. nomor_id=7532.', true),
  ('72664b53-d10f-3b80-9d3a-c7db8ce173ae', 'GK-4069-3FB4BD', 'ANITA BINTANG NGATIYONONGATIY ONO', '4069', 'Import GudangKu kardus. nomor_id=4069.', true),
  ('6d40e0ae-7323-36d6-8c46-58a84400baf1', 'GK-4069-D3A1E9', 'ESRA TEAM RINA ESRA RENDEN', '4069', 'Import GudangKu kardus. nomor_id=4069.', true),
  ('85bf65f5-77f7-3aaa-b4c1-eb35205558fa', 'GK-4069-09BDD2', 'AMI ANDREAS PAIAN', '4069', 'Import GudangKu kardus. nomor_id=4069.', true),
  ('95dbe42b-f0e8-3bb4-abe3-fb6aba2c9b60', 'GK-2742-76A481', 'SISKA YUNI T WIFA SISKA YUNI', '2742', 'Import GudangKu kardus. nomor_id=2742.', true),
  ('1f149979-5336-3dfa-b5c4-fb6ea82cead0', 'GK-4114-41C21B', 'AMI T ANDREW KUSASHI SMANDREW KUSASHI', '4114', 'Import GudangKu kardus. nomor_id=4114.', true),
  ('0297d4f9-45a5-308e-8762-52f35d6b905b', 'GK-4168-C5FF43', 'MIA AUDINA NURSAIDAH', '4168', 'Import GudangKu kardus. nomor_id=4168.', true),
  ('403f28b3-e533-3684-95e4-9443a7256d1f', 'GK-4168-0D4FC7', 'AMI AGNES JESSICA', '4168', 'Import GudangKu kardus. nomor_id=4168.', true),
  ('6bfdb72e-8b28-3c3c-8517-73ba0b492bb0', 'GK-4168-36A0F1', 'AMI ANDREW KUSASHI', '4168', 'Import GudangKu kardus. nomor_id=4168.', true),
  ('4754b7a0-d062-3177-ae9a-9af86766b41e', 'GK-4154-29D7B1', 'ANITA BINTANG FELIXFELIX', '4154', 'Import GudangKu kardus. nomor_id=4154.', true),
  ('0771e12d-94aa-3a2f-b3b1-268127a8ccdb', 'GK-5041-58E566', 'TJONG LI MI EDI SULAEMAN', '5041', 'Import GudangKu kardus. nomor_id=5041.', true),
  ('f6e56934-841e-395d-a61f-a06f8dea0f62', 'GK-4154-FD824C', 'ANITA BINTANG TASMI TASMI', '4154', 'Import GudangKu kardus. nomor_id=4154.', true),
  ('a83fc095-3f5e-3f3d-821a-38861683b861', 'GK-3564-1BFA1B', 'ANITA BINTANG DINDA DINDA', '3564', 'Import GudangKu kardus. nomor_id=3564.', true),
  ('da9ab3c4-2206-3497-877d-32566c63b6cc', 'GK-0275-D2D592', 'ANITA BINTANG AULIA AULIA', '0275', 'Import GudangKu kardus. nomor_id=0275.', true),
  ('ea7f8cc5-8d78-34ce-87c5-ac43ff46ad37', 'GK-0275-B284A3', 'ANITA BINTANG GADING GADING MARTHIN', '0275', 'Import GudangKu kardus. nomor_id=0275.', true),
  ('4982101f-3d27-380f-b5a6-2778f326db78', 'GK-0275-94090E', 'ANITA BINTANG DIMAS DIMAS', '0275', 'Import GudangKu kardus. nomor_id=0275.', true),
  ('4ea659bc-f369-38a7-a576-18a30480a91c', 'GK-3496-EE2777', 'ANITA BINTANG LUSI LUSIO NANTIKA', '3496', 'Import GudangKu kardus. nomor_id=3496.', true),
  ('f943b4d2-6955-38cf-ae85-7edcee7964ac', 'GK-3496-470D9B', 'ANITA BINTANG RIAN FIRMANSYAH RIAN FFIRMANSYAH', '3496', 'Import GudangKu kardus. nomor_id=3496.', true),
  ('9a732c8b-bba0-3c88-866a-471b015d28ad', 'GK-3496-B25FCD', 'ANITA BINTANG ARDIANSYAHARDIANSYAH PUTRA', '3496', 'Import GudangKu kardus. nomor_id=3496.', true),
  ('f21050ee-02d1-3ea5-9215-81119b290ea4', 'GK-0635-31FCC1', 'neng kanan t papua asum sumiati', '0635', 'Import GudangKu kardus. nomor_id=0635.', true),
  ('920490ea-c919-318e-b873-f68943ed4d71', 'GK-3496-362AD0', 'ANITA BINTANG WENDAH ALISIA WENDAH', '3496', 'Import GudangKu kardus. nomor_id=3496.', true),
  ('631327e7-7419-379f-9857-7fed0bdedc40', 'GK-3496-830929', 'ANITA BINTANG WENDI SALIM WENDI SALIN', '3496', 'Import GudangKu kardus. nomor_id=3496.', true),
  ('fbb891b0-4793-35cb-b90e-80ef58f3279a', 'GK-2791-8B7DA3', 'jumriyeh anita jumriyeh', '2791', 'Import GudangKu kardus. nomor_id=2791.', true),
  ('8c233f4e-1a88-358e-b95e-3079cbb147b7', 'GK-6114-970BA2', 'ANITA BINTANG SITI AULIA SITI AULIA', '6114', 'Import GudangKu kardus. nomor_id=6114.', true),
  ('7140cec1-3b86-3140-80e6-424b7c77e06b', 'GK-6114-F34CBD', 'ANITA BINTANG HAFSA NABILA HAFSA', '6114', 'Import GudangKu kardus. nomor_id=6114.', true),
  ('577bb013-1189-3eb6-93c5-446997a09ac8', 'GK-4124-46B257', 'ANITA BINTANG KENNY KENNY NG', '4124', 'Import GudangKu kardus. nomor_id=4124.', true),
  ('15add158-0121-3fed-8288-fcbe2afc6637', 'GK-6097-6D273F', 'ANITA BINTANG SARISARI', '6097', 'Import GudangKu kardus. nomor_id=6097.', true),
  ('45c975bc-50af-3fcf-9e0d-4cdb2ce1766f', 'GK-6097-ECC3EC', 'ANITA BINTANG PIN BOENTARAN PIN BOENTARAN', '6097', 'Import GudangKu kardus. nomor_id=6097.', true),
  ('2507c710-5e8c-382b-969c-dfae9b6c0c01', 'GK-6097-BE09CE', 'ANITA BINTANG SITI NURHALIZA SITI NURHALIZA', '6097', 'Import GudangKu kardus. nomor_id=6097.', true),
  ('05c072d4-f5dd-3ff6-a7f3-3ffa91557c86', 'GK-6097-0C39EA', 'ANITA BINTANG ANDREAS ANDREAS', '6097', 'Import GudangKu kardus. nomor_id=6097.', true),
  ('c6aa0650-3662-35c6-aa96-9b17b8d49db9', 'GK-6097-2915B7', 'ANITA BINTANG IDAH IDAH', '6097', 'Import GudangKu kardus. nomor_id=6097.', true),
  ('1230b8ac-8c2e-30e9-ad53-41837bec38b4', 'GK-6097-C9998E', 'ANITA BINTANG VENDA HALIN VENDA HALIN', '6097', 'Import GudangKu kardus. nomor_id=6097.', true),
  ('8923c036-4157-3772-a87f-5bbf9c873bfe', 'GK-3540-DC6CF5', 'anita bintang agnesagnes kewa padak', '3540', 'Import GudangKu kardus. nomor_id=3540.', true),
  ('e0438bb1-b905-37a8-8465-5e277ce21bed', 'GK-0106-00131C', 'NENG KANAN T PAPUA LIVINA AYU', '0106', 'Import GudangKu kardus. nomor_id=0106.', true),
  ('c8cdfb44-43c6-3ba6-be5d-fc2ff45a9318', 'GK-6022-53C04A', 'anita bintang dwi medlin dwi medlins', '6022', 'Import GudangKu kardus. nomor_id=6022.', true),
  ('11ea591f-30f2-3d22-987b-dca49d91fba9', 'GK-3562-283056', 'anita bintang vincenciavinsensius neon basu', '3562', 'Import GudangKu kardus. nomor_id=3562.', true),
  ('d276bfe8-ef28-36e4-8bbc-d103f0bd3bae', 'GK-3531-3E5BFF', 'ANITA BINTANG JANUAR NEPA AMTIRAN JANUAR', '3531', 'Import GudangKu kardus. nomor_id=3531.', true),
  ('65fccb67-12dc-3a7b-8e1a-62aac1bf29f1', 'GK-6474-DCCEFB', 'sumanto anita sumanto halim', '6474', 'Import GudangKu kardus. nomor_id=6474.', true),
  ('32f19317-47f8-3c9a-b680-39167c8e034d', 'GK-6036-436939', 'ANITA BINTANG SOFIA HUSNA SHOFIA', '6036', 'Import GudangKu kardus. nomor_id=6036.', true),
  ('a9f52578-f782-3c13-8d2d-edc343a2ed95', 'GK-6036-D0F7F8', 'ANITA BINTANG ZAKI MUBARAK ZAKI MUBARAK', '6036', 'Import GudangKu kardus. nomor_id=6036.', true),
  ('5ce2e75b-f950-33b7-97e5-8589bb0a5f5e', 'GK-6065-7F213D', 'ANITA BINTANG ALFAHRIALFAHRI', '6065', 'Import GudangKu kardus. nomor_id=6065.', true),
  ('d7899385-9ce3-3cb6-8141-b5d23ec603d3', 'GK-6065-0DA3F7', 'ANITA BINTANG RAIHAN NUGRAHARAIHAN', '6065', 'Import GudangKu kardus. nomor_id=6065.', true),
  ('09e4eff2-385a-3f78-b02e-e60f840d4e62', 'GK-6065-E5C412', 'ANITA BINTANG NADIA NADIA', '6065', 'Import GudangKu kardus. nomor_id=6065.', true),
  ('de23ad71-af24-3b8f-aa81-ffcfc1e96546', 'GK-6542-3A9D84', 'GADING ANITA GADING MARTHIN', '6542', 'Import GudangKu kardus. nomor_id=6542.', true),
  ('34de4bf8-f9dd-3699-a616-237a86106f0c', 'GK-6837-749A34', 'DETRONI ANITA DETRONI WARUWU', '6837', 'Import GudangKu kardus. nomor_id=6837.', true),
  ('1091fe10-d550-33dd-b31b-e8559e1aec2f', 'GK-6047-1554D7', 'anita bintang dedi mulyanto dedi mulyanto', '6047', 'Import GudangKu kardus. nomor_id=6047.', true),
  ('ddce095e-3c6b-3efb-992b-2e7e36e92555', 'GK-0219-C1432F', 'NENG KANAN T PAPUA IHAT SOLIHAT', '0219', 'Import GudangKu kardus. nomor_id=0219.', true),
  ('84bf29b9-8214-312e-8233-db27a7396717', 'GK-2058-896FB0', 'AMI T NICOLAUS SM SURAMEN NICOLAUS NIA', '2058', 'Import GudangKu kardus. nomor_id=2058.', true),
  ('bafc347a-39de-304a-91ae-d1023de253f1', 'GK-3962-57D652', 'Ahmad Fauzan T bendhar dahmad Fauzan', '3962', 'Import GudangKu kardus. nomor_id=3962.', true),
  ('07cef4e2-560a-308f-bcf8-0176fbc8d824', 'GK-8923-D6E556', 'Hafiz Anita', '8923', 'Import GudangKu kardus. nomor_id=8923.', true),
  ('86c39dbc-eeb0-3449-a715-0e9d81231bad', 'GK-1756-230DC3', 'DEWINTA SARI WIFA DEWINTA SARI', '1756', 'Import GudangKu kardus. nomor_id=1756.', true),
  ('77f1c01a-4209-35bb-b958-7da334a25a61', 'GK-4045-546BAD', 'Diyan T bend kiri diyan', '4045', 'Import GudangKu kardus. nomor_id=4045.', true),
  ('8e85e416-5bbb-3503-a6d9-45479422e71e', 'GK-1696-3AF253', 'NENG KANAN T PAPUA KAYLA PUTRI', '1696', 'Import GudangKu kardus. nomor_id=1696.', true),
  ('03c3f53f-a146-39e1-b04f-9f958f86437a', 'GK-3932-94681B', 'ANISA RAHMAWATI T ERLIN KANAN ANISA RAHMAWATI', '3932', 'Import GudangKu kardus. nomor_id=3932.', true),
  ('281c889d-c6b4-3750-8273-17d917da9f74', 'GK-9681-D7B336', 'Neng Kanan T Papua Puspita Lasm', '9681', 'Import GudangKu kardus. nomor_id=9681.', true),
  ('cb5801be-9f34-3da3-a7e4-831d45d77253', 'GK-2563-5E121E', 'DEVIN MULYONO T TOMY KANAN DEVIN MULYONO', '2563', 'Import GudangKu kardus. nomor_id=2563.', true),
  ('ba32037c-209f-3a63-9ee6-c5fc458a1302', 'GK-0272-492097', 'Sambaru Team Rina', '0272', 'Import GudangKu kardus. nomor_id=0272.', true),
  ('486db147-0226-3e66-896f-7959ac5dbfd5', 'GK-0737-4544B6', 'Neng Kanan T. Nabila', '0737', 'Import GudangKu kardus. nomor_id=0737.', true),
  ('8ebde010-1235-3055-9e9c-43f6b7479b0b', 'GK-0325-E7B8E4', 'ANITA BINTANG DONIDONI', '0325', 'Import GudangKu kardus. nomor_id=0325.', true),
  ('99d5ad2c-2977-386e-8217-e27b47ac730b', 'GK-0760-8010E5', 'NENG KANAN T PAPUA ILHAM PURNAMA', '0760', 'Import GudangKu kardus. nomor_id=0760.', true),
  ('55fada34-bfc3-32e5-b40e-6b6b8031d8fa', 'GK-2607-2446E5', 'NENG KANAN T PAPUA PUSPITA LASMI', '2607', 'Import GudangKu kardus. nomor_id=2607.', true),
  ('0d94eace-a47d-3334-b0c8-9f327a872b39', 'GK-7585-0C47F4', 'TJONG LI MI', '7585', 'Import GudangKu kardus. nomor_id=7585.', true),
  ('4ce30a5d-34f5-3cae-8aba-9d15bd55c888', 'GK-2188-B8F629', 'Rika Nahami T. Wifa Rica', '2188', 'Import GudangKu kardus. nomor_id=2188.', true),
  ('d9e3ec1a-786a-3053-84c4-5ed86a10b05f', 'GK-1397-9EB307', 'AKBAR ANITA AKBAR', '1397', 'Import GudangKu kardus. nomor_id=1397.', true),
  ('4cc7037d-ff6f-3090-8d85-51bae41941f7', 'GK-7552-00131C', 'NENG KANAN T PAPUA LIVINA AYU', '7552', 'Import GudangKu kardus. nomor_id=7552.', true),
  ('7dd49990-d0c6-375d-a9ac-a96bc1cfe454', 'GK-9713-F288F2', 'NENG KANAN T PAPUA NURLIDA', '9713', 'Import GudangKu kardus. nomor_id=9713.', true),
  ('3387385d-4f38-3e6e-8c3c-3d77dada75ad', 'GK-1461-CA40B4', 'AMI T WIFA ASEP', '1461', 'Import GudangKu kardus. nomor_id=1461.', true),
  ('0da48cbf-8171-3803-9175-6c004421e3e1', 'GK-7598-91FA6B', 'TJong li mi Agus Septian', '7598', 'Import GudangKu kardus. nomor_id=7598.', true),
  ('5d61a22f-2b07-373e-bd7e-9ec042ef37d8', 'GK-0729-FA6F1F', 'NENG KANAN T PAPUA ANISA NURAWWALIYAH', '0729', 'Import GudangKu kardus. nomor_id=0729.', true),
  ('d7a46bbf-644a-31ff-8643-4c4ed9d74935', 'GK-0688-EFA402', 'Neng karan T. Nunu Nuhdin', '0688', 'Import GudangKu kardus. nomor_id=0688.', true),
  ('d240ce33-d271-3389-b318-a9c97e174085', 'GK-0249-43D2B5', 'KEVIN T TOMY KANAN KEVIN', '0249', 'Import GudangKu kardus. nomor_id=0249.', true),
  ('bec710ae-2c1e-3472-98c3-4def7ae4be6f', 'GK-4170-012C23', 'AMI JONATHAN KENZIRO SUWITO', '4170', 'Import GudangKu kardus. nomor_id=4170.', true),
  ('2a0a3612-9131-3975-9dab-b5d2245e5786', 'GK-3948-2FD0FE', 'winda T mawarni winda', '3948', 'Import GudangKu kardus. nomor_id=3948.', true),
  ('c2c65eca-0b18-38c4-872d-e3746d1f3a95', 'GK-1353-ECF5CE', 'SANDRI ANITA SANDRIYANO KORNAMNE PAYARA', '1353', 'Import GudangKu kardus. nomor_id=1353.', true),
  ('3eecf104-19cc-3666-b4ed-0b1e7f813f91', 'GK-3984-B1FB7A', 'Efendi kornamne T boen kanan efendi', '3984', 'Import GudangKu kardus. nomor_id=3984.', true),
  ('c097d9cc-6b80-399f-97ce-23f5ea528112', 'GK-8262-6E648C', 'NURUL HUDA ID T MAWARNI NURUL HUDA', '8262', 'Import GudangKu kardus. nomor_id=8262.', true),
  ('6ac857f3-a3f5-361f-9a17-3b6f1f1c8111', 'GK-1140-BC5634', 'NENG KANAN T PAPUA UNDANG SUKARSA', '1140', 'Import GudangKu kardus. nomor_id=1140.', true),
  ('c44de7af-d6cd-34fb-91ef-d086a4a84614', 'GK-9962-F9584E', 'Meti Anita Meti Delsi', '9962', 'Import GudangKu kardus. nomor_id=9962.', true),
  ('f719ffbc-2753-3c56-ad39-023542fe5854', 'GK-9922-910D6C', 'NENG KANAN T PAPUA IHSAN IFTIKAR', '9922', 'Import GudangKu kardus. nomor_id=9922.', true),
  ('d182ab61-dcd7-3d93-b87d-23d65c7e6857', 'GK-7566-899033', 'Tjong Li Mi Anita kelop', '7566', 'Import GudangKu kardus. nomor_id=7566.', true),
  ('de5c7149-c6a6-30c3-877f-73a0bb8f027d', 'GK-7604-466A96', 'Tjong li mi Dinda putri', '7604', 'Import GudangKu kardus. nomor_id=7604.', true),
  ('be5effb3-cacf-359c-a1a6-138c78817b74', 'GK-0063-53E31A', 'denny Anita denny setiawan', '0063', 'Import GudangKu kardus. nomor_id=0063.', true),
  ('7a6d79d4-d5bd-3390-a973-112d3aa69327', 'GK-1752-6E13D5', 'TEODORUS TEAM RINA TEODORUS BREYNOL', '1752', 'Import GudangKu kardus. nomor_id=1752.', true),
  ('4865e151-fda4-38ca-8864-8847693b8983', 'GK-7482-ED4BFA', 'Neng Kanan T Papua Citra Cantika', '7482', 'Import GudangKu kardus. nomor_id=7482.', true),
  ('3abf7c0f-66d3-3fa3-8d14-f2fe09a45610', 'GK-4162-8DC0C5', 'Anita bintang sunarsih sunarsih', '4162', 'Import GudangKu kardus. nomor_id=4162.', true),
  ('76525095-2813-3d57-b665-23e45641f6a2', 'GK-9860-C7FD6E', 'Tjong li mi merina', '9860', 'Import GudangKu kardus. nomor_id=9860.', true),
  ('5ad20e1a-74fb-381d-a420-949efae918f4', 'GK-4165-A0F795', 'Nurhaini DM Nurhaini', '4165', 'Import GudangKu kardus. nomor_id=4165.', true),
  ('85e857a1-1021-3785-a3da-5640084fd263', 'GK-1372-986689', 'PHILIPS ANITA PHILIPS FREIZENZ LOKWATY', '1372', 'Import GudangKu kardus. nomor_id=1372.', true),
  ('70b1cb25-fc95-389a-a6cc-a0f355565dca', 'GK-2054-22DE0E', 'Neng karan T. Nunu Nuhdini', '2054', 'Import GudangKu kardus. nomor_id=2054.', true),
  ('32df9cf3-5302-3508-99ef-fb84b02e91c1', 'GK-7781-E459CE', 'Neng kanan T Papua widi', '7781', 'Import GudangKu kardus. nomor_id=7781.', true),
  ('b0c3e6a4-b535-39ca-83db-f054d33a0d77', 'GK-1667-B307BE', 'Neng Kanan T. Nining Yuningsih.', '1667', 'Import GudangKu kardus. nomor_id=1667.', true),
  ('322e8d7a-8852-3795-ac34-fb2e8fc34e4d', 'GK-2615-A60B0C', 'NENG KANAN T PAPUA ROSMA ROSTIKA', '2615', 'Import GudangKu kardus. nomor_id=2615.', true),
  ('4aa4dc46-b781-3539-87da-863e8fc9decc', 'GK-3789-EDCD4F', 'Rafli Hidayat T Mawarni', '3789', 'Import GudangKu kardus. nomor_id=3789.', true),
  ('9112a3e2-6385-32e6-b96e-ecbe8375e64a', 'GK-0465-1D80E2', 'Neng Kanan T. Riki suswanto', '0465', 'Import GudangKu kardus. nomor_id=0465.', true),
  ('40764f4b-7a76-3e07-8469-6eff6018dc27', 'GK-0096-F5621F', 'Intan Anita Intan permata', '0096', 'Import GudangKu kardus. nomor_id=0096.', true),
  ('fa0ede1b-95d7-3468-9110-73de2fe5d691', 'GK-2624-D80061', 'AGIL KIRANA WIFA AGIL KIRANA', '2624', 'Import GudangKu kardus. nomor_id=2624.', true),
  ('aeb77788-1ec1-3f6b-ae42-a228bec38a42', 'GK-2152-DAB7E1', 'Fajar Permatasari T. WIFA', '2152', 'Import GudangKu kardus. nomor_id=2152.', true),
  ('136d4edd-14cf-319a-84b8-fa12c42ff50e', 'GK-0880-57C704', 'M DAME ANITA DAME SIHOMBING', '0880', 'Import GudangKu kardus. nomor_id=0880.', true),
  ('0f9f5a48-5d58-38df-b387-91466d24f86f', 'GK-7625-9E9B86', 'Neng kanan T Papua wili Saputra', '7625', 'Import GudangKu kardus. nomor_id=7625.', true),
  ('17b387dc-a70a-3a16-b437-d4240db5874d', 'GK-1027-2B1634', 'Neng Kanan T. Marjono', '1027', 'Import GudangKu kardus. nomor_id=1027.', true),
  ('737c0a06-6b5f-35d1-9e13-42d77309dd0d', 'GK-5119-2ED76E', 'Tjoy li mi Agus tinus Ojara', '5119', 'Import GudangKu kardus. nomor_id=5119.', true),
  ('f9ec9690-2f1a-3434-98e0-76cafb9cee4e', 'GK-2405-C0A53A', 'Neng Kanan T. asum sumiati', '2405', 'Import GudangKu kardus. nomor_id=2405.', true),
  ('35378cee-5b2e-35ae-99cb-b0db8b598052', 'GK-0784-BC9519', 'raisha afra sakila t wifa raisha afra sakila', '0784', 'Import GudangKu kardus. nomor_id=0784.', true),
  ('12c0675a-ec2e-31c0-ad4b-de8fc24a78b1', 'GK-0231-BB6BD3', 'christal geraldine wifa christal geraldine kirsten', '0231', 'Import GudangKu kardus. nomor_id=0231.', true),
  ('e8c9a937-7af4-3874-9f29-1e7da0f38873', 'GK-2304-827CDD', 'doni anita doni setia', '2304', 'Import GudangKu kardus. nomor_id=2304.', true),
  ('b50313f0-3d7d-3b25-8301-1e34f69ec6e4', 'GK-8181-B9CFB4', 'Ami Alvin PRAkOSO', '8181', 'Import GudangKu kardus. nomor_id=8181.', true),
  ('ded0bbfd-5e41-3fb1-86fb-07bef0b4446d', 'GK-3874-7C9088', 'Ami Fitri Aulia', '3874', 'Import GudangKu kardus. nomor_id=3874.', true),
  ('fe867514-f94d-3bf5-adfa-bc4b0b0d388c', 'GK-8181-D66020', 'AMIPITRIADAMAYANTI', '8181', 'Import GudangKu kardus. nomor_id=8181.', true),
  ('acb66399-5bc9-3b72-8b38-adde93daa640', 'GK-2171-DB0466', 'Neng Kanan T.Irfan', '2171', 'Import GudangKu kardus. nomor_id=2171.', true),
  ('8653e465-740b-30e7-b325-13a2628f8a21', 'GK-9805-A34010', 'Yoga Anita yoga bagus', '9805', 'Import GudangKu kardus. nomor_id=9805.', true),
  ('ac68d4ff-c432-3b75-8b04-1a23320ce63b', 'GK-4085-C1AACA', 'DWi DM edydwi medling', '4085', 'Import GudangKu kardus. nomor_id=4085.', true),
  ('89aafaf3-de66-3389-8002-a40b828c3b61', 'GK-3805-E913C5', 'PRabowo Adi T mawarni Prabowo Adi', '3805', 'Import GudangKu kardus. nomor_id=3805.', true),
  ('3ce048a2-12ad-30b7-9d3d-37ec300b8dda', 'GK-4821-E3A44A', 'tjong li mi Maria bernadet bunga betan', '4821', 'Import GudangKu kardus. nomor_id=4821.', true),
  ('e1c50931-4ae0-342e-a7e0-973ab2abf1fb', 'GK-7629-D1182F', 'neng kanan t papua rajan akbar', '7629', 'Import GudangKu kardus. nomor_id=7629.', true),
  ('4d9590cd-c555-375e-ad8b-6b63fbf9fe00', 'GK-3788-4FFA97', 'Joko Susilo t marta joko Susilo', '3788', 'Import GudangKu kardus. nomor_id=3788.', true),
  ('3394b6d0-bc22-3a0c-9741-55651cb34ac9', 'GK-1550-390A1D', 'Setepen T. Dadang kanan', '1550', 'Import GudangKu kardus. nomor_id=1550.', true),
  ('8c924dcd-4654-3ece-b131-18d81f396c21', 'GK-7619-0D0A77', 'Neng kanan T papua muhamad Riyas', '7619', 'Import GudangKu kardus. nomor_id=7619.', true),
  ('5ce00d80-e0e6-382d-9158-677477dd0dbf', 'GK-7798-7F03A6', 'NenG kanan I papua Lalita Surlina', '7798', 'Import GudangKu kardus. nomor_id=7798.', true),
  ('bf50a135-85ec-3d91-b1a4-28e90b3de914', 'GK-1646-2F6079', 'Oki Seatiwan T. Raisa', '1646', 'Import GudangKu kardus. nomor_id=1646.', true),
  ('58b56e7a-38c6-3696-9a04-6a741e10049b', 'GK-3775-11D61E', 'Nur efendi team Rina nur efendi', '3775', 'Import GudangKu kardus. nomor_id=3775.', true),
  ('d7dbef5e-754f-3240-82e8-5b059d375b56', 'GK-0047-7A20E6', 'tina mariana dm tina', '0047', 'Import GudangKu kardus. nomor_id=0047.', true),
  ('e7838b73-d97f-35b8-b3c2-45678b531552', 'GK-3893-DA0DD8', 'Ami metta sutanto', '3893', 'Import GudangKu kardus. nomor_id=3893.', true),
  ('d9994e72-f927-3dbb-bbff-d207baf6017a', 'GK-2509-53AD0E', 'Neng Kanan T. ABDUL ADID', '2509', 'Import GudangKu kardus. nomor_id=2509.', true),
  ('bc0a291a-2c83-3505-b60d-888e11a24343', 'GK-3955-CAF4E8', 'Angga Pranata T erlin kanan angga pranata', '3955', 'Import GudangKu kardus. nomor_id=3955.', true),
  ('9e69937b-4bed-3a28-b600-6efd181e1ba7', 'GK-2338-664744', 'Yuyun Jiman T Martha', '2338', 'Import GudangKu kardus. nomor_id=2338.', true),
  ('95032b43-3275-37fd-bb55-691e7bbbc10b', 'GK-3817-B8719A', 'Intan Permatasari T Erlin Intan', '3817', 'Import GudangKu kardus. nomor_id=3817.', true),
  ('b02e654e-883b-34d2-bb2a-42c979069cc1', 'GK-7592-73ED16', 'Neng kanan T Papua Nita Lingga citra', '7592', 'Import GudangKu kardus. nomor_id=7592.', true),
  ('781d7982-b1a4-3407-8b01-be6ccf0feada', 'GK-1238-F68631', 'neng kanan t papua hotmaria sinaga', '1238', 'Import GudangKu kardus. nomor_id=1238.', true),
  ('871ab5a3-06d9-3230-9cd0-94550ef04290', 'GK-2576-BF59D2', 'Tomy Effendy Sm T. Raisha', '2576', 'Import GudangKu kardus. nomor_id=2576.', true),
  ('dbb6ca27-a084-322c-aee9-36b038e09c2e', 'GK-1556-72B5E8', 'Neng kanan T. Novie Masayu', '1556', 'Import GudangKu kardus. nomor_id=1556.', true),
  ('37e93353-3646-3b1d-bbc7-8d0e5fc58dac', 'GK-1093-945980', 'Ami T. Ichsan yarmi', '1093', 'Import GudangKu kardus. nomor_id=1093.', true),
  ('ded86b3e-e273-3bc9-9743-a98acd82ecc4', 'GK-0348-B284A3', 'Anita bintang gading gading marthin', '0348', 'Import GudangKu kardus. nomor_id=0348.', true),
  ('20daab16-0f55-35d8-8d28-7b20215b85b0', 'GK-2560-459DD3', 'neng kanan t papua widya vania', '2560', 'Import GudangKu kardus. nomor_id=2560.', true),
  ('40a4077b-7f2a-3895-9faa-c15334076f06', 'GK-5095-449698', 'Tjong li mi niken lestari', '5095', 'Import GudangKu kardus. nomor_id=5095.', true),
  ('85ef5ad5-d801-3c2f-9c67-3429e8f9e270', 'GK-3946-CBAAF1', 'Halim julianto t mawar nithalim Julianto', '3946', 'Import GudangKu kardus. nomor_id=3946.', true),
  ('09eaafa7-ac30-361d-92dc-047894d28244', 'GK-8176-8A03D1', 'edi anita edi saptono', '8176', 'Import GudangKu kardus. nomor_id=8176.', true),
  ('4e18b4cd-3d4b-319c-8a46-0b509be2dc90', 'GK-7496-C42014', 'Neng kanan T Papua niko Lius', '7496', 'Import GudangKu kardus. nomor_id=7496.', true),
  ('22633728-c948-31d2-b77b-e1e64e1b4695', 'GK-9934-FE0501', 'neng kanan t papua ujang mansur', '9934', 'Import GudangKu kardus. nomor_id=9934.', true),
  ('beecf0e7-7cc9-3c56-ae39-738489ed3b3c', 'GK-0260-B71C7A', 'Putri Maheshwara Kanan Dadang', '0260', 'Import GudangKu kardus. nomor_id=0260.', true),
  ('3dcf275a-2171-3d79-bd17-2864ce842b66', 'GK-3852-B6AD22', 'Ami Diyan', '3852', 'Import GudangKu kardus. nomor_id=3852.', true),
  ('3bb07eba-dc63-3d7a-befb-caf9e01917d3', 'GK-4112-D23476', 'ami sean murphy moeis', '4112', 'Import GudangKu kardus. nomor_id=4112.', true),
  ('f4af4ba8-e6a1-3179-89cd-50d8ad5c692d', 'GK-1264-87C613', 'Neng Kanan T Papua Abel Putri', '1264', 'Import GudangKu kardus. nomor_id=1264.', true),
  ('b0e5fbf3-58a9-3c31-96f2-7006d0cc4fdf', 'GK-4112-FE1DAE', 'dian kartika t erlin dian kartika', '4112', 'Import GudangKu kardus. nomor_id=4112.', true),
  ('d383efa1-ad0f-3a7e-9b4c-94097176742f', 'GK-1154-061A85', 'Neng Kanan T. Kartika', '1154', 'Import GudangKu kardus. nomor_id=1154.', true),
  ('cf588bf5-6852-3e04-8be8-5bf81b0eef0f', 'GK-2332-81457D', 'Neng Kanan T. Parva Fika Andira', '2332', 'Import GudangKu kardus. nomor_id=2332.', true),
  ('08023fdf-77db-32c6-9ded-b3bafee1e517', 'GK-8294-F0223F', 'lena selvi lena arumi', '8294', 'Import GudangKu kardus. nomor_id=8294.', true),
  ('11057e65-b5d1-37e3-a705-4be1f2790f67', 'GK-4023-84B127', 'Woen lily ID T boen kanan woen lily', '4023', 'Import GudangKu kardus. nomor_id=4023.', true),
  ('7391e3ba-6a61-35d2-92b1-a344708dd7ed', 'GK-1233-DADA95', 'Neng Kanan T Papua Afika Andika', '1233', 'Import GudangKu kardus. nomor_id=1233.', true),
  ('b9d4a8f3-6ac5-36d0-b2bd-80a7571430fd', 'GK-0732-DBC479', 'Puput Kembang Wifa', '0732', 'Import GudangKu kardus. nomor_id=0732.', true),
  ('5a987a5c-de5c-3c38-8874-fdb90956393f', 'GK-7401-FC54D6', 'Adriana Team Rina', '7401', 'Import GudangKu kardus. nomor_id=7401.', true),
  ('0728fcdb-6a89-3c67-884f-d9b8abb9b741', 'GK-2342-45E920', 'Nurul Anita Khotimah', '2342', 'Import GudangKu kardus. nomor_id=2342.', true),
  ('a7c48d7e-39af-368e-aaae-8d6d07397c7b', 'GK-8456-E73EE7', 'Yani Anita Yaniingsi', '8456', 'Import GudangKu kardus. nomor_id=8456.', true),
  ('4f15758a-1ce2-3970-ad1a-3744b2791e3c', 'GK-0079-D9F943', 'dian anita dian', '0079', 'Import GudangKu kardus. nomor_id=0079.', true),
  ('f767617a-8532-33f7-9489-d09d81eb166d', 'GK-1406-8010E5', 'Neng Kanan T Papua Ilham Purnama', '1406', 'Import GudangKu kardus. nomor_id=1406.', true),
  ('733d746f-c58d-31a2-bb79-2aa59c8d55cf', 'GK-8215-DA51B6', 'Jojor Selvi Jojor Simanjuntak', '8215', 'Import GudangKu kardus. nomor_id=8215.', true),
  ('64567a6b-fe4e-3b20-bd9b-07c667bc2365', 'GK-9849-61C56A', 'Neng kanan T papua Syaifullah hidayat', '9849', 'Import GudangKu kardus. nomor_id=9849.', true),
  ('402ec6d7-754a-3814-a966-89b4787caa5c', 'GK-0791-07A182', 'Neng kanan T. Papuakharisma Palupi', '0791', 'Import GudangKu kardus. nomor_id=0791.', true),
  ('cc5e0078-1444-360f-aa9f-7b89d4306cfc', 'GK-2520-78C1FF', 'neng kanan t papua juliana', '2520', 'Import GudangKu kardus. nomor_id=2520.', true),
  ('2bea73e0-00a4-3850-bacd-8c7ac41d1d25', 'GK-1586-468B25', 'Neng kanan T. Yati', '1586', 'Import GudangKu kardus. nomor_id=1586.', true),
  ('3552a05d-f418-3426-a291-e510118e07e3', 'GK-9743-1EC964', 'Farhan Anita Farhan maulana', '9743', 'Import GudangKu kardus. nomor_id=9743.', true),
  ('3ee71dd6-35c5-32f4-8f85-00c02c1f5ce3', 'GK-0037-C6DC16', 'neng kanan t papua tatan', '0037', 'Import GudangKu kardus. nomor_id=0037.', true),
  ('bfe074b2-fd47-3ba1-a39f-eb72d9da3556', 'GK-2600-09E172', 'Neng Kanan T. Ammar Kholid', '2600', 'Import GudangKu kardus. nomor_id=2600.', true),
  ('9fb1b136-2edf-3bcc-8a57-46dac57cb9e0', 'GK-7630-71FB01', 'Mirna team rina mirna sumindar', '7630', 'Import GudangKu kardus. nomor_id=7630.', true),
  ('97b97d82-ccce-3e21-8531-69b2108f7a32', 'GK-3831-F4AC7F', 'Ami Ahmad rifai', '3831', 'Import GudangKu kardus. nomor_id=3831.', true),
  ('cb83a9a3-3d76-3274-bfc2-4e90deb7960e', 'GK-8195-7FF8A5', 'boima silalahi t mawarni boima silalahi', '8195', 'Import GudangKu kardus. nomor_id=8195.', true),
  ('19386839-a9f6-3a01-9b53-a7f5a95ea68c', 'GK-8557-9A8C8A', 'Gilang Anita Gilang', '8557', 'Import GudangKu kardus. nomor_id=8557.', true),
  ('7122ca1b-a9c3-38f6-a189-6088bccfe8f5', 'GK-1940-137196', 'Wilson by Ami Frendy Butar', '1940', 'Import GudangKu kardus. nomor_id=1940.', true),
  ('b501fd5e-dbb5-36b1-a530-bcca582b1b43', 'GK-1382-0D0A77', 'Neng kanan T papua muhamad Riyas', '1382', 'Import GudangKu kardus. nomor_id=1382.', true),
  ('6f6ef83d-8280-3ace-962b-18856cd04962', 'GK-1088-E485B5', 'Gerad firmansya Kanan Dadang', '1088', 'Import GudangKu kardus. nomor_id=1088.', true),
  ('1ad3c66b-689f-3463-85d8-12f05275ea4a', 'GK-3871-81F0DA', 'Bagiono SM T Shofia kiri bagiono', '3871', 'Import GudangKu kardus. nomor_id=3871.', true),
  ('28ba4cf1-ae1b-3496-bb6f-bf6a330fceb0', 'GK-7849-7C8F69', 'wulan anita wulan', '7849', 'Import GudangKu kardus. nomor_id=7849.', true),
  ('373f0755-1983-3b2e-9d76-375e0c031fb3', 'GK-2139-2B1634', 'Neng kanan T. Marjono', '2139', 'Import GudangKu kardus. nomor_id=2139.', true),
  ('bad8b96b-e399-3fda-9e8a-2a30c93b9728', 'GK-2535-0ED9BF', 'LIDIA Team Rinalidia', '2535', 'Import GudangKu kardus. nomor_id=2535.', true),
  ('0de75edb-7876-3282-a5ec-34018d868cf9', 'GK-4005-FF3B04', 'Asnawi Hafel T Mawarni', '4005', 'Import GudangKu kardus. nomor_id=4005.', true),
  ('a4f4fe07-64d3-3e22-a93a-6d619a27acf6', 'GK-4005-07340C', 'amiliho', '4005', 'Import GudangKu kardus. nomor_id=4005.', true),
  ('f4258a0e-f0db-3123-b361-0626ce6a082c', 'GK-8890-E34860', 'Fahmi Anitafahmi', '8890', 'Import GudangKu kardus. nomor_id=8890.', true),
  ('72f36d1e-6fe3-3e2e-b2e4-7cf2478bf2e4', 'GK-2340-4BC70A', 'Wenny Anita', '2340', 'Import GudangKu kardus. nomor_id=2340.', true),
  ('c7e05c5e-0a5f-3197-866c-6d8205339ec0', 'GK-7576-F9584E', 'Meti Anita meti Delsi', '7576', 'Import GudangKu kardus. nomor_id=7576.', true),
  ('80b01516-f390-3844-a60d-5911734f9035', 'GK-0301-DB4C10', 'Neng Kanan T. Papua IHSAN IFTIKAR', '0301', 'Import GudangKu kardus. nomor_id=0301.', true),
  ('11ec0e64-d2ad-3f34-ac81-f6a3c4ad7bda', 'GK-1594-4E9B17', 'juliyana team rina puji lestar', '1594', 'Import GudangKu kardus. nomor_id=1594.', true),
  ('998d00e6-f3f6-39d3-87c2-d6439154bfa3', 'GK-1863-5D2EAE', 'samsul anita samsul sumitarya', '1863', 'Import GudangKu kardus. nomor_id=1863.', true),
  ('688ca58d-dfdf-36aa-90c4-045be9caaab1', 'GK-0735-7800C6', 'neng kanan t papua heri kuswanto', '0735', 'Import GudangKu kardus. nomor_id=0735.', true),
  ('2efe0585-c398-3c0e-aa62-2514897210d4', 'GK-1190-49CF88', 'juliyana team rina julyana nainggolan', '1190', 'Import GudangKu kardus. nomor_id=1190.', true),
  ('d0be4707-81ee-3d94-a8c8-daa456b71d83', 'GK-2668-E0A1EC', 'Neng Kanan T. PAPUA AQILA', '2668', 'Import GudangKu kardus. nomor_id=2668.', true),
  ('6b1cbffc-544b-3585-b64f-7807c36f8610', 'GK-8497-CDBEAA', 'Deni Anita Deni', '8497', 'Import GudangKu kardus. nomor_id=8497.', true),
  ('f75876f0-a775-3a8f-8607-872cab6745f1', 'GK-2199-FE0501', 'Neng Kanan T Papua Ujang Mansur', '2199', 'Import GudangKu kardus. nomor_id=2199.', true),
  ('6e8ba448-6a0f-3837-853e-7e8229bdac09', 'GK-0786-CC5671', 'Neng Kanan T. Papua Daniah', '0786', 'Import GudangKu kardus. nomor_id=0786.', true),
  ('acdeacd1-dd77-316a-9372-48fb09b4c60a', 'GK-0639-7C0426', 'Neng kanan T. Papua Darrel Lingga', '0639', 'Import GudangKu kardus. nomor_id=0639.', true),
  ('c6c0699e-45c4-3ffe-8be2-74a89229433e', 'GK-1381-01E92F', 'Nengkanan T. Papua Darrel', '1381', 'Import GudangKu kardus. nomor_id=1381.', true),
  ('b67ab2e6-615c-3392-89b4-32e87f0fa3b4', 'GK-3808-FE1DAE', 'Dian kartika T erlin dian kartika', '3808', 'Import GudangKu kardus. nomor_id=3808.', true),
  ('6853d66d-5084-3879-9610-1cc8eaccf266', 'GK-1852-8E6843', 'Neng kanan T. Widya Vania', '1852', 'Import GudangKu kardus. nomor_id=1852.', true),
  ('f88d475a-6614-3ad1-b960-01db6fb4aff8', 'GK-0906-4ECA0F', 'Neng kanan, T. bianca', '0906', 'Import GudangKu kardus. nomor_id=0906.', true),
  ('7e9a9827-d4ad-38ce-ae5a-d32b4e9e1bbb', 'GK-2674-A23E22', 'Neng Kanan t papua kartika', '2674', 'Import GudangKu kardus. nomor_id=2674.', true),
  ('3139ebf3-dd91-33b7-896b-381cc08ab916', 'GK-1273-508CDA', 'Neng Kanan T. Papua Euis Indasiah,', '1273', 'Import GudangKu kardus. nomor_id=1273.', true),
  ('5dbcf107-1857-3ccd-ab7f-201444c25a77', 'GK-3941-E7A362', 'Anita bintang Sinta sinta Susilawati', '3941', 'Import GudangKu kardus. nomor_id=3941.', true),
  ('4960b71a-e43e-3a38-9335-5ee75617af97', 'GK-3875-9A465B', 'Mesha T boen kiri mesha', '3875', 'Import GudangKu kardus. nomor_id=3875.', true),
  ('181de891-3a3a-35be-96ce-3209566b4ade', 'GK-0584-C774BA', 'Tori Aldonso T Raisha', '0584', 'Import GudangKu kardus. nomor_id=0584.', true),
  ('3f024972-e907-357c-8b27-ecdc1ce09d8b', 'GK-2542-BCF765', 'Tina Mariana DM Tina.', '2542', 'Import GudangKu kardus. nomor_id=2542.', true),
  ('1d615192-aeca-3096-b189-460913247cd1', 'GK-1625-8076E6', 'Ami Yanuar Iskandar', '1625', 'Import GudangKu kardus. nomor_id=1625.', true),
  ('6b9a9fef-4003-3d32-82a1-88130cdd8fba', 'GK-2510-37AB36', 'Neng Kanan T. Lisna Fadilah', '2510', 'Import GudangKu kardus. nomor_id=2510.', true),
  ('78d74e41-9abf-38b9-aef0-653de3a9fcca', 'GK-2797-F0979D', 'Nengkanan T. Papua Herlina', '2797', 'Import GudangKu kardus. nomor_id=2797.', true),
  ('1dbdd81a-014f-3bec-88b2-a8fc1afd2741', 'GK-1383-1D166E', 'Neng kanan Т. Ека', '1383', 'Import GudangKu kardus. nomor_id=1383.', true),
  ('6f24963d-c285-3acd-9f69-40978f8ee789', 'GK-2313-E0A1EC', 'Neng Kanan T. PAPUA AQILA', '2313', 'Import GudangKu kardus. nomor_id=2313.', true),
  ('dd47a7f4-ddf0-3081-b842-27d5b308aec0', 'GK-0487-7A20E6', 'Tina Mariana DM Tina', '0487', 'Import GudangKu kardus. nomor_id=0487.', true),
  ('4c482d31-db2a-3121-b5c1-8645f3959805', 'GK-0268-886987', 'Sakilah Team Rina Sakilah', '0268', 'Import GudangKu kardus. nomor_id=0268.', true),
  ('787ca015-304f-38bc-b6c5-59bd7639f6f1', 'GK-1819-868EDD', 'Neng kanan T. Rusmini', '1819', 'Import GudangKu kardus. nomor_id=1819.', true),
  ('cc6deebf-5381-34bd-b0d1-b71b7976b9d2', 'GK-3813-CFEFE0', 'zamas wiliam T Erlin zamas wiliam', '3813', 'Import GudangKu kardus. nomor_id=3813.', true),
  ('c5bb5c44-a993-32cf-8bf1-455643985571', 'GK-0308-15EE10', 'Suryani Arab lenny Fransiska', '0308', 'Import GudangKu kardus. nomor_id=0308.', true),
  ('119c2c6a-88ec-367e-8ad1-61ba1d7c4a58', 'GK-3791-66E4FA', 'bagus setiawan T erlin bagus setiawan', '3791', 'Import GudangKu kardus. nomor_id=3791.', true),
  ('b3e217bc-221e-351c-ba04-615d28d2aab8', 'GK-0103-492097', 'Sambaru Team Rina', '0103', 'Import GudangKu kardus. nomor_id=0103.', true),
  ('80a54de3-6d14-3390-be79-b219944b63fa', 'GK-1301-E76D78', 'Neng kanan T. Papuaabdurahman', '1301', 'Import GudangKu kardus. nomor_id=1301.', true),
  ('0a6edca6-1758-338b-b758-d1373c20bf67', 'GK-2354-73CCDF', 'Neng Kanan T. Hidayatuloh.', '2354', 'Import GudangKu kardus. nomor_id=2354.', true),
  ('a87f2dd5-f936-33fa-9a21-bc7ca7771c9d', 'GK-1265-459DD3', 'Neng Kanan T Papua Widya Vania', '1265', 'Import GudangKu kardus. nomor_id=1265.', true),
  ('82337133-01c6-380c-bd86-712dfd5ed552', 'GK-3868-6AA393', 'Ami T Djohan SM Boen', '3868', 'Import GudangKu kardus. nomor_id=3868.', true),
  ('c033ca56-5c41-3052-8714-197df8ff28dd', 'GK-3900-A12E28', 'Paudi Iskandar Hasibuan Shofia', '3900', 'Import GudangKu kardus. nomor_id=3900.', true),
  ('ce24cb87-539f-3c81-a96e-0cdee4beb43c', 'GK-3842-9590C1', 'Wulan sari T Erlin wulan sari', '3842', 'Import GudangKu kardus. nomor_id=3842.', true),
  ('e20ef9b4-ea5f-3bca-9b2c-cf2b99cc59a8', 'GK-9874-5D040E', 'dony anita dony eko janingrum', '9874', 'Import GudangKu kardus. nomor_id=9874.', true),
  ('72d35fb4-5141-36a2-935b-1088588e6082', 'GK-1218-53AD0E', 'Neng kanan T. Abdul Adid', '1218', 'Import GudangKu kardus. nomor_id=1218.', true),
  ('d1482aed-a92e-3350-ae79-83e68044dc76', 'GK-2089-E12695', 'Juliyana T. Rina Juliyana', '2089', 'Import GudangKu kardus. nomor_id=2089.', true),
  ('7a2b6065-2158-3a7f-a7ac-8c5c2acfeb2f', 'GK-2478-CA5C18', 'Roney Steven T Wifa', '2478', 'Import GudangKu kardus. nomor_id=2478.', true),
  ('56ca0613-d900-3690-acb0-6fb4441da712', 'GK-4064-546BAD', 'diyan T bend kiri diyan', '4064', 'Import GudangKu kardus. nomor_id=4064.', true),
  ('b418e6fd-5f57-3941-bab5-46a47f7aa2c4', 'GK-0653-1D80E2', 'Neng Kanan T. Riki Suswanto', '0653', 'Import GudangKu kardus. nomor_id=0653.', true),
  ('e3c8e7dd-a8cd-325e-8a70-6873a60b075b', 'GK-2612-6D0080', 'Neng Kanan T. Sunarsih', '2612', 'Import GudangKu kardus. nomor_id=2612.', true),
  ('0e64086b-87be-3e48-b26a-5ab8df12de41', 'GK-4120-529E07', 'Intan Permatasari T Erlin', '4120', 'Import GudangKu kardus. nomor_id=4120.', true),
  ('78aa8c6d-17d8-305d-b5eb-5b5d2843a071', 'GK-4120-FA40B6', 'IMMANUEL T CARLES IMMANUEL NATANAEL', '4120', 'Import GudangKu kardus. nomor_id=4120.', true),
  ('0f56fb5e-d16d-30d5-bd3b-65b1074bb4cd', 'GK-0143-C8B8DA', 'AMI APUD GUSMAN S PD', '0143', 'Import GudangKu kardus. nomor_id=0143.', true),
  ('0aa2428c-2172-3607-9d95-a056d23bb441', 'GK-4813-42EF75', 'NADIA AMI NADIA', '4813', 'Import GudangKu kardus. nomor_id=4813.', true),
  ('f444d4a8-4aa6-34ff-a805-8cad767db0e4', 'GK-4813-50DA17', 'SUPARMAN AMI SUPARMAN', '4813', 'Import GudangKu kardus. nomor_id=4813.', true),
  ('d86980f7-a894-3e36-b31f-4104ca3ec5da', 'GK-4827-61ABEC', 'AMI SEPTIAN', '4827', 'Import GudangKu kardus. nomor_id=4827.', true),
  ('4bd96636-2d41-302d-9621-2fca4dc32abb', 'GK-4826-8EA866', 'AMI ZAHRA LESTARI', '4826', 'Import GudangKu kardus. nomor_id=4826.', true),
  ('46da6c56-963a-34d9-8485-455484437a51', 'GK-4828-551FDD', 'AMI MALLIKAH BILQIS', '4828', 'Import GudangKu kardus. nomor_id=4828.', true),
  ('7c1511c8-6899-3560-b1ba-6a77c82e7d94', 'GK-0740-43825A', 'AMI RASTINI', '0740', 'Import GudangKu kardus. nomor_id=0740.', true),
  ('aea558c3-ed6c-3629-85d7-d70df5556dbc', 'GK-4404-071084', 'AMI JENNY OKTAVIANI', '4404', 'Import GudangKu kardus. nomor_id=4404.', true),
  ('575c01e7-d1f1-328e-8134-4896bd42d3f7', 'GK-4405-FD15D1', 'AMI HADI SUWITO', '4405', 'Import GudangKu kardus. nomor_id=4405.', true),
  ('110a4454-eed4-3395-9c01-621334d7c389', 'GK-0231-5431EA', 'AMI SOPYAN', '0231', 'Import GudangKu kardus. nomor_id=0231.', true),
  ('c7c72683-2185-38ad-82e9-150da625edf2', 'GK-2779-2C8490', 'PUTRI AMI PUTRI CINDY', '2779', 'Import GudangKu kardus. nomor_id=2779.', true),
  ('eac1cfdf-fc4f-313f-a5a5-adc075f073e5', 'GK-4402-D5A043', 'aminadia', '4402', 'Import GudangKu kardus. nomor_id=4402.', true),
  ('27d89c46-83a2-384d-af24-5d6fa1b03ea6', 'GK-0492-7720B2', 'AMI SUSANTI', '0492', 'Import GudangKu kardus. nomor_id=0492.', true),
  ('6c8d7819-fbbb-3506-af09-9418ee643711', 'GK-4403-0266EE', 'AMI SUWARJI', '4403', 'Import GudangKu kardus. nomor_id=4403.', true),
  ('816f8102-d70b-3a9e-a030-4ad26bf5729d', 'GK-4375-B2C04B', 'ANITA BINTANG DANANG DANANG', '4375', 'Import GudangKu kardus. nomor_id=4375.', true),
  ('f55c6d49-a45c-3ce9-89f0-d5462a2bc83f', 'GK-4401-7A32E3', 'AMI SUPARMAN', '4401', 'Import GudangKu kardus. nomor_id=4401.', true),
  ('9db0e9af-749e-3504-9242-3858458a433a', 'GK-0332-990A1E', 'AMIKSAM', '0332', 'Import GudangKu kardus. nomor_id=0332.', true),
  ('e3eb4988-d79d-3711-9eba-692822fa8e2c', 'GK-2317-7256F9', 'MIA AUDINA NURHIDAYAH', '2317', 'Import GudangKu kardus. nomor_id=2317.', true),
  ('3aa446cf-6fca-360a-a05b-1c11815a0a7a', 'GK-0088-F14911', 'ami lina', '0088', 'Import GudangKu kardus. nomor_id=0088.', true),
  ('794f4cf6-c7d3-3b89-b29e-521f0f5cb00e', 'GK-2318-8036DD', 'amicevi', '2318', 'Import GudangKu kardus. nomor_id=2318.', true),
  ('14127f7a-310f-3df9-b03b-48ffb52339e2', 'GK-1014-2C8490', 'PUTRI AMI PUTRI CINDY', '1014', 'Import GudangKu kardus. nomor_id=1014.', true),
  ('4793abbf-dbb3-351c-a6aa-f318845a3ac6', 'GK-2323-FF1AD9', 'ami erick putra', '2323', 'Import GudangKu kardus. nomor_id=2323.', true),
  ('5c9e7ce0-f491-3673-91e0-73090215232c', 'GK-2322-38B157', 'SEPTIAN AMI', '2322', 'Import GudangKu kardus. nomor_id=2322.', true),
  ('6eb9ee59-b03b-380d-942f-9de9c97a8ca1', 'GK-2316-A31866', 'achmad ami achmad suheli', '2316', 'Import GudangKu kardus. nomor_id=2316.', true),
  ('271aef6e-6f5c-3cd4-b442-e23160e57af4', 'GK-0189-FA22C4', 'ami agung setiawan', '0189', 'Import GudangKu kardus. nomor_id=0189.', true),
  ('e4d0d56a-424c-31f1-9453-5f56ebd51165', 'GK-4793-425C57', 'ami antika sari', '4793', 'Import GudangKu kardus. nomor_id=4793.', true),
  ('175d7621-ad5d-32f3-b213-ff503e9daba5', 'GK-8675-6FA479', 'ANUNSIATA MBEOWAKE WARE', '8675', 'Import GudangKu kardus. nomor_id=8675.', true),
  ('61d06b1b-a1aa-3ed1-90a7-4d0f551765bd', 'GK-8675-F4E056', 'AMIMALIKAH BILQIS', '8675', 'Import GudangKu kardus. nomor_id=8675.', true),
  ('68677e56-81fa-39b1-b0be-0e274d9dedf0', 'GK-4931-7AFA01', 'tjong li mi ratnasari', '4931', 'Import GudangKu kardus. nomor_id=4931.', true),
  ('b5fd2433-edb3-3106-8d5e-3385610e494b', 'GK-8696-CA23D0', 'ami sahirin', '8696', 'Import GudangKu kardus. nomor_id=8696.', true),
  ('635333af-7e56-36b3-9793-6bf6f7e792be', 'GK-0935-CA1C86', 'AMIYULIA', '0935', 'Import GudangKu kardus. nomor_id=0935.', true),
  ('2ed38cb4-bab8-3877-a35c-2a35232a17b9', 'GK-4678-82C3CE', 'ami kisam', '4678', 'Import GudangKu kardus. nomor_id=4678.', true),
  ('afc79f7c-513d-3122-a4aa-bf30a2fcd23c', 'GK-0898-7720B2', 'ami susanti', '0898', 'Import GudangKu kardus. nomor_id=0898.', true),
  ('830f23b9-77cf-373b-b7eb-896d9e9d0458', 'GK-0886-E1C3F9', 'rasto by ami rasto hartono', '0886', 'Import GudangKu kardus. nomor_id=0886.', true),
  ('f165f95a-0af6-35c8-934c-d441904ae8f4', 'GK-8186-425C57', 'AMI ANTIKA SARI', '8186', 'Import GudangKu kardus. nomor_id=8186.', true),
  ('2bcfb540-d3d0-3971-870a-eb2de7f77f6f', 'GK-1741-5EDFB0', 'Mita T WIFA AMita karya', '1741', 'Import GudangKu kardus. nomor_id=1741.', true),
  ('cd5b8de6-8d58-3fdc-af98-647e66ac1235', 'GK-1678-7B370D', 'jeffry dwi a', '1678', 'Import GudangKu kardus. nomor_id=1678.', true),
  ('4085405c-835f-309c-a8c6-5a342c8812cb', 'GK-1661-953F17', 'jeffry bshofia husna', '1661', 'Import GudangKu kardus. nomor_id=1661.', true),
  ('634f5f61-5292-31a5-8409-f724569e20c3', 'GK-2802-60FB37', 'ilham anita ilham kurniawan', '2802', 'Import GudangKu kardus. nomor_id=2802.', true),
  ('aff23c61-bc37-32af-a41b-4ba655fb7310', 'GK-0012-F8DB76', 'stevannystevani y peea', '0012', 'Import GudangKu kardus. nomor_id=0012.', true),
  ('8e5f60bb-7625-3213-8faa-d8c67f0c8890', 'GK-9383-BC5634', 'Neng Kanan T PAPUA UNDANG SUKARSA', '9383', 'Import GudangKu kardus. nomor_id=9383.', true),
  ('d4e4d447-b886-3a46-9aa5-8614df443b06', 'GK-9521-2C772F', 'NENG KANAN T PAPUA NUNU NUHDIN', '9521', 'Import GudangKu kardus. nomor_id=9521.', true),
  ('7d004c47-a759-36ee-8e23-4f5427950b1a', 'GK-0827-0255C1', 'NENG KANNA T PAPUA IYAH SOPIYAH', '0827', 'Import GudangKu kardus. nomor_id=0827.', true),
  ('3163b4e3-29fa-34cf-a5b8-2f4ad5509f82', 'GK-1396-2B4366', 'indra anita indra lesmana', '1396', 'Import GudangKu kardus. nomor_id=1396.', true),
  ('1ca3359e-74fc-3b0c-bfe4-b35dc55f2c7c', 'GK-9407-2BAB65', 'ABDUL TEAM NENG ABDUL ADID', '9407', 'Import GudangKu kardus. nomor_id=9407.', true),
  ('cdc8d442-aca6-3bda-a9b3-4abe8602adce', 'GK-9608-1A781B', 'neng kanan t papua iyah sopiyah', '9608', 'Import GudangKu kardus. nomor_id=9608.', true),
  ('4a3484a0-5d6d-3888-8339-b6f51accb2b7', 'GK-9457-6369D3', 'NENG KANAN T PAPUA RIKI ARIYANTO', '9457', 'Import GudangKu kardus. nomor_id=9457.', true),
  ('71cc9d6b-05dd-351c-961a-9e50b78e5e5a', 'GK-0025-DD41DB', 'dinda anita dinda simaung', '0025', 'Import GudangKu kardus. nomor_id=0025.', true),
  ('b090bd9f-d484-3fd4-b31f-04c6c600b06f', 'GK-9342-089C94', 'NENG KANAN T PAPUA NOVIE MASAYU AZAN', '9342', 'Import GudangKu kardus. nomor_id=9342.', true),
  ('ad4ee719-7cb5-357d-a951-b56d5a772310', 'GK-9598-7FFFEE', 'NENG KANAN T PAPUA LISNA FADILAH YUSTIANI', '9598', 'Import GudangKu kardus. nomor_id=9598.', true),
  ('f133d825-73c0-3e09-9c7c-6cea98a6dc30', 'GK-9409-003785', 'NENG KANAN T PAPUA NINING YUNINGSIH', '9409', 'Import GudangKu kardus. nomor_id=9409.', true),
  ('4656100c-c8d2-3232-b6ae-87ef06c67e09', 'GK-9573-A9464E', 'NENG KANAN T PAPUA EVA MIRAWATI', '9573', 'Import GudangKu kardus. nomor_id=9573.', true),
  ('94882d69-dd5c-3b1f-ab1b-854ed391179f', 'GK-9350-950F0D', 'NENG KANAN T PAPUA ASTUTI DEWI', '9350', 'Import GudangKu kardus. nomor_id=9350.', true),
  ('94ca7efb-d459-3e06-871b-d4e1ab3bfc3c', 'GK-7663-3536D6', 'NENG KANNA T PAPUA HERI KUSWANTO', '7663', 'Import GudangKu kardus. nomor_id=7663.', true),
  ('dd8084a8-8a5e-3236-9ed7-04bb6e96af44', 'GK-9505-A83F1A', 'NENG KANAN T PAPUA SARIPAH', '9505', 'Import GudangKu kardus. nomor_id=9505.', true),
  ('0ab4abb2-888e-303a-a4e2-655f807a1d02', 'GK-9421-0CE773', 'NENG KANAN T PAPUA RUSMINI', '9421', 'Import GudangKu kardus. nomor_id=9421.', true),
  ('725fdabb-011e-3620-ac46-1316ab2f59af', 'GK-9595-009A4F', 'NENG KANAN T PAPUA BIRIN', '9595', 'Import GudangKu kardus. nomor_id=9595.', true),
  ('9ab83855-ee91-3b9a-88bb-df2f1f30cbe8', 'GK-1186-A60B0C', 'NENG KANAN T PAPUA ROSMA ROSTIKA', '1186', 'Import GudangKu kardus. nomor_id=1186.', true),
  ('5bc84e3c-b4c2-3bce-956f-cc348df84fb8', 'GK-2796-AD0DD8', 'YUNUS ANITA YUNUS', '2796', 'Import GudangKu kardus. nomor_id=2796.', true),
  ('727596db-209a-31e5-ae28-b496d805a29a', 'GK-1092-9FD7C9', 'NENG KANAN T PAPUA YATI', '1092', 'Import GudangKu kardus. nomor_id=1092.', true),
  ('0ff2bfd8-750c-3d19-9934-4ccf33b89028', 'GK-0973-3DAD12', 'NENG KANAN T PAPUA AYU LESTARI', '0973', 'Import GudangKu kardus. nomor_id=0973.', true),
  ('245432e7-2e6b-3c4d-9fb7-943e054df609', 'GK-0017-B000AC', 'NENG KANAN T PAPUA ADIT SURYA', '0017', 'Import GudangKu kardus. nomor_id=0017.', true),
  ('34d458d1-8b87-301d-8b95-8c903053c070', 'GK-0031-C759BA', 'NENG KANAN T PAPUA ANNISA NURAWWALIYAH', '0031', 'Import GudangKu kardus. nomor_id=0031.', true),
  ('b17afc8d-f85f-374b-8976-242bab90b35c', 'GK-2012-E6F220', 'NENG KANNA T PAPUA ANNISA NURAWWALIYAH', '2012', 'Import GudangKu kardus. nomor_id=2012.', true),
  ('8d3f5843-99b1-3f4c-990d-b722efa63a41', 'GK-1664-98B68B', 'NENG KANAN T PAPUA BADRIAH', '1664', 'Import GudangKu kardus. nomor_id=1664.', true),
  ('5b6999fb-d5fd-327d-b193-6c1f082ccc92', 'GK-1939-7800C6', 'NENG KANAN T PAPUA HERI KUSWANTO', '1939', 'Import GudangKu kardus. nomor_id=1939.', true),
  ('4086a465-747f-39c8-b1aa-0f92b290e7c9', 'GK-1207-4B53CE', 'NENG KANAN T PAPUA ARUNI HIDAYAT SURYA', '1207', 'Import GudangKu kardus. nomor_id=1207.', true),
  ('c50946e5-318f-3e20-a656-b940234b0330', 'GK-1407-0C2909', 'EDI ANITAEDI SAPTONO', '1407', 'Import GudangKu kardus. nomor_id=1407.', true),
  ('94eea1fa-f7f7-3356-82e0-4974bdee42a8', 'GK-0046-C1432F', 'NENG KANAN T PAPUA IHAT SOLIHAT', '0046', 'Import GudangKu kardus. nomor_id=0046.', true),
  ('df0240a9-b2c5-3894-82a6-dd7f25b27fb1', 'GK-1705-CA0F89', 'SETEPEN T WIFASETEPEN', '1705', 'Import GudangKu kardus. nomor_id=1705.', true),
  ('5b1d76f3-9b48-30df-bf14-19445ead1e1c', 'GK-0903-F70AAF', 'GILANG ANITA GILANG RAMADHAN', '0903', 'Import GudangKu kardus. nomor_id=0903.', true),
  ('30db23e7-767a-350a-a001-d0ae8fccc8ef', 'GK-1193-38BA47', 'NENG KANAN T P--APUA RATU PERMATA SARI', '1193', 'Import GudangKu kardus. nomor_id=1193.', true),
  ('ba2b2898-2aaf-3b9c-8ff7-98da35544d73', 'GK-0886-FFA435', 'RASTO BY AMI RASTO BUDI', '0886', 'Import GudangKu kardus. nomor_id=0886.', true),
  ('35521879-6860-394f-88c5-a18772ee722d', 'GK-0236-37654F', 'HERIYANTO WIFA HERIYANTO', '0236', 'Import GudangKu kardus. nomor_id=0236.', true),
  ('d53e007a-0542-3da2-b3dc-00c84024f930', 'GK-0935-7AED5F', 'AMI YULIA', '0935', 'Import GudangKu kardus. nomor_id=0935.', true),
  ('94f246e4-d068-386f-b69b-f5a0d76382c3', 'GK-0649-A9464E', 'NENG KANAN T PAPUA EVA MIRAWATI', '0649', 'Import GudangKu kardus. nomor_id=0649.', true),
  ('f4c53b77-53b8-3651-b758-2cf6d83f803b', 'GK-1597-1AF885', 'NENG KANAN T PAPUA IPAH SARIPAH', '1597', 'Import GudangKu kardus. nomor_id=1597.', true),
  ('5d5debfd-839c-3bd8-9ec3-962fea7fe3f2', 'GK-1428-910D6C', 'NENG KANAN T PAPUA IHSAN IFTIKAR', '1428', 'Import GudangKu kardus. nomor_id=1428.', true),
  ('650abe1d-d94e-3c22-b24c-c522a94e8dba', 'GK-1242-D35AD4', 'NENG KANAN T PAPUA NOVIE MASAYU', '1242', 'Import GudangKu kardus. nomor_id=1242.', true),
  ('f1e8c62a-471a-3489-b636-6db2abd5a736', 'GK-0042-BC5634', 'NENG KANAN T PAPUA UNDANG SUKARSA', '0042', 'Import GudangKu kardus. nomor_id=0042.', true),
  ('c8936b02-fef8-3e19-9d45-25f0d0a78c1a', 'GK-2391-950F0D', 'NENG KANAN T PAPUA ASTUTI DEWI', '2391', 'Import GudangKu kardus. nomor_id=2391.', true),
  ('7c38ac9d-d7c7-3071-98b9-05d51fe0faef', 'GK-0917-CDBEAA', 'DENI ANITA DENI', '0917', 'Import GudangKu kardus. nomor_id=0917.', true),
  ('6e2e6ed0-d2a1-3303-9af0-aac9ce9b5967', 'GK-0686-19916D', 'NENG KANAN T PAPUA EUIS INDASIAH', '0686', 'Import GudangKu kardus. nomor_id=0686.', true),
  ('c61d6de2-00e9-3c98-af27-6eeca9068821', 'GK-1679-51580A', 'YOHANES WIFA YOHANES', '1679', 'Import GudangKu kardus. nomor_id=1679.', true),
  ('967b5d1b-02bd-3130-a183-ee446f806371', 'GK-0215-386871', 'NENG KANAN T PAPUA ASUM SUMIIATI', '0215', 'Import GudangKu kardus. nomor_id=0215.', true),
  ('190a7f32-f94d-3ec8-acac-53b1bc9d08c7', 'GK-1036-6369D3', 'NENG KANAN T PAPUA RIKI ARIYANTO', '1036', 'Import GudangKu kardus. nomor_id=1036.', true),
  ('36987046-9c95-3695-9551-efb8bbe80650', 'GK-1977-A9464E', 'NENG KANAN T PAPUA EVA MIRAWATI', '1977', 'Import GudangKu kardus. nomor_id=1977.', true),
  ('51a1f35e-3b5b-3a56-8fc1-6871be59a9ac', 'GK-1504-950F0D', 'NENG KANAN T PAPUA ASTUTI DEWI', '1504', 'Import GudangKu kardus. nomor_id=1504.', true),
  ('7d36ca28-5616-39ac-a8c7-026776517e63', 'GK-2527-483DEF', 'NENG KANAN T PAPUA IRFAN', '2527', 'Import GudangKu kardus. nomor_id=2527.', true),
  ('02dfb792-0d94-3b6d-a661-4e4175205d74', 'GK-9820-7E705B', 'NENG KANAN T PAPUA ARFATHAN MALIK', '9820', 'Import GudangKu kardus. nomor_id=9820.', true),
  ('5d96c70c-d52a-3152-9e2a-28528b222d01', 'GK-1385-4D3FBC', 'SILWANUS TABANA T MARTAWANUS TABANA', '1385', 'Import GudangKu kardus. nomor_id=1385.', true),
  ('99aff5c7-3a5c-3631-88c6-f7b01e35d59e', 'GK-0201-14140F', 'INIEDWATI T KANNA RAISHA INIEDWATI', '0201', 'Import GudangKu kardus. nomor_id=0201.', true)
on conflict (owner_code) do update set
  owner_name = excluded.owner_name,
  atomy_member_id = excluded.atomy_member_id,
  notes = excluded.notes,
  is_active = true;

insert into public.products(id, sku, product_name, category, unit, default_barcode, is_active)
values
  ('9cf4ec5d-01b7-3f68-bc7a-53636f088480', 'AMPOULE', 'Ampoule', 'GudangKu Package Component', 'pcs', null, true),
  ('b78f7f95-1c30-3ef4-bb7c-e779665e3612', 'ATOMY-ABSOLUTE-AMPOULE', 'Atomy Absolute Ampoule', 'GudangKu Inventory', 'pcs', null, true),
  ('a9d506d8-9b40-3c2c-b3de-79f9f8ddfb64', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 'Atomy Absolute CellActive Ampoule', 'GudangKu Inventory', 'pcs', null, true),
  ('83c6afad-e18c-3347-bf64-f966b3df828f', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 'Atomy Absolute CellActive Skincare Set', 'GudangKu Inventory', 'pcs', null, true),
  ('d945cf18-556f-3219-8a3f-864dd759ac4b', 'ATOMY-ABSOLUTE-EYE-COMPLEX', 'Atomy Absolute Eye-complex', 'GudangKu Inventory', 'pcs', null, true),
  ('c921c439-caa4-354d-82ec-6ce8c69e4b0b', 'ATOMY-ABSOLUTE-LOTION', 'Atomy Absolute Lotion', 'GudangKu Inventory', 'pcs', null, true),
  ('5dc6376d-0086-383f-a61a-87d1026e74b9', 'ATOMY-ABSOLUTE-TONER', 'Atomy Absolute Toner', 'GudangKu Inventory', 'pcs', null, true),
  ('2d3dc290-bb23-3f5f-a23a-d0510ba0e0f7', 'ATOMY-AIDAM-CLEANSER', 'Atomy Aidam Cleanser', 'GudangKu Inventory', 'pcs', null, true),
  ('3b7d5a60-0a4f-311e-84ce-5f796a8132cd', 'ATOMY-BABY-LOTION', 'Atomy Baby Lotion', 'GudangKu Inventory', 'pcs', null, true),
  ('613a82bb-ccc1-34ac-9c01-e8bd7af76f71', 'ATOMY-BB-CREAM', 'Atomy BB Cream', 'GudangKu Inventory', 'pcs', null, true),
  ('43fced49-31fc-3c68-8169-dc18131cbafd', 'ATOMY-BODY-CLEANSER', 'Atomy Body Cleanser', 'GudangKu Inventory', 'pcs', null, true),
  ('6b14a002-e6bc-39e3-81d5-4fc88c53adbb', 'ATOMY-BODY-LOTION', 'Atomy Body Lotion', 'GudangKu Inventory', 'pcs', null, true),
  ('ba8dcbe1-cb8e-3155-8684-ae4e89923b0f', 'ATOMY-CAFE-ARABICA', 'Atomy Cafe Arabica', 'GudangKu Inventory', 'pcs', null, true),
  ('dde27e37-b2b2-31ad-8329-95a2430175aa', 'ATOMY-COLOR-FOOD-VITAMIN-C', 'Atomy Color Food Vitamin C', 'GudangKu Inventory', 'pcs', null, true),
  ('f9587c23-c94a-396b-92e8-2884a89764d1', 'ATOMY-DEEP-CLEANSER-150ML', 'Atomy Deep Cleanser 150ml', 'GudangKu Inventory', 'pcs', null, true),
  ('3d80667b-86b6-36f0-a654-c1a59bb0ba10', 'ATOMY-ETHEREAL-OIL-PATCH', 'Atomy Ethereal Oil Patch', 'GudangKu Inventory', 'pcs', null, true),
  ('fb15160a-0e67-36e7-b149-142985d09429', 'ATOMY-EVENING-CARE-4-SET', 'Atomy Evening Care 4 Set', 'GudangKu Inventory', 'pcs', null, true),
  ('cc11c011-afd4-32f5-9508-16053191b006', 'ATOMY-EVENING-CARE-FOAM-CLEANSER', 'Atomy Evening Care Foam Cleanser', 'GudangKu Inventory', 'pcs', null, true),
  ('63aae908-1f9c-3bbf-a82f-2178983db0a7', 'ATOMY-FINEZYME', 'Atomy Finezyme', 'GudangKu Inventory', 'pcs', null, true),
  ('4ede9ccb-cff2-3ab0-bd9d-e22eb6db4e45', 'ATOMY-FOAM-CLEANSER-150ML', 'Atomy Foam Cleanser 150ml', 'GudangKu Inventory', 'pcs', null, true),
  ('a26b1b3d-a0f3-31cf-b30b-095bc1a55bb6', 'ATOMY-HAIR-ESSENTIAL-OIL', 'Atomy Hair Essential Oil', 'GudangKu Inventory', 'pcs', null, true),
  ('89288675-1ff0-3ca4-b060-1fb7175dfc9d', 'ATOMY-HEALTHY-GLOW-BASE', 'Atomy Healthy Glow Base', 'GudangKu Inventory', 'pcs', null, true),
  ('4299a215-c6a3-347b-9e58-faa1cb507c0d', 'ATOMY-HEMOHIM', 'Atomy HemoHim', 'GudangKu Inventory', 'pcs', null, true),
  ('3496e8cc-2922-31dc-9d1d-47c7033b5902', 'ATOMY-HEMOHIM-4-SETS', 'Atomy HemoHim 4 Sets', 'GudangKu Inventory', 'pcs', null, true),
  ('05a04df5-cc28-333c-ad19-08b42e18e42d', 'ATOMY-HEMOHIM-SET-4', 'Atomy HemoHim Set 4', 'GudangKu Inventory', 'pcs', null, true),
  ('695028b4-9f5f-3a1a-bb11-db571be7cce0', 'ATOMY-HERBAL-HAIR-CONDITIONER', 'Atomy Herbal Hair Conditioner', 'GudangKu Inventory', 'pcs', null, true),
  ('f9030f81-29ad-3057-a333-bf017c09f150', 'ATOMY-HERBAL-HAIR-SHAMPOO', 'Atomy Herbal Hair Shampoo', 'GudangKu Inventory', 'pcs', null, true),
  ('b155b2d2-6b97-3c58-9230-e5cfd43d89f9', 'ATOMY-HERBAL-HAIR-TONIC', 'Atomy Herbal Hair Tonic', 'GudangKu Inventory', 'pcs', null, true),
  ('b52f31ed-956b-3974-bf85-d8156bbd5dd6', 'ATOMY-HONGSAMDAN-RED-GINSENG', 'Atomy Hongsamdan Red Ginseng', 'GudangKu Inventory', 'pcs', null, true),
  ('c41976d4-1504-3a0a-8ef7-58a4b43d3874', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 'Atomy Hydra Brightening Care Set', 'GudangKu Inventory', 'pcs', null, true),
  ('3c0cbd55-424c-39f8-98bb-2a045be45479', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 'Atomy Paket Berkah Ramadan A', 'GudangKu Inventory', 'pcs', null, true),
  ('171e7e39-0986-3f04-9bc2-382ae5115728', 'ATOMY-PAKET-BERKAH-RAMADAN-B', 'Atomy Paket Berkah Ramadan B', 'GudangKu Inventory', 'pcs', null, true),
  ('dd6d85d6-ceb6-395c-a9d1-e9350812070e', 'ATOMY-PAKET-BERKAH-RAMADAN-C', 'Atomy Paket Berkah Ramadan C', 'GudangKu Inventory', 'pcs', null, true),
  ('365a45f1-a99b-3483-8f2e-260ff310a1fe', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 'Atomy Paket Bingkisan Lebaran', 'GudangKu Inventory', 'pcs', null, true),
  ('7ebe11c6-3d8b-3eaf-aaa4-6e1b4090550a', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 'Atomy Paket Lebaran A (Health Care)', 'GudangKu Inventory', 'pcs', null, true),
  ('592ea648-fd11-3c4d-9dfc-15bfbcbef2c4', 'ATOMY-PAKET-RAMADHAN-CARE', 'Atomy Paket Ramadhan Care', 'GudangKu Inventory', 'pcs', null, true),
  ('c120d328-1e39-3082-80a3-60067f08a43f', 'ATOMY-PROBIOTICS-10', 'Atomy Probiotics 10+', 'GudangKu Inventory', 'pcs', null, true),
  ('65dd1536-54f3-3717-9a4b-779041cf3086', 'ATOMY-PROMO-RAMADHAN-1', 'Atomy Promo Ramadhan 1', 'GudangKu Inventory', 'pcs', null, true),
  ('d8786979-df12-3544-8e3a-b3c00b592c7d', 'ATOMY-PROMO-RAMADHAN-2', 'Atomy Promo Ramadhan 2', 'GudangKu Inventory', 'pcs', null, true),
  ('6386acc6-bb98-3367-8016-c6575c28f8fb', 'ATOMY-PROPOLIS-TOOTHPASTE-200G', 'Atomy Propolis Toothpaste 200g', 'GudangKu Inventory', 'pcs', null, true),
  ('954bda1b-739f-3313-9209-2def07001044', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 'Atomy Propolis Toothpaste 50g', 'GudangKu Inventory', 'pcs', null, true),
  ('d5949e02-b5a9-368e-a8bd-ae4896537591', 'ATOMY-PSYLLIUM-HUSK', 'Atomy Psyllium Husk', 'GudangKu Inventory', 'pcs', null, true),
  ('29c736f3-af7b-3a70-875f-b3332929f832', 'ATOMY-PU-ER-TEA', 'Atomy Pu''er Tea', 'GudangKu Inventory', 'pcs', null, true),
  ('1483de2f-e0a7-3d23-8252-831a031de4bc', 'ATOMY-PURE-SPIRULINA', 'Atomy Pure Spirulina', 'GudangKu Inventory', 'pcs', null, true),
  ('6fe923ab-799a-3839-9dbc-8ef99b19242b', 'ATOMY-SAENGMODAN-HAIR-TONIC', 'Atomy Saengmodan Hair Tonic', 'GudangKu Inventory', 'pcs', null, true),
  ('79130d23-8bf9-3908-82ad-43f77913cd3c', 'ATOMY-SLIM-BODY-SHAKE-2-0', 'Atomy Slim Body Shake 2.0', 'GudangKu Inventory', 'pcs', null, true),
  ('e9ce14a6-7582-3287-8ac9-8f2114771489', 'ATOMY-STAINLESS-STEEL-SCRUBBER', 'Atomy Stainless Steel Scrubber', 'GudangKu Inventory', 'pcs', null, true),
  ('85b02f80-525e-314a-a0b1-6f6dcd964cc2', 'ATOMY-SUNSCREEN-BEIGE', 'Atomy Sunscreen Beige', 'GudangKu Inventory', 'pcs', null, true),
  ('1f34d8ac-85a3-3835-b6f0-a80deffa8e7d', 'ATOMY-SUNSCREEN-WHITE', 'Atomy Sunscreen White', 'GudangKu Inventory', 'pcs', null, true),
  ('c55abc92-36f3-36ce-8b1a-52f828fe4c26', 'ATOMY-TOOTHBRUSH', 'Atomy Toothbrush', 'GudangKu Inventory', 'pcs', null, true),
  ('3e615270-b3c6-35d6-b94a-2aa5fa321a40', 'ATOMY-TOOTHPASTE-200G', 'Atomy Toothpaste 200g', 'GudangKu Inventory', 'pcs', null, true),
  ('2b8c8bfc-ce93-31dc-90a6-c116ff15e73a', 'ATOMY-TOOTHPASTE-50G', 'Atomy Toothpaste 50g', 'GudangKu Inventory', 'pcs', null, true),
  ('dad240f4-4562-3f51-8beb-0654cfa89e19', 'ATOMY-TRAVEL-KIT', 'Atomy Travel Kit', 'GudangKu Inventory', 'pcs', null, true),
  ('ed32935a-e193-32a1-ae75-c0f58ba3491f', 'ATOMY-VITAMIN-B-COMPLEX', 'Atomy Vitamin B-Complex', 'GudangKu Inventory', 'pcs', null, true),
  ('2efa5794-8a79-3676-acf7-daf9a53bfb1c', 'COLOR-FOOD-VITAMIN-C', 'Color Food Vitamin C', 'GudangKu Package Component', 'pcs', null, true),
  ('8514d3ba-42f3-3b9a-b823-dda6d840f09a', 'DEEP-CLEANSER', 'Deep Cleanser', 'GudangKu Package Component', 'pcs', null, true),
  ('e87951f8-e1c5-30eb-a985-dcd5cf76fd18', 'DERMA-REAL-CICA-SERIES-COMPONENTS', 'Derma Real Cica Series Components', 'GudangKu Package Component', 'set', null, true),
  ('d2cf9cb4-61f7-38c8-9c02-caba633c3ee8', 'EASY-CLEAN-WATER-FILTER-PITCHER', 'Easy Clean Water Filter Pitcher', 'GudangKu Package Component', 'pcs', null, true),
  ('1133e8d5-b0ce-3214-9cd3-749f5f7c8191', 'EYE-COMPLEX', 'Eye Complex', 'GudangKu Package Component', 'pcs', null, true),
  ('0eb93d91-8453-38ea-8fdf-c3178c93ee4f', 'EYE-HEALTH-LUAXANTHIN', 'Eye Health Luaxanthin', 'GudangKu Package Component', 'pcs', null, true),
  ('3f1a90e3-f8bf-324c-9315-0ca91075bd4a', 'FINEZYME', 'Finezyme', 'GudangKu Package Component', 'pcs', null, true),
  ('b427fefd-9b6c-34b3-8d32-3a34d3cf3ac3', 'FOAM-CLEANSER', 'Foam Cleanser', 'GudangKu Package Component', 'pcs', null, true),
  ('1a327ead-7f17-39f3-8831-d3a24e523f48', 'HAIRESSENTIAL-OIL', 'Hairessential Oil', 'GudangKu Package Component', 'pcs', null, true),
  ('a9cbe0ae-4d7d-3c18-a2c3-021c944ce6b2', 'HEMOHIM', 'HemoHIM', 'GudangKu Package Component', 'set', null, true),
  ('6dd7c6b2-1e0e-3197-b726-0e2fc7d0661c', 'HERBAL-HAIR-CONDITIONER', 'Herbal Hair Conditioner', 'GudangKu Package Component', 'pcs', null, true),
  ('b52c5f22-4c62-3016-9895-ca76257442d8', 'HERBAL-HAIR-SHAMPOO', 'Herbal Hair Shampoo', 'GudangKu Package Component', 'pcs', null, true),
  ('abebe7ad-ef9e-35d2-a463-7ab813a1c0f7', 'HONGSAMDAN', 'Hongsamdan', 'GudangKu Package Component', 'pcs', null, true),
  ('c85fa9ce-10f6-3aac-be65-bf487148d5ae', 'HYDRA-BRIGHTENING-CAPSULE-ESSENCE', 'Hydra Brightening Capsule Essence', 'GudangKu Package Component', 'pcs', null, true),
  ('eedd8f7e-9b4c-301a-be25-809ab9fc7d5e', 'HYDRA-BRIGHTENING-CREAM', 'Hydra Brightening Cream', 'GudangKu Package Component', 'pcs', null, true),
  ('3efa8434-b9fd-3bdb-a9db-c4502ff945af', 'LOTION', 'Lotion', 'GudangKu Package Component', 'pcs', null, true),
  ('814f56b0-8871-35a2-9b59-3647aa7740c0', 'NUTRITION-CREAM', 'Nutrition Cream', 'GudangKu Package Component', 'pcs', null, true),
  ('3d807aab-87ab-36d8-9192-951a8abd33ca', 'PEEL-OFF-MASK', 'Peel-Off Mask', 'GudangKu Package Component', 'pcs', null, true),
  ('f2795335-d72d-33e0-9db9-f521d3e4bdbe', 'PEELING-GEL', 'Peeling Gel', 'GudangKu Package Component', 'pcs', null, true),
  ('a14463d5-72fe-3dea-8f31-58e92c4c10a0', 'PSYLLIUM-HUSK', 'Psyllium Husk', 'GudangKu Package Component', 'pcs', null, true),
  ('a950c567-1c75-305d-9494-af4213d55aad', 'PUER-TEA', 'Puer Tea', 'GudangKu Package Component', 'pcs', null, true),
  ('56465612-e2da-39f6-a9f3-9d753bc889c0', 'SAENGMODAN-HAIR-TONIC', 'Saengmodan Hair Tonic', 'GudangKu Package Component', 'pcs', null, true),
  ('e42d4b89-d517-3034-9c76-2a913b2771be', 'SERUM', 'Serum', 'GudangKu Package Component', 'pcs', null, true),
  ('941773ee-c452-3b07-8ca3-7f1e5ce4a2d2', 'SUNSCREEN-BEIGE', 'Sunscreen Beige', 'GudangKu Package Component', 'pcs', null, true),
  ('872db359-cd1d-380c-af08-4ede7d914092', 'SUNSCREEN-WHITE', 'Sunscreen White', 'GudangKu Package Component', 'pcs', null, true),
  ('ec9973e3-54f2-3d25-931f-be47700d1317', 'SYNERGY-AMPOULE', 'Synergy Ampoule', 'GudangKu Package Component', 'set', null, true),
  ('56aaa217-c525-313c-9b86-0097028b9a4f', 'TONER', 'Toner', 'GudangKu Package Component', 'pcs', null, true),
  ('5ca6808d-221f-3235-8be1-9063d0f0fb0d', 'TOOTHBRUSH', 'Toothbrush', 'GudangKu Package Component', 'pcs', null, true),
  ('2523e246-8e81-3d9d-9915-ae83792813e3', 'TOOTHPASTE', 'Toothpaste', 'GudangKu Package Component', 'pcs', null, true),
  ('9e15f2b1-b351-3abc-a786-cfbe544c4daf', 'TOOTHPASTE-TOOTHBRUSH', 'Toothpaste + Toothbrush', 'GudangKu Package Component', 'set', null, true),
  ('b58305a0-c912-32c2-8aa4-b43e96703fce', 'TOOTHPASTE-SET', 'Toothpaste Set', 'GudangKu Package Component', 'pcs', null, true),
  ('ae55d6d5-1b2a-3eea-9352-121e3a4152e6', 'TRAVEL-KIT-COMPONENTS', 'Travel Kit Components', 'GudangKu Package Component', 'set', null, true)
on conflict (sku) do update set
  product_name = excluded.product_name,
  category = excluded.category,
  unit = excluded.unit,
  is_active = true;

insert into public.package_templates(id, package_code, package_name, description, is_active)
values
  ('84cf1523-655c-3d2b-a3dd-ca15e6d7edaf', 'GKP-001', 'HemoHIM 1 Set', 'Import GudangKu paket. no=1.', true),
  ('5f9a0eda-6109-385f-a167-bcf3204ad313', 'GKP-002', 'HemoHIM 4 Set', 'Import GudangKu paket. no=2.', true),
  ('44a0b14d-fdba-3a54-b0ea-cbf7c0cd5e82', 'GKP-003', 'PV Up HemoHIM 4 Sets', 'Import GudangKu paket. no=3.', true),
  ('e8bc2319-8c98-3a6e-b15a-770fc41dd5cb', 'GKP-004', 'HemoHIM 4+1 Promo', 'Import GudangKu paket. no=4.', true),
  ('03eb29ce-62d4-3d81-8b07-a7e4c4308430', 'GKP-005', 'Hydra Brightening Care Set', 'Import GudangKu paket. no=5.', true),
  ('b34306db-8247-314d-b140-a16306c26b73', 'GKP-006', 'Evening Care 4 Set', 'Import GudangKu paket. no=6.', true),
  ('a93e8053-fd87-3e1c-875c-f277d2875681', 'GKP-007', 'Absolute CellActive Skincare Set', 'Import GudangKu paket. no=7.', true),
  ('e9523433-571d-3420-a5eb-519bd5fc99dd', 'GKP-008', 'Derma Real Cica Set', 'Import GudangKu paket. no=8.', true),
  ('c1256435-0768-3484-ad58-38d9697af0c7', 'GKP-009', 'Synergy Ampoule Set', 'Import GudangKu paket. no=9.', true),
  ('6d077af1-51b3-345e-b3fa-70e73c7a6579', 'GKP-010', 'Cleansing Travel Kit', 'Import GudangKu paket. no=10.', true),
  ('f90c3f63-95f8-3c63-9e89-6f16e1bb68d1', 'GKP-011', 'Oral Care System Set', 'Import GudangKu paket. no=11.', true),
  ('21f045ae-970a-3998-930b-74395444e669', 'GKP-012', 'Toothpaste Set', 'Import GudangKu paket. no=12.', true),
  ('ec22e062-7de2-35a6-bb95-190a91b35294', 'GKP-013', 'Toothbrush Set', 'Import GudangKu paket. no=13.', true),
  ('b98c7f3d-e293-309d-8e64-950296637cb6', 'GKP-014', 'Promo Ramadan 2026 Paket A', 'Import GudangKu paket. no=14.', true),
  ('2cb1c9ec-6bfc-32b5-83e2-c00ba2f03b85', 'GKP-015', 'Promo Ramadan 2026 Paket B', 'Import GudangKu paket. no=15.', true),
  ('a2df5edb-ec6c-384e-8ec4-3000cbacc8c4', 'GKP-016', 'Promo Ramadan 2026 Paket C', 'Import GudangKu paket. no=16.', true),
  ('dccb4692-75bf-302d-9e7b-8dc12129bce6', 'GKP-017', 'Promo Ramadan 2026 Paket D', 'Import GudangKu paket. no=17.', true),
  ('4130a35a-f6cb-3ecd-a601-24621727804a', 'GKP-018', 'Promo Ramadan 2026 Paket E', 'Import GudangKu paket. no=18.', true),
  ('a81f2f5f-7b4f-3e0e-9fe2-429f2ffe752f', 'GKP-019', 'Promotion PV Up Januari 2026', 'Import GudangKu paket. no=19.', true),
  ('15bbe195-783b-3807-8129-e0f89113d9bb', 'GKP-020', 'Promo PV Up Mei 2025', 'Import GudangKu paket. no=20.', true),
  ('d9e90f5d-e62f-320f-9d5c-f02a4a380d92', 'GKP-021', 'HemoHIM Spesial Promo 4 Gratis 1 April 2025', 'Import GudangKu paket. no=21.', true),
  ('c5f54ba0-bd29-3527-b893-f576d027017d', 'GKP-022', 'Promotion PV Up November 2025', 'Import GudangKu paket. no=22.', true)
on conflict (package_code) do update set
  package_name = excluded.package_name,
  description = excluded.description,
  is_active = excluded.is_active;

with source_package_items(id, package_code, sku, qty_per_package) as (
  values
  ('e0c019c3-1e27-3f2a-adec-643be5360e60', 'GKP-001', 'HEMOHIM', 1),
  ('fadbd0d2-9f41-3d7c-93cd-30cdbd7e780e', 'GKP-002', 'HEMOHIM', 4),
  ('5bdd0e3f-f1a6-313b-8a04-9b3312ff1e1e', 'GKP-003', 'HEMOHIM', 4),
  ('08c1276f-282b-3446-a8c6-0b1953f36772', 'GKP-004', 'HEMOHIM', 5),
  ('589e3840-413f-37e1-b69b-107505c2ba9d', 'GKP-005', 'HYDRA-BRIGHTENING-CAPSULE-ESSENCE', 1),
  ('47bf3431-b2d0-3b35-8d54-37a55fb702c1', 'GKP-005', 'HYDRA-BRIGHTENING-CREAM', 1),
  ('5082eb55-e6d4-3cab-bc92-cda48e3bafd5', 'GKP-006', 'DEEP-CLEANSER', 1),
  ('18b30595-94d9-3f7e-8df3-f325e5fc24c2', 'GKP-006', 'FOAM-CLEANSER', 1),
  ('96894d38-f05e-3b6e-afa2-11f5f82513b2', 'GKP-006', 'PEEL-OFF-MASK', 1),
  ('8755d3ea-372f-350f-97eb-d564a9a72729', 'GKP-006', 'PEELING-GEL', 1),
  ('f99b1829-ba1b-3d64-959c-7a4698ccb06d', 'GKP-007', 'AMPOULE', 1),
  ('78cd6089-6305-3695-b89c-4ab4054bb6ba', 'GKP-007', 'EYE-COMPLEX', 1),
  ('b4402ea3-ed18-30bf-af24-09e27d23711d', 'GKP-007', 'LOTION', 1),
  ('1fd6b539-bef8-3589-8fea-abc6030431f8', 'GKP-007', 'NUTRITION-CREAM', 1),
  ('e30edcef-63f7-3ce3-b8e2-56138135dcfa', 'GKP-007', 'SERUM', 1),
  ('e4cdae43-149e-3288-b089-f00102250698', 'GKP-007', 'TONER', 1),
  ('25330671-aadf-396a-9a2c-6ad489e431e3', 'GKP-008', 'DERMA-REAL-CICA-SERIES-COMPONENTS', 1),
  ('cbdb0b97-f41f-36a9-bd10-afe070c93a2c', 'GKP-009', 'SYNERGY-AMPOULE', 1),
  ('f7e04ed8-4725-37bf-a440-5e14a465e7e9', 'GKP-010', 'TRAVEL-KIT-COMPONENTS', 1),
  ('f7271a1f-9f9c-3f6b-b612-bbef6a9438d2', 'GKP-011', 'TOOTHPASTE-TOOTHBRUSH', 1),
  ('6ce45a8b-534b-3bdf-ad7e-4a9fdd2ae2ee', 'GKP-012', 'TOOTHPASTE', 5),
  ('2a596a5b-7b35-3885-a75f-4a635b99923a', 'GKP-013', 'TOOTHBRUSH', 8),
  ('74b692cf-1686-3c3a-840c-b20193332a24', 'GKP-014', 'COLOR-FOOD-VITAMIN-C', 2),
  ('b9cb5229-57a7-3cb5-a7c1-61ffe0d039ca', 'GKP-014', 'FINEZYME', 2),
  ('4b7d9f42-a754-3dab-8da0-c8618fd935b3', 'GKP-014', 'HEMOHIM', 1),
  ('0d818275-9420-3069-91d0-b2e8d16928a7', 'GKP-014', 'HONGSAMDAN', 2),
  ('fac34280-198a-34ad-a5cd-9a1ef43b561a', 'GKP-015', 'SUNSCREEN-BEIGE', 2),
  ('549be214-120e-38eb-afa3-058543a5f924', 'GKP-015', 'SUNSCREEN-WHITE', 2),
  ('44fc1b41-9d25-3b54-b0f7-d6b8d03d0e7e', 'GKP-015', 'TOOTHBRUSH', 2),
  ('6a6e44d4-cc3c-3783-822c-d48ab45dbd54', 'GKP-015', 'TOOTHPASTE-SET', 2),
  ('f51f5ef3-0316-3d77-945e-b0449e2f5500', 'GKP-016', 'HAIRESSENTIAL-OIL', 2),
  ('7a112331-8c15-33cf-b31e-53e8fa1aed99', 'GKP-016', 'HERBAL-HAIR-CONDITIONER', 2),
  ('5ff47cd4-af48-3072-815a-d8883de7334c', 'GKP-016', 'HERBAL-HAIR-SHAMPOO', 2),
  ('076d41e3-f049-3739-99e5-bd507400cc75', 'GKP-016', 'SAENGMODAN-HAIR-TONIC', 2),
  ('c1ebd4c7-619e-3c25-87ea-31bf33ac62db', 'GKP-017', 'PSYLLIUM-HUSK', 2),
  ('d049e6fc-f15e-3a9f-b2cc-fee3413a0016', 'GKP-018', 'EASY-CLEAN-WATER-FILTER-PITCHER', 2),
  ('9d68fe1c-bf65-3ca9-aa42-c59825d718d7', 'GKP-019', 'HEMOHIM', 4),
  ('dff735ef-ddf6-3944-8d0d-faf601c8b1bc', 'GKP-020', 'HEMOHIM', 4),
  ('25151f7e-40ae-33f2-8065-d29bcc9ecf44', 'GKP-021', 'HEMOHIM', 5),
  ('f86a9634-9b05-398f-8ebc-0bfba78e0c5f', 'GKP-022', 'EYE-HEALTH-LUAXANTHIN', 1),
  ('6024bc37-3419-34f0-9a32-8a49bcbd6bab', 'GKP-022', 'PUER-TEA', 2)
)
insert into public.package_template_items(id, package_id, product_id, qty_per_package)
select
  source_package_items.id::uuid,
  package_templates.id,
  products.id,
  source_package_items.qty_per_package::numeric
from source_package_items
join public.package_templates on package_templates.package_code = source_package_items.package_code
join public.products on products.sku = source_package_items.sku
on conflict (package_id, product_id) do update set
  qty_per_package = excluded.qty_per_package;

with source_boxes(id, id_box, pemilik_id_box, box_name, owner_code, location_code, created_at, updated_at, notes) as (
  values
  ('379e2cd3-6528-3340-8095-ac9dec94b0a6', 'GK-KARDUS-000001', 'GK-7713-E4F48B-GK-KARDUS-000001', '4400-7713-SAMUEL ANITA SAMUEL MALUMUS', 'GK-7713-E4F48B', 'GUDANG ANITA', '2026-04-29 07:43:00+07', '2026-04-29 07:43:00+07', 'Import GudangKu kardus; client_id=1; label=4400-7713-SAMUEL ANITA SAMUEL MALUMUS; nomor_pesanan=4400; nomor_id=7713; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('1d1b022e-f17c-35ca-ba34-1fefeed8f51e', 'GK-KARDUS-000002', 'GK-7886-A34010-GK-KARDUS-000002', '9000-7886-YOGA ANITA YOGA BAGUS', 'GK-7886-A34010', 'GUDANG ANITA', '2026-04-29 07:45:00+07', '2026-04-29 07:45:00+07', 'Import GudangKu kardus; client_id=2; label=9000-7886-YOGA ANITA YOGA BAGUS; nomor_pesanan=9000; nomor_id=7886; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('67bdbeba-417b-35ce-ba30-a47ddddf3ed1', 'GK-KARDUS-000007', 'GK-7426-0A142D-GK-KARDUS-000007', '8800-7426-ATHI TEAM RINA ATHI BASTIANA MANIA WASI', 'GK-7426-0A142D', 'GUDANG RINA', '2026-04-29 07:50:00+07', '2026-04-29 07:50:00+07', 'Import GudangKu kardus; client_id=7; label=8800-7426-ATHI TEAM RINA ATHI BASTIANA MANIA WASI; nomor_pesanan=8800; nomor_id=7426; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('a92de8c3-0335-315f-a60e-a84823ff1c8c', 'GK-KARDUS-000009', 'GK-9940-261550-GK-KARDUS-000009', '3000-9940-SURYANI ARABIS TIKOMAH', 'GK-9940-261550', 'GUDANG SURYANI', '2026-04-29 07:52:00+07', '2026-04-29 07:52:00+07', 'Import GudangKu kardus; client_id=9; label=3000-9940-SURYANI ARABIS TIKOMAH; nomor_pesanan=3000; nomor_id=9940; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('0486703c-740f-372a-b474-78d15d8b747d', 'GK-KARDUS-000011', 'GK-7916-B05F0F-GK-KARDUS-000011', '2500-7916-ALVIN ANITA ALVIN', 'GK-7916-B05F0F', 'GUDANG ANITA', '2026-04-29 07:55:00+07', '2026-04-29 07:55:00+07', 'Import GudangKu kardus; client_id=11; label=2500-7916-ALVIN ANITA ALVIN; nomor_pesanan=2500; nomor_id=7916; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('d9a9ef34-ee26-3343-9a52-3b7654cae45c', 'GK-KARDUS-000012', 'GK-0028-1263DF-GK-KARDUS-000012', '0400-0028-SURYANI ARA NOVAL PUSPITA SARI', 'GK-0028-1263DF', 'GUDANG SURYANI', '2026-04-29 07:56:00+07', '2026-04-29 07:56:00+07', 'Import GudangKu kardus; client_id=12; label=0400-0028-SURYANI ARA NOVAL PUSPITA SARI; nomor_pesanan=0400; nomor_id=0028; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('09034aa6-d666-3fd9-a9b6-57c71f460b43', 'GK-KARDUS-000013', 'GK-9784-8CF0AC-GK-KARDUS-000013', '6900-9784-TJONG LI MI TJ AHJA LIAY', 'GK-9784-8CF0AC', 'GUDANG AMI', '2026-04-29 07:58:00+07', '2026-04-29 07:58:00+07', 'Import GudangKu kardus; client_id=13; label=6900-9784-TJONG LI MI TJ AHJA LIAY; nomor_pesanan=6900; nomor_id=9784; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('adfedf3d-05f4-3173-b936-ca2939a85810', 'GK-KARDUS-000014', 'GK-7802-DD41DB-GK-KARDUS-000014', '9200-7802-DINDA ANITA DINDA SIMAUNG', 'GK-7802-DD41DB', 'GUDANG ANITA', '2026-04-29 07:59:00+07', '2026-04-29 07:59:00+07', 'Import GudangKu kardus; client_id=14; label=9200-7802-DINDA ANITA DINDA SIMAUNG; nomor_pesanan=9200; nomor_id=7802; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('1343fcb5-1900-3175-9f9e-0ca8e1edf127', 'GK-KARDUS-000016', 'GK-9197-438819-GK-KARDUS-000016', '3600-9197-FERRY ANITA FERRY SANTOSO', 'GK-9197-438819', 'GUDANG ANITA', '2026-04-29 08:05:00+07', '2026-04-29 08:05:00+07', 'Import GudangKu kardus; client_id=16; label=3600-9197-FERRY ANITA FERRY SANTOSO; nomor_pesanan=3600; nomor_id=9197; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('e3923fbd-7936-30be-b714-00aa06fba3e0', 'GK-KARDUS-000017', 'GK-7770-F5621F-GK-KARDUS-000017', '1900-7770-INTAN ANITA INTAN PERMATA', 'GK-7770-F5621F', 'GUDANG ANITA', '2026-04-29 08:06:00+07', '2026-04-29 08:06:00+07', 'Import GudangKu kardus; client_id=17; label=1900-7770-INTAN ANITA INTAN PERMATA; nomor_pesanan=1900; nomor_id=7770; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('4701c603-e6c4-3f19-a366-61bc212c204a', 'GK-KARDUS-000020', 'GK-1376-8E0DB1-GK-KARDUS-000020', '3700-1376-NENG KANAN T PAPUA SUNARSIH', 'GK-1376-8E0DB1', 'GUDANG NENG', '2026-04-29 08:10:00+07', '2026-04-29 08:10:00+07', 'Import GudangKu kardus; client_id=20; label=3700-1376-NENG KANAN T PAPUA SUNARSIH; nomor_pesanan=3700; nomor_id=1376; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('9912f8df-ee9c-39ed-ad4d-e5b066eade64', 'GK-KARDUS-000021', 'GK-5034-43C1DD-GK-KARDUS-000021', '4400-5034-SURYANI ARABA C HMAD TANTOWI', 'GK-5034-43C1DD', 'GUDANG SURYANI', '2026-04-29 08:11:00+07', '2026-04-29 08:11:00+07', 'Import GudangKu kardus; client_id=21; label=4400-5034-SURYANI ARABA C HMAD TANTOWI; nomor_pesanan=4400; nomor_id=5034; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('a6fc9fb4-ec15-3d94-a22f-d92192f03740', 'GK-KARDUS-000023', 'GK-7455-53E31A-GK-KARDUS-000023', '2800-7455-DENNY ANITA DENNY SETIAWAN', 'GK-7455-53E31A', 'GUDANG ANITA', '2026-04-29 08:14:00+07', '2026-04-29 08:14:00+07', 'Import GudangKu kardus; client_id=23; label=2800-7455-DENNY ANITA DENNY SETIAWAN; nomor_pesanan=2800; nomor_id=7455; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('850a746b-3e14-3fb6-8507-7cbbc486eaa6', 'GK-KARDUS-000026', 'GK-1272-7ABC75-GK-KARDUS-000026', '8700-1272-NIRMA TEAM RINA NIRMA', 'GK-1272-7ABC75', 'GUDANG RINA', '2026-04-29 08:18:00+07', '2026-04-29 08:18:00+07', 'Import GudangKu kardus; client_id=26; label=8700-1272-NIRMA TEAM RINA NIRMA; nomor_pesanan=8700; nomor_id=1272; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('aab78cd7-9343-31a1-a1dc-66f57f6de776', 'GK-KARDUS-000028', 'GK-0190-04EBA9-GK-KARDUS-000028', '3300-0190-TJONG LI MI NABILA', 'GK-0190-04EBA9', 'GUDANG AMI', '2026-04-29 08:21:00+07', '2026-04-29 08:21:00+07', 'Import GudangKu kardus; client_id=28; label=3300-0190-TJONG LI MI NABILA; nomor_pesanan=3300; nomor_id=0190; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('73352360-3dd1-3086-a5be-ed32e71455ef', 'GK-KARDUS-000029', 'GK-6127-970BA2-GK-KARDUS-000029', '1400-6127-ANITA BINTANG SITI AULIA SITI AULIA', 'GK-6127-970BA2', 'GUDANG ANITA', '2026-04-29 08:22:00+07', '2026-04-29 08:22:00+07', 'Import GudangKu kardus; client_id=29; label=1400-6127-ANITA BINTANG SITI AULIA SITI AULIA; nomor_pesanan=1400; nomor_id=6127; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('5dc58742-7025-345a-8a28-5dd6c7c1e476', 'GK-KARDUS-000032', 'GK-0080-B7F529-GK-KARDUS-000032', '6500-0080-TJONG LI MI ASEP', 'GK-0080-B7F529', 'GUDANG AMI', '2026-04-29 08:25:00+07', '2026-04-29 08:25:00+07', 'Import GudangKu kardus; client_id=32; label=6500-0080-TJONG LI MI ASEP; nomor_pesanan=6500; nomor_id=0080; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f281a433-06a2-3f54-8ba1-e51ee4461d16', 'GK-KARDUS-000033', 'GK-9813-9B5734-GK-KARDUS-000033', '3600-9813-SURYANI ARAB SILVIA', 'GK-9813-9B5734', 'GUDANG SURYANI', '2026-04-29 08:26:00+07', '2026-04-29 08:26:00+07', 'Import GudangKu kardus; client_id=33; label=3600-9813-SURYANI ARAB SILVIA; nomor_pesanan=3600; nomor_id=9813; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('69000c22-a7d2-32f1-905f-cbfd7fdc2fd4', 'GK-KARDUS-000035', 'GK-9736-337511-GK-KARDUS-000035', '7300-9736-TJONG LI MI HERLAN PERLANA', 'GK-9736-337511', 'GUDANG AMI', '2026-04-29 08:29:00+07', '2026-04-29 08:29:00+07', 'Import GudangKu kardus; client_id=35; label=7300-9736-TJONG LI MI HERLAN PERLANA; nomor_pesanan=7300; nomor_id=9736; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('d4074ae6-cb5e-333e-8d41-0c285a4acd60', 'GK-KARDUS-000036', 'GK-0082-9B1E23-GK-KARDUS-000036', '6600-0082-TJONG LI MI MICAHEL PRATAMA SOELI ES TYO', 'GK-0082-9B1E23', 'GUDANG AMI', '2026-04-29 08:31:00+07', '2026-04-29 08:31:00+07', 'Import GudangKu kardus; client_id=36; label=6600-0082-TJONG LI MI MICAHEL PRATAMA SOELI ES TYO; nomor_pesanan=6600; nomor_id=0082; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('dfd92feb-5414-362f-88c5-c8ba77af3932', 'GK-KARDUS-000040', 'GK-9723-902F19-GK-KARDUS-000040', '5500-9723-NENG KANAN T PAPUA SITI KHUSNUL', 'GK-9723-902F19', 'GUDANG NENG', '2026-04-29 08:35:00+07', '2026-04-29 08:35:00+07', 'Import GudangKu kardus; client_id=40; label=5500-9723-NENG KANAN T PAPUA SITI KHUSNUL; nomor_pesanan=5500; nomor_id=9723; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ef7f75ac-e294-3d9b-9267-25e93678ba23', 'GK-KARDUS-000043', 'GK-1382-148E5E-GK-KARDUS-000043', '6300-1382-DEVIN MULYONO T WIFA DEVIN MULYONO', 'GK-1382-148E5E', 'GUDANG WIFA', '2026-04-29 08:49:00+07', '2026-04-29 08:49:00+07', 'Import GudangKu kardus; client_id=43; label=6300-1382-DEVIN MULYONO T WIFA DEVIN MULYONO; nomor_pesanan=6300; nomor_id=1382; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('912e98fb-14c5-3bd3-ab1a-6670613fc03d', 'GK-KARDUS-000046', 'GK-9766-54FA8A-GK-KARDUS-000046', '9900-9766-TJONG LI MI NGATIAH', 'GK-9766-54FA8A', 'GUDANG AMI', '2026-04-29 08:51:00+07', '2026-04-29 08:51:00+07', 'Import GudangKu kardus; client_id=46; label=9900-9766-TJONG LI MI NGATIAH; nomor_pesanan=9900; nomor_id=9766; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('fb15a3b8-8610-353c-9b22-190fa5e372f0', 'GK-KARDUS-000053', 'GK-0085-50E873-GK-KARDUS-000053', '7000-0085-TJONG LI MI KIKI RUHMAN', 'GK-0085-50E873', 'GUDANG AMI', '2026-04-29 08:57:00+07', '2026-04-29 08:57:00+07', 'Import GudangKu kardus; client_id=53; label=7000-0085-TJONG LI MI KIKI RUHMAN; nomor_pesanan=7000; nomor_id=0085; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('07f0cbc7-7915-353d-bdeb-e80d27fcb223', 'GK-KARDUS-000056', 'GK-9742-5FE752-GK-KARDUS-000056', '9300-9742-TJONG LI MI KRIS PINUS KAPITAN TENA NIRON', 'GK-9742-5FE752', 'GUDANG TJONG LI MI', '2026-04-29 08:58:00+07', '2026-04-29 08:58:00+07', 'Import GudangKu kardus; client_id=56; label=9300-9742-TJONG LI MI KRIS PINUS KAPITAN TENA NIRON; nomor_pesanan=9300; nomor_id=9742; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f94b79d9-b08b-3086-8402-8a148edc9d5f', 'GK-KARDUS-000059', 'GK-0170-03DBCF-GK-KARDUS-000059', '1600-0170-TJONG LI MI MANDIKA', 'GK-0170-03DBCF', 'GUDANG AMI', '2026-04-29 09:02:00+07', '2026-04-29 09:02:00+07', 'Import GudangKu kardus; client_id=59; label=1600-0170-TJONG LI MI MANDIKA; nomor_pesanan=1600; nomor_id=0170; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('97b0a3ed-30a3-34e5-a229-998cda925025', 'GK-KARDUS-000060', 'GK-6819-F8058D-GK-KARDUS-000060', '1000-6819-AJENG AJENG SUITA', 'GK-6819-F8058D', 'GUDANG AJENG', '2026-04-29 09:02:00+07', '2026-04-29 09:02:00+07', 'Import GudangKu kardus; client_id=60; label=1000-6819-AJENG AJENG SUITA; nomor_pesanan=1000; nomor_id=6819; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('a6bfac94-c5de-303e-add2-2bf4b7cabf00', 'GK-KARDUS-000062', 'GK-9809-899033-GK-KARDUS-000062', '9600-9809-TJONG LI MI ANITA KELOP', 'GK-9809-899033', 'GUDANG AMI', '2026-04-29 09:04:00+07', '2026-04-29 09:04:00+07', 'Import GudangKu kardus; client_id=62; label=9600-9809-TJONG LI MI ANITA KELOP; nomor_pesanan=9600; nomor_id=9809; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('cf9d9c85-1e1f-3a10-a252-a501d7b0b086', 'GK-KARDUS-000064', 'GK-4819-544857-GK-KARDUS-000064', '2800-4819-SURYANI ARAB RINI YASLIANA SITOHAMG', 'GK-4819-544857', 'GUDANG SURYANI', '2026-04-29 09:06:00+07', '2026-04-29 09:06:00+07', 'Import GudangKu kardus; client_id=64; label=2800-4819-SURYANI ARAB RINI YASLIANA SITOHAMG; nomor_pesanan=2800; nomor_id=4819; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('b974952c-0d42-3288-a448-364f988a49b5', 'GK-KARDUS-000065', 'GK-7926-DCCEFB-GK-KARDUS-000065', '5600-7926-SUMANTO ANITA SUMANTO HALIM', 'GK-7926-DCCEFB', 'GUDANG ANITA', '2026-04-29 09:06:00+07', '2026-04-29 09:06:00+07', 'Import GudangKu kardus; client_id=65; label=5600-7926-SUMANTO ANITA SUMANTO HALIM; nomor_pesanan=5600; nomor_id=7926; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('1305cfe6-7d63-3af7-8de3-300b72ed6e50', 'GK-KARDUS-000067', 'GK-0291-684578-GK-KARDUS-000067', '5700-0291-TJONG LI MI NANDA BERMAHTA', 'GK-0291-684578', 'GUDANG AMI', '2026-04-29 09:10:00+07', '2026-04-29 09:10:00+07', 'Import GudangKu kardus; client_id=67; label=5700-0291-TJONG LI MI NANDA BERMAHTA; nomor_pesanan=5700; nomor_id=0291; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('7508016c-045c-39bc-98f8-5188aeb217e0', 'GK-KARDUS-000068', 'GK-0395-D3A1E9-GK-KARDUS-000068', '5900-0395-ESRA TEAM RINA ESRA RENDEN', 'GK-0395-D3A1E9', 'GUDANG RINA', '2026-04-29 09:10:00+07', '2026-04-29 09:10:00+07', 'Import GudangKu kardus; client_id=68; label=5900-0395-ESRA TEAM RINA ESRA RENDEN; nomor_pesanan=5900; nomor_id=0395; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('c5b3d5ba-e297-345e-823c-de2a1b344836', 'GK-KARDUS-000070', 'GK-9808-91FA6B-GK-KARDUS-000070', '9100-9808-TJONG LI MI AGUS SEPTIAN', 'GK-9808-91FA6B', 'GUDANG AMI', '2026-04-29 09:11:00+07', '2026-04-29 09:11:00+07', 'Import GudangKu kardus; client_id=70; label=9100-9808-TJONG LI MI AGUS SEPTIAN; nomor_pesanan=9100; nomor_id=9808; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('8489b756-6011-390b-a913-27ad2bb46d7e', 'GK-KARDUS-000072', 'GK-0290-25E319-GK-KARDUS-000072', '3900-0290-TJONG LI MI LALA KIKI', 'GK-0290-25E319', 'GUDANG AMI', '2026-04-29 09:13:00+07', '2026-04-29 09:13:00+07', 'Import GudangKu kardus; client_id=72; label=3900-0290-TJONG LI MI LALA KIKI; nomor_pesanan=3900; nomor_id=0290; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('4119d67b-3973-37a2-a290-27ffba28a351', 'GK-KARDUS-000073', 'GK-9884-466A96-GK-KARDUS-000073', '8000-9884-TJONG LI MI DINDA PUTRI', 'GK-9884-466A96', 'GUDANG AMI', '2026-04-29 09:14:00+07', '2026-04-29 09:14:00+07', 'Import GudangKu kardus; client_id=73; label=8000-9884-TJONG LI MI DINDA PUTRI; nomor_pesanan=8000; nomor_id=9884; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('2096f77f-36de-3d85-ac35-f8680d36946e', 'GK-KARDUS-000077', 'GK-6219-AD2911-GK-KARDUS-000077', '8000-6219-JANSEN HUTAPEA T MAWARNI JANSEN HUTAPEA', 'GK-6219-AD2911', 'GUDANG SELVI', '2026-04-29 09:17:00+07', '2026-04-29 09:17:00+07', 'Import GudangKu kardus; client_id=77; label=8000-6219-JANSEN HUTAPEA T MAWARNI JANSEN HUTAPEA; nomor_pesanan=8000; nomor_id=6219; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('46dd5d0d-bc53-3505-8fd5-2303941ab418', 'GK-KARDUS-000078', 'GK-9729-439989-GK-KARDUS-000078', '8000-9729-TJONG LI MI LALITA AGUSTIN', 'GK-9729-439989', 'GUDNAG AMI', '2026-04-29 09:18:00+07', '2026-04-29 09:18:00+07', 'Import GudangKu kardus; client_id=78; label=8000-9729-TJONG LI MI LALITA AGUSTIN; nomor_pesanan=8000; nomor_id=9729; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('73fed92b-cc1d-3429-8409-d064f757a062', 'GK-KARDUS-000084', 'GK-3482-85F02C-GK-KARDUS-000084', '1700-3482-AMI RAISA AFRA SAKILA', 'GK-3482-85F02C', 'GUDANG AMI', '2026-04-29 09:24:00+07', '2026-04-29 09:24:00+07', 'Import GudangKu kardus; client_id=84; label=1700-3482-AMI RAISA AFRA SAKILA; nomor_pesanan=1700; nomor_id=3482; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('dfaa25b5-e679-3570-8221-ae1abf106957', 'GK-KARDUS-000085', 'GK-9801-7C8F69-GK-KARDUS-000085', '9700-9801-WULAN ANITA WULAN', 'GK-9801-7C8F69', 'GUDANG ANITA', '2026-04-29 09:25:00+07', '2026-04-29 09:25:00+07', 'Import GudangKu kardus; client_id=85; label=9700-9801-WULAN ANITA WULAN; nomor_pesanan=9700; nomor_id=9801; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f2d7a958-019a-3ab1-bce8-bd4d6b478e89', 'GK-KARDUS-000086', 'GK-4282-53768B-GK-KARDUS-000086', '8600-4282-DODI IMANUEL ANITA DODI IMANUEL', 'GK-4282-53768B', 'GUDANG ANITA', '2026-04-29 09:26:00+07', '2026-04-29 09:26:00+07', 'Import GudangKu kardus; client_id=86; label=8600-4282-DODI IMANUEL ANITA DODI IMANUEL; nomor_pesanan=8600; nomor_id=4282; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('760f4908-dd9b-3a30-8df9-1826a556ca31', 'GK-KARDUS-000087', 'GK-9733-B786FE-GK-KARDUS-000087', '5000-9733-TJONG LI MI TIARA VINA', 'GK-9733-B786FE', 'GUDANG AMI', '2026-04-29 09:40:00+07', '2026-04-29 09:40:00+07', 'Import GudangKu kardus; client_id=87; label=5000-9733-TJONG LI MI TIARA VINA; nomor_pesanan=5000; nomor_id=9733; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('4f967938-68de-3f0b-8d43-cb51b8c88d69', 'GK-KARDUS-000088', 'GK-7632-BE3F0A-GK-KARDUS-000088', '1100-7632-YERIKHO ANITA YERIKHO RIDO HUTAHAEAN', 'GK-7632-BE3F0A', 'GUDANG ANITA', '2026-04-29 09:42:00+07', '2026-04-29 09:42:00+07', 'Import GudangKu kardus; client_id=88; label=1100-7632-YERIKHO ANITA YERIKHO RIDO HUTAHAEAN; nomor_pesanan=1100; nomor_id=7632; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('7675ba21-a8d4-312d-accf-0ef710ca702b', 'GK-KARDUS-000096', 'GK-9855-68B36E-GK-KARDUS-000096', '3400-9855-NENG KANAN T PAPUA WIDURI', 'GK-9855-68B36E', 'GUDANG NENG', '2026-04-29 09:53:00+07', '2026-04-29 09:53:00+07', 'Import GudangKu kardus; client_id=96; label=3400-9855-NENG KANAN T PAPUA WIDURI; nomor_pesanan=3400; nomor_id=9855; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('8b5dd126-3cd4-381f-a5b2-2d6770c0624f', 'GK-KARDUS-000097', 'GK-7827-54C2BB-GK-KARDUS-000097', '8700-7827-HERMANSYAH ANITA', 'GK-7827-54C2BB', 'GUDANG ANITA', '2026-04-29 09:55:00+07', '2026-04-29 09:55:00+07', 'Import GudangKu kardus; client_id=97; label=8700-7827-HERMANSYAH ANITA; nomor_pesanan=8700; nomor_id=7827; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('03212d54-59a9-3552-b4cb-6408341b9ae4', 'GK-KARDUS-000098', 'GK-7507-427FF3-GK-KARDUS-000098', '5200-7507-NENG KANAN T PAPUA YULLI', 'GK-7507-427FF3', 'GUDANG NENG', '2026-04-29 09:55:00+07', '2026-04-29 09:55:00+07', 'Import GudangKu kardus; client_id=98; label=5200-7507-NENG KANAN T PAPUA YULLI; nomor_pesanan=5200; nomor_id=7507; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('9db4474e-ca17-3ffe-85fa-072983c24dc9', 'GK-KARDUS-000102', 'GK-7850-F7EE9F-GK-KARDUS-000102', '5900-7850-FARHAN ANITA MAULANA', 'GK-7850-F7EE9F', 'GUDANG ANITA', '2026-04-29 09:59:00+07', '2026-04-29 09:59:00+07', 'Import GudangKu kardus; client_id=102; label=5900-7850-FARHAN ANITA MAULANA; nomor_pesanan=5900; nomor_id=7850; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('a2f82b56-6320-3aaa-af43-3538c7140499', 'GK-KARDUS-000103', 'GK-6179-294269-GK-KARDUS-000103', '8300-6179-ANITA BINTANG SOFIAH HUSNA SHOFIA', 'GK-6179-294269', 'GUDANG ANITA', '2026-04-29 10:00:00+07', '2026-04-29 10:00:00+07', 'Import GudangKu kardus; client_id=103; label=8300-6179-ANITA BINTANG SOFIAH HUSNA SHOFIA; nomor_pesanan=8300; nomor_id=6179; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ed847b6e-08a7-3d12-9b4c-7c22ba84b12e', 'GK-KARDUS-000105', 'GK-0041-889FD0-GK-KARDUS-000105', '1500-0041-NENG KANAN T PAPUA LIAM PUTRA', 'GK-0041-889FD0', 'GUDANG NENG', '2026-04-29 10:01:00+07', '2026-04-29 10:01:00+07', 'Import GudangKu kardus; client_id=105; label=1500-0041-NENG KANAN T PAPUA LIAM PUTRA; nomor_pesanan=1500; nomor_id=0041; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('bb1bf338-9a53-3b08-b7d0-f0017829e632', 'GK-KARDUS-000108', 'GK-7737-B72624-GK-KARDUS-000108', '4000-7737-RAHMAD ANITA RAHMAD HIDAYAT', 'GK-7737-B72624', 'GUDANG ANITA', '2026-04-29 10:04:00+07', '2026-04-29 10:04:00+07', 'Import GudangKu kardus; client_id=108; label=4000-7737-RAHMAD ANITA RAHMAD HIDAYAT; nomor_pesanan=4000; nomor_id=7737; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('d66cbead-5a3e-3099-a519-997b647ac199', 'GK-KARDUS-000109', 'GK-6207-FEB098-GK-KARDUS-000109', '0700-6207-ABDUL SELVI ABDUL AZIZ', 'GK-6207-FEB098', 'GUDANG SELVI', '2026-04-29 10:05:00+07', '2026-04-29 10:05:00+07', 'Import GudangKu kardus; client_id=109; label=0700-6207-ABDUL SELVI ABDUL AZIZ; nomor_pesanan=0700; nomor_id=6207; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('3aad4943-91cf-382a-9f65-28f9015b87bd', 'GK-KARDUS-000111', 'GK-7736-D6B56B-GK-KARDUS-000111', '7500-7736-MIRENDI ANITA MIRENDI SAMBO', 'GK-7736-D6B56B', 'GUDANG ANITA', '2026-04-29 10:07:00+07', '2026-04-29 10:07:00+07', 'Import GudangKu kardus; client_id=111; label=7500-7736-MIRENDI ANITA MIRENDI SAMBO; nomor_pesanan=7500; nomor_id=7736; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('893f2137-7c36-3df9-b5fd-0cca7a4a1c20', 'GK-KARDUS-000112', 'GK-4216-50E873-GK-KARDUS-000112', '7000-4216-TJONG LI MI KIKI RUHMAN', 'GK-4216-50E873', 'GUDANG AMI', '2026-04-29 10:07:00+07', '2026-04-29 10:07:00+07', 'Import GudangKu kardus; client_id=112; label=7000-4216-TJONG LI MI KIKI RUHMAN; nomor_pesanan=7000; nomor_id=4216; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('31f8b967-8141-329a-b25d-0932d7fe7e39', 'GK-KARDUS-000113', 'GK-9965-C04674-GK-KARDUS-000113', '8000-9965-NENG KANAN T PAPUA ARFATHAN MALIK RAZI', 'GK-9965-C04674', 'GUDANG NENG', '2026-04-29 10:09:00+07', '2026-04-29 10:09:00+07', 'Import GudangKu kardus; client_id=113; label=8000-9965-NENG KANAN T PAPUA ARFATHAN MALIK RAZI; nomor_pesanan=8000; nomor_id=9965; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('31956025-02e4-331b-94c0-5edccbdecd17', 'GK-KARDUS-000114', 'GK-4219-684578-GK-KARDUS-000114', '5700-4219-TJONG LI MI NANDA BERMAHTA', 'GK-4219-684578', 'GUDANG AMI', '2026-04-29 10:09:00+07', '2026-04-29 10:09:00+07', 'Import GudangKu kardus; client_id=114; label=5700-4219-TJONG LI MI NANDA BERMAHTA; nomor_pesanan=5700; nomor_id=4219; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('cdfb74b2-7ff8-30de-870f-98f4c018a78b', 'GK-KARDUS-000115', 'GK-7546-5A7792-GK-KARDUS-000115', '2400-7546-DENI ANITA DENI KURNIAWAN', 'GK-7546-5A7792', 'GUDANG ANITA', '2026-04-29 10:11:00+07', '2026-04-29 10:11:00+07', 'Import GudangKu kardus; client_id=115; label=2400-7546-DENI ANITA DENI KURNIAWAN; nomor_pesanan=2400; nomor_id=7546; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('a586075d-351f-3193-8ce2-ab5f49cb7d36', 'GK-KARDUS-000117', 'GK-4224-69E415-GK-KARDUS-000117', '0900-4224-TJONG LI MI SUKIRNO', 'GK-4224-69E415', 'GUDANG AMI', '2026-04-29 10:13:00+07', '2026-04-29 10:13:00+07', 'Import GudangKu kardus; client_id=117; label=0900-4224-TJONG LI MI SUKIRNO; nomor_pesanan=0900; nomor_id=4224; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('c048e7eb-e08c-34ea-87bc-6cebb71b008a', 'GK-KARDUS-000119', 'GK-4228-A6683B-GK-KARDUS-000119', '1500-4228-AMI AMALIA PUTRI', 'GK-4228-A6683B', 'GUDANG AMI', '2026-04-29 10:15:00+07', '2026-04-29 10:15:00+07', 'Import GudangKu kardus; client_id=119; label=1500-4228-AMI AMALIA PUTRI; nomor_pesanan=1500; nomor_id=4228; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('8c0c17a6-7e0f-314c-ab61-ede217b2940c', 'GK-KARDUS-000121', 'GK-7592-B786FE-GK-KARDUS-000121', '5000-7592-TJONG LI MI TIARA VINA', 'GK-7592-B786FE', 'GUDANG AMI', '2026-04-29 10:17:00+07', '2026-04-29 10:17:00+07', 'Import GudangKu kardus; client_id=121; label=5000-7592-TJONG LI MI TIARA VINA; nomor_pesanan=5000; nomor_id=7592; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('94942eec-80a6-3f5c-bcaf-39ffb83214e9', 'GK-KARDUS-000122', 'GK-4214-68D112-GK-KARDUS-000122', '6600-4214-TJONG LI MI MICHAEL PRATAMA SOELIESTYO', 'GK-4214-68D112', 'GUDANG AMI', '2026-04-29 10:19:00+07', '2026-04-29 10:19:00+07', 'Import GudangKu kardus; client_id=122; label=6600-4214-TJONG LI MI MICHAEL PRATAMA SOELIESTYO; nomor_pesanan=6600; nomor_id=4214; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('f2816d0c-3225-3751-925e-b9d4e7c3f25e', 'GK-KARDUS-000124', 'GK-4222-2E05FC-GK-KARDUS-000124', '3900-4222-TJONG LALA KIKI', 'GK-4222-2E05FC', 'GUDANG AMI', '2026-04-29 10:19:00+07', '2026-04-29 10:19:00+07', 'Import GudangKu kardus; client_id=124; label=3900-4222-TJONG LALA KIKI; nomor_pesanan=3900; nomor_id=4222; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('846af04f-89ea-34e1-a30e-b89566f81546', 'GK-KARDUS-000125', 'GK-7581-704847-GK-KARDUS-000125', '2300-7581-ELLYS BYRALIMUDDIN DG NAI', 'GK-7581-704847', 'GUDANG ELLYS', '2026-04-29 10:20:00+07', '2026-04-29 10:20:00+07', 'Import GudangKu kardus; client_id=125; label=2300-7581-ELLYS BYRALIMUDDIN DG NAI; nomor_pesanan=2300; nomor_id=7581; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('9b60115a-2d0b-3a45-889c-57c707e04fee', 'GK-KARDUS-000126', 'GK-0367-53768B-GK-KARDUS-000126', '8600-0367-DODI IMANUEL ANITA DODI IMANUEL', 'GK-0367-53768B', 'GUDANG ANITA', '2026-04-29 10:21:00+07', '2026-04-29 10:21:00+07', 'Import GudangKu kardus; client_id=126; label=8600-0367-DODI IMANUEL ANITA DODI IMANUEL; nomor_pesanan=8600; nomor_id=0367; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('cac9f968-11cd-330a-848d-51aa84e35750', 'GK-KARDUS-000127', 'GK-3575-A1C36D-GK-KARDUS-000127', '8600-3575-ANITA BINTANG MIRA RACHEL', 'GK-3575-A1C36D', 'GUDANG ANITA', '2026-04-29 10:22:00+07', '2026-04-29 10:22:00+07', 'Import GudangKu kardus; client_id=127; label=8600-3575-ANITA BINTANG MIRA RACHEL; nomor_pesanan=8600; nomor_id=3575; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('091bff0e-9a5d-3178-87de-998f04774b07', 'GK-KARDUS-000129', 'GK-0319-6E0B32-GK-KARDUS-000129', '2700-0319-AMI ASNI PASARIBU', 'GK-0319-6E0B32', 'GUDANG AMI', '2026-04-29 10:25:00+07', '2026-04-29 10:25:00+07', 'Import GudangKu kardus; client_id=129; label=2700-0319-AMI ASNI PASARIBU; nomor_pesanan=2700; nomor_id=0319; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('8e77c1e8-53df-3c26-84aa-47319a826fbc', 'GK-KARDUS-000130', 'GK-9835-DD482A-GK-KARDUS-000130', '9900-9835-NENG KANAN T PAPUA ABDURAHMAN', 'GK-9835-DD482A', 'GUDANG NENG', '2026-04-29 10:26:00+07', '2026-04-29 10:26:00+07', 'Import GudangKu kardus; client_id=130; label=9900-9835-NENG KANAN T PAPUA ABDURAHMAN; nomor_pesanan=9900; nomor_id=9835; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('921c28ea-b94f-3537-93c0-825504ef3c14', 'GK-KARDUS-000131', 'GK-9740-B5547E-GK-KARDUS-000131', '1800-9740-NENG KANAN T PAPUA RINA HANDAYANI', 'GK-9740-B5547E', 'GUDANG NENG', '2026-04-29 10:28:00+07', '2026-04-29 10:28:00+07', 'Import GudangKu kardus; client_id=131; label=1800-9740-NENG KANAN T PAPUA RINA HANDAYANI; nomor_pesanan=1800; nomor_id=9740; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('a4c4d2c3-c48e-3141-95d5-40588e9b882d', 'GK-KARDUS-000132', 'GK-9943-6F116C-GK-KARDUS-000132', '7700-9943-NABILA ANITA NABILA', 'GK-9943-6F116C', 'GUDANG ANITA', '2026-04-29 10:29:00+07', '2026-04-29 10:29:00+07', 'Import GudangKu kardus; client_id=132; label=7700-9943-NABILA ANITA NABILA; nomor_pesanan=7700; nomor_id=9943; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('7cf8abe7-0917-3293-aeeb-fdd9ff3fd7c7', 'GK-KARDUS-000134', 'GK-7622-895F67-GK-KARDUS-000134', '1600-7622-NENG KANAN T PAPUA ARUNA PUTRI', 'GK-7622-895F67', 'GUDANG NENG', '2026-04-29 10:32:00+07', '2026-04-29 10:32:00+07', 'Import GudangKu kardus; client_id=134; label=1600-7622-NENG KANAN T PAPUA ARUNA PUTRI; nomor_pesanan=1600; nomor_id=7622; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f844aaaa-1a1c-3e23-8849-690789cea89b', 'GK-KARDUS-000135', 'GK-9968-5F8860-GK-KARDUS-000135', '2200-9968-RUDIANTO TEAM RINA RUDIANTO', 'GK-9968-5F8860', 'GUDANG RINA', '2026-04-29 10:35:00+07', '2026-04-29 10:35:00+07', 'Import GudangKu kardus; client_id=135; label=2200-9968-RUDIANTO TEAM RINA RUDIANTO; nomor_pesanan=2200; nomor_id=9968; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('3bd28968-84a0-32f6-b622-982f14013140', 'GK-KARDUS-000136', 'GK-4208-5232D0-GK-KARDUS-000136', '1600-4208-TJONG LI MI ANDIKA', 'GK-4208-5232D0', 'GUDANG AMI', '2026-04-29 10:37:00+07', '2026-04-29 10:37:00+07', 'Import GudangKu kardus; client_id=136; label=1600-4208-TJONG LI MI ANDIKA; nomor_pesanan=1600; nomor_id=4208; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f4b926de-be76-356d-af85-93087b64a1d2', 'GK-KARDUS-000137', 'GK-1359-355619-GK-KARDUS-000137', '7000-1359-TJAHJA LIAY T WIFATJAHJA LIAY', 'GK-1359-355619', 'GUDANG WIFA', '2026-04-29 10:37:00+07', '2026-04-29 10:37:00+07', 'Import GudangKu kardus; client_id=137; label=7000-1359-TJAHJA LIAY T WIFATJAHJA LIAY; nomor_pesanan=7000; nomor_id=1359; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('8dbfa91c-6735-3300-840f-d0068fd07de8', 'GK-KARDUS-000138', 'GK-6616-D001E7-GK-KARDUS-000138', '0500-6616-GINTING ANITA GINTING HAMATIR', 'GK-6616-D001E7', 'GUDANG ANITA', '2026-04-29 10:39:00+07', '2026-04-29 10:39:00+07', 'Import GudangKu kardus; client_id=138; label=0500-6616-GINTING ANITA GINTING HAMATIR; nomor_pesanan=0500; nomor_id=6616; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('d78d916f-cf48-3ebd-a210-10ae658f1340', 'GK-KARDUS-000139', 'GK-9754-D6C0C7-GK-KARDUS-000139', '2800-9754-NENG KANAN T PAPUA UUM SUPRIYADI', 'GK-9754-D6C0C7', 'GUDANG NENG', '2026-04-29 10:39:00+07', '2026-04-29 10:39:00+07', 'Import GudangKu kardus; client_id=139; label=2800-9754-NENG KANAN T PAPUA UUM SUPRIYADI; nomor_pesanan=2800; nomor_id=9754; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f37d3056-c525-30ba-a3ce-e78e4669900f', 'GK-KARDUS-000140', 'GK-9802-B441AB-GK-KARDUS-000140', '5200-9802-EVA ANITA EKA SAPUTRA', 'GK-9802-B441AB', 'GUDANG ANITA', '2026-04-29 10:41:00+07', '2026-04-29 10:41:00+07', 'Import GudangKu kardus; client_id=140; label=5200-9802-EVA ANITA EKA SAPUTRA; nomor_pesanan=5200; nomor_id=9802; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('251399bd-92f4-3fca-9c45-bf768f981e46', 'GK-KARDUS-000141', 'GK-0000-615F28-GK-KARDUS-000141', '6800-0000-MARCO ANITA MARCORIUS', 'GK-0000-615F28', 'GUDANG ANITA', '2026-04-29 10:44:00+07', '2026-04-29 10:44:00+07', 'Import GudangKu kardus; client_id=141; label=6800-0000-MARCO ANITA MARCORIUS; nomor_pesanan=6800; nomor_id=0000; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('691dcccf-396b-3ca3-b75d-3b22885ae633', 'GK-KARDUS-000142', 'GK-9781-E4F48B-GK-KARDUS-000142', '4400-9781-SAMUEL ANITA SAMUEL MALUMUS', 'GK-9781-E4F48B', 'GUDANG ANITA', '2026-04-29 10:46:00+07', '2026-04-29 10:46:00+07', 'Import GudangKu kardus; client_id=142; label=4400-9781-SAMUEL ANITA SAMUEL MALUMUS; nomor_pesanan=4400; nomor_id=9781; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('2a8e6613-8a4c-3366-ad60-97ffeef74554', 'GK-KARDUS-000143', 'GK-0236-8B7DA3-GK-KARDUS-000143', '0000-0236-JUMRIYEH ANITA JUMRIYEH', 'GK-0236-8B7DA3', 'GUDANG ANITA', '2026-04-29 10:46:00+07', '2026-04-29 10:46:00+07', 'Import GudangKu kardus; client_id=143; label=0000-0236-JUMRIYEH ANITA JUMRIYEH; nomor_pesanan=0000; nomor_id=0236; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('eb8f9d1b-54bd-34e9-93a2-8b172d229229', 'GK-KARDUS-000147', 'GK-5035-B501E8-GK-KARDUS-000147', '6400-5035-TJONG LI MI ALOY HALIMUS', 'GK-5035-B501E8', 'GUDANG AMI', '2026-04-29 10:49:00+07', '2026-04-29 10:49:00+07', 'Import GudangKu kardus; client_id=147; label=6400-5035-TJONG LI MI ALOY HALIMUS; nomor_pesanan=6400; nomor_id=5035; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('20b31d21-b4a7-3395-8ee3-710249c2617c', 'GK-KARDUS-000148', 'GK-9795-F312F0-GK-KARDUS-000148', '0200-9795-NENG KANAN T PAPUA KURNIA HIDAYAT', 'GK-9795-F312F0', 'GUDANG NENG', '2026-04-29 10:50:00+07', '2026-04-29 10:50:00+07', 'Import GudangKu kardus; client_id=148; label=0200-9795-NENG KANAN T PAPUA KURNIA HIDAYAT; nomor_pesanan=0200; nomor_id=9795; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f32de160-2cd7-3abb-9006-8823cec9f611', 'GK-KARDUS-000149', 'GK-9709-5993C3-GK-KARDUS-000149', '9800-9709-NENG KANAN T PAPUA RAMDAN', 'GK-9709-5993C3', 'GUDANG NENG', '2026-04-29 10:53:00+07', '2026-04-29 10:53:00+07', 'Import GudangKu kardus; client_id=149; label=9800-9709-NENG KANAN T PAPUA RAMDAN; nomor_pesanan=9800; nomor_id=9709; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('c77ea1c7-25ed-391d-bb7c-2ce9929d264e', 'GK-KARDUS-000150', 'GK-8172-AA7BE3-GK-KARDUS-000150', '9600-8172-AMI BUYUNG TANJUNG', 'GK-8172-AA7BE3', 'GUDANG AMI', '2026-04-29 10:54:00+07', '2026-04-29 10:54:00+07', 'Import GudangKu kardus; client_id=150; label=9600-8172-AMI BUYUNG TANJUNG; nomor_pesanan=9600; nomor_id=8172; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('75027093-841f-3363-8889-1b5b3caea98b', 'GK-KARDUS-000152', 'GK-7610-03E1AB-GK-KARDUS-000152', '9000-7610-HERMIN TEAM RINA HERMIN PAKIDING', 'GK-7610-03E1AB', 'GUDANG RINA', '2026-04-29 10:55:00+07', '2026-04-29 10:55:00+07', 'Import GudangKu kardus; client_id=152; label=9000-7610-HERMIN TEAM RINA HERMIN PAKIDING; nomor_pesanan=9000; nomor_id=7610; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ca9a6f52-e365-3d59-bc6c-11de6bea3d36', 'GK-KARDUS-000154', 'GK-7586-04B1C4-GK-KARDUS-000154', '4100-7586-NENG KANAN T PAPUA AMMAR KHOLID', 'GK-7586-04B1C4', 'GUDANG NENG', '2026-04-29 10:59:00+07', '2026-04-29 10:59:00+07', 'Import GudangKu kardus; client_id=154; label=4100-7586-NENG KANAN T PAPUA AMMAR KHOLID; nomor_pesanan=4100; nomor_id=7586; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('c209b679-d11c-38c0-a32e-beea3e99ab6d', 'GK-KARDUS-000155', 'GK-9897-B38A9C-GK-KARDUS-000155', '3800-9897-BOEN DM ANITA PIN BOENTARAN', 'GK-9897-B38A9C', 'GUDANG ANITA', '2026-04-29 10:59:00+07', '2026-04-29 10:59:00+07', 'Import GudangKu kardus; client_id=155; label=3800-9897-BOEN DM ANITA PIN BOENTARAN; nomor_pesanan=3800; nomor_id=9897; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('c6aa43ba-3733-33ec-a7d8-168a813d6f44', 'GK-KARDUS-000156', 'GK-0387-69E415-GK-KARDUS-000156', '0900-0387-TJONG LI MI SUKIRNO', 'GK-0387-69E415', 'GUDANG AMI', '2026-04-30 05:55:00+07', '2026-04-30 05:55:00+07', 'Import GudangKu kardus; client_id=156; label=0900-0387-TJONG LI MI SUKIRNO; nomor_pesanan=0900; nomor_id=0387; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('71af7000-284f-3d77-9f2a-60641f78d4f9', 'GK-KARDUS-000157', 'GK-0351-49B0DE-GK-KARDUS-000157', '8400-0351-ANITA BINTANG AMELIA AMELIA', 'GK-0351-49B0DE', 'GUDANG ANITA', '2026-04-30 06:03:00+07', '2026-04-30 06:03:00+07', 'Import GudangKu kardus; client_id=157; label=8400-0351-ANITA BINTANG AMELIA AMELIA; nomor_pesanan=8400; nomor_id=0351; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('1203d2cc-790d-3e8f-9c48-832aa2977a92', 'GK-KARDUS-000158', 'GK-1746-85C0E4-GK-KARDUS-000158', '8600-1746-AMI T CHAELESS JULI SUJIANTO', 'GK-1746-85C0E4', 'GUDANG AMI', '2026-04-30 06:04:00+07', '2026-04-30 06:04:00+07', 'Import GudangKu kardus; client_id=158; label=8600-1746-AMI T CHAELESS JULI SUJIANTO; nomor_pesanan=8600; nomor_id=1746; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('96ed414d-2b8d-37d0-bcd5-9a928a6f3753', 'GK-KARDUS-000159', 'GK-3571-0AC2EE-GK-KARDUS-000159', '0600-3571-AMI ROPINDAH HASIBUAN', 'GK-3571-0AC2EE', 'GUDANG AMI', '2026-04-30 06:05:00+07', '2026-04-30 06:05:00+07', 'Import GudangKu kardus; client_id=159; label=0600-3571-AMI ROPINDAH HASIBUAN; nomor_pesanan=0600; nomor_id=3571; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('11aa7bb1-9e5a-38ba-a73d-0b14ebaf9d54', 'GK-KARDUS-000160', 'GK-0101-0FFC02-GK-KARDUS-000160', '3900-0101-TJONG LI MI LALA KLARA', 'GK-0101-0FFC02', 'GUDANG AMI', '2026-04-30 06:06:00+07', '2026-04-30 06:06:00+07', 'Import GudangKu kardus; client_id=160; label=3900-0101-TJONG LI MI LALA KLARA; nomor_pesanan=3900; nomor_id=0101; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('fbf31d93-3d1b-3d7a-b9d6-c81b5a1f9206', 'GK-KARDUS-000161', 'GK-1381-07BBF1-GK-KARDUS-000161', '3700-1381-AMI T WIFA ANDIKA', 'GK-1381-07BBF1', 'GUDANG AMI', '2026-04-30 06:08:00+07', '2026-04-30 06:08:00+07', 'Import GudangKu kardus; client_id=161; label=3700-1381-AMI T WIFA ANDIKA; nomor_pesanan=3700; nomor_id=1381; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('143b6303-3360-34ec-9033-a37ccaff5702', 'GK-KARDUS-000162', 'GK-9790-AD21D6-GK-KARDUS-000162', '8900-9790-SURYANI ARABROPINTA SIHITE', 'GK-9790-AD21D6', 'GUDANG SURYANI', '2026-04-30 06:11:00+07', '2026-04-30 06:11:00+07', 'Import GudangKu kardus; client_id=162; label=8900-9790-SURYANI ARABROPINTA SIHITE; nomor_pesanan=8900; nomor_id=9790; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('69d99433-ceac-3d02-9662-a9ac6cccb198', 'GK-KARDUS-000163', 'GK-9790-AD21D6-GK-KARDUS-000163', '8900-9790-SURYANI ARABROPINTA SIHITE', 'GK-9790-AD21D6', 'GUDANG SURYANI', '2026-04-30 06:44:00+07', '2026-04-30 06:44:00+07', 'Import GudangKu kardus; client_id=163; label=8900-9790-SURYANI ARABROPINTA SIHITE; nomor_pesanan=8900; nomor_id=9790; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('17ce0175-983e-370c-a83d-04821f25ef3c', 'GK-KARDUS-000164', 'GK-7754-D36E80-GK-KARDUS-000164', '2200-7754-RUDIANTO TEAM RINA', 'GK-7754-D36E80', 'GUDANG RINA', '2026-04-30 06:45:00+07', '2026-04-30 06:45:00+07', 'Import GudangKu kardus; client_id=164; label=2200-7754-RUDIANTO TEAM RINA; nomor_pesanan=2200; nomor_id=7754; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ae3e4865-b066-3f9f-b9c7-c16500439f76', 'GK-KARDUS-000165', 'GK-7754-D36E80-GK-KARDUS-000165', '2200-7754-RUDIANTO TEAM RINA', 'GK-7754-D36E80', 'GUDANG RINA', '2026-04-30 06:50:00+07', '2026-04-30 06:50:00+07', 'Import GudangKu kardus; client_id=165; label=2200-7754-RUDIANTO TEAM RINA; nomor_pesanan=2200; nomor_id=7754; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('c06c8fdb-94dc-3880-96f5-1a16cf0de996', 'GK-KARDUS-000166', 'GK-2804-1D8A39-GK-KARDUS-000166', '8500-2804-NENG KANAN T PAPUA CANTIKA PUTRI', 'GK-2804-1D8A39', 'GUDANG NENG', '2026-04-30 06:53:00+07', '2026-04-30 06:53:00+07', 'Import GudangKu kardus; client_id=166; label=8500-2804-NENG KANAN T PAPUA CANTIKA PUTRI; nomor_pesanan=8500; nomor_id=2804; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('e31d7707-fae7-333a-a60b-a3dc23596a66', 'GK-KARDUS-000167', 'GK-0211-E87F75-GK-KARDUS-000167', '2400-0211-RAISHA T WIFA AFRA SAKILA', 'GK-0211-E87F75', 'GUDANG WIFA', '2026-04-30 06:57:00+07', '2026-04-30 06:57:00+07', 'Import GudangKu kardus; client_id=167; label=2400-0211-RAISHA T WIFA AFRA SAKILA; nomor_pesanan=2400; nomor_id=0211; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('b90b4d09-f910-3b1e-b757-dfb02268aeac', 'GK-KARDUS-000168', 'GK-2957-F40958-GK-KARDUS-000168', '7500-2957-AMELIA ANITA', 'GK-2957-F40958', 'GUDANG ANITA', '2026-04-30 07:01:00+07', '2026-04-30 07:01:00+07', 'Import GudangKu kardus; client_id=168; label=7500-2957-AMELIA ANITA; nomor_pesanan=7500; nomor_id=2957; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('58a7f69c-cef7-34f4-b1d7-2297c9e43f0c', 'GK-KARDUS-000169', 'GK-9989-DE76BA-GK-KARDUS-000169', '0900-9989-CONTOTUA SELVI MARBUN', 'GK-9989-DE76BA', 'GUDANG SELVI', '2026-04-30 07:03:00+07', '2026-04-30 07:03:00+07', 'Import GudangKu kardus; client_id=169; label=0900-9989-CONTOTUA SELVI MARBUN; nomor_pesanan=0900; nomor_id=9989; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f5b562b2-3a39-3acc-b780-749df3795493', 'GK-KARDUS-000170', 'GK-9769-6BE1FF-GK-KARDUS-000170', '0100-9769-PAJAR SELVI PAJAR RUDI', 'GK-9769-6BE1FF', 'GUDANG SELVI', '2026-04-30 07:04:00+07', '2026-04-30 07:04:00+07', 'Import GudangKu kardus; client_id=170; label=0100-9769-PAJAR SELVI PAJAR RUDI; nomor_pesanan=0100; nomor_id=9769; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('3a44d258-a2af-32bd-95c3-93267402ddd0', 'GK-KARDUS-000171', 'GK-0641-2DBD9C-GK-KARDUS-000171', '6200-0641-NENG KANAN T PAPUA ADINDA ARISA', 'GK-0641-2DBD9C', 'GUDANG NENG', '2026-04-30 07:07:00+07', '2026-04-30 07:07:00+07', 'Import GudangKu kardus; client_id=171; label=6200-0641-NENG KANAN T PAPUA ADINDA ARISA; nomor_pesanan=6200; nomor_id=0641; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('da04ffda-7dc8-37fd-abf7-8f57669b849e', 'GK-KARDUS-000172', 'GK-9854-384F21-GK-KARDUS-000172', '2800-9854-iqbal selvi iqbal fariski sinaga', 'GK-9854-384F21', 'GUDANG SELVI', '2026-04-30 09:32:00+07', '2026-04-30 09:32:00+07', 'Import GudangKu kardus; client_id=172; label=2800-9854-iqbal selvi iqbal fariski sinaga; nomor_pesanan=2800; nomor_id=9854; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('9f7033b7-2e94-3d3f-8a3d-dab773ba97c4', 'GK-KARDUS-000173', 'GK-0035-4EFDA4-GK-KARDUS-000173', '7700-0035-NENG KANAN T PAPUA BULAN BAGASWARI', 'GK-0035-4EFDA4', 'GUDANG NENG', '2026-04-30 09:33:00+07', '2026-04-30 09:33:00+07', 'Import GudangKu kardus; client_id=173; label=7700-0035-NENG KANAN T PAPUA BULAN BAGASWARI; nomor_pesanan=7700; nomor_id=0035; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f89fcad0-c4a1-3915-8d57-b9a2f489c924', 'GK-KARDUS-000174', 'GK-7514-6A13C8-GK-KARDUS-000174', '9800-7514-TUTIK TEAM RINA TUTIK RAHAYU', 'GK-7514-6A13C8', 'GUDANG RINA', '2026-04-30 09:35:00+07', '2026-04-30 09:35:00+07', 'Import GudangKu kardus; client_id=174; label=9800-7514-TUTIK TEAM RINA TUTIK RAHAYU; nomor_pesanan=9800; nomor_id=7514; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('65ffe0ce-10e2-3e96-8b47-3ea170fe2ef2', 'GK-KARDUS-000176', 'GK-6556-9B897A-GK-KARDUS-000176', '0400-6556-SAMSUL TEAM RINA SAMSUL ARIPIN', 'GK-6556-9B897A', 'GUDANG RINA', '2026-04-30 09:36:00+07', '2026-04-30 09:36:00+07', 'Import GudangKu kardus; client_id=176; label=0400-6556-SAMSUL TEAM RINA SAMSUL ARIPIN; nomor_pesanan=0400; nomor_id=6556; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('cda51674-c648-3972-8102-62cac8412731', 'GK-KARDUS-000177', 'GK-9696-F38051-GK-KARDUS-000177', '7700-9696-FADLI ANITA FADLI', 'GK-9696-F38051', 'GUDANG ANITA', '2026-04-30 09:37:00+07', '2026-04-30 09:37:00+07', 'Import GudangKu kardus; client_id=177; label=7700-9696-FADLI ANITA FADLI; nomor_pesanan=7700; nomor_id=9696; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('d5034b1e-dcfb-380f-954e-c2eea6b83950', 'GK-KARDUS-000178', 'GK-7435-DCDA85-GK-KARDUS-000178', '2500-7435-NENG KANAN T PAPUA ANDITA PUTRI', 'GK-7435-DCDA85', 'GUDANG NENG', '2026-04-30 09:38:00+07', '2026-04-30 09:38:00+07', 'Import GudangKu kardus; client_id=178; label=2500-7435-NENG KANAN T PAPUA ANDITA PUTRI; nomor_pesanan=2500; nomor_id=7435; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('b88132c0-e4cf-37d5-bc32-d48ac15b0e5e', 'GK-KARDUS-000180', 'GK-7614-5D04F4-GK-KARDUS-000180', '2000-7614-NENG KANAN T PAPUA ARFHATAN MALIK RAZI', 'GK-7614-5D04F4', 'GUDANG NENG', '2026-04-30 09:39:00+07', '2026-04-30 09:39:00+07', 'Import GudangKu kardus; client_id=180; label=2000-7614-NENG KANAN T PAPUA ARFHATAN MALIK RAZI; nomor_pesanan=2000; nomor_id=7614; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('6b6859ea-5d8b-3487-a258-3c5a24d61bc2', 'GK-KARDUS-000181', 'GK-0067-292595-GK-KARDUS-000181', '6000-0067-NENG KANAN T PAPUA OLIVIA KIMI', 'GK-0067-292595', 'GUDANG NENG', '2026-04-30 09:40:00+07', '2026-04-30 09:40:00+07', 'Import GudangKu kardus; client_id=181; label=6000-0067-NENG KANAN T PAPUA OLIVIA KIMI; nomor_pesanan=6000; nomor_id=0067; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('19eb50e6-d905-3e52-9854-47560e491528', 'GK-KARDUS-000183', 'GK-9837-3AF253-GK-KARDUS-000183', '4600-9837-NENG KANAN T PAPUA KAYLA PUTRI', 'GK-9837-3AF253', 'GUDANG NENG', '2026-04-30 09:41:00+07', '2026-04-30 09:41:00+07', 'Import GudangKu kardus; client_id=183; label=4600-9837-NENG KANAN T PAPUA KAYLA PUTRI; nomor_pesanan=4600; nomor_id=9837; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('1a521062-f30b-30f1-aa08-71c0053f6d1c', 'GK-KARDUS-000184', 'GK-9881-080F5A-GK-KARDUS-000184', '1100-9881-YERIKO ANITA YERIKO RIDHO HUTAHEAN', 'GK-9881-080F5A', 'GUDANG ANITA', '2026-04-30 09:42:00+07', '2026-04-30 09:42:00+07', 'Import GudangKu kardus; client_id=184; label=1100-9881-YERIKO ANITA YERIKO RIDHO HUTAHEAN; nomor_pesanan=1100; nomor_id=9881; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('617585c7-0dc0-36d6-8609-e62f3b412542', 'GK-KARDUS-000186', 'GK-5075-95B698-GK-KARDUS-000186', '1300-5075-RAKA ANITA RAKA WIJAYA', 'GK-5075-95B698', 'GUDANG ANITA', '2026-04-30 09:43:00+07', '2026-04-30 09:43:00+07', 'Import GudangKu kardus; client_id=186; label=1300-5075-RAKA ANITA RAKA WIJAYA; nomor_pesanan=1300; nomor_id=5075; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('eaa2a04c-0d64-301c-a7cb-66f5b9bf4932', 'GK-KARDUS-000187', 'GK-0062-0B0E15-GK-KARDUS-000187', '7700-0062-tjong li mi eplin rutris sabuna', 'GK-0062-0B0E15', 'GUDANG AMI', '2026-04-30 09:44:00+07', '2026-04-30 09:44:00+07', 'Import GudangKu kardus; client_id=187; label=7700-0062-tjong li mi eplin rutris sabuna; nomor_pesanan=7700; nomor_id=0062; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('f6a11c7e-94fa-38d8-b5fc-95ab084585f4', 'GK-KARDUS-000188', 'GK-5024-F2B75B-GK-KARDUS-000188', '4100-5024-TJONG LI MI ERLANG HAMUDI', 'GK-5024-F2B75B', 'GUDANG AMI', '2026-04-30 09:45:00+07', '2026-04-30 09:45:00+07', 'Import GudangKu kardus; client_id=188; label=4100-5024-TJONG LI MI ERLANG HAMUDI; nomor_pesanan=4100; nomor_id=5024; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('149ddbc2-56bc-33d9-8d01-e2e7c819cbc7', 'GK-KARDUS-000191', 'GK-9920-5F39EA-GK-KARDUS-000191', '4900-9920-neng kanan t papua bayu', 'GK-9920-5F39EA', 'GUDANG NENG', '2026-04-30 09:50:00+07', '2026-04-30 09:50:00+07', 'Import GudangKu kardus; client_id=191; label=4900-9920-neng kanan t papua bayu; nomor_pesanan=4900; nomor_id=9920; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('219c532b-8832-3c01-a37a-d255fe672498', 'GK-KARDUS-000194', 'GK-8261-4C7EA9-GK-KARDUS-000194', '2900-8261-AMI SARTIKA DEWI', 'GK-8261-4C7EA9', 'GUDANG AMI', '2026-04-30 09:51:00+07', '2026-04-30 09:51:00+07', 'Import GudangKu kardus; client_id=194; label=2900-8261-AMI SARTIKA DEWI; nomor_pesanan=2900; nomor_id=8261; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('d3c10bba-6bcd-384c-96e2-2fd280e278f5', 'GK-KARDUS-000196', 'GK-0057-0C0ACD-GK-KARDUS-000196', '8700-0057-HERMANSYAH ANITA HERMANSYAH', 'GK-0057-0C0ACD', 'GUDANG ANITA', '2026-04-30 09:52:00+07', '2026-04-30 09:52:00+07', 'Import GudangKu kardus; client_id=196; label=8700-0057-HERMANSYAH ANITA HERMANSYAH; nomor_pesanan=8700; nomor_id=0057; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('3a8dc496-d158-3e8a-af67-0cd8dc5dfbe8', 'GK-KARDUS-000197', 'GK-9833-316895-GK-KARDUS-000197', '0800-9833-NENG KANAN T PAPUA MIMI AISYAH', 'GK-9833-316895', 'GUDANG NENG', '2026-04-30 09:53:00+07', '2026-04-30 09:53:00+07', 'Import GudangKu kardus; client_id=197; label=0800-9833-NENG KANAN T PAPUA MIMI AISYAH; nomor_pesanan=0800; nomor_id=9833; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('bd8a3b49-7978-3db6-beca-b27d92e18f44', 'GK-KARDUS-000198', 'GK-4840-7700F3-GK-KARDUS-000198', '9000-4840-YUSPIN TEAM RINA YUSPIN PARIMATA', 'GK-4840-7700F3', 'GUDANG RINA', '2026-04-30 09:54:00+07', '2026-04-30 09:54:00+07', 'Import GudangKu kardus; client_id=198; label=9000-4840-YUSPIN TEAM RINA YUSPIN PARIMATA; nomor_pesanan=9000; nomor_id=4840; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('b2acc88d-0a73-3d4c-b209-00362ce6ea59', 'GK-KARDUS-000199', 'GK-7633-13025E-GK-KARDUS-000199', '3800-7633-neng kanan t papua alvan', 'GK-7633-13025E', 'GUDANG NENG', '2026-04-30 09:55:00+07', '2026-04-30 09:55:00+07', 'Import GudangKu kardus; client_id=199; label=3800-7633-neng kanan t papua alvan; nomor_pesanan=3800; nomor_id=7633; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('df46c3dd-da49-3a59-ae07-fa063124f5ea', 'GK-KARDUS-000200', 'GK-4841-26E3F5-GK-KARDUS-000200', '0300-4841-RIANTO TEAM RINA RIANTO KARURU', 'GK-4841-26E3F5', 'GUDANG RINA', '2026-04-30 09:55:00+07', '2026-04-30 09:55:00+07', 'Import GudangKu kardus; client_id=200; label=0300-4841-RIANTO TEAM RINA RIANTO KARURU; nomor_pesanan=0300; nomor_id=4841; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('fc736eb4-b1a5-337d-b324-286ff39514c2', 'GK-KARDUS-000201', 'GK-3434-04EBA9-GK-KARDUS-000201', '3300-3434-Tjong li mi nabila', 'GK-3434-04EBA9', 'GUDANG AMI', '2026-04-30 09:56:00+07', '2026-04-30 09:56:00+07', 'Import GudangKu kardus; client_id=201; label=3300-3434-Tjong li mi nabila; nomor_pesanan=3300; nomor_id=3434; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('7738920c-8f97-300d-83bb-d36d2f8d013d', 'GK-KARDUS-000202', 'GK-0058-CAA8DF-GK-KARDUS-000202', '2900-0058-NENG KANAN T PAPUA IPIN HIDAYAT', 'GK-0058-CAA8DF', 'GUDANG NENG', '2026-04-30 09:57:00+07', '2026-04-30 09:57:00+07', 'Import GudangKu kardus; client_id=202; label=2900-0058-NENG KANAN T PAPUA IPIN HIDAYAT; nomor_pesanan=2900; nomor_id=0058; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('79d51532-7732-369f-be07-a0da657a0b63', 'GK-KARDUS-000203', 'GK-4980-8248DD-GK-KARDUS-000203', '2500-4980-DERLY TEAM RINA DERLY APRILIANI', 'GK-4980-8248DD', 'GUDANG RINA', '2026-04-30 09:58:00+07', '2026-04-30 09:58:00+07', 'Import GudangKu kardus; client_id=203; label=2500-4980-DERLY TEAM RINA DERLY APRILIANI; nomor_pesanan=2500; nomor_id=4980; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('4556adb2-7ec4-34f0-88ea-d1d29ec7ebb3', 'GK-KARDUS-000206', 'GK-7554-E76735-GK-KARDUS-000206', '2300-7554-NENG KANAN T PAPUA NASIWA AZIZAH', 'GK-7554-E76735', 'GUDANG NENG', '2026-04-30 10:01:00+07', '2026-04-30 10:01:00+07', 'Import GudangKu kardus; client_id=206; label=2300-7554-NENG KANAN T PAPUA NASIWA AZIZAH; nomor_pesanan=2300; nomor_id=7554; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('2f6d2daa-928c-3fff-b82b-1bd05c825c17', 'GK-KARDUS-000207', 'GK-3876-03E1AB-GK-KARDUS-000207', '4800-3876-HERMIN TEAM RINA HERMIN PAKIDING', 'GK-3876-03E1AB', 'GUDANG RINA', '2026-04-30 10:05:00+07', '2026-04-30 10:05:00+07', 'Import GudangKu kardus; client_id=207; label=4800-3876-HERMIN TEAM RINA HERMIN PAKIDING; nomor_pesanan=4800; nomor_id=3876; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('dfe7c123-b9ab-3c43-ac8f-dbe598cf3c63', 'GK-KARDUS-000209', 'GK-3619-674523-GK-KARDUS-000209', '1400-3619-TINA MARIANA D MAMI', 'GK-3619-674523', 'GUDANG TINA', '2026-04-30 10:09:00+07', '2026-04-30 10:09:00+07', 'Import GudangKu kardus; client_id=209; label=1400-3619-TINA MARIANA D MAMI; nomor_pesanan=1400; nomor_id=3619; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('1707e4ba-8380-33c9-9a66-c9df6b733e69', 'GK-KARDUS-000210', 'GK-9882-FE1CC7-GK-KARDUS-000210', '4600-9882-NENG KANAN T PAPUA WELI', 'GK-9882-FE1CC7', 'GUDANG NENG', '2026-04-30 10:12:00+07', '2026-04-30 10:12:00+07', 'Import GudangKu kardus; client_id=210; label=4600-9882-NENG KANAN T PAPUA WELI; nomor_pesanan=4600; nomor_id=9882; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('2c13ccfa-2542-38a3-b995-568eb539168f', 'GK-KARDUS-000211', 'GK-8099-1EC964-GK-KARDUS-000211', '5100-8099-FARHAN ANITA FARHAN MAULANA', 'GK-8099-1EC964', 'GUDANG ANITA', '2026-04-30 10:12:00+07', '2026-04-30 10:12:00+07', 'Import GudangKu kardus; client_id=211; label=5100-8099-FARHAN ANITA FARHAN MAULANA; nomor_pesanan=5100; nomor_id=8099; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('d00b59c0-2e81-3942-9821-a69b432dd0ba', 'GK-KARDUS-000213', 'GK-9950-175BF2-GK-KARDUS-000213', '9000-9950-NENG KANAN T PAPUA DEVI AULIA', 'GK-9950-175BF2', 'GUDANG NENG', '2026-04-30 10:16:00+07', '2026-04-30 10:16:00+07', 'Import GudangKu kardus; client_id=213; label=9000-9950-NENG KANAN T PAPUA DEVI AULIA; nomor_pesanan=9000; nomor_id=9950; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('5732cf6a-ce3a-3c0d-88fa-f3d6c4d30c93', 'GK-KARDUS-000218', 'GK-6229-71FB01-GK-KARDUS-000218', '9500-6229-MIRNA TEAM RINA MIRNA SUMINDAR', 'GK-6229-71FB01', 'GUDANG RINA', '2026-04-30 10:20:00+07', '2026-04-30 10:20:00+07', 'Import GudangKu kardus; client_id=218; label=9500-6229-MIRNA TEAM RINA MIRNA SUMINDAR; nomor_pesanan=9500; nomor_id=6229; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('67934a62-cbef-38bc-86c6-d15c47626592', 'GK-KARDUS-000228', 'GK-0395-3EEAC2-GK-KARDUS-000228', '9900-0395-NENG KANAN T PAPUA ANITA MARLITA', 'GK-0395-3EEAC2', 'GUDANG NENG', '2026-04-30 10:37:00+07', '2026-04-30 10:37:00+07', 'Import GudangKu kardus; client_id=228; label=9900-0395-NENG KANAN T PAPUA ANITA MARLITA; nomor_pesanan=9900; nomor_id=0395; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ab66ba95-e0bc-3832-b555-42d95b7f1777', 'GK-KARDUS-000230', 'GK-3960-4323AD-GK-KARDUS-000230', '8500-3960-LIHO T BENDLIHO', 'GK-3960-4323AD', 'GUDANG RANDOM', '2026-04-30 10:40:00+07', '2026-04-30 10:40:00+07', 'Import GudangKu kardus; client_id=230; label=8500-3960-LIHO T BENDLIHO; nomor_pesanan=8500; nomor_id=3960; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('3b6e31c1-bfef-33ea-b8f7-8600bdbde588', 'GK-KARDUS-000235', 'GK-3975-263FF1-GK-KARDUS-000235', '5100-3975-SUKAEMI T MAWARNI', 'GK-3975-263FF1', 'GUDANG MAWARNI', '2026-04-30 10:45:00+07', '2026-04-30 10:45:00+07', 'Import GudangKu kardus; client_id=235; label=5100-3975-SUKAEMI T MAWARNI; nomor_pesanan=5100; nomor_id=3975; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('6e631ce1-1340-33c1-b3b8-31d5ff339715', 'GK-KARDUS-000236', 'GK-6114-D9AC31-GK-KARDUS-000236', '0600-6114-Ami amalia safira', 'GK-6114-D9AC31', 'KANTOR', '2026-05-02 07:45:00+07', '2026-05-02 07:45:00+07', 'Import GudangKu kardus; client_id=236; label=0600-6114-Ami amalia safira; nomor_pesanan=0600; nomor_id=6114; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('c2c9053f-7cd4-373e-a9b4-a215d1115f41', 'GK-KARDUS-000237', 'GK-3564-40191E-GK-KARDUS-000237', '7700-3564-ami januar hendratama', 'GK-3564-40191E', 'KANTOR', '2026-05-02 07:50:00+07', '2026-05-02 07:50:00+07', 'Import GudangKu kardus; client_id=237; label=7700-3564-ami januar hendratama; nomor_pesanan=7700; nomor_id=3564; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('10bcb76d-e4ef-365f-9048-55e1a91ce7a9', 'GK-KARDUS-000238', 'GK-5041-57543B-GK-KARDUS-000238', '0600-5041-Tjong li mi dedi sulaeman', 'GK-5041-57543B', 'KANTOR', '2026-05-02 07:55:00+07', '2026-05-02 07:55:00+07', 'Import GudangKu kardus; client_id=238; label=0600-5041-Tjong li mi dedi sulaeman; nomor_pesanan=0600; nomor_id=5041; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('5f8b3f92-7ef2-30be-afc8-ea68aed0aa80', 'GK-KARDUS-000241', 'GK-6238-02E5F8-GK-KARDUS-000241', '8000-6238-ami t mawarni lukman hakim', 'GK-6238-02E5F8', 'KANTOR', '2026-05-02 07:57:00+07', '2026-05-02 07:57:00+07', 'Import GudangKu kardus; client_id=241; label=8000-6238-ami t mawarni lukman hakim; nomor_pesanan=8000; nomor_id=6238; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('1352f68e-9d97-3d7b-bf20-330d616d1d38', 'GK-KARDUS-000264', 'GK-1398-BBD7D0-GK-KARDUS-000264', '8700-1398-EKI Fadli Hutasuhut t marta eki fadli hutasuhut', 'GK-1398-BBD7D0', 'GUDANG MARTA', '2026-05-02 08:21:00+07', '2026-05-02 08:21:00+07', 'Import GudangKu kardus; client_id=264; label=8700-1398-EKI Fadli Hutasuhut t marta eki fadli hutasuhut; nomor_pesanan=8700; nomor_id=1398; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('2d3a2d90-9311-3a6b-aded-6f875854cd15', 'GK-KARDUS-000272', 'GK-2447-279A28-GK-KARDUS-000272', '0900-2447-Juliyana T. RINA Naingoian.', 'GK-2447-279A28', 'GUDANG RINA', '2026-05-02 08:28:00+07', '2026-05-02 08:28:00+07', 'Import GudangKu kardus; client_id=272; label=0900-2447-Juliyana T. RINA Naingoian.; nomor_pesanan=0900; nomor_id=2447; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('46934b34-9ea0-3fa8-a937-a96fb31510a5', 'GK-KARDUS-000277', 'GK-1411-3AF253-GK-KARDUS-000277', '1800-1411-NENG KANAN T PAPUA KAYLA PUTRI', 'GK-1411-3AF253', 'GUDANG NENG', '2026-05-02 08:32:00+07', '2026-05-02 08:32:00+07', 'Import GudangKu kardus; client_id=277; label=1800-1411-NENG KANAN T PAPUA KAYLA PUTRI; nomor_pesanan=1800; nomor_id=1411; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('bb80d7f0-11b9-36d7-8120-02d3be6939a5', 'GK-KARDUS-000283', 'GK-9862-946138-GK-KARDUS-000283', '9700-9862-Neng Kanan T Papua Citra Putri', 'GK-9862-946138', 'GUDANG NENG', '2026-05-02 08:37:00+07', '2026-05-02 08:37:00+07', 'Import GudangKu kardus; client_id=283; label=9700-9862-Neng Kanan T Papua Citra Putri; nomor_pesanan=9700; nomor_id=9862; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ee250d5b-cdcb-3d02-bc99-50568cfd9e9a', 'GK-KARDUS-000287', 'GK-1374-4D30BC-GK-KARDUS-000287', '9000-1374-Neng kanan T. Billy Ciputra', 'GK-1374-4D30BC', 'GUDANG NENG', '2026-05-02 08:45:00+07', '2026-05-02 08:45:00+07', 'Import GudangKu kardus; client_id=287; label=9000-1374-Neng kanan T. Billy Ciputra; nomor_pesanan=9000; nomor_id=1374; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('0bd19f83-9032-3e59-859f-24f7209da29f', 'GK-KARDUS-000288', 'GK-2319-444018-GK-KARDUS-000288', '9400-2319-Neng Kanan Kanan T. Kartika', 'GK-2319-444018', 'GUDANG NENG', '2026-05-02 08:48:00+07', '2026-05-02 08:48:00+07', 'Import GudangKu kardus; client_id=288; label=9400-2319-Neng Kanan Kanan T. Kartika; nomor_pesanan=9400; nomor_id=2319; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f010e6f4-60c7-3713-b0cf-efcea4bef609', 'GK-KARDUS-000291', 'GK-5073-334EA5-GK-KARDUS-000291', '3700-5073-Tjong Li mi marselinus male', 'GK-5073-334EA5', 'GUDANG AMI', '2026-05-02 08:59:00+07', '2026-05-02 08:59:00+07', 'Import GudangKu kardus; client_id=291; label=3700-5073-Tjong Li mi marselinus male; nomor_pesanan=3700; nomor_id=5073; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('9bc38450-3811-34f4-928f-ba8194b12463', 'GK-KARDUS-000292', 'GK-9927-04B1C4-GK-KARDUS-000292', '0700-9927-Neng Kanan T Papua Ammar Kholid', 'GK-9927-04B1C4', 'GUDANG NENG', '2026-05-02 09:01:00+07', '2026-05-02 09:01:00+07', 'Import GudangKu kardus; client_id=292; label=0700-9927-Neng Kanan T Papua Ammar Kholid; nomor_pesanan=0700; nomor_id=9927; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('66a01b07-2c31-389e-b52b-06192c484f4e', 'GK-KARDUS-000298', 'GK-5120-2EE85F-GK-KARDUS-000298', '5200-5120-TJONG LI MI MARIA CARINA METIKORES', 'GK-5120-2EE85F', 'GUDANG AMI', '2026-05-02 09:09:00+07', '2026-05-02 09:09:00+07', 'Import GudangKu kardus; client_id=298; label=5200-5120-TJONG LI MI MARIA CARINA METIKORES; nomor_pesanan=5200; nomor_id=5120; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('bdaed931-aafb-32fd-bb71-12e2cf418d47', 'GK-KARDUS-000299', 'GK-9905-1443B1-GK-KARDUS-000299', '1000-9905-Suryani Arab tiffani jocelyn loe', 'GK-9905-1443B1', 'GUDANG SURYANI', '2026-05-02 09:11:00+07', '2026-05-02 09:11:00+07', 'Import GudangKu kardus; client_id=299; label=1000-9905-Suryani Arab tiffani jocelyn loe; nomor_pesanan=1000; nomor_id=9905; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('6ee910bd-ef1d-3ac1-9e2e-637d61cc382f', 'GK-KARDUS-000301', 'GK-8291-3F11EE-GK-KARDUS-000301', '0700-8291-ILHAM Anita Kurniawan', 'GK-8291-3F11EE', 'GUDANG ANITA', '2026-05-02 09:14:00+07', '2026-05-02 09:14:00+07', 'Import GudangKu kardus; client_id=301; label=0700-8291-ILHAM Anita Kurniawan; nomor_pesanan=0700; nomor_id=8291; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('6c109590-3b1e-355f-8b79-7c6b25dfa9c4', 'GK-KARDUS-000303', 'GK-1861-19F8F1-GK-KARDUS-000303', '8800-1861-Neng Kanan T. Putri Ayu', 'GK-1861-19F8F1', 'GUDANG NENG', '2026-05-02 09:17:00+07', '2026-05-02 09:17:00+07', 'Import GudangKu kardus; client_id=303; label=8800-1861-Neng Kanan T. Putri Ayu; nomor_pesanan=8800; nomor_id=1861; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('d82bd669-636d-3197-8894-3894f1bb47e6', 'GK-KARDUS-000306', 'GK-1871-56EE5F-GK-KARDUS-000306', '0300-1871-Neng Karan T. cici Sriyana', 'GK-1871-56EE5F', 'GUDANG NENG', '2026-05-02 09:21:00+07', '2026-05-02 09:21:00+07', 'Import GudangKu kardus; client_id=306; label=0300-1871-Neng Karan T. cici Sriyana; nomor_pesanan=0300; nomor_id=1871; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('e06865b8-a5ad-3251-89bc-2d3e84152ef3', 'GK-KARDUS-000307', 'GK-2065-A7A53C-GK-KARDUS-000307', '3700-2065-NENG KANAN T PAPUA DANIAH JASMANIAH', 'GK-2065-A7A53C', 'GUDANG NENG', '2026-05-02 09:23:00+07', '2026-05-02 09:23:00+07', 'Import GudangKu kardus; client_id=307; label=3700-2065-NENG KANAN T PAPUA DANIAH JASMANIAH; nomor_pesanan=3700; nomor_id=2065; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('4c4a3c75-7622-3773-8bdc-0ca15b42c489', 'GK-KARDUS-000308', 'GK-2640-7A0853-GK-KARDUS-000308', '3000-2640-Nerg kanan T. Bashir', 'GK-2640-7A0853', 'GUDANG NENG', '2026-05-02 09:26:00+07', '2026-05-02 09:26:00+07', 'Import GudangKu kardus; client_id=308; label=3000-2640-Nerg kanan T. Bashir; nomor_pesanan=3000; nomor_id=2640; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('72f6ef83-d120-3543-ae04-fbabf0eb931c', 'GK-KARDUS-000317', 'GK-2801-F68631-GK-KARDUS-000317', '4500-2801-NENG KANAN T PAPUA HOTMARIA SINAGA', 'GK-2801-F68631', 'GUDANG NENG', '2026-05-02 09:36:00+07', '2026-05-02 09:36:00+07', 'Import GudangKu kardus; client_id=317; label=4500-2801-NENG KANAN T PAPUA HOTMARIA SINAGA; nomor_pesanan=4500; nomor_id=2801; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('0874446b-fc7f-34f6-b206-1938254aea65', 'GK-KARDUS-000318', 'GK-4101-79BFD2-GK-KARDUS-000318', '2500-4101-AMI DELILA BR HARIANJA', 'GK-4101-79BFD2', 'GUDANG AMI', '2026-05-02 09:40:00+07', '2026-05-02 09:40:00+07', 'Import GudangKu kardus; client_id=318; label=2500-4101-AMI DELILA BR HARIANJA; nomor_pesanan=2500; nomor_id=4101; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('7944cb98-97b3-3020-ad1c-b7979cb73482', 'GK-KARDUS-000320', 'GK-4101-A15E64-GK-KARDUS-000320', '1600-4101-GO SU CHEN GO SU CHEN', 'GK-4101-A15E64', 'KANTOR', '2026-05-02 09:41:00+07', '2026-05-02 09:41:00+07', 'Import GudangKu kardus; client_id=320; label=1600-4101-GO SU CHEN GO SU CHEN; nomor_pesanan=1600; nomor_id=4101; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('645ce0fa-e5d6-366b-a8ef-5ecaba7ed749', 'GK-KARDUS-000321', 'GK-4101-005B16-GK-KARDUS-000321', '5000-4101-AMI T CHARLES KANAN YOHANA AFRA BABO RAKI', 'GK-4101-005B16', 'KANTOR', '2026-05-02 09:43:00+07', '2026-05-02 09:43:00+07', 'Import GudangKu kardus; client_id=321; label=5000-4101-AMI T CHARLES KANAN YOHANA AFRA BABO RAKI; nomor_pesanan=5000; nomor_id=4101; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('88ca800a-950c-3681-a872-437c33448930', 'GK-KARDUS-000322', 'GK-1157-0CE773-GK-KARDUS-000322', '5600-1157-NENG KANAN T PAPUA RUSMINI', 'GK-1157-0CE773', 'GUDANG NENG', '2026-05-02 09:45:00+07', '2026-05-02 09:45:00+07', 'Import GudangKu kardus; client_id=322; label=5600-1157-NENG KANAN T PAPUA RUSMINI; nomor_pesanan=5600; nomor_id=1157; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ef7d75fc-eb36-330a-aa66-eaa44088a69b', 'GK-KARDUS-000323', 'GK-4101-25BC25-GK-KARDUS-000323', '9600-4101-ANITA BINTANG HINTA SINTA SUSILAWATI', 'GK-4101-25BC25', 'KANTOR', '2026-05-02 09:46:00+07', '2026-05-02 09:46:00+07', 'Import GudangKu kardus; client_id=323; label=9600-4101-ANITA BINTANG HINTA SINTA SUSILAWATI; nomor_pesanan=9600; nomor_id=4101; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f1f5d21e-f20a-322e-8c92-0f20062ab649', 'GK-KARDUS-000324', 'GK-6502-5E01C4-GK-KARDUS-000324', '7100-6502-ANISAHARI SUSANTO', 'GK-6502-5E01C4', 'GUDANG RANDOM', '2026-05-02 09:47:00+07', '2026-05-02 09:47:00+07', 'Import GudangKu kardus; client_id=324; label=7100-6502-ANISAHARI SUSANTO; nomor_pesanan=7100; nomor_id=6502; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('e2552db2-4fc2-32bf-951c-d78f9a0891dc', 'GK-KARDUS-000325', 'GK-1703-F88A6D-GK-KARDUS-000325', '3700-1703-NENG KANAN T PAPUA CICI SRIYANA', 'GK-1703-F88A6D', 'GUDANG NENG', '2026-05-02 09:49:00+07', '2026-05-02 09:49:00+07', 'Import GudangKu kardus; client_id=325; label=3700-1703-NENG KANAN T PAPUA CICI SRIYANA; nomor_pesanan=3700; nomor_id=1703; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('61294359-d3eb-3244-9eab-c81b8e180779', 'GK-KARDUS-000327', 'GK-4101-48005C-GK-KARDUS-000327', '0000-4101-MAGDALENA TEAM ANISA EASTER YULI WESTERN YULI', 'GK-4101-48005C', 'GUDANG ANISA', '2026-05-02 09:53:00+07', '2026-05-02 09:53:00+07', 'Import GudangKu kardus; client_id=327; label=0000-4101-MAGDALENA TEAM ANISA EASTER YULI WESTERN YULI; nomor_pesanan=0000; nomor_id=4101; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('205808a1-27fe-3a46-9e75-ee301872f0ee', 'GK-KARDUS-000329', 'GK-4069-291A22-GK-KARDUS-000329', '9500-4069-AMI HIKMAH SYAIFULLOH', 'GK-4069-291A22', 'KANTOR', '2026-05-02 09:59:00+07', '2026-05-02 09:59:00+07', 'Import GudangKu kardus; client_id=329; label=9500-4069-AMI HIKMAH SYAIFULLOH; nomor_pesanan=9500; nomor_id=4069; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('8bc68ce2-f0d3-3b90-8e98-528336ec74e3', 'GK-KARDUS-000331', 'GK-4069-3FB4BD-GK-KARDUS-000331', '1900-4069-ANITA BINTANG NGATIYONONGATIY ONO', 'GK-4069-3FB4BD', 'KANTOR', '2026-05-02 10:01:00+07', '2026-05-02 10:01:00+07', 'Import GudangKu kardus; client_id=331; label=1900-4069-ANITA BINTANG NGATIYONONGATIY ONO; nomor_pesanan=1900; nomor_id=4069; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('7dbaa1d7-793e-3548-a56a-1995649d8ef1', 'GK-KARDUS-000332', 'GK-4069-D3A1E9-GK-KARDUS-000332', '3600-4069-ESRA TEAM RINA ESRA RENDEN', 'GK-4069-D3A1E9', 'KANTOR', '2026-05-02 10:02:00+07', '2026-05-02 10:02:00+07', 'Import GudangKu kardus; client_id=332; label=3600-4069-ESRA TEAM RINA ESRA RENDEN; nomor_pesanan=3600; nomor_id=4069; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('caba6a98-d98f-3dd4-bcd1-e21f04a9ccf4', 'GK-KARDUS-000333', 'GK-4069-09BDD2-GK-KARDUS-000333', '9900-4069-AMI ANDREAS PAIAN', 'GK-4069-09BDD2', 'KANTOR', '2026-05-02 10:02:00+07', '2026-05-02 10:02:00+07', 'Import GudangKu kardus; client_id=333; label=9900-4069-AMI ANDREAS PAIAN; nomor_pesanan=9900; nomor_id=4069; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('5a0bc8b9-7baa-39f8-8978-958abf652d76', 'GK-KARDUS-000334', 'GK-2742-76A481-GK-KARDUS-000334', '4300-2742-SISKA YUNI T WIFA SISKA YUNI', 'GK-2742-76A481', 'GUDANG RANDOM', '2026-05-02 10:03:00+07', '2026-05-02 10:03:00+07', 'Import GudangKu kardus; client_id=334; label=4300-2742-SISKA YUNI T WIFA SISKA YUNI; nomor_pesanan=4300; nomor_id=2742; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('eefeeecf-d551-3706-b0aa-60f4abfbc516', 'GK-KARDUS-000335', 'GK-4114-41C21B-GK-KARDUS-000335', '2600-4114-AMI T ANDREW KUSASHI SMANDREW KUSASHI', 'GK-4114-41C21B', 'KANTOR', '2026-05-02 10:12:00+07', '2026-05-02 10:12:00+07', 'Import GudangKu kardus; client_id=335; label=2600-4114-AMI T ANDREW KUSASHI SMANDREW KUSASHI; nomor_pesanan=2600; nomor_id=4114; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('dbcffa2b-f5cc-36eb-8465-5a6b1b251ed3', 'GK-KARDUS-000336', 'GK-4168-C5FF43-GK-KARDUS-000336', '1000-4168-MIA AUDINA NURSAIDAH', 'GK-4168-C5FF43', 'KANTOR', '2026-05-02 10:18:00+07', '2026-05-02 10:18:00+07', 'Import GudangKu kardus; client_id=336; label=1000-4168-MIA AUDINA NURSAIDAH; nomor_pesanan=1000; nomor_id=4168; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('a5a0b675-731e-37d2-ad0f-9b9e79b2c3e6', 'GK-KARDUS-000337', 'GK-4168-0D4FC7-GK-KARDUS-000337', '2200-4168-AMI AGNES JESSICA', 'GK-4168-0D4FC7', 'KANTOR', '2026-05-02 10:18:00+07', '2026-05-02 10:18:00+07', 'Import GudangKu kardus; client_id=337; label=2200-4168-AMI AGNES JESSICA; nomor_pesanan=2200; nomor_id=4168; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('70f98029-7a62-30c2-9746-e97213e402e8', 'GK-KARDUS-000338', 'GK-4168-36A0F1-GK-KARDUS-000338', '9600-4168-AMI ANDREW KUSASHI', 'GK-4168-36A0F1', 'KANTOR', '2026-05-02 10:19:00+07', '2026-05-02 10:19:00+07', 'Import GudangKu kardus; client_id=338; label=9600-4168-AMI ANDREW KUSASHI; nomor_pesanan=9600; nomor_id=4168; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('2ee00732-f287-376d-b0b5-8589a260999e', 'GK-KARDUS-000353', 'GK-2791-8B7DA3-GK-KARDUS-000353', '1600-2791-jumriyeh anita jumriyeh', 'GK-2791-8B7DA3', 'GUDANG ANITA', '2026-05-02 10:37:00+07', '2026-05-02 10:37:00+07', 'Import GudangKu kardus; client_id=353; label=1600-2791-jumriyeh anita jumriyeh; nomor_pesanan=1600; nomor_id=2791; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('47f9cda5-60f6-3ef6-9e58-4e2cc3b4e608', 'GK-KARDUS-000365', 'GK-0106-00131C-GK-KARDUS-000365', '0500-0106-NENG KANAN T PAPUA LIVINA AYU', 'GK-0106-00131C', 'GUDANG NENG', '2026-05-02 10:47:00+07', '2026-05-02 10:47:00+07', 'Import GudangKu kardus; client_id=365; label=0500-0106-NENG KANAN T PAPUA LIVINA AYU; nomor_pesanan=0500; nomor_id=0106; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('14d24a1d-7ba3-3956-9ac5-a6ac43b9e371', 'GK-KARDUS-000369', 'GK-6474-DCCEFB-GK-KARDUS-000369', '5600-6474-sumanto anita sumanto halim', 'GK-6474-DCCEFB', 'LOKASI ANITA', '2026-05-02 10:51:00+07', '2026-05-02 10:51:00+07', 'Import GudangKu kardus; client_id=369; label=5600-6474-sumanto anita sumanto halim; nomor_pesanan=5600; nomor_id=6474; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('60975565-40b2-31e5-bf1d-292a3aace984', 'GK-KARDUS-000375', 'GK-6542-3A9D84-GK-KARDUS-000375', '1600-6542-GADING ANITA GADING MARTHIN', 'GK-6542-3A9D84', 'GUDANG ANITA', '2026-05-02 10:57:00+07', '2026-05-02 10:57:00+07', 'Import GudangKu kardus; client_id=375; label=1600-6542-GADING ANITA GADING MARTHIN; nomor_pesanan=1600; nomor_id=6542; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('c46c7430-4e45-3f1c-a3b6-a20a9b2caf95', 'GK-KARDUS-000376', 'GK-6837-749A34-GK-KARDUS-000376', '2900-6837-DETRONI ANITA DETRONI WARUWU', 'GK-6837-749A34', 'GUDANG ANITA', '2026-05-02 11:02:00+07', '2026-05-02 11:02:00+07', 'Import GudangKu kardus; client_id=376; label=2900-6837-DETRONI ANITA DETRONI WARUWU; nomor_pesanan=2900; nomor_id=6837; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('204b1fa2-dd68-3498-9891-55148d812e97', 'GK-KARDUS-000378', 'GK-0219-C1432F-GK-KARDUS-000378', '2800-0219-NENG KANAN T PAPUA IHAT SOLIHAT', 'GK-0219-C1432F', 'GUDANG NENG', '2026-05-04 07:08:00+07', '2026-05-04 07:08:00+07', 'Import GudangKu kardus; client_id=378; label=2800-0219-NENG KANAN T PAPUA IHAT SOLIHAT; nomor_pesanan=2800; nomor_id=0219; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('d064f8e7-cdb6-3920-8556-b7bbdb759d2e', 'GK-KARDUS-000382', 'GK-1756-230DC3-GK-KARDUS-000382', '2400-1756-DEWINTA SARI WIFA DEWINTA SARI', 'GK-1756-230DC3', 'GUDANG WIFA', '2026-05-04 07:21:00+07', '2026-05-04 07:21:00+07', 'Import GudangKu kardus; client_id=382; label=2400-1756-DEWINTA SARI WIFA DEWINTA SARI; nomor_pesanan=2400; nomor_id=1756; type=Titipan; created_by=Oktavia; updated_by=Oktavia'),
  ('5a6dcf2b-87dd-37d8-9f9b-ad496c89b6f5', 'GK-KARDUS-000384', 'GK-1696-3AF253-GK-KARDUS-000384', '1800-1696-NENG KANAN T PAPUA KAYLA PUTRI', 'GK-1696-3AF253', 'GUDANG NENG', '2026-05-04 07:24:00+07', '2026-05-04 07:24:00+07', 'Import GudangKu kardus; client_id=384; label=1800-1696-NENG KANAN T PAPUA KAYLA PUTRI; nomor_pesanan=1800; nomor_id=1696; type=Titipan; created_by=Oktavia; updated_by=Oktavia'),
  ('a7783729-5798-3cb0-93f1-287606dc5b15', 'GK-KARDUS-000387', 'GK-2563-5E121E-GK-KARDUS-000387', '6300-2563-DEVIN MULYONO T TOMY KANAN DEVIN MULYONO', 'GK-2563-5E121E', 'GUDANG RANDOM', '2026-05-04 07:30:00+07', '2026-05-04 07:30:00+07', 'Import GudangKu kardus; client_id=387; label=6300-2563-DEVIN MULYONO T TOMY KANAN DEVIN MULYONO; nomor_pesanan=6300; nomor_id=2563; type=Titipan; created_by=Oktavia; updated_by=Oktavia'),
  ('cd2ede9b-04a2-3f25-a7d5-d5ad454fd192', 'GK-KARDUS-000389', 'GK-0737-4544B6-GK-KARDUS-000389', '0200-0737-Neng Kanan T. Nabila', 'GK-0737-4544B6', 'GUDANG NENG', '2026-05-04 07:33:00+07', '2026-05-04 07:33:00+07', 'Import GudangKu kardus; client_id=389; label=0200-0737-Neng Kanan T. Nabila; nomor_pesanan=0200; nomor_id=0737; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('fbe49a48-db9d-383c-8f3c-562bf98f164e', 'GK-KARDUS-000392', 'GK-0760-8010E5-GK-KARDUS-000392', '0700-0760-NENG KANAN T PAPUA ILHAM PURNAMA', 'GK-0760-8010E5', 'GUDANG NENG', '2026-05-04 07:35:00+07', '2026-05-04 07:35:00+07', 'Import GudangKu kardus; client_id=392; label=0700-0760-NENG KANAN T PAPUA ILHAM PURNAMA; nomor_pesanan=0700; nomor_id=0760; type=Titipan; created_by=Oktavia; updated_by=Oktavia'),
  ('b75be348-8094-3383-86f4-094e327a2290', 'GK-KARDUS-000393', 'GK-2607-2446E5-GK-KARDUS-000393', '6700-2607-NENG KANAN T PAPUA PUSPITA LASMI', 'GK-2607-2446E5', 'GUDANG NENG', '2026-05-04 07:38:00+07', '2026-05-04 07:38:00+07', 'Import GudangKu kardus; client_id=393; label=6700-2607-NENG KANAN T PAPUA PUSPITA LASMI; nomor_pesanan=6700; nomor_id=2607; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ce30c6bb-d9ac-39fe-80db-d030e98ead32', 'GK-KARDUS-000394', 'GK-7585-0C47F4-GK-KARDUS-000394', '5900-7585-TJONG LI MI', 'GK-7585-0C47F4', 'GUDANG AMI', '2026-05-04 07:38:00+07', '2026-05-04 07:38:00+07', 'Import GudangKu kardus; client_id=394; label=5900-7585-TJONG LI MI; nomor_pesanan=5900; nomor_id=7585; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('06113554-0743-3fcc-b63e-b806d23ced82', 'GK-KARDUS-000395', 'GK-2188-B8F629-GK-KARDUS-000395', '4400-2188-Rika Nahami T. Wifa Rica', 'GK-2188-B8F629', 'GUDANG WIFA', '2026-05-04 07:38:00+07', '2026-05-04 07:38:00+07', 'Import GudangKu kardus; client_id=395; label=4400-2188-Rika Nahami T. Wifa Rica; nomor_pesanan=4400; nomor_id=2188; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('a4b89d4d-1dde-3ec5-89bf-235c570d8ade', 'GK-KARDUS-000396', 'GK-1397-9EB307-GK-KARDUS-000396', '7400-1397-AKBAR ANITA AKBAR', 'GK-1397-9EB307', 'GUDANG ANITA', '2026-05-04 07:43:00+07', '2026-05-04 07:43:00+07', 'Import GudangKu kardus; client_id=396; label=7400-1397-AKBAR ANITA AKBAR; nomor_pesanan=7400; nomor_id=1397; type=Titipan; created_by=Oktavia; updated_by=Oktavia'),
  ('c8afb74a-0895-3728-aed3-ae77a7ba4841', 'GK-KARDUS-000397', 'GK-7552-00131C-GK-KARDUS-000397', '0500-7552-NENG KANAN T PAPUA LIVINA AYU', 'GK-7552-00131C', 'GUDANG NENG', '2026-05-04 07:44:00+07', '2026-05-04 07:44:00+07', 'Import GudangKu kardus; client_id=397; label=0500-7552-NENG KANAN T PAPUA LIVINA AYU; nomor_pesanan=0500; nomor_id=7552; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('71f55e92-a7a8-3fa9-be79-14578962204d', 'GK-KARDUS-000398', 'GK-9713-F288F2-GK-KARDUS-000398', '9200-9713-NENG KANAN T PAPUA NURLIDA', 'GK-9713-F288F2', 'GUDANG NENG', '2026-05-04 07:45:00+07', '2026-05-04 07:45:00+07', 'Import GudangKu kardus; client_id=398; label=9200-9713-NENG KANAN T PAPUA NURLIDA; nomor_pesanan=9200; nomor_id=9713; type=Titipan; created_by=Oktavia; updated_by=Oktavia'),
  ('e11185ba-345c-3dbe-a93e-53083566f384', 'GK-KARDUS-000399', 'GK-1461-CA40B4-GK-KARDUS-000399', '4900-1461-AMI T WIFA ASEP', 'GK-1461-CA40B4', 'GUDANG AMI', '2026-05-04 07:47:00+07', '2026-05-04 07:47:00+07', 'Import GudangKu kardus; client_id=399; label=4900-1461-AMI T WIFA ASEP; nomor_pesanan=4900; nomor_id=1461; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('8883efc6-c4dc-3b7e-8a5a-301be5b6b384', 'GK-KARDUS-000400', 'GK-7598-91FA6B-GK-KARDUS-000400', '9100-7598-TJong li mi Agus Septian', 'GK-7598-91FA6B', 'GUDANG AMI', '2026-05-04 07:49:00+07', '2026-05-04 07:49:00+07', 'Import GudangKu kardus; client_id=400; label=9100-7598-TJong li mi Agus Septian; nomor_pesanan=9100; nomor_id=7598; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('55798341-7627-3f38-9779-8d90be258672', 'GK-KARDUS-000401', 'GK-0729-FA6F1F-GK-KARDUS-000401', '2700-0729-NENG KANAN T PAPUA ANISA NURAWWALIYAH', 'GK-0729-FA6F1F', 'GUDANG NENG', '2026-05-04 07:53:00+07', '2026-05-04 07:53:00+07', 'Import GudangKu kardus; client_id=401; label=2700-0729-NENG KANAN T PAPUA ANISA NURAWWALIYAH; nomor_pesanan=2700; nomor_id=0729; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('09159d0b-3737-3a88-a32e-cc37c0a7b562', 'GK-KARDUS-000402', 'GK-0688-EFA402-GK-KARDUS-000402', '8300-0688-Neng karan T. Nunu Nuhdin', 'GK-0688-EFA402', 'GUDANG NENG', '2026-05-04 07:54:00+07', '2026-05-04 07:54:00+07', 'Import GudangKu kardus; client_id=402; label=8300-0688-Neng karan T. Nunu Nuhdin; nomor_pesanan=8300; nomor_id=0688; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('11580ddb-ee55-3b6c-bdd0-6e90295bf3ce', 'GK-KARDUS-000403', 'GK-0249-43D2B5-GK-KARDUS-000403', '5800-0249-KEVIN T TOMY KANAN KEVIN', 'GK-0249-43D2B5', 'GUDANG RANDOM', '2026-05-04 07:57:00+07', '2026-05-04 07:57:00+07', 'Import GudangKu kardus; client_id=403; label=5800-0249-KEVIN T TOMY KANAN KEVIN; nomor_pesanan=5800; nomor_id=0249; type=Titipan; created_by=Oktavia; updated_by=Oktavia'),
  ('bad03bd8-b516-32c6-a01f-8b58e03a4d2b', 'GK-KARDUS-000404', 'GK-4170-012C23-GK-KARDUS-000404', '6600-4170-AMI JONATHAN KENZIRO SUWITO', 'GK-4170-012C23', 'GUDANG AMI', '2026-05-04 07:59:00+07', '2026-05-04 07:59:00+07', 'Import GudangKu kardus; client_id=404; label=6600-4170-AMI JONATHAN KENZIRO SUWITO; nomor_pesanan=6600; nomor_id=4170; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('372e19cd-b084-3b85-9270-9af4c500fc30', 'GK-KARDUS-000406', 'GK-1353-ECF5CE-GK-KARDUS-000406', '7200-1353-SANDRI ANITA SANDRIYANO KORNAMNE PAYARA', 'GK-1353-ECF5CE', 'GUDANG RANDOM', '2026-05-04 08:04:00+07', '2026-05-04 08:04:00+07', 'Import GudangKu kardus; client_id=406; label=7200-1353-SANDRI ANITA SANDRIYANO KORNAMNE PAYARA; nomor_pesanan=7200; nomor_id=1353; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('528ab4bc-1469-3a58-809f-291db777cb3c', 'GK-KARDUS-000409', 'GK-1140-BC5634-GK-KARDUS-000409', '7000-1140-NENG KANAN T PAPUA UNDANG SUKARSA', 'GK-1140-BC5634', 'GUDANG NENG', '2026-05-04 08:07:00+07', '2026-05-04 08:07:00+07', 'Import GudangKu kardus; client_id=409; label=7000-1140-NENG KANAN T PAPUA UNDANG SUKARSA; nomor_pesanan=7000; nomor_id=1140; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('153f626a-ef21-3921-8016-36b6e7be5b2e', 'GK-KARDUS-000410', 'GK-9962-F9584E-GK-KARDUS-000410', '7900-9962-Meti Anita Meti Delsi', 'GK-9962-F9584E', 'GUDANG ANITA', '2026-05-04 08:09:00+07', '2026-05-04 08:09:00+07', 'Import GudangKu kardus; client_id=410; label=7900-9962-Meti Anita Meti Delsi; nomor_pesanan=7900; nomor_id=9962; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f8316b92-acef-3efd-943b-39a5a6b3fc54', 'GK-KARDUS-000411', 'GK-9922-910D6C-GK-KARDUS-000411', '5200-9922-NENG KANAN T PAPUA IHSAN IFTIKAR', 'GK-9922-910D6C', 'GUDANG NENG', '2026-05-04 08:10:00+07', '2026-05-04 08:10:00+07', 'Import GudangKu kardus; client_id=411; label=5200-9922-NENG KANAN T PAPUA IHSAN IFTIKAR; nomor_pesanan=5200; nomor_id=9922; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('d05f60ec-9d36-30c6-9227-7b85a84d3a24', 'GK-KARDUS-000412', 'GK-7566-899033-GK-KARDUS-000412', '9600-7566-Tjong Li Mi Anita kelop', 'GK-7566-899033', 'GUDANG AMI', '2026-05-04 08:11:00+07', '2026-05-04 08:11:00+07', 'Import GudangKu kardus; client_id=412; label=9600-7566-Tjong Li Mi Anita kelop; nomor_pesanan=9600; nomor_id=7566; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('6fb57740-c9e5-3b55-bf7b-10f4cbfa61ee', 'GK-KARDUS-000413', 'GK-7604-466A96-GK-KARDUS-000413', '8000-7604-Tjong li mi Dinda putri', 'GK-7604-466A96', 'GUDANG AMI', '2026-05-04 08:11:00+07', '2026-05-04 08:11:00+07', 'Import GudangKu kardus; client_id=413; label=8000-7604-Tjong li mi Dinda putri; nomor_pesanan=8000; nomor_id=7604; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('71657eca-d4fb-3fb7-9f0d-4816e51719c2', 'GK-KARDUS-000414', 'GK-0063-53E31A-GK-KARDUS-000414', '2800-0063-denny Anita denny setiawan', 'GK-0063-53E31A', 'GUDANG ANITA', '2026-05-04 08:14:00+07', '2026-05-04 08:14:00+07', 'Import GudangKu kardus; client_id=414; label=2800-0063-denny Anita denny setiawan; nomor_pesanan=2800; nomor_id=0063; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('039ccd71-030c-3efd-97d5-1b9d95161d3c', 'GK-KARDUS-000415', 'GK-1752-6E13D5-GK-KARDUS-000415', '2900-1752-TEODORUS TEAM RINA TEODORUS BREYNOL', 'GK-1752-6E13D5', 'GUDANG RINA', '2026-05-04 08:15:00+07', '2026-05-04 08:15:00+07', 'Import GudangKu kardus; client_id=415; label=2900-1752-TEODORUS TEAM RINA TEODORUS BREYNOL; nomor_pesanan=2900; nomor_id=1752; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('0c8a00dd-1cff-3d96-9dd1-1ead8ac01a1e', 'GK-KARDUS-000416', 'GK-7482-ED4BFA-GK-KARDUS-000416', '0800-7482-Neng Kanan T Papua Citra Cantika', 'GK-7482-ED4BFA', 'GUDANG NENG', '2026-05-04 08:15:00+07', '2026-05-04 08:15:00+07', 'Import GudangKu kardus; client_id=416; label=0800-7482-Neng Kanan T Papua Citra Cantika; nomor_pesanan=0800; nomor_id=7482; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('7171fa1a-7d4a-3439-a2d1-d1cc972786d2', 'GK-KARDUS-000418', 'GK-9860-C7FD6E-GK-KARDUS-000418', '3000-9860-Tjong li mi merina', 'GK-9860-C7FD6E', 'GUDANG AMI', '2026-05-04 08:17:00+07', '2026-05-04 08:17:00+07', 'Import GudangKu kardus; client_id=418; label=3000-9860-Tjong li mi merina; nomor_pesanan=3000; nomor_id=9860; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ce61a475-4cc1-3b68-a68c-e6cb90f561a9', 'GK-KARDUS-000420', 'GK-1372-986689-GK-KARDUS-000420', '7800-1372-PHILIPS ANITA PHILIPS FREIZENZ LOKWATY', 'GK-1372-986689', 'GUDANG ANITA', '2026-05-04 08:19:00+07', '2026-05-04 08:19:00+07', 'Import GudangKu kardus; client_id=420; label=7800-1372-PHILIPS ANITA PHILIPS FREIZENZ LOKWATY; nomor_pesanan=7800; nomor_id=1372; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('63b19c50-36fa-3207-a60b-8d4ac2654499', 'GK-KARDUS-000421', 'GK-2054-22DE0E-GK-KARDUS-000421', '8300-2054-Neng karan T. Nunu Nuhdini', 'GK-2054-22DE0E', 'GUDANG NENG', '2026-05-04 08:20:00+07', '2026-05-04 08:20:00+07', 'Import GudangKu kardus; client_id=421; label=8300-2054-Neng karan T. Nunu Nuhdini; nomor_pesanan=8300; nomor_id=2054; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('94f19102-4425-37f6-8419-9e9ed69ae30e', 'GK-KARDUS-000422', 'GK-7781-E459CE-GK-KARDUS-000422', '6900-7781-Neng kanan T Papua widi', 'GK-7781-E459CE', 'GUDANG NENG', '2026-05-04 08:21:00+07', '2026-05-04 08:21:00+07', 'Import GudangKu kardus; client_id=422; label=6900-7781-Neng kanan T Papua widi; nomor_pesanan=6900; nomor_id=7781; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('dea470bb-99ea-372f-ad78-645d0b04f31b', 'GK-KARDUS-000423', 'GK-1667-B307BE-GK-KARDUS-000423', '7300-1667-Neng Kanan T. Nining Yuningsih.', 'GK-1667-B307BE', 'GUDANG NENG', '2026-05-04 08:24:00+07', '2026-05-04 08:24:00+07', 'Import GudangKu kardus; client_id=423; label=7300-1667-Neng Kanan T. Nining Yuningsih.; nomor_pesanan=7300; nomor_id=1667; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('45dc7a52-61e1-3175-8996-42c1bc942254', 'GK-KARDUS-000424', 'GK-2615-A60B0C-GK-KARDUS-000424', '8300-2615-NENG KANAN T PAPUA ROSMA ROSTIKA', 'GK-2615-A60B0C', 'GUDANG NENG', '2026-05-04 08:24:00+07', '2026-05-04 08:24:00+07', 'Import GudangKu kardus; client_id=424; label=8300-2615-NENG KANAN T PAPUA ROSMA ROSTIKA; nomor_pesanan=8300; nomor_id=2615; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('81e6161b-91cc-33ca-b0df-ae8389a49157', 'GK-KARDUS-000426', 'GK-0465-1D80E2-GK-KARDUS-000426', '6500-0465-Neng Kanan T. Riki suswanto', 'GK-0465-1D80E2', 'GUDANG NENG', '2026-05-04 08:27:00+07', '2026-05-04 08:27:00+07', 'Import GudangKu kardus; client_id=426; label=6500-0465-Neng Kanan T. Riki suswanto; nomor_pesanan=6500; nomor_id=0465; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('cf87b1c9-3dfe-351e-b764-6a93811b6dec', 'GK-KARDUS-000428', 'GK-2624-D80061-GK-KARDUS-000428', '4500-2624-AGIL KIRANA WIFA AGIL KIRANA', 'GK-2624-D80061', 'GUDANG WIFA', '2026-05-04 08:28:00+07', '2026-05-04 08:28:00+07', 'Import GudangKu kardus; client_id=428; label=4500-2624-AGIL KIRANA WIFA AGIL KIRANA; nomor_pesanan=4500; nomor_id=2624; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('e308541d-fa05-3f7c-8c40-9ad085884d90', 'GK-KARDUS-000429', 'GK-2152-DAB7E1-GK-KARDUS-000429', '6500-2152-Fajar Permatasari T. WIFA', 'GK-2152-DAB7E1', 'GUDANG WIFA', '2026-05-04 08:29:00+07', '2026-05-04 08:29:00+07', 'Import GudangKu kardus; client_id=429; label=6500-2152-Fajar Permatasari T. WIFA; nomor_pesanan=6500; nomor_id=2152; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('c1522435-cebd-3499-8147-2925e8044e7f', 'GK-KARDUS-000430', 'GK-0880-57C704-GK-KARDUS-000430', '8700-0880-M DAME ANITA DAME SIHOMBING', 'GK-0880-57C704', 'GUDANG ANITA', '2026-05-04 08:30:00+07', '2026-05-04 08:30:00+07', 'Import GudangKu kardus; client_id=430; label=8700-0880-M DAME ANITA DAME SIHOMBING; nomor_pesanan=8700; nomor_id=0880; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('e4524a12-fffc-34eb-be2b-916516cabf03', 'GK-KARDUS-000431', 'GK-7625-9E9B86-GK-KARDUS-000431', '4800-7625-Neng kanan T Papua wili Saputra', 'GK-7625-9E9B86', 'GUDANG NENG', '2026-05-04 08:30:00+07', '2026-05-04 08:30:00+07', 'Import GudangKu kardus; client_id=431; label=4800-7625-Neng kanan T Papua wili Saputra; nomor_pesanan=4800; nomor_id=7625; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('8968b154-c964-3112-b20b-b250a33207df', 'GK-KARDUS-000432', 'GK-1027-2B1634-GK-KARDUS-000432', '2800-1027-Neng Kanan T. Marjono', 'GK-1027-2B1634', 'GUDANG NENG', '2026-05-04 08:31:00+07', '2026-05-04 08:31:00+07', 'Import GudangKu kardus; client_id=432; label=2800-1027-Neng Kanan T. Marjono; nomor_pesanan=2800; nomor_id=1027; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ef9c0a8b-b8b7-3bf8-9251-abdcb630ce79', 'GK-KARDUS-000433', 'GK-5119-2ED76E-GK-KARDUS-000433', '6913-5119-Tjoy li mi Agus tinus Ojara', 'GK-5119-2ED76E', 'GUDANG AMI', '2026-05-04 08:33:00+07', '2026-05-04 08:33:00+07', 'Import GudangKu kardus; client_id=433; label=6913-5119-Tjoy li mi Agus tinus Ojara; nomor_pesanan=6913; nomor_id=5119; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('01e35602-5678-3d97-9370-1a1e833ee803', 'GK-KARDUS-000434', 'GK-2405-C0A53A-GK-KARDUS-000434', '1900-2405-Neng Kanan T. asum sumiati', 'GK-2405-C0A53A', 'GUDANG NENG', '2026-05-04 08:33:00+07', '2026-05-04 08:33:00+07', 'Import GudangKu kardus; client_id=434; label=1900-2405-Neng Kanan T. asum sumiati; nomor_pesanan=1900; nomor_id=2405; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('3a708855-e324-30dd-9a40-def91a195a61', 'GK-KARDUS-000435', 'GK-0784-BC9519-GK-KARDUS-000435', '0220-0784-raisha afra sakila t wifa raisha afra sakila', 'GK-0784-BC9519', 'GUDANG WIFA', '2026-05-04 08:34:00+07', '2026-05-04 08:34:00+07', 'Import GudangKu kardus; client_id=435; label=0220-0784-raisha afra sakila t wifa raisha afra sakila; nomor_pesanan=0220; nomor_id=0784; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('cf047e36-21f5-3258-b5c5-1f7b76f08f17', 'GK-KARDUS-000436', 'GK-0231-BB6BD3-GK-KARDUS-000436', '2800-0231-christal geraldine wifa christal geraldine kirsten', 'GK-0231-BB6BD3', 'GUDANG WIFA', '2026-05-04 08:37:00+07', '2026-05-04 08:37:00+07', 'Import GudangKu kardus; client_id=436; label=2800-0231-christal geraldine wifa christal geraldine kirsten; nomor_pesanan=2800; nomor_id=0231; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('c90cf041-2cdf-3ab7-9261-456e029d4d3a', 'GK-KARDUS-000437', 'GK-2304-827CDD-GK-KARDUS-000437', '0100-2304-doni anita doni setia', 'GK-2304-827CDD', 'GUDANG ANITA', '2026-05-04 08:40:00+07', '2026-05-04 08:40:00+07', 'Import GudangKu kardus; client_id=437; label=0100-2304-doni anita doni setia; nomor_pesanan=0100; nomor_id=2304; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('b5f096e3-4d29-33ea-8fdd-14ec53c32b9a', 'GK-KARDUS-000441', 'GK-2171-DB0466-GK-KARDUS-000441', '3700-2171-Neng Kanan T.Irfan', 'GK-2171-DB0466', 'GUDANG NENG', '2026-05-04 08:43:00+07', '2026-05-04 08:43:00+07', 'Import GudangKu kardus; client_id=441; label=3700-2171-Neng Kanan T.Irfan; nomor_pesanan=3700; nomor_id=2171; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('3ebfbaf2-ec54-3daa-8808-530b3207d35a', 'GK-KARDUS-000442', 'GK-9805-A34010-GK-KARDUS-000442', '9000-9805-Yoga Anita yoga bagus', 'GK-9805-A34010', 'GUDANG ANITA', '2026-05-04 08:44:00+07', '2026-05-04 08:44:00+07', 'Import GudangKu kardus; client_id=442; label=9000-9805-Yoga Anita yoga bagus; nomor_pesanan=9000; nomor_id=9805; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('155ac316-6dec-35df-bef9-08ae025e41b8', 'GK-KARDUS-000447', 'GK-7629-D1182F-GK-KARDUS-000447', '8200-7629-neng kanan t papua rajan akbar', 'GK-7629-D1182F', 'GUDANG NENG', '2026-05-04 08:48:00+07', '2026-05-04 08:48:00+07', 'Import GudangKu kardus; client_id=447; label=8200-7629-neng kanan t papua rajan akbar; nomor_pesanan=8200; nomor_id=7629; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('759cce3d-bc86-3513-a020-2063f7dc2c95', 'GK-KARDUS-000449', 'GK-1550-390A1D-GK-KARDUS-000449', '7600-1550-Setepen T. Dadang kanan', 'GK-1550-390A1D', 'GUDANG RANDOM', '2026-05-04 08:52:00+07', '2026-05-04 08:52:00+07', 'Import GudangKu kardus; client_id=449; label=7600-1550-Setepen T. Dadang kanan; nomor_pesanan=7600; nomor_id=1550; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('1b012903-40a8-3039-9610-e2bcaf712c09', 'GK-KARDUS-000450', 'GK-7619-0D0A77-GK-KARDUS-000450', '8700-7619-Neng kanan T papua muhamad Riyas', 'GK-7619-0D0A77', 'GUDANG NENG', '2026-05-04 08:52:00+07', '2026-05-04 08:52:00+07', 'Import GudangKu kardus; client_id=450; label=8700-7619-Neng kanan T papua muhamad Riyas; nomor_pesanan=8700; nomor_id=7619; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('c7a8e32f-5f21-30c6-b13f-58d25e9d4964', 'GK-KARDUS-000451', 'GK-7798-7F03A6-GK-KARDUS-000451', '2300-7798-NenG kanan I papua Lalita Surlina', 'GK-7798-7F03A6', 'GUDANG NENG', '2026-05-04 08:54:00+07', '2026-05-04 08:54:00+07', 'Import GudangKu kardus; client_id=451; label=2300-7798-NenG kanan I papua Lalita Surlina; nomor_pesanan=2300; nomor_id=7798; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('b3967ac8-efef-33b6-83a2-122d1897a11b', 'GK-KARDUS-000452', 'GK-1646-2F6079-GK-KARDUS-000452', '7700-1646-Oki Seatiwan T. Raisa', 'GK-1646-2F6079', 'GUDANG RANDOM', '2026-05-04 08:57:00+07', '2026-05-04 08:57:00+07', 'Import GudangKu kardus; client_id=452; label=7700-1646-Oki Seatiwan T. Raisa; nomor_pesanan=7700; nomor_id=1646; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('d276d84c-bb58-372a-b228-85ff3506087f', 'GK-KARDUS-000454', 'GK-0047-7A20E6-GK-KARDUS-000454', '3600-0047-tina mariana dm tina', 'GK-0047-7A20E6', 'GUDANG RANDOM', '2026-05-04 08:58:00+07', '2026-05-04 08:58:00+07', 'Import GudangKu kardus; client_id=454; label=3600-0047-tina mariana dm tina; nomor_pesanan=3600; nomor_id=0047; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('4b0cb184-3baa-3d45-97e8-101afa76f7b8', 'GK-KARDUS-000456', 'GK-2509-53AD0E-GK-KARDUS-000456', '5700-2509-Neng Kanan T. ABDUL ADID', 'GK-2509-53AD0E', 'GUDANG NENG', '2026-05-04 09:00:00+07', '2026-05-04 09:00:00+07', 'Import GudangKu kardus; client_id=456; label=5700-2509-Neng Kanan T. ABDUL ADID; nomor_pesanan=5700; nomor_id=2509; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('89e24a0f-bfc7-3286-b1f9-eb91e84fcc3b', 'GK-KARDUS-000458', 'GK-2338-664744-GK-KARDUS-000458', '7600-2338-Yuyun Jiman T Martha', 'GK-2338-664744', 'GUDANG MARTHA', '2026-05-04 09:04:00+07', '2026-05-04 09:04:00+07', 'Import GudangKu kardus; client_id=458; label=7600-2338-Yuyun Jiman T Martha; nomor_pesanan=7600; nomor_id=2338; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('3c68703d-4bfc-3dd1-a9dd-98aff2773b6d', 'GK-KARDUS-000460', 'GK-7592-73ED16-GK-KARDUS-000460', '0400-7592-Neng kanan T Papua Nita Lingga citra', 'GK-7592-73ED16', 'GUDANG NENG', '2026-05-04 09:07:00+07', '2026-05-04 09:07:00+07', 'Import GudangKu kardus; client_id=460; label=0400-7592-Neng kanan T Papua Nita Lingga citra; nomor_pesanan=0400; nomor_id=7592; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('7d254c57-bc98-36e8-92fb-d2aa83c4abce', 'GK-KARDUS-000461', 'GK-1238-F68631-GK-KARDUS-000461', '7300-1238-neng kanan t papua hotmaria sinaga', 'GK-1238-F68631', 'GUDANG NENG', '2026-05-04 09:08:00+07', '2026-05-04 09:08:00+07', 'Import GudangKu kardus; client_id=461; label=7300-1238-neng kanan t papua hotmaria sinaga; nomor_pesanan=7300; nomor_id=1238; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('5ff82a8a-739f-3f16-b1af-719aa545f4af', 'GK-KARDUS-000462', 'GK-2576-BF59D2-GK-KARDUS-000462', '4900-2576-Tomy Effendy Sm T. Raisha', 'GK-2576-BF59D2', 'GUDANG RANDOM', '2026-05-04 09:08:00+07', '2026-05-04 09:08:00+07', 'Import GudangKu kardus; client_id=462; label=4900-2576-Tomy Effendy Sm T. Raisha; nomor_pesanan=4900; nomor_id=2576; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('db371a33-8274-36e2-824c-5c0c0a3544ba', 'GK-KARDUS-000463', 'GK-1556-72B5E8-GK-KARDUS-000463', '5400-1556-Neng kanan T. Novie Masayu', 'GK-1556-72B5E8', 'GUDANG NENG', '2026-05-04 09:09:00+07', '2026-05-04 09:09:00+07', 'Import GudangKu kardus; client_id=463; label=5400-1556-Neng kanan T. Novie Masayu; nomor_pesanan=5400; nomor_id=1556; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('b5e455f6-dd96-33fb-ab5f-f9659594ba2c', 'GK-KARDUS-000464', 'GK-1093-945980-GK-KARDUS-000464', '4200-1093-Ami T. Ichsan yarmi', 'GK-1093-945980', 'GUDANG AMI', '2026-05-04 09:10:00+07', '2026-05-04 09:10:00+07', 'Import GudangKu kardus; client_id=464; label=4200-1093-Ami T. Ichsan yarmi; nomor_pesanan=4200; nomor_id=1093; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f4c8d714-5012-36c7-85be-1f1435f063e7', 'GK-KARDUS-000466', 'GK-2560-459DD3-GK-KARDUS-000466', '4200-2560-neng kanan t papua widya vania', 'GK-2560-459DD3', 'GUDANG NENG', '2026-05-04 09:12:00+07', '2026-05-04 09:12:00+07', 'Import GudangKu kardus; client_id=466; label=4200-2560-neng kanan t papua widya vania; nomor_pesanan=4200; nomor_id=2560; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('3a8d8a12-3b23-3e3d-a856-dd516975fb99', 'GK-KARDUS-000467', 'GK-5095-449698-GK-KARDUS-000467', '5800-5095-Tjong li mi niken lestari', 'GK-5095-449698', 'GUDANG AMI', '2026-05-04 09:12:00+07', '2026-05-04 09:12:00+07', 'Import GudangKu kardus; client_id=467; label=5800-5095-Tjong li mi niken lestari; nomor_pesanan=5800; nomor_id=5095; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('7d24c0de-1e2a-354b-9df5-1afed6b1bfc4', 'GK-KARDUS-000469', 'GK-8176-8A03D1-GK-KARDUS-000469', '0900-8176-edi anita edi saptono', 'GK-8176-8A03D1', 'GUDANG ANITA', '2026-05-04 09:14:00+07', '2026-05-04 09:14:00+07', 'Import GudangKu kardus; client_id=469; label=0900-8176-edi anita edi saptono; nomor_pesanan=0900; nomor_id=8176; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('0b6ccd8b-dd0f-3d7c-9421-30b2da6abf82', 'GK-KARDUS-000470', 'GK-7496-C42014-GK-KARDUS-000470', '5600-7496-Neng kanan T Papua niko Lius', 'GK-7496-C42014', 'GUDANG NENG', '2026-05-04 09:15:00+07', '2026-05-04 09:15:00+07', 'Import GudangKu kardus; client_id=470; label=5600-7496-Neng kanan T Papua niko Lius; nomor_pesanan=5600; nomor_id=7496; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('16ab72f1-55b5-3b3a-b91c-7e6a9b5dcbcc', 'GK-KARDUS-000471', 'GK-9934-FE0501-GK-KARDUS-000471', '0200-9934-neng kanan t papua ujang mansur', 'GK-9934-FE0501', 'GUDANG NENG', '2026-05-04 09:17:00+07', '2026-05-04 09:17:00+07', 'Import GudangKu kardus; client_id=471; label=0200-9934-neng kanan t papua ujang mansur; nomor_pesanan=0200; nomor_id=9934; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('6212cbc2-b20b-3ad6-9392-097f15e7f6d7', 'GK-KARDUS-000472', 'GK-0260-B71C7A-GK-KARDUS-000472', '0200-0260-Putri Maheshwara Kanan Dadang', 'GK-0260-B71C7A', 'GUDANG RANDOM', '2026-05-04 09:17:00+07', '2026-05-04 09:17:00+07', 'Import GudangKu kardus; client_id=472; label=0200-0260-Putri Maheshwara Kanan Dadang; nomor_pesanan=0200; nomor_id=0260; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('49ac38a9-a69a-332a-b993-ad320f0368b6', 'GK-KARDUS-000475', 'GK-1264-87C613-GK-KARDUS-000475', '1800-1264-Neng Kanan T Papua Abel Putri', 'GK-1264-87C613', 'GUDANG NENG', '2026-05-04 09:20:00+07', '2026-05-04 09:20:00+07', 'Import GudangKu kardus; client_id=475; label=1800-1264-Neng Kanan T Papua Abel Putri; nomor_pesanan=1800; nomor_id=1264; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('2e67d47b-ffc4-31e1-a768-26a7a9547c05', 'GK-KARDUS-000477', 'GK-1154-061A85-GK-KARDUS-000477', '5100-1154-Neng Kanan T. Kartika', 'GK-1154-061A85', 'GUDANG NENG', '2026-05-04 09:21:00+07', '2026-05-04 09:21:00+07', 'Import GudangKu kardus; client_id=477; label=5100-1154-Neng Kanan T. Kartika; nomor_pesanan=5100; nomor_id=1154; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('97cbc9cf-a419-3622-8624-4724bcf3fa18', 'GK-KARDUS-000478', 'GK-2332-81457D-GK-KARDUS-000478', '6300-2332-Neng Kanan T. Parva Fika Andira', 'GK-2332-81457D', 'GUDANG NENG', '2026-05-04 09:22:00+07', '2026-05-04 09:22:00+07', 'Import GudangKu kardus; client_id=478; label=6300-2332-Neng Kanan T. Parva Fika Andira; nomor_pesanan=6300; nomor_id=2332; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('9ac9d2cc-ea68-3442-a965-1a53da72c76d', 'GK-KARDUS-000481', 'GK-1233-DADA95-GK-KARDUS-000481', '3000-1233-Neng Kanan T Papua Afika Andika', 'GK-1233-DADA95', 'GUDANG NENG', '2026-05-04 09:24:00+07', '2026-05-04 09:24:00+07', 'Import GudangKu kardus; client_id=481; label=3000-1233-Neng Kanan T Papua Afika Andika; nomor_pesanan=3000; nomor_id=1233; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('b787ccf3-fe03-3dd0-a25f-b7f98aa62293', 'GK-KARDUS-000482', 'GK-0732-DBC479-GK-KARDUS-000482', '3800-0732-Puput Kembang Wifa', 'GK-0732-DBC479', 'GUDANG WIFA', '2026-05-04 09:26:00+07', '2026-05-04 09:26:00+07', 'Import GudangKu kardus; client_id=482; label=3800-0732-Puput Kembang Wifa; nomor_pesanan=3800; nomor_id=0732; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('5fd8b4f5-4b7b-30cc-ad57-232b321451d6', 'GK-KARDUS-000483', 'GK-7401-FC54D6-GK-KARDUS-000483', '9900-7401-Adriana Team Rina', 'GK-7401-FC54D6', 'GUDANG RINA', '2026-05-04 09:26:00+07', '2026-05-04 09:26:00+07', 'Import GudangKu kardus; client_id=483; label=9900-7401-Adriana Team Rina; nomor_pesanan=9900; nomor_id=7401; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('5a7ad0fb-a669-325d-a145-adf49480fb78', 'GK-KARDUS-000484', 'GK-2342-45E920-GK-KARDUS-000484', '3000-2342-Nurul Anita Khotimah', 'GK-2342-45E920', 'GUDANG ANITA', '2026-05-04 09:28:00+07', '2026-05-04 09:28:00+07', 'Import GudangKu kardus; client_id=484; label=3000-2342-Nurul Anita Khotimah; nomor_pesanan=3000; nomor_id=2342; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('00a6a7e8-71c6-38f7-bac0-5a35c4afc12b', 'GK-KARDUS-000485', 'GK-8456-E73EE7-GK-KARDUS-000485', '6400-8456-Yani Anita Yaniingsi', 'GK-8456-E73EE7', 'GUDANG ANITA', '2026-05-04 09:31:00+07', '2026-05-04 09:31:00+07', 'Import GudangKu kardus; client_id=485; label=6400-8456-Yani Anita Yaniingsi; nomor_pesanan=6400; nomor_id=8456; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('c2e3bfc9-5b6d-371a-bb8f-ff7454820eb1', 'GK-KARDUS-000486', 'GK-0079-D9F943-GK-KARDUS-000486', '0200-0079-dian anita dian', 'GK-0079-D9F943', 'GUDANG ANITA', '2026-05-04 09:32:00+07', '2026-05-04 09:32:00+07', 'Import GudangKu kardus; client_id=486; label=0200-0079-dian anita dian; nomor_pesanan=0200; nomor_id=0079; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('a9ee30d2-0913-37f5-b0af-25c60182fdd7', 'GK-KARDUS-000487', 'GK-1406-8010E5-GK-KARDUS-000487', '8600-1406-Neng Kanan T Papua Ilham Purnama', 'GK-1406-8010E5', 'GUDANG NENG', '2026-05-04 09:32:00+07', '2026-05-04 09:32:00+07', 'Import GudangKu kardus; client_id=487; label=8600-1406-Neng Kanan T Papua Ilham Purnama; nomor_pesanan=8600; nomor_id=1406; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('65359d2a-e65d-345f-be48-ea0d2f0b381b', 'GK-KARDUS-000489', 'GK-9849-61C56A-GK-KARDUS-000489', '6100-9849-Neng kanan T papua Syaifullah hidayat', 'GK-9849-61C56A', 'GUDANG NENG', '2026-05-04 09:35:00+07', '2026-05-04 09:35:00+07', 'Import GudangKu kardus; client_id=489; label=6100-9849-Neng kanan T papua Syaifullah hidayat; nomor_pesanan=6100; nomor_id=9849; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f34706cc-ac1f-3acd-be34-31f713582d56', 'GK-KARDUS-000490', 'GK-0791-07A182-GK-KARDUS-000490', '4200-0791-Neng kanan T. Papuakharisma Palupi', 'GK-0791-07A182', 'GUDANG NENG', '2026-05-04 09:36:00+07', '2026-05-04 09:36:00+07', 'Import GudangKu kardus; client_id=490; label=4200-0791-Neng kanan T. Papuakharisma Palupi; nomor_pesanan=4200; nomor_id=0791; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('288d12a0-7dab-30d7-98ac-7c8564f15891', 'GK-KARDUS-000491', 'GK-2520-78C1FF-GK-KARDUS-000491', '5000-2520-neng kanan t papua juliana', 'GK-2520-78C1FF', 'GUDANG ANITA', '2026-05-04 09:38:00+07', '2026-05-04 09:38:00+07', 'Import GudangKu kardus; client_id=491; label=5000-2520-neng kanan t papua juliana; nomor_pesanan=5000; nomor_id=2520; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('bb2ac860-7d0d-3a3f-805e-a7809e9e4164', 'GK-KARDUS-000492', 'GK-1586-468B25-GK-KARDUS-000492', '0600-1586-Neng kanan T. Yati', 'GK-1586-468B25', 'GUDANG NENG', '2026-05-04 09:38:00+07', '2026-05-04 09:38:00+07', 'Import GudangKu kardus; client_id=492; label=0600-1586-Neng kanan T. Yati; nomor_pesanan=0600; nomor_id=1586; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('37fc12e9-92a7-3bf4-a455-1f3e407509cb', 'GK-KARDUS-000493', 'GK-9743-1EC964-GK-KARDUS-000493', '5900-9743-Farhan Anita Farhan maulana', 'GK-9743-1EC964', 'GUDANG ANITA', '2026-05-04 09:39:00+07', '2026-05-04 09:39:00+07', 'Import GudangKu kardus; client_id=493; label=5900-9743-Farhan Anita Farhan maulana; nomor_pesanan=5900; nomor_id=9743; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('6f5832c0-6ebc-3646-a3fa-a29ece16fe93', 'GK-KARDUS-000494', 'GK-0037-C6DC16-GK-KARDUS-000494', '1900-0037-neng kanan t papua tatan', 'GK-0037-C6DC16', 'GUDANG NENG', '2026-05-04 09:40:00+07', '2026-05-04 09:40:00+07', 'Import GudangKu kardus; client_id=494; label=1900-0037-neng kanan t papua tatan; nomor_pesanan=1900; nomor_id=0037; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('45aa0953-42cd-3b8c-a9e8-660246094769', 'GK-KARDUS-000495', 'GK-2600-09E172-GK-KARDUS-000495', '2900-2600-Neng Kanan T. Ammar Kholid', 'GK-2600-09E172', 'GUDANG NENG', '2026-05-04 09:40:00+07', '2026-05-04 09:40:00+07', 'Import GudangKu kardus; client_id=495; label=2900-2600-Neng Kanan T. Ammar Kholid; nomor_pesanan=2900; nomor_id=2600; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('882b0a65-7f04-3e80-878e-2dd51a38cc10', 'GK-KARDUS-000496', 'GK-7630-71FB01-GK-KARDUS-000496', '9500-7630-Mirna team rina mirna sumindar', 'GK-7630-71FB01', 'GUDANG RINA', '2026-05-04 09:41:00+07', '2026-05-04 09:41:00+07', 'Import GudangKu kardus; client_id=496; label=9500-7630-Mirna team rina mirna sumindar; nomor_pesanan=9500; nomor_id=7630; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('e80a070a-aa03-3dc1-9a69-121cc06b357b', 'GK-KARDUS-000498', 'GK-8195-7FF8A5-GK-KARDUS-000498', '7200-8195-boima silalahi t mawarni boima silalahi', 'GK-8195-7FF8A5', 'GUDANG MAWARNI', '2026-05-04 09:45:00+07', '2026-05-04 09:45:00+07', 'Import GudangKu kardus; client_id=498; label=7200-8195-boima silalahi t mawarni boima silalahi; nomor_pesanan=7200; nomor_id=8195; type=Titipan; created_by=Admin; updated_by=Admin; duplicate_client_id_rows=498|499'),
  ('16c8191a-c294-3339-b77b-93f6e2618d89', 'GK-KARDUS-000499', 'GK-1940-137196-GK-KARDUS-000499', '9700-1940-Wilson by Ami Frendy Butar', 'GK-1940-137196', 'GUDANG AMI', '2026-05-04 09:46:00+07', '2026-05-04 09:46:00+07', 'Import GudangKu kardus; client_id=499; label=9700-1940-Wilson by Ami Frendy Butar; nomor_pesanan=9700; nomor_id=1940; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('b32365c9-1a05-36fa-b7aa-b2d85324fecd', 'GK-KARDUS-000500', 'GK-1382-0D0A77-GK-KARDUS-000500', '9100-1382-Neng kanan T papua muhamad Riyas', 'GK-1382-0D0A77', 'GUDANG NENG', '2026-05-04 09:48:00+07', '2026-05-04 09:48:00+07', 'Import GudangKu kardus; client_id=500; label=9100-1382-Neng kanan T papua muhamad Riyas; nomor_pesanan=9100; nomor_id=1382; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('bc44c85c-f1dc-37ab-a2d6-58153634a8ed', 'GK-KARDUS-000501', 'GK-1088-E485B5-GK-KARDUS-000501', '0200-1088-Gerad firmansya Kanan Dadang', 'GK-1088-E485B5', 'GUDANG RANDOM', '2026-05-04 09:48:00+07', '2026-05-04 09:48:00+07', 'Import GudangKu kardus; client_id=501; label=0200-1088-Gerad firmansya Kanan Dadang; nomor_pesanan=0200; nomor_id=1088; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('2c4a0b6f-bdbf-3e26-a5d4-5a9dfa33e511', 'GK-KARDUS-000503', 'GK-7849-7C8F69-GK-KARDUS-000503', '9700-7849-wulan anita wulan', 'GK-7849-7C8F69', 'GUDANG ANITA', '2026-05-04 09:52:00+07', '2026-05-04 09:52:00+07', 'Import GudangKu kardus; client_id=503; label=9700-7849-wulan anita wulan; nomor_pesanan=9700; nomor_id=7849; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('2a56c702-0b60-3293-91f2-dfccee86fc31', 'GK-KARDUS-000504', 'GK-2139-2B1634-GK-KARDUS-000504', '8500-2139-Neng kanan T. Marjono', 'GK-2139-2B1634', 'GUDANG NENG', '2026-05-04 09:53:00+07', '2026-05-04 09:53:00+07', 'Import GudangKu kardus; client_id=504; label=8500-2139-Neng kanan T. Marjono; nomor_pesanan=8500; nomor_id=2139; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('022b4161-43c1-320e-8da3-babf724b4cc2', 'GK-KARDUS-000505', 'GK-2535-0ED9BF-GK-KARDUS-000505', '6900-2535-LIDIA Team Rinalidia', 'GK-2535-0ED9BF', 'GUDANG RINA', '2026-05-04 09:54:00+07', '2026-05-04 09:54:00+07', 'Import GudangKu kardus; client_id=505; label=6900-2535-LIDIA Team Rinalidia; nomor_pesanan=6900; nomor_id=2535; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ac1ff343-fe9a-3685-bdfd-591efb5b616c', 'GK-KARDUS-000508', 'GK-8890-E34860-GK-KARDUS-000508', '9200-8890-Fahmi Anitafahmi', 'GK-8890-E34860', 'GUDANG ANITA', '2026-05-04 09:56:00+07', '2026-05-04 09:56:00+07', 'Import GudangKu kardus; client_id=508; label=9200-8890-Fahmi Anitafahmi; nomor_pesanan=9200; nomor_id=8890; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('9154fcee-7cb4-3a1b-8a50-69305754df6a', 'GK-KARDUS-000510', 'GK-7576-F9584E-GK-KARDUS-000510', '7900-7576-Meti Anita meti Delsi', 'GK-7576-F9584E', 'GUDANG ANITA', '2026-05-04 09:58:00+07', '2026-05-04 09:58:00+07', 'Import GudangKu kardus; client_id=510; label=7900-7576-Meti Anita meti Delsi; nomor_pesanan=7900; nomor_id=7576; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('81705624-c785-3cf7-9fc1-7d254059a055', 'GK-KARDUS-000511', 'GK-0301-DB4C10-GK-KARDUS-000511', '2700-0301-Neng Kanan T. Papua IHSAN IFTIKAR', 'GK-0301-DB4C10', 'GUDANG NENG', '2026-05-04 10:00:00+07', '2026-05-04 10:00:00+07', 'Import GudangKu kardus; client_id=511; label=2700-0301-Neng Kanan T. Papua IHSAN IFTIKAR; nomor_pesanan=2700; nomor_id=0301; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('3575021b-7f71-3859-a1d0-23e099d8f847', 'GK-KARDUS-000512', 'GK-1594-4E9B17-GK-KARDUS-000512', '1600-1594-juliyana team rina puji lestar', 'GK-1594-4E9B17', 'GUDANG RINA', '2026-05-04 10:00:00+07', '2026-05-04 10:00:00+07', 'Import GudangKu kardus; client_id=512; label=1600-1594-juliyana team rina puji lestar; nomor_pesanan=1600; nomor_id=1594; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('4fa58d15-ef79-373c-9a3f-ee813f612bfc', 'GK-KARDUS-000513', 'GK-1863-5D2EAE-GK-KARDUS-000513', '4000-1863-samsul anita samsul sumitarya', 'GK-1863-5D2EAE', 'GUDANG ANITA', '2026-05-04 10:09:00+07', '2026-05-04 10:09:00+07', 'Import GudangKu kardus; client_id=513; label=4000-1863-samsul anita samsul sumitarya; nomor_pesanan=4000; nomor_id=1863; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('5a321acf-39e5-36f6-8b51-d0d190f75e91', 'GK-KARDUS-000514', 'GK-0735-7800C6-GK-KARDUS-000514', '8100-0735-neng kanan t papua heri kuswanto', 'GK-0735-7800C6', 'GUDANG NENG', '2026-05-04 10:13:00+07', '2026-05-04 10:13:00+07', 'Import GudangKu kardus; client_id=514; label=8100-0735-neng kanan t papua heri kuswanto; nomor_pesanan=8100; nomor_id=0735; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('412cc89f-6700-3f43-a973-48d3f2d97e05', 'GK-KARDUS-000515', 'GK-1190-49CF88-GK-KARDUS-000515', '9900-1190-juliyana team rina julyana nainggolan', 'GK-1190-49CF88', 'GUDANG RINA', '2026-05-04 10:15:00+07', '2026-05-04 10:15:00+07', 'Import GudangKu kardus; client_id=515; label=9900-1190-juliyana team rina julyana nainggolan; nomor_pesanan=9900; nomor_id=1190; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('e019f649-72ce-370e-a7e4-0ad917f22f83', 'GK-KARDUS-000516', 'GK-2668-E0A1EC-GK-KARDUS-000516', '2300-2668-Neng Kanan T. PAPUA AQILA', 'GK-2668-E0A1EC', 'GUDANG ANITA', '2026-05-05 08:42:00+07', '2026-05-05 08:42:00+07', 'Import GudangKu kardus; client_id=516; label=2300-2668-Neng Kanan T. PAPUA AQILA; nomor_pesanan=2300; nomor_id=2668; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('046cc682-5449-3d10-92d3-2ce914bcb24b', 'GK-KARDUS-000517', 'GK-8497-CDBEAA-GK-KARDUS-000517', '8000-8497-Deni Anita Deni', 'GK-8497-CDBEAA', 'GUDANG ANITA', '2026-05-05 08:44:00+07', '2026-05-05 08:44:00+07', 'Import GudangKu kardus; client_id=517; label=8000-8497-Deni Anita Deni; nomor_pesanan=8000; nomor_id=8497; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('8a12dc35-1569-3e03-90f3-2b89e1003a73', 'GK-KARDUS-000518', 'GK-2199-FE0501-GK-KARDUS-000518', '4600-2199-Neng Kanan T Papua Ujang Mansur', 'GK-2199-FE0501', 'GUDANG NENG', '2026-05-05 08:46:00+07', '2026-05-05 08:46:00+07', 'Import GudangKu kardus; client_id=518; label=4600-2199-Neng Kanan T Papua Ujang Mansur; nomor_pesanan=4600; nomor_id=2199; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('0795faba-504f-3918-ba16-202183f2bbab', 'GK-KARDUS-000519', 'GK-0786-CC5671-GK-KARDUS-000519', '9000-0786-Neng Kanan T. Papua Daniah', 'GK-0786-CC5671', 'GUDANG NENG', '2026-05-05 08:49:00+07', '2026-05-05 08:49:00+07', 'Import GudangKu kardus; client_id=519; label=9000-0786-Neng Kanan T. Papua Daniah; nomor_pesanan=9000; nomor_id=0786; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('1043e3ad-9900-3651-a1d9-46f1d6797ac4', 'GK-KARDUS-000520', 'GK-0639-7C0426-GK-KARDUS-000520', '4500-0639-Neng kanan T. Papua Darrel Lingga', 'GK-0639-7C0426', 'GUDANG NENG', '2026-05-05 08:50:00+07', '2026-05-05 08:50:00+07', 'Import GudangKu kardus; client_id=520; label=4500-0639-Neng kanan T. Papua Darrel Lingga; nomor_pesanan=4500; nomor_id=0639; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('cbfa350a-2ad0-3ced-9d5b-a37660bf7a94', 'GK-KARDUS-000521', 'GK-1381-01E92F-GK-KARDUS-000521', '7600-1381-Nengkanan T. Papua Darrel', 'GK-1381-01E92F', 'GUDANG NENG', '2026-05-05 08:51:00+07', '2026-05-05 08:51:00+07', 'Import GudangKu kardus; client_id=521; label=7600-1381-Nengkanan T. Papua Darrel; nomor_pesanan=7600; nomor_id=1381; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('6802fe20-f0b3-30f8-8dd9-e5e1220a3b46', 'GK-KARDUS-000523', 'GK-1852-8E6843-GK-KARDUS-000523', '7400-1852-Neng kanan T. Widya Vania', 'GK-1852-8E6843', 'GUDANG NENG', '2026-05-05 08:59:00+07', '2026-05-05 08:59:00+07', 'Import GudangKu kardus; client_id=523; label=7400-1852-Neng kanan T. Widya Vania; nomor_pesanan=7400; nomor_id=1852; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('a43a5fd2-7f01-3a52-8e8e-c63d9bb5d85e', 'GK-KARDUS-000524', 'GK-0906-4ECA0F-GK-KARDUS-000524', '9600-0906-Neng kanan, T. bianca', 'GK-0906-4ECA0F', 'GUDANG NENG', '2026-05-05 09:00:00+07', '2026-05-05 09:00:00+07', 'Import GudangKu kardus; client_id=524; label=9600-0906-Neng kanan, T. bianca; nomor_pesanan=9600; nomor_id=0906; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('11b86196-7b3c-35e9-97d9-6d6a4c0493a2', 'GK-KARDUS-000525', 'GK-2674-A23E22-GK-KARDUS-000525', '0400-2674-Neng Kanan t papua kartika', 'GK-2674-A23E22', 'GUDANG NENG', '2026-05-05 09:03:00+07', '2026-05-05 09:03:00+07', 'Import GudangKu kardus; client_id=525; label=0400-2674-Neng Kanan t papua kartika; nomor_pesanan=0400; nomor_id=2674; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('9900927b-bd13-353f-b255-2dea1583e800', 'GK-KARDUS-000530', 'GK-0584-C774BA-GK-KARDUS-000530', '6400-0584-Tori Aldonso T Raisha', 'GK-0584-C774BA', 'GUDANG RANDOM', '2026-05-05 09:08:00+07', '2026-05-05 09:08:00+07', 'Import GudangKu kardus; client_id=530; label=6400-0584-Tori Aldonso T Raisha; nomor_pesanan=6400; nomor_id=0584; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('72eb25d9-2b70-3d8d-be0f-314fb004f7f9', 'GK-KARDUS-000531', 'GK-2542-BCF765-GK-KARDUS-000531', '0100-2542-Tina Mariana DM Tina.', 'GK-2542-BCF765', 'GUDANG TINA', '2026-05-05 09:10:00+07', '2026-05-05 09:10:00+07', 'Import GudangKu kardus; client_id=531; label=0100-2542-Tina Mariana DM Tina.; nomor_pesanan=0100; nomor_id=2542; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ab953b8b-e054-322d-bb7a-ed675f405b21', 'GK-KARDUS-000532', 'GK-1625-8076E6-GK-KARDUS-000532', '9500-1625-Ami Yanuar Iskandar', 'GK-1625-8076E6', 'GUDANG AMI', '2026-05-05 09:14:00+07', '2026-05-05 09:14:00+07', 'Import GudangKu kardus; client_id=532; label=9500-1625-Ami Yanuar Iskandar; nomor_pesanan=9500; nomor_id=1625; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('7169df7e-65a1-39ef-ad8c-7939a49954b6', 'GK-KARDUS-000533', 'GK-2510-37AB36-GK-KARDUS-000533', '7800-2510-Neng Kanan T. Lisna Fadilah', 'GK-2510-37AB36', 'GUDANG NENG', '2026-05-05 09:16:00+07', '2026-05-05 09:16:00+07', 'Import GudangKu kardus; client_id=533; label=7800-2510-Neng Kanan T. Lisna Fadilah; nomor_pesanan=7800; nomor_id=2510; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('a282cef7-1183-3b54-b47a-ccc88506bd1f', 'GK-KARDUS-000534', 'GK-2797-F0979D-GK-KARDUS-000534', '9600-2797-Nengkanan T. Papua Herlina', 'GK-2797-F0979D', 'GUDANG NENG', '2026-05-05 09:22:00+07', '2026-05-05 09:22:00+07', 'Import GudangKu kardus; client_id=534; label=9600-2797-Nengkanan T. Papua Herlina; nomor_pesanan=9600; nomor_id=2797; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('d57dae85-eb2e-3aef-8471-ce62b8f7edd5', 'GK-KARDUS-000535', 'GK-1383-1D166E-GK-KARDUS-000535', '4700-1383-Neng kanan Т. Ека', 'GK-1383-1D166E', 'GUDANG NENG', '2026-05-05 09:28:00+07', '2026-05-05 09:28:00+07', 'Import GudangKu kardus; client_id=535; label=4700-1383-Neng kanan Т. Ека; nomor_pesanan=4700; nomor_id=1383; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('0387d081-42e0-3202-85a1-11929a006a39', 'GK-KARDUS-000536', 'GK-2313-E0A1EC-GK-KARDUS-000536', '2300-2313-Neng Kanan T. PAPUA AQILA', 'GK-2313-E0A1EC', 'GUDANG NENG', '2026-05-05 09:28:00+07', '2026-05-05 09:28:00+07', 'Import GudangKu kardus; client_id=536; label=2300-2313-Neng Kanan T. PAPUA AQILA; nomor_pesanan=2300; nomor_id=2313; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('1f95a5bd-84df-3803-9ace-befa279d25fd', 'GK-KARDUS-000537', 'GK-0487-7A20E6-GK-KARDUS-000537', '4200-0487-Tina Mariana DM Tina', 'GK-0487-7A20E6', 'GUDANG RANDOM', '2026-05-05 09:30:00+07', '2026-05-05 09:30:00+07', 'Import GudangKu kardus; client_id=537; label=4200-0487-Tina Mariana DM Tina; nomor_pesanan=4200; nomor_id=0487; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('9132a264-c810-3940-ad42-ece982cbaf6d', 'GK-KARDUS-000538', 'GK-0268-886987-GK-KARDUS-000538', '8800-0268-Sakilah Team Rina Sakilah', 'GK-0268-886987', 'GUDANG RINA', '2026-05-05 09:30:00+07', '2026-05-05 09:30:00+07', 'Import GudangKu kardus; client_id=538; label=8800-0268-Sakilah Team Rina Sakilah; nomor_pesanan=8800; nomor_id=0268; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('eecb344a-0414-35f5-aa99-0171ccffbfbe', 'GK-KARDUS-000540', 'GK-1819-868EDD-GK-KARDUS-000540', '1700-1819-Neng kanan T. Rusmini', 'GK-1819-868EDD', 'GUDANG NEG', '2026-05-05 09:31:00+07', '2026-05-05 09:31:00+07', 'Import GudangKu kardus; client_id=540; label=1700-1819-Neng kanan T. Rusmini; nomor_pesanan=1700; nomor_id=1819; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('2d673af2-789d-353e-b87f-1b2e2f240317', 'GK-KARDUS-000541', 'GK-3813-CFEFE0-GK-KARDUS-000541', '9100-3813-zamas wiliam T Erlin zamas wiliam', 'GK-3813-CFEFE0', 'GUDANG ERLIN', '2026-05-05 09:33:00+07', '2026-05-05 09:33:00+07', 'Import GudangKu kardus; client_id=541; label=9100-3813-zamas wiliam T Erlin zamas wiliam; nomor_pesanan=9100; nomor_id=3813; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('5b8b7829-f316-3018-8a9c-23d892d836bd', 'GK-KARDUS-000542', 'GK-0308-15EE10-GK-KARDUS-000542', '2000-0308-Suryani Arab lenny Fransiska', 'GK-0308-15EE10', 'GUDANG RANDOM', '2026-05-05 09:35:00+07', '2026-05-05 09:35:00+07', 'Import GudangKu kardus; client_id=542; label=2000-0308-Suryani Arab lenny Fransiska; nomor_pesanan=2000; nomor_id=0308; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('57ddc890-34f4-3bea-bf32-eb43e301b036', 'GK-KARDUS-000543', 'GK-3791-66E4FA-GK-KARDUS-000543', '1555-3791-bagus setiawan T erlin bagus setiawan', 'GK-3791-66E4FA', 'GUDANG ERLIN', '2026-05-05 09:37:00+07', '2026-05-05 09:37:00+07', 'Import GudangKu kardus; client_id=543; label=1555-3791-bagus setiawan T erlin bagus setiawan; nomor_pesanan=1555; nomor_id=3791; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f920c0da-b6de-325c-8d84-a41a40a27e26', 'GK-KARDUS-000544', 'GK-0103-492097-GK-KARDUS-000544', '1900-0103-Sambaru Team Rina', 'GK-0103-492097', 'GUDANG RINA', '2026-05-05 09:37:00+07', '2026-05-05 09:37:00+07', 'Import GudangKu kardus; client_id=544; label=1900-0103-Sambaru Team Rina; nomor_pesanan=1900; nomor_id=0103; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('6a71554f-5dfe-38b3-bffb-fe5cfdd325a2', 'GK-KARDUS-000546', 'GK-2354-73CCDF-GK-KARDUS-000546', '2200-2354-Neng Kanan T. Hidayatuloh.', 'GK-2354-73CCDF', 'GUDANG NENG', '2026-05-05 09:39:00+07', '2026-05-05 09:39:00+07', 'Import GudangKu kardus; client_id=546; label=2200-2354-Neng Kanan T. Hidayatuloh.; nomor_pesanan=2200; nomor_id=2354; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('3f479edc-2c1a-3697-aa30-682f6d4bde7b', 'GK-KARDUS-000547', 'GK-1265-459DD3-GK-KARDUS-000547', '0100-1265-Neng Kanan T Papua Widya Vania', 'GK-1265-459DD3', 'GUDANG NENG', '2026-05-05 09:40:00+07', '2026-05-05 09:40:00+07', 'Import GudangKu kardus; client_id=547; label=0100-1265-Neng Kanan T Papua Widya Vania; nomor_pesanan=0100; nomor_id=1265; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('8e005ce2-9e1a-3529-9e2c-f8e44165c026', 'GK-KARDUS-000548', 'GK-3868-6AA393-GK-KARDUS-000548', '2800-3868-Ami T Djohan SM Boen', 'GK-3868-6AA393', 'GUDANG AMI', '2026-05-05 09:41:00+07', '2026-05-05 09:41:00+07', 'Import GudangKu kardus; client_id=548; label=2800-3868-Ami T Djohan SM Boen; nomor_pesanan=2800; nomor_id=3868; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('2e6871f4-4f3b-3e33-88f9-22b397044d8d', 'GK-KARDUS-000551', 'GK-9874-5D040E-GK-KARDUS-000551', '1700-9874-dony anita dony eko janingrum', 'GK-9874-5D040E', 'GUDANG ANITA', '2026-05-05 09:47:00+07', '2026-05-05 09:47:00+07', 'Import GudangKu kardus; client_id=551; label=1700-9874-dony anita dony eko janingrum; nomor_pesanan=1700; nomor_id=9874; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('319a9799-15ae-3084-b179-39cf7cefdecd', 'GK-KARDUS-000552', 'GK-1218-53AD0E-GK-KARDUS-000552', '9200-1218-Neng kanan T. Abdul Adid', 'GK-1218-53AD0E', 'GUDANG NENG', '2026-05-05 09:48:00+07', '2026-05-05 09:48:00+07', 'Import GudangKu kardus; client_id=552; label=9200-1218-Neng kanan T. Abdul Adid; nomor_pesanan=9200; nomor_id=1218; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ad69e547-a2ec-3d8b-8697-d0629b5838a5', 'GK-KARDUS-000553', 'GK-2089-E12695-GK-KARDUS-000553', '0100-2089-Juliyana T. Rina Juliyana', 'GK-2089-E12695', 'GUDANG RINA', '2026-05-05 09:50:00+07', '2026-05-05 09:50:00+07', 'Import GudangKu kardus; client_id=553; label=0100-2089-Juliyana T. Rina Juliyana; nomor_pesanan=0100; nomor_id=2089; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('11a51a2c-b757-37fc-8bbe-9eef9e23e408', 'GK-KARDUS-000554', 'GK-2478-CA5C18-GK-KARDUS-000554', '2900-2478-Roney Steven T Wifa', 'GK-2478-CA5C18', 'GUDANG WIFA', '2026-05-05 09:52:00+07', '2026-05-05 09:52:00+07', 'Import GudangKu kardus; client_id=554; label=2900-2478-Roney Steven T Wifa; nomor_pesanan=2900; nomor_id=2478; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('af5b09f5-4200-349b-acbb-3b4a15b411ed', 'GK-KARDUS-000556', 'GK-0653-1D80E2-GK-KARDUS-000556', '3200-0653-Neng Kanan T. Riki Suswanto', 'GK-0653-1D80E2', 'GUDANG NENG', '2026-05-05 09:54:00+07', '2026-05-05 09:54:00+07', 'Import GudangKu kardus; client_id=556; label=3200-0653-Neng Kanan T. Riki Suswanto; nomor_pesanan=3200; nomor_id=0653; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('3d24dc56-1ffa-3894-b176-31ebbd29ecfb', 'GK-KARDUS-000557', 'GK-2612-6D0080-GK-KARDUS-000557', '7000-2612-Neng Kanan T. Sunarsih', 'GK-2612-6D0080', 'GUDANG NENG', '2026-05-05 09:55:00+07', '2026-05-05 09:55:00+07', 'Import GudangKu kardus; client_id=557; label=7000-2612-Neng Kanan T. Sunarsih; nomor_pesanan=7000; nomor_id=2612; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('e9ddfd6e-0a64-3084-85c9-bafe3f982721', 'GK-KARDUS-000566', 'GK-0740-43825A-GK-KARDUS-000566', '7800-0740-AMI RASTINI', 'GK-0740-43825A', 'GUDANG AMI', '2026-05-20 09:05:00+07', '2026-05-20 09:05:00+07', 'Import GudangKu kardus; client_id=566; label=7800-0740-AMI RASTINI; nomor_pesanan=7800; nomor_id=0740; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('6ab28ac3-f07a-35f5-8e16-537bc33a592b', 'GK-KARDUS-000567', 'GK-4404-071084-GK-KARDUS-000567', '3500-4404-AMI JENNY OKTAVIANI', 'GK-4404-071084', 'GUDANG AMI', '2026-05-20 09:07:00+07', '2026-05-20 09:07:00+07', 'Import GudangKu kardus; client_id=567; label=3500-4404-AMI JENNY OKTAVIANI; nomor_pesanan=3500; nomor_id=4404; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('65a559c0-9bb9-3a35-9a6b-f4b3ae61aa0b', 'GK-KARDUS-000568', 'GK-4405-FD15D1-GK-KARDUS-000568', '1100-4405-AMI HADI SUWITO', 'GK-4405-FD15D1', 'GUDANG AMI', '2026-05-20 09:08:00+07', '2026-05-20 09:08:00+07', 'Import GudangKu kardus; client_id=568; label=1100-4405-AMI HADI SUWITO; nomor_pesanan=1100; nomor_id=4405; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('73beffae-dbba-3a27-ac91-8f2144a64d46', 'GK-KARDUS-000569', 'GK-0231-5431EA-GK-KARDUS-000569', '0500-0231-AMI SOPYAN', 'GK-0231-5431EA', 'GUDANG AMI', '2026-05-20 09:09:00+07', '2026-05-20 09:09:00+07', 'Import GudangKu kardus; client_id=569; label=0500-0231-AMI SOPYAN; nomor_pesanan=0500; nomor_id=0231; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('925180f6-a8cc-31c9-8f15-ae4066cb7e4b', 'GK-KARDUS-000570', 'GK-2779-2C8490-GK-KARDUS-000570', '5000-2779-PUTRI AMI PUTRI CINDY', 'GK-2779-2C8490', 'GUDANG AMI', '2026-05-20 09:11:00+07', '2026-05-20 09:11:00+07', 'Import GudangKu kardus; client_id=570; label=5000-2779-PUTRI AMI PUTRI CINDY; nomor_pesanan=5000; nomor_id=2779; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('2d85bdf2-011e-360e-8191-468b9b511935', 'GK-KARDUS-000572', 'GK-0492-7720B2-GK-KARDUS-000572', '2300-0492-AMI SUSANTI', 'GK-0492-7720B2', 'GUDANG AMI', '2026-05-20 09:12:00+07', '2026-05-20 09:12:00+07', 'Import GudangKu kardus; client_id=572; label=2300-0492-AMI SUSANTI; nomor_pesanan=2300; nomor_id=0492; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('e6a69ae0-6092-3638-9de8-b50f70cd20f5', 'GK-KARDUS-000573', 'GK-4403-0266EE-GK-KARDUS-000573', '9500-4403-AMI SUWARJI', 'GK-4403-0266EE', 'GUDANG AMI', '2026-05-20 09:14:00+07', '2026-05-20 09:14:00+07', 'Import GudangKu kardus; client_id=573; label=9500-4403-AMI SUWARJI; nomor_pesanan=9500; nomor_id=4403; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('662d3a4b-1634-319e-943a-4d0168faa908', 'GK-KARDUS-000577', 'GK-0332-990A1E-GK-KARDUS-000577', '4800-0332-AMIKSAM', 'GK-0332-990A1E', 'KANTOR', '2026-05-20 09:19:00+07', '2026-05-20 09:19:00+07', 'Import GudangKu kardus; client_id=577; label=4800-0332-AMIKSAM; nomor_pesanan=4800; nomor_id=0332; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('33aac9d9-14c0-35d8-bb39-9f23cbc66029', 'GK-KARDUS-000578', 'GK-2317-7256F9-GK-KARDUS-000578', '9100-2317-MIA AUDINA NURHIDAYAH', 'GK-2317-7256F9', 'KANTOR', '2026-05-20 09:22:00+07', '2026-05-20 09:22:00+07', 'Import GudangKu kardus; client_id=578; label=9100-2317-MIA AUDINA NURHIDAYAH; nomor_pesanan=9100; nomor_id=2317; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('7ed0eb24-f37a-364f-8e9c-205aecc52b67', 'GK-KARDUS-000580', 'GK-2318-8036DD-GK-KARDUS-000580', '8400-2318-amicevi', 'GK-2318-8036DD', 'KANTOR', '2026-05-20 09:24:00+07', '2026-05-20 09:24:00+07', 'Import GudangKu kardus; client_id=580; label=8400-2318-amicevi; nomor_pesanan=8400; nomor_id=2318; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('48267c9d-2384-32ac-b572-4cbc866af29b', 'GK-KARDUS-000581', 'GK-1014-2C8490-GK-KARDUS-000581', '5000-1014-PUTRI AMI PUTRI CINDY', 'GK-1014-2C8490', 'GUDANG AMI', '2026-05-20 09:25:00+07', '2026-05-20 09:25:00+07', 'Import GudangKu kardus; client_id=581; label=5000-1014-PUTRI AMI PUTRI CINDY; nomor_pesanan=5000; nomor_id=1014; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('573edbcf-2fed-358d-bfc3-7bb05dd76287', 'GK-KARDUS-000582', 'GK-2323-FF1AD9-GK-KARDUS-000582', '9000-2323-ami erick putra', 'GK-2323-FF1AD9', 'KANTOR', '2026-05-20 09:25:00+07', '2026-05-20 09:25:00+07', 'Import GudangKu kardus; client_id=582; label=9000-2323-ami erick putra; nomor_pesanan=9000; nomor_id=2323; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('443bec14-a49b-361d-bd29-3c796a6982be', 'GK-KARDUS-000583', 'GK-2322-38B157-GK-KARDUS-000583', '0600-2322-SEPTIAN AMI', 'GK-2322-38B157', 'KANTOR', '2026-05-20 09:27:00+07', '2026-05-20 09:27:00+07', 'Import GudangKu kardus; client_id=583; label=0600-2322-SEPTIAN AMI; nomor_pesanan=0600; nomor_id=2322; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('21da24d3-a34e-3dd1-b5cc-7a662042ceda', 'GK-KARDUS-000584', 'GK-2316-A31866-GK-KARDUS-000584', '5000-2316-achmad ami achmad suheli', 'GK-2316-A31866', 'KANTOR', '2026-05-20 09:27:00+07', '2026-05-20 09:27:00+07', 'Import GudangKu kardus; client_id=584; label=5000-2316-achmad ami achmad suheli; nomor_pesanan=5000; nomor_id=2316; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('5d43a64e-f328-3706-ae04-3504069ab4b9', 'GK-KARDUS-000585', 'GK-0189-FA22C4-GK-KARDUS-000585', '7700-0189-ami agung setiawan', 'GK-0189-FA22C4', 'KANTOR', '2026-05-20 09:30:00+07', '2026-05-20 09:30:00+07', 'Import GudangKu kardus; client_id=585; label=7700-0189-ami agung setiawan; nomor_pesanan=7700; nomor_id=0189; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('481d8352-0c02-3c7e-b048-8b236136b279', 'GK-KARDUS-000586', 'GK-4793-425C57-GK-KARDUS-000586', '3500-4793-ami antika sari', 'GK-4793-425C57', 'KANTOR', '2026-05-20 09:33:00+07', '2026-05-20 09:33:00+07', 'Import GudangKu kardus; client_id=586; label=3500-4793-ami antika sari; nomor_pesanan=3500; nomor_id=4793; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('abb52c4b-0ae9-3712-8a6a-6d6be0623b2c', 'GK-KARDUS-000587', 'GK-8675-6FA479-GK-KARDUS-000587', '3400-8675-ANUNSIATA MBEOWAKE WARE', 'GK-8675-6FA479', 'KANTOR', '2026-05-20 09:34:00+07', '2026-05-20 09:34:00+07', 'Import GudangKu kardus; client_id=587; label=3400-8675-ANUNSIATA MBEOWAKE WARE; nomor_pesanan=3400; nomor_id=8675; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('74cffa36-6f6c-3ca0-b6d2-9d12e3b1a450', 'GK-KARDUS-000588', 'GK-8675-F4E056-GK-KARDUS-000588', '0800-8675-AMIMALIKAH BILQIS', 'GK-8675-F4E056', 'KANTOR', '2026-05-20 09:35:00+07', '2026-05-20 09:35:00+07', 'Import GudangKu kardus; client_id=588; label=0800-8675-AMIMALIKAH BILQIS; nomor_pesanan=0800; nomor_id=8675; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('27cd1fab-7922-3c25-a874-ab4685179ce5', 'GK-KARDUS-000589', 'GK-4931-7AFA01-GK-KARDUS-000589', '4600-4931-tjong li mi ratnasari', 'GK-4931-7AFA01', 'KANTOR', '2026-05-20 09:35:00+07', '2026-05-20 09:35:00+07', 'Import GudangKu kardus; client_id=589; label=4600-4931-tjong li mi ratnasari; nomor_pesanan=4600; nomor_id=4931; type=Milik Sendiri; created_by=Admin; updated_by=Admin'),
  ('96b0994a-3f5f-34af-8f09-1a47030c5531', 'GK-KARDUS-000591', 'GK-0935-CA1C86-GK-KARDUS-000591', '7200-0935-AMIYULIA', 'GK-0935-CA1C86', 'KANTOR', '2026-05-20 09:38:00+07', '2026-05-20 09:38:00+07', 'Import GudangKu kardus; client_id=591; label=7200-0935-AMIYULIA; nomor_pesanan=7200; nomor_id=0935; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('80d4a0b1-f147-39dc-9dea-ae459c4787ec', 'GK-KARDUS-000592', 'GK-4678-82C3CE-GK-KARDUS-000592', '8500-4678-ami kisam', 'GK-4678-82C3CE', 'KANTOR', '2026-05-20 09:38:00+07', '2026-05-20 09:38:00+07', 'Import GudangKu kardus; client_id=592; label=8500-4678-ami kisam; nomor_pesanan=8500; nomor_id=4678; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('29a69274-5206-3f66-b2f6-8c383629a183', 'GK-KARDUS-000594', 'GK-0886-E1C3F9-GK-KARDUS-000594', '8300-0886-rasto by ami rasto hartono', 'GK-0886-E1C3F9', 'KANTOR', '2026-05-20 09:47:00+07', '2026-05-20 09:47:00+07', 'Import GudangKu kardus; client_id=594; label=8300-0886-rasto by ami rasto hartono; nomor_pesanan=8300; nomor_id=0886; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('1dfc5487-b69f-3b19-a8b8-82444b55ba23', 'GK-KARDUS-000595', 'GK-8186-425C57-GK-KARDUS-000595', '3500-8186-AMI ANTIKA SARI', 'GK-8186-425C57', 'GUDANG AMI', '2026-05-20 09:47:00+07', '2026-05-20 09:47:00+07', 'Import GudangKu kardus; client_id=595; label=3500-8186-AMI ANTIKA SARI; nomor_pesanan=3500; nomor_id=8186; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('05fb0a03-90f0-37e0-a027-0c8d3ebdfbef', 'GK-KARDUS-000596', 'GK-1741-5EDFB0-GK-KARDUS-000596', '7132-1741-Mita T WIFA AMita karya', 'GK-1741-5EDFB0', 'GUDANG', '2026-05-28 11:36:00+07', '2026-05-28 11:36:00+07', 'Import GudangKu kardus; client_id=596; label=7132-1741-Mita T WIFA AMita karya; nomor_pesanan=7132; nomor_id=1741; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('91908585-c0ab-31a0-b726-dfd2da6fe481', 'GK-KARDUS-000600', 'GK-0012-F8DB76-GK-KARDUS-000600', '3400-0012-stevannystevani y peea', 'GK-0012-F8DB76', 'GUDANG STEVANI', '2026-05-30 09:17:00+07', '2026-05-30 09:17:00+07', 'Import GudangKu kardus; client_id=600; label=3400-0012-stevannystevani y peea; nomor_pesanan=3400; nomor_id=0012; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('23d198ac-da98-3e44-b494-88e8c4c706b9', 'GK-KARDUS-000601', 'GK-9383-BC5634-GK-KARDUS-000601', '1000-9383-Neng Kanan T PAPUA UNDANG SUKARSA', 'GK-9383-BC5634', 'GUDANG NENG', '2026-05-30 09:18:00+07', '2026-05-30 09:18:00+07', 'Import GudangKu kardus; client_id=601; label=1000-9383-Neng Kanan T PAPUA UNDANG SUKARSA; nomor_pesanan=1000; nomor_id=9383; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('86fe792e-49ba-3a56-88d6-9cd4c5d90800', 'GK-KARDUS-000602', 'GK-9521-2C772F-GK-KARDUS-000602', '2700-9521-NENG KANAN T PAPUA NUNU NUHDIN', 'GK-9521-2C772F', 'GUDANG NENG', '2026-05-30 09:21:00+07', '2026-05-30 09:21:00+07', 'Import GudangKu kardus; client_id=602; label=2700-9521-NENG KANAN T PAPUA NUNU NUHDIN; nomor_pesanan=2700; nomor_id=9521; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('aefd2e0f-b98e-3dc9-8cc9-281c7acbb0e9', 'GK-KARDUS-000604', 'GK-1396-2B4366-GK-KARDUS-000604', '5700-1396-indra anita indra lesmana', 'GK-1396-2B4366', 'GUDANG ANITA', '2026-05-30 09:23:00+07', '2026-05-30 09:23:00+07', 'Import GudangKu kardus; client_id=604; label=5700-1396-indra anita indra lesmana; nomor_pesanan=5700; nomor_id=1396; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('91302693-cff7-3a61-be24-f31a257bdbb5', 'GK-KARDUS-000605', 'GK-9407-2BAB65-GK-KARDUS-000605', '3000-9407-ABDUL TEAM NENG ABDUL ADID', 'GK-9407-2BAB65', 'GUDANG NENG', '2026-05-30 09:24:00+07', '2026-05-30 09:24:00+07', 'Import GudangKu kardus; client_id=605; label=3000-9407-ABDUL TEAM NENG ABDUL ADID; nomor_pesanan=3000; nomor_id=9407; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('fb2f37a8-0275-32b7-a007-43ae0a3fbbba', 'GK-KARDUS-000607', 'GK-9457-6369D3-GK-KARDUS-000607', '2000-9457-NENG KANAN T PAPUA RIKI ARIYANTO', 'GK-9457-6369D3', 'GUDANG NENG', '2026-05-30 09:26:00+07', '2026-05-30 09:26:00+07', 'Import GudangKu kardus; client_id=607; label=2000-9457-NENG KANAN T PAPUA RIKI ARIYANTO; nomor_pesanan=2000; nomor_id=9457; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('03567725-5478-3d3d-aa6d-e35bc8223295', 'GK-KARDUS-000609', 'GK-9342-089C94-GK-KARDUS-000609', '3500-9342-NENG KANAN T PAPUA NOVIE MASAYU AZAN', 'GK-9342-089C94', 'GUDANG NENG', '2026-05-30 09:34:00+07', '2026-05-30 09:34:00+07', 'Import GudangKu kardus; client_id=609; label=3500-9342-NENG KANAN T PAPUA NOVIE MASAYU AZAN; nomor_pesanan=3500; nomor_id=9342; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f0847aa0-8e3a-3e1d-acd5-427cfa2e0cc7', 'GK-KARDUS-000610', 'GK-9598-7FFFEE-GK-KARDUS-000610', '2400-9598-NENG KANAN T PAPUA LISNA FADILAH YUSTIANI', 'GK-9598-7FFFEE', 'GUDANG NENG', '2026-05-30 09:35:00+07', '2026-05-30 09:35:00+07', 'Import GudangKu kardus; client_id=610; label=2400-9598-NENG KANAN T PAPUA LISNA FADILAH YUSTIANI; nomor_pesanan=2400; nomor_id=9598; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('0f8727d8-5491-3257-9f0f-1efc6c1b7979', 'GK-KARDUS-000611', 'GK-9409-003785-GK-KARDUS-000611', '2900-9409-NENG KANAN T PAPUA NINING YUNINGSIH', 'GK-9409-003785', 'GUDANG NENG', '2026-05-30 09:36:00+07', '2026-05-30 09:36:00+07', 'Import GudangKu kardus; client_id=611; label=2900-9409-NENG KANAN T PAPUA NINING YUNINGSIH; nomor_pesanan=2900; nomor_id=9409; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('32b0088e-b437-3252-a57d-1fc3f53a6224', 'GK-KARDUS-000612', 'GK-9573-A9464E-GK-KARDUS-000612', '4500-9573-NENG KANAN T PAPUA EVA MIRAWATI', 'GK-9573-A9464E', 'GUDANG NENG', '2026-05-30 09:37:00+07', '2026-05-30 09:37:00+07', 'Import GudangKu kardus; client_id=612; label=4500-9573-NENG KANAN T PAPUA EVA MIRAWATI; nomor_pesanan=4500; nomor_id=9573; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('f9231a64-87d5-3802-b08a-ba5a831ff499', 'GK-KARDUS-000613', 'GK-9407-2BAB65-GK-KARDUS-000613', '3000-9407-ABDUL TEAM NENG ABDUL ADID', 'GK-9407-2BAB65', 'GUDANG NENG', '2026-05-30 09:40:00+07', '2026-05-30 09:40:00+07', 'Import GudangKu kardus; client_id=613; label=3000-9407-ABDUL TEAM NENG ABDUL ADID; nomor_pesanan=3000; nomor_id=9407; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('276e7c17-df15-34e9-9fea-dcfe0a6d4e18', 'GK-KARDUS-000614', 'GK-9350-950F0D-GK-KARDUS-000614', '1800-9350-NENG KANAN T PAPUA ASTUTI DEWI', 'GK-9350-950F0D', 'GUDANG NENG', '2026-05-30 09:40:00+07', '2026-05-30 09:40:00+07', 'Import GudangKu kardus; client_id=614; label=1800-9350-NENG KANAN T PAPUA ASTUTI DEWI; nomor_pesanan=1800; nomor_id=9350; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('83894361-323b-3cd4-9f0c-b916a1d332f6', 'GK-KARDUS-000615', 'GK-7663-3536D6-GK-KARDUS-000615', '7100-7663-NENG KANNA T PAPUA HERI KUSWANTO', 'GK-7663-3536D6', 'GUDANG NENG', '2026-05-30 09:41:00+07', '2026-05-30 09:41:00+07', 'Import GudangKu kardus; client_id=615; label=7100-7663-NENG KANNA T PAPUA HERI KUSWANTO; nomor_pesanan=7100; nomor_id=7663; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('36fcad0f-80d2-3e5b-a0f0-11c04ba402b0', 'GK-KARDUS-000616', 'GK-9505-A83F1A-GK-KARDUS-000616', '1400-9505-NENG KANAN T PAPUA SARIPAH', 'GK-9505-A83F1A', 'GUDANG NENG', '2026-05-30 09:42:00+07', '2026-05-30 09:42:00+07', 'Import GudangKu kardus; client_id=616; label=1400-9505-NENG KANAN T PAPUA SARIPAH; nomor_pesanan=1400; nomor_id=9505; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('e160a9c1-f899-3af1-b4b4-3b7ad090deda', 'GK-KARDUS-000617', 'GK-9421-0CE773-GK-KARDUS-000617', '4000-9421-NENG KANAN T PAPUA RUSMINI', 'GK-9421-0CE773', 'GUDANG NENG', '2026-05-30 09:44:00+07', '2026-05-30 09:44:00+07', 'Import GudangKu kardus; client_id=617; label=4000-9421-NENG KANAN T PAPUA RUSMINI; nomor_pesanan=4000; nomor_id=9421; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('ec968e29-cd35-305a-b483-c2ddb529d258', 'GK-KARDUS-000618', 'GK-9595-009A4F-GK-KARDUS-000618', '9800-9595-NENG KANAN T PAPUA BIRIN', 'GK-9595-009A4F', 'GUDANG NENG', '2026-05-30 09:45:00+07', '2026-05-30 09:45:00+07', 'Import GudangKu kardus; client_id=618; label=9800-9595-NENG KANAN T PAPUA BIRIN; nomor_pesanan=9800; nomor_id=9595; type=Titipan; created_by=Admin; updated_by=Admin'),
  ('9c736406-9b2c-3ac7-9dac-dbbe5b8e4074', 'GK-KARDUS-000619', 'GK-9608-1A781B-GK-KARDUS-000619', '8600-9608-NENG KANAN T PAPUA IYAH SOPIYAH', 'GK-9608-1A781B', 'GUDANG NENG', '2026-05-30 09:45:00+07', '2026-05-30 09:45:00+07', 'Import GudangKu kardus; client_id=619; label=8600-9608-NENG KANAN T PAPUA IYAH SOPIYAH; nomor_pesanan=8600; nomor_id=9608; type=Titipan; created_by=Admin; updated_by=Admin')
)
insert into public.boxes(
  id,
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
  source_boxes.id::uuid,
  source_boxes.id_box,
  source_boxes.pemilik_id_box,
  public.build_box_barcode_value(source_boxes.id_box),
  source_boxes.box_name,
  owners.id,
  'custom',
  null,
  0,
  null,
  source_boxes.location_code,
  'active',
  source_boxes.created_at::timestamptz,
  source_boxes.updated_at::timestamptz,
  null,
  source_boxes.notes
from source_boxes
join public.owners on owners.owner_code = source_boxes.owner_code
on conflict (id_box) do update set
  pemilik_id_box = excluded.pemilik_id_box,
  barcode_value = excluded.barcode_value,
  box_name = excluded.box_name,
  owner_id = excluded.owner_id,
  source_type = excluded.source_type,
  package_id = excluded.package_id,
  package_qty = excluded.package_qty,
  expired_at = excluded.expired_at,
  location_code = excluded.location_code,
  status = excluded.status,
  updated_at = excluded.updated_at,
  notes = excluded.notes;

with source_items(id, id_box, sku, qty_initial, qty_available, created_at, updated_at, notes) as (
  values
  ('b51623d9-4133-3959-b5b4-1f5268176a85', 'GK-KARDUS-000001', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 07:43:00+07', '2026-04-29 07:43:00+07', 'source_inventory_rows=1'),
  ('4428c1a9-bfce-3e38-bf02-4655758c2e00', 'GK-KARDUS-000002', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 07:45:00+07', '2026-04-29 07:45:00+07', 'source_inventory_rows=2'),
  ('0ffbb036-e75c-3427-ae29-df5e9851a8ec', 'GK-KARDUS-000007', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 07:50:00+07', '2026-04-29 07:50:00+07', 'source_inventory_rows=3'),
  ('87b64a69-3417-3439-ae53-639906b9dee4', 'GK-KARDUS-000009', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 07:52:00+07', '2026-04-29 07:52:00+07', 'source_inventory_rows=4'),
  ('02a3ba76-ae51-3124-a271-b62579231629', 'GK-KARDUS-000011', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 07:55:00+07', '2026-04-29 07:55:00+07', 'source_inventory_rows=5'),
  ('8287e271-c8e6-3829-9454-971740270fad', 'GK-KARDUS-000012', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 07:56:00+07', '2026-04-29 07:56:00+07', 'source_inventory_rows=6'),
  ('c225c9c5-1a1b-3308-90eb-a8d1dfc0be8e', 'GK-KARDUS-000013', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 07:58:00+07', '2026-04-29 07:58:00+07', 'source_inventory_rows=7'),
  ('5997f980-7e92-3e8c-9c0b-4569fb3c5e23', 'GK-KARDUS-000014', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 08:00:00+07', '2026-04-29 08:00:00+07', 'source_inventory_rows=8'),
  ('692574c1-4b03-32cb-9f97-c7e8f900f63e', 'GK-KARDUS-000016', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 08:05:00+07', '2026-04-29 08:05:00+07', 'source_inventory_rows=9'),
  ('c9a93f55-acb1-3096-b2ab-eba5707e8944', 'GK-KARDUS-000017', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 08:06:00+07', '2026-04-29 08:06:00+07', 'source_inventory_rows=10'),
  ('9c58b9ea-cd5c-31b9-98ae-22e029adab2d', 'GK-KARDUS-000020', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 08:10:00+07', '2026-04-29 08:10:00+07', 'source_inventory_rows=11'),
  ('b708d21c-8a92-359a-b9a4-d2d5f625b2df', 'GK-KARDUS-000021', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 08:12:00+07', '2026-04-29 08:12:00+07', 'source_inventory_rows=12'),
  ('e34fe6b8-0d7d-3703-b37e-a6da7db1d1fc', 'GK-KARDUS-000023', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 08:14:00+07', '2026-04-29 08:14:00+07', 'source_inventory_rows=13'),
  ('7c1864f6-9514-3acb-9b89-8687b7cf88cb', 'GK-KARDUS-000026', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 08:18:00+07', '2026-04-29 08:18:00+07', 'source_inventory_rows=14'),
  ('28de0c53-20cd-31a8-ae92-6c5becbec5ba', 'GK-KARDUS-000028', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 08:21:00+07', '2026-04-29 08:21:00+07', 'source_inventory_rows=15'),
  ('2f96c06f-c7f1-3742-b3b1-fae75c002cb9', 'GK-KARDUS-000029', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 08:22:00+07', '2026-04-29 08:22:00+07', 'source_inventory_rows=16'),
  ('93d8f513-e2d0-33f5-b321-df09b64b5df3', 'GK-KARDUS-000032', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 08:25:00+07', '2026-04-29 08:25:00+07', 'source_inventory_rows=17'),
  ('909acca7-c264-3e2a-9798-8a3198c7ed72', 'GK-KARDUS-000033', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 08:27:00+07', '2026-04-29 08:27:00+07', 'source_inventory_rows=18'),
  ('6ae34fcf-9c23-3e81-b3a0-70d02a0e4d40', 'GK-KARDUS-000035', 'ATOMY-HONGSAMDAN-RED-GINSENG', 1, 1, '2026-04-29 08:29:00+07', '2026-04-29 08:29:00+07', 'source_inventory_rows=19'),
  ('b8e51d1f-d9f9-33d3-a4a1-f97670eb22a3', 'GK-KARDUS-000035', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 08:29:00+07', '2026-04-29 08:29:00+07', 'source_inventory_rows=20'),
  ('d2bd3975-c452-3dac-ab43-c4d45b2cd152', 'GK-KARDUS-000035', 'ATOMY-PROBIOTICS-10', 1, 1, '2026-04-29 08:29:00+07', '2026-04-29 08:29:00+07', 'source_inventory_rows=21'),
  ('f781c405-b32f-307c-b63e-38fc7b35f224', 'GK-KARDUS-000035', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 1, '2026-04-29 08:29:00+07', '2026-04-29 08:29:00+07', 'source_inventory_rows=22'),
  ('6e4fb731-22be-3017-bea6-a2ba3d478534', 'GK-KARDUS-000036', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 08:31:00+07', '2026-04-29 08:31:00+07', 'source_inventory_rows=23'),
  ('83c4a818-f308-3a85-b24c-170d70d2fe78', 'GK-KARDUS-000040', 'ATOMY-PAKET-RAMADHAN-CARE', 1, 1, '2026-04-29 08:36:00+07', '2026-04-29 08:36:00+07', 'source_inventory_rows=24'),
  ('12b1aa16-ce06-3e2e-80ad-94ac7197c5d9', 'GK-KARDUS-000043', 'ATOMY-HEMOHIM', 5, 5, '2026-04-29 08:49:00+07', '2026-04-29 08:49:00+07', 'source_inventory_rows=25|26'),
  ('a990292b-ffe1-3c92-9cd8-b475b1a0cba9', 'GK-KARDUS-000046', 'ATOMY-PAKET-RAMADHAN-CARE', 1, 1, '2026-04-29 08:52:00+07', '2026-04-29 08:52:00+07', 'source_inventory_rows=27'),
  ('7d395ae9-e7f8-3341-a146-45e2ef283f61', 'GK-KARDUS-000053', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 08:57:00+07', '2026-04-29 08:57:00+07', 'source_inventory_rows=28'),
  ('bea9d8eb-e529-3625-bb4c-5bdb079540e1', 'GK-KARDUS-000056', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 08:59:00+07', '2026-04-29 08:59:00+07', 'source_inventory_rows=29'),
  ('39487550-0252-3ef3-8d25-c95491c42f6e', 'GK-KARDUS-000059', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 09:02:00+07', '2026-04-29 09:02:00+07', 'source_inventory_rows=30'),
  ('2e6c16c4-7768-315f-a3ea-8837ecf3cdad', 'GK-KARDUS-000060', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:03:00+07', '2026-04-29 09:03:00+07', 'source_inventory_rows=31'),
  ('5c6690a0-45a7-3292-93c6-b9158416d8e9', 'GK-KARDUS-000062', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:04:00+07', '2026-04-29 09:04:00+07', 'source_inventory_rows=32'),
  ('e3f5eaf9-b3c0-330a-8205-c20b22210f91', 'GK-KARDUS-000064', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:06:00+07', '2026-04-29 09:06:00+07', 'source_inventory_rows=33'),
  ('1be0bebf-68c3-3601-953b-8cd5bd2c2dc7', 'GK-KARDUS-000065', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 09:06:00+07', '2026-04-29 09:06:00+07', 'source_inventory_rows=34'),
  ('82949603-da40-36c1-9a9a-9681de981aaf', 'GK-KARDUS-000068', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:10:00+07', '2026-04-29 09:10:00+07', 'source_inventory_rows=35'),
  ('bcca9dd0-2e8a-3d0e-b2d5-b22dc920091d', 'GK-KARDUS-000067', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:11:00+07', '2026-04-29 09:11:00+07', 'source_inventory_rows=36'),
  ('6317a9cb-6711-3089-90cd-e80a041b24f2', 'GK-KARDUS-000070', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:12:00+07', '2026-04-29 09:12:00+07', 'source_inventory_rows=37'),
  ('4baad448-8707-3261-8185-42aa5a48ae1e', 'GK-KARDUS-000072', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:13:00+07', '2026-04-29 09:13:00+07', 'source_inventory_rows=38'),
  ('766bfcc5-2006-3aaf-bd30-b38f75c19eb8', 'GK-KARDUS-000073', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:14:00+07', '2026-04-29 09:14:00+07', 'source_inventory_rows=39'),
  ('cb3d4c7d-9a07-375f-bcb4-63ae11369dca', 'GK-KARDUS-000077', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:17:00+07', '2026-04-29 09:17:00+07', 'source_inventory_rows=40'),
  ('bfd05397-9106-3f23-b19c-46bbab77bb61', 'GK-KARDUS-000078', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:18:00+07', '2026-04-29 09:18:00+07', 'source_inventory_rows=41'),
  ('06130321-2e2e-369a-a4d7-df84bb372f5b', 'GK-KARDUS-000084', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:24:00+07', '2026-04-29 09:24:00+07', 'source_inventory_rows=42'),
  ('b3e3cd55-52fe-3e9c-8047-468e6b674520', 'GK-KARDUS-000085', 'ATOMY-BODY-CLEANSER', 1, 1, '2026-04-29 09:25:00+07', '2026-04-29 09:25:00+07', 'source_inventory_rows=43'),
  ('6eb3fbf8-5370-3900-b5a2-d0af3f989272', 'GK-KARDUS-000085', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-04-29 09:25:00+07', '2026-04-29 09:25:00+07', 'source_inventory_rows=44'),
  ('97b19aea-2fcf-3f54-b165-0c79d747eed1', 'GK-KARDUS-000085', 'ATOMY-EVENING-CARE-4-SET', 2, 2, '2026-04-29 09:26:00+07', '2026-04-29 09:26:00+07', 'source_inventory_rows=45'),
  ('f21bf9b9-7050-34a2-9cfd-53503e85acb3', 'GK-KARDUS-000085', 'ATOMY-BODY-LOTION', 2, 2, '2026-04-29 09:26:00+07', '2026-04-29 09:26:00+07', 'source_inventory_rows=46'),
  ('81eab242-207c-30b0-9831-693fc3f68063', 'GK-KARDUS-000086', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:26:00+07', '2026-04-29 09:26:00+07', 'source_inventory_rows=47'),
  ('259bcbab-33d1-3556-9d02-99743eb4764d', 'GK-KARDUS-000087', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:40:00+07', '2026-04-29 09:40:00+07', 'source_inventory_rows=48'),
  ('43f1d2d3-cd07-34d7-92dc-a1602622c7f8', 'GK-KARDUS-000088', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:43:00+07', '2026-04-29 09:43:00+07', 'source_inventory_rows=49'),
  ('10c28703-0b96-34aa-b01d-a42ca999dd82', 'GK-KARDUS-000096', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-29 09:54:00+07', '2026-04-29 09:54:00+07', 'source_inventory_rows=50'),
  ('d0932371-dd61-3cc0-88de-676253f87c3a', 'GK-KARDUS-000097', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:55:00+07', '2026-04-29 09:55:00+07', 'source_inventory_rows=51'),
  ('adbe1e38-c05f-3aa9-a0b0-1dc1db557cef', 'GK-KARDUS-000098', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-29 09:56:00+07', '2026-04-29 09:56:00+07', 'source_inventory_rows=52'),
  ('31049aaf-591a-3165-898e-6fdd4ce97fad', 'GK-KARDUS-000102', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 09:59:00+07', '2026-04-29 09:59:00+07', 'source_inventory_rows=53'),
  ('1216206a-c844-3a65-bc2b-d53d17cce724', 'GK-KARDUS-000103', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 10:00:00+07', '2026-04-29 10:00:00+07', 'source_inventory_rows=54'),
  ('2020b094-cf58-3233-8a27-59a57d15cc4f', 'GK-KARDUS-000105', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-29 10:01:00+07', '2026-04-29 10:01:00+07', 'source_inventory_rows=55'),
  ('66b46aea-0f51-3cf6-a8fa-9855388286a4', 'GK-KARDUS-000108', 'ATOMY-HEMOHIM', 8, 8, '2026-04-29 10:04:00+07', '2026-04-29 10:04:00+07', 'source_inventory_rows=56|57'),
  ('bc25048f-5a11-3fc1-8bd3-54c288bcd738', 'GK-KARDUS-000109', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 10:05:00+07', '2026-04-29 10:05:00+07', 'source_inventory_rows=58'),
  ('5dea73cf-7f11-3766-a2a2-f461b1585e04', 'GK-KARDUS-000111', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 10:07:00+07', '2026-04-29 10:07:00+07', 'source_inventory_rows=59'),
  ('b4f1ea1e-63cb-3fb9-9b84-17e765147fe1', 'GK-KARDUS-000112', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 10:08:00+07', '2026-04-29 10:08:00+07', 'source_inventory_rows=60'),
  ('67c44b5c-27d6-3d7b-b074-538874f58dd1', 'GK-KARDUS-000113', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 10:09:00+07', '2026-04-29 10:09:00+07', 'source_inventory_rows=61'),
  ('858dd63a-8785-3111-9ddf-37df71e45aef', 'GK-KARDUS-000114', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 10:10:00+07', '2026-04-29 10:10:00+07', 'source_inventory_rows=62'),
  ('858870e0-ce4b-3f59-a1ef-ad3bb22e19b6', 'GK-KARDUS-000115', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 10:12:00+07', '2026-04-29 10:12:00+07', 'source_inventory_rows=63'),
  ('f2e45d82-d6d9-3e3c-9465-c0503a8e1def', 'GK-KARDUS-000117', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 10:13:00+07', '2026-04-29 10:13:00+07', 'source_inventory_rows=64'),
  ('b4dec31a-422b-3ab2-a199-964773ac05b0', 'GK-KARDUS-000119', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 10:16:00+07', '2026-04-29 10:16:00+07', 'source_inventory_rows=65'),
  ('2fd2238f-b97d-398c-8de4-6aa4129c2d57', 'GK-KARDUS-000121', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 10:17:00+07', '2026-04-29 10:17:00+07', 'source_inventory_rows=66'),
  ('c0e4e693-0f01-3c80-82d6-33a16677b082', 'GK-KARDUS-000122', 'ATOMY-HEMOHIM', 2, 2, '2026-04-29 10:19:00+07', '2026-04-29 10:20:00+07', 'source_inventory_rows=67|68'),
  ('d40a8dce-cbc0-3ad8-b7b8-d363931a5b41', 'GK-KARDUS-000124', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 10:20:00+07', '2026-04-29 10:20:00+07', 'source_inventory_rows=69'),
  ('9550dd4f-1af4-3061-b893-efd48f2b1d9c', 'GK-KARDUS-000125', 'ATOMY-HEMOHIM', 4, 4, '2026-04-29 10:20:00+07', '2026-04-29 10:20:00+07', 'source_inventory_rows=70'),
  ('01c72a58-d4d4-30a8-896d-493bb6470ff4', 'GK-KARDUS-000127', 'ATOMY-ABSOLUTE-LOTION', 1, 1, '2026-04-29 10:22:00+07', '2026-04-29 10:22:00+07', 'source_inventory_rows=71'),
  ('76dfcae7-8cd1-31bb-b292-ba7cced8ba5a', 'GK-KARDUS-000129', 'ATOMY-ABSOLUTE-LOTION', 1, 1, '2026-04-29 10:25:00+07', '2026-04-29 10:25:00+07', 'source_inventory_rows=72'),
  ('75e03cfc-5f7f-365f-83a6-1ae2c25dc1d1', 'GK-KARDUS-000126', 'ATOMY-SUNSCREEN-WHITE', 1, 1, '2026-04-29 10:25:00+07', '2026-04-29 10:25:00+07', 'source_inventory_rows=73'),
  ('e46f67ae-9804-3924-9e03-6e5472f68993', 'GK-KARDUS-000130', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-29 10:26:00+07', '2026-04-29 10:26:00+07', 'source_inventory_rows=74'),
  ('bf1a6e79-7941-3edc-861c-78ec82f27e27', 'GK-KARDUS-000130', 'ATOMY-ABSOLUTE-EYE-COMPLEX', 1, 1, '2026-04-29 10:27:00+07', '2026-04-29 10:27:00+07', 'source_inventory_rows=75'),
  ('ef7320ca-b101-35b6-b1d0-9c27e8036b97', 'GK-KARDUS-000126', 'ATOMY-CAFE-ARABICA', 1, 1, '2026-04-29 10:27:00+07', '2026-04-29 10:27:00+07', 'source_inventory_rows=76'),
  ('958e951b-a692-39ab-abfa-d4acdf198306', 'GK-KARDUS-000131', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-29 10:28:00+07', '2026-04-29 10:28:00+07', 'source_inventory_rows=77'),
  ('7826f188-6558-31fc-b078-cf67afe2b55e', 'GK-KARDUS-000132', 'ATOMY-HERBAL-HAIR-CONDITIONER', 2, 2, '2026-04-29 10:29:00+07', '2026-04-29 10:30:00+07', 'source_inventory_rows=78|80'),
  ('d3d97fe7-941a-3c45-b867-304f7aaa3adb', 'GK-KARDUS-000132', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 10:30:00+07', '2026-04-29 10:30:00+07', 'source_inventory_rows=79'),
  ('2534e5b2-8011-344f-aa38-46e4d44e4a19', 'GK-KARDUS-000132', 'ATOMY-HERBAL-HAIR-TONIC', 2, 2, '2026-04-29 10:31:00+07', '2026-04-29 10:31:00+07', 'source_inventory_rows=81'),
  ('ae56310b-bc2b-37a0-b102-0ae4b792d76f', 'GK-KARDUS-000132', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 2, '2026-04-29 10:31:00+07', '2026-04-29 10:31:00+07', 'source_inventory_rows=82'),
  ('a90b2cc5-782b-3702-9eb5-b73d1e62d6cf', 'GK-KARDUS-000132', 'ATOMY-PROBIOTICS-10', 2, 2, '2026-04-29 10:32:00+07', '2026-04-29 10:32:00+07', 'source_inventory_rows=83'),
  ('a7015300-117c-338e-8f33-753daf4f237d', 'GK-KARDUS-000132', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 2, '2026-04-29 10:32:00+07', '2026-04-29 10:32:00+07', 'source_inventory_rows=84'),
  ('5b3dba9d-3f55-3ed2-8a0c-5be9fe99e2fa', 'GK-KARDUS-000134', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-29 10:32:00+07', '2026-04-29 10:32:00+07', 'source_inventory_rows=85'),
  ('ee37b440-ee1b-3360-9acd-650d0bba4e6b', 'GK-KARDUS-000134', 'ATOMY-HERBAL-HAIR-TONIC', 2, 2, '2026-04-29 10:32:00+07', '2026-04-29 10:32:00+07', 'source_inventory_rows=86'),
  ('2815c092-d748-36b6-9f95-e338d24410db', 'GK-KARDUS-000135', 'ATOMY-BODY-CLEANSER', 1, 1, '2026-04-29 10:35:00+07', '2026-04-29 10:35:00+07', 'source_inventory_rows=87'),
  ('7b02e536-98c7-3fac-867f-c80c76b79728', 'GK-KARDUS-000135', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-04-29 10:35:00+07', '2026-04-29 10:35:00+07', 'source_inventory_rows=88'),
  ('82306b5d-b53c-3fbb-87c5-77b56e414f34', 'GK-KARDUS-000135', 'ATOMY-EVENING-CARE-4-SET', 2, 2, '2026-04-29 10:35:00+07', '2026-04-29 10:35:00+07', 'source_inventory_rows=89'),
  ('5264c88a-06af-3caa-973e-fbab2bad2ac1', 'GK-KARDUS-000135', 'ATOMY-BODY-LOTION', 2, 2, '2026-04-29 10:36:00+07', '2026-04-29 10:36:00+07', 'source_inventory_rows=90'),
  ('09d8264a-a7b1-3e2a-84bb-4c7633ac8821', 'GK-KARDUS-000136', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 10:37:00+07', '2026-04-29 10:37:00+07', 'source_inventory_rows=91'),
  ('ab47261d-13f0-3abd-a058-f5a6edadcea1', 'GK-KARDUS-000137', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 10:38:00+07', '2026-04-29 10:38:00+07', 'source_inventory_rows=92'),
  ('2bbc56e4-42f5-37ec-9c07-d968007bee60', 'GK-KARDUS-000138', 'ATOMY-HERBAL-HAIR-CONDITIONER', 2, 2, '2026-04-29 10:39:00+07', '2026-04-29 10:39:00+07', 'source_inventory_rows=93'),
  ('f719568d-85d9-328b-8bc0-e82d9f374425', 'GK-KARDUS-000138', 'ATOMY-ABSOLUTE-AMPOULE', 1, 1, '2026-04-29 10:39:00+07', '2026-04-29 10:39:00+07', 'source_inventory_rows=94'),
  ('4aeb473d-df06-3907-8ed7-b6aaa2f23c4e', 'GK-KARDUS-000139', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 1, '2026-04-29 10:39:00+07', '2026-04-29 10:39:00+07', 'source_inventory_rows=95'),
  ('d757f730-810c-35be-ab90-a2cbda1cc1ab', 'GK-KARDUS-000138', 'ATOMY-HERBAL-HAIR-TONIC', 4, 4, '2026-04-29 10:40:00+07', '2026-04-29 10:43:00+07', 'source_inventory_rows=96|102'),
  ('85d3819b-ce24-3b2e-9941-6bc91409098b', 'GK-KARDUS-000140', 'ATOMY-BODY-CLEANSER', 1, 1, '2026-04-29 10:42:00+07', '2026-04-29 10:42:00+07', 'source_inventory_rows=97'),
  ('7bc20f13-3c3d-3665-9d79-ae44efd3ecec', 'GK-KARDUS-000140', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-04-29 10:42:00+07', '2026-04-29 10:42:00+07', 'source_inventory_rows=98'),
  ('59d2438f-714f-36db-a380-8966de53da65', 'GK-KARDUS-000140', 'ATOMY-EVENING-CARE-4-SET', 1, 1, '2026-04-29 10:42:00+07', '2026-04-29 10:42:00+07', 'source_inventory_rows=99'),
  ('6a0e52ee-93ff-3435-8dfc-20b925a4f3bc', 'GK-KARDUS-000140', 'ATOMY-BODY-LOTION', 1, 1, '2026-04-29 10:42:00+07', '2026-04-29 10:42:00+07', 'source_inventory_rows=100'),
  ('ecf796ea-05b9-347b-bd59-0db6e5f0a93a', 'GK-KARDUS-000140', 'ATOMY-PROBIOTICS-10', 1, 1, '2026-04-29 10:43:00+07', '2026-04-29 10:43:00+07', 'source_inventory_rows=101'),
  ('b3d94b9d-35af-3f9f-a7d2-45ff5b5a5871', 'GK-KARDUS-000141', 'ATOMY-BODY-CLEANSER', 1, 1, '2026-04-29 10:44:00+07', '2026-04-29 10:44:00+07', 'source_inventory_rows=103'),
  ('8f44e067-c71b-38a1-ae3e-c7f4c6bf9b43', 'GK-KARDUS-000141', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 2, '2026-04-29 10:44:00+07', '2026-04-29 10:44:00+07', 'source_inventory_rows=104'),
  ('dfcf80ed-315b-386d-bb50-eeff6e3fbae1', 'GK-KARDUS-000141', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-04-29 10:44:00+07', '2026-04-29 10:44:00+07', 'source_inventory_rows=105'),
  ('97bd2ee7-770e-3e2b-a7f4-093cf456f2ec', 'GK-KARDUS-000141', 'ATOMY-EVENING-CARE-4-SET', 1, 1, '2026-04-29 10:44:00+07', '2026-04-29 10:44:00+07', 'source_inventory_rows=106'),
  ('050fdc6f-4519-3b8f-8d50-a83865f91685', 'GK-KARDUS-000141', 'ATOMY-BODY-LOTION', 1, 1, '2026-04-29 10:44:00+07', '2026-04-29 10:44:00+07', 'source_inventory_rows=107'),
  ('d4c8d597-30a0-350a-9f70-0de523f2c3b9', 'GK-KARDUS-000142', 'ATOMY-BODY-CLEANSER', 1, 1, '2026-04-29 10:46:00+07', '2026-04-29 10:46:00+07', 'source_inventory_rows=108'),
  ('68cbe3fe-d806-36ab-bafb-ef857d62b6d2', 'GK-KARDUS-000142', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-04-29 10:46:00+07', '2026-04-29 10:46:00+07', 'source_inventory_rows=109'),
  ('ca99b099-2aa2-3f3a-ad57-98188b1b516a', 'GK-KARDUS-000142', 'ATOMY-EVENING-CARE-4-SET', 1, 1, '2026-04-29 10:46:00+07', '2026-04-29 10:46:00+07', 'source_inventory_rows=110'),
  ('a8e5948d-9ed4-3dd7-915f-30b6ab186477', 'GK-KARDUS-000142', 'ATOMY-BODY-LOTION', 1, 1, '2026-04-29 10:46:00+07', '2026-04-29 10:46:00+07', 'source_inventory_rows=111'),
  ('172ca23f-d17c-3e70-968d-b42289943a80', 'GK-KARDUS-000143', 'ATOMY-TRAVEL-KIT', 4, 4, '2026-04-29 10:47:00+07', '2026-04-29 10:47:00+07', 'source_inventory_rows=112'),
  ('ed4a038f-78ee-36b7-a08e-b9962e6b10cd', 'GK-KARDUS-000147', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-29 10:49:00+07', '2026-04-29 10:49:00+07', 'source_inventory_rows=113'),
  ('8673c9fe-8d98-37c9-a9e9-391bf3bb9ea9', 'GK-KARDUS-000147', 'ATOMY-HEMOHIM', 2, 2, '2026-04-29 10:50:00+07', '2026-04-29 10:50:00+07', 'source_inventory_rows=114'),
  ('b2cd4214-d8fb-3b1b-a0e9-b4785d2a1191', 'GK-KARDUS-000148', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-29 10:51:00+07', '2026-04-29 10:51:00+07', 'source_inventory_rows=115'),
  ('3c34b725-cb0f-3bd9-906c-4fd01bd21fdd', 'GK-KARDUS-000148', 'ATOMY-VITAMIN-B-COMPLEX', 1, 1, '2026-04-29 10:51:00+07', '2026-04-29 10:51:00+07', 'source_inventory_rows=116'),
  ('75d72991-aac7-3318-a103-2838dca264cb', 'GK-KARDUS-000149', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-29 10:53:00+07', '2026-04-29 10:53:00+07', 'source_inventory_rows=117'),
  ('b7af7002-2aca-3b93-a1e6-4b3c4dffdc9d', 'GK-KARDUS-000150', 'ATOMY-HEMOHIM', 1, 1, '2026-04-29 10:54:00+07', '2026-04-29 10:54:00+07', 'source_inventory_rows=118'),
  ('d1903717-f415-38fa-92d4-c99f83c71b81', 'GK-KARDUS-000150', 'ATOMY-TRAVEL-KIT', 1, 1, '2026-04-29 10:54:00+07', '2026-04-29 10:54:00+07', 'source_inventory_rows=119'),
  ('2f34aeae-8eb9-38ed-bd38-92e34fe66462', 'GK-KARDUS-000152', 'ATOMY-BODY-CLEANSER', 1, 1, '2026-04-29 10:56:00+07', '2026-04-29 10:56:00+07', 'source_inventory_rows=120'),
  ('a101e505-c040-3b6e-9b33-623ab0039a58', 'GK-KARDUS-000152', 'ATOMY-EVENING-CARE-4-SET', 1, 1, '2026-04-29 10:56:00+07', '2026-04-29 10:56:00+07', 'source_inventory_rows=121'),
  ('f1197d30-3234-360b-9ef0-4c5b370877a5', 'GK-KARDUS-000152', 'ATOMY-BODY-LOTION', 1, 1, '2026-04-29 10:56:00+07', '2026-04-29 10:56:00+07', 'source_inventory_rows=122'),
  ('338ea7e3-fafd-32b8-9c72-96092c07dcb7', 'GK-KARDUS-000152', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-04-29 10:56:00+07', '2026-04-29 10:56:00+07', 'source_inventory_rows=123'),
  ('0859ad56-0dd1-3375-b776-b42143866846', 'GK-KARDUS-000155', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 1, '2026-04-29 10:59:00+07', '2026-04-29 10:59:00+07', 'source_inventory_rows=124'),
  ('028fbfba-7844-3573-bced-12ceea423704', 'GK-KARDUS-000154', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-29 10:59:00+07', '2026-04-29 10:59:00+07', 'source_inventory_rows=125'),
  ('e090a8b2-e1de-3ea9-8331-0e25c861831f', 'GK-KARDUS-000154', 'ATOMY-HERBAL-HAIR-TONIC', 3, 3, '2026-04-29 10:59:00+07', '2026-04-29 11:00:00+07', 'source_inventory_rows=126|127|133'),
  ('e8005926-7de4-3ad8-990e-c7b43d58d0b3', 'GK-KARDUS-000154', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 2, '2026-04-29 11:00:00+07', '2026-04-29 11:00:00+07', 'source_inventory_rows=128|129'),
  ('81500521-f9ef-3dec-a949-770b6558fd63', 'GK-KARDUS-000154', 'ATOMY-PROBIOTICS-10', 2, 2, '2026-04-29 11:00:00+07', '2026-04-29 11:00:00+07', 'source_inventory_rows=130|131'),
  ('6bc4944c-4e21-3f1b-96f9-5010a52e2aa9', 'GK-KARDUS-000154', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 1, '2026-04-29 11:00:00+07', '2026-04-29 11:00:00+07', 'source_inventory_rows=132'),
  ('e6882d5d-81c8-3cd3-a8f8-2e81663701e1', 'GK-KARDUS-000156', 'ATOMY-HEMOHIM', 4, 4, '2026-04-30 05:55:00+07', '2026-04-30 05:55:00+07', 'source_inventory_rows=134'),
  ('f3644809-2d96-3e1d-b73b-3b8c624b3645', 'GK-KARDUS-000157', 'ATOMY-HEMOHIM', 4, 4, '2026-04-30 06:03:00+07', '2026-04-30 06:03:00+07', 'source_inventory_rows=135'),
  ('2b44e2fc-02f7-3c5b-a759-e9bf4dfe3079', 'GK-KARDUS-000158', 'ATOMY-HEMOHIM', 4, 4, '2026-04-30 06:04:00+07', '2026-04-30 06:04:00+07', 'source_inventory_rows=136'),
  ('d826b946-4fa2-3ca0-bef2-d6f03bd9c36a', 'GK-KARDUS-000159', 'ATOMY-HEMOHIM', 4, 4, '2026-04-30 06:06:00+07', '2026-04-30 06:06:00+07', 'source_inventory_rows=137'),
  ('aa4c52b2-84b7-384f-aea8-29e64c51d725', 'GK-KARDUS-000160', 'ATOMY-HEMOHIM', 4, 4, '2026-04-30 06:07:00+07', '2026-04-30 06:07:00+07', 'source_inventory_rows=138'),
  ('ba2e89ea-17dd-325f-897b-60b6641672aa', 'GK-KARDUS-000161', 'ATOMY-HEMOHIM', 2, 2, '2026-04-30 06:09:00+07', '2026-04-30 06:09:00+07', 'source_inventory_rows=139'),
  ('b34b743a-6163-37f5-b949-c121949f4896', 'GK-KARDUS-000162', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 06:12:00+07', '2026-04-30 06:12:00+07', 'source_inventory_rows=140'),
  ('96e6557f-9134-3426-ac2c-9736e9f8a383', 'GK-KARDUS-000163', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 06:45:00+07', '2026-04-30 06:45:00+07', 'source_inventory_rows=141'),
  ('c5af9ea9-8ab5-35e3-b724-041ebbf24806', 'GK-KARDUS-000164', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 06:46:00+07', '2026-04-30 06:46:00+07', 'source_inventory_rows=142'),
  ('690f53f3-ba4d-3ee0-9db8-1e04a3267483', 'GK-KARDUS-000165', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 06:51:00+07', '2026-04-30 06:51:00+07', 'source_inventory_rows=143'),
  ('70fa993a-9ad3-3fdb-9d76-927006dcd6a5', 'GK-KARDUS-000166', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 06:53:00+07', '2026-04-30 06:53:00+07', 'source_inventory_rows=144'),
  ('4f60603a-a7f3-30c6-a789-8e39d259f3e8', 'GK-KARDUS-000167', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 06:57:00+07', '2026-04-30 06:57:00+07', 'source_inventory_rows=145'),
  ('9d072e96-0309-31cb-990f-0b4a37c4f914', 'GK-KARDUS-000168', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 07:02:00+07', '2026-04-30 07:02:00+07', 'source_inventory_rows=146'),
  ('ec356c1b-38af-3ab5-a5a4-eca8ebfb7589', 'GK-KARDUS-000169', 'ATOMY-PAKET-RAMADHAN-CARE', 1, 1, '2026-04-30 07:03:00+07', '2026-04-30 07:03:00+07', 'source_inventory_rows=147'),
  ('d00be9bd-023e-39a0-9686-c7352d66baa3', 'GK-KARDUS-000170', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 1, '2026-04-30 07:04:00+07', '2026-04-30 07:04:00+07', 'source_inventory_rows=148'),
  ('fd65d781-87eb-3b09-96de-588e2787f034', 'GK-KARDUS-000170', 'ATOMY-PROBIOTICS-10', 1, 1, '2026-04-30 07:05:00+07', '2026-04-30 07:05:00+07', 'source_inventory_rows=149'),
  ('2f1cce3d-e2d1-345c-917d-949d5c201982', 'GK-KARDUS-000170', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 07:05:00+07', '2026-04-30 07:05:00+07', 'source_inventory_rows=150'),
  ('ab3dfb39-9295-3083-80f8-d4bddb9ef92b', 'GK-KARDUS-000171', 'ATOMY-HONGSAMDAN-RED-GINSENG', 2, 2, '2026-04-30 07:07:00+07', '2026-04-30 07:07:00+07', 'source_inventory_rows=151'),
  ('695b733d-3d5b-3843-b7c8-97201285f27b', 'GK-KARDUS-000172', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 09:33:00+07', '2026-04-30 09:33:00+07', 'source_inventory_rows=152'),
  ('d5e54658-4aab-343f-b3cc-aeb2027c7973', 'GK-KARDUS-000173', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 09:33:00+07', '2026-04-30 09:33:00+07', 'source_inventory_rows=153'),
  ('fbd30e91-0c29-3d3e-8781-caf0f5e67438', 'GK-KARDUS-000174', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 1, '2026-04-30 09:35:00+07', '2026-04-30 09:35:00+07', 'source_inventory_rows=154'),
  ('28369ea8-d534-33d6-b637-68d82b1fd743', 'GK-KARDUS-000176', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 1, '2026-04-30 09:36:00+07', '2026-04-30 09:36:00+07', 'source_inventory_rows=155'),
  ('15c90758-cdb5-35c0-8d73-29e617266e29', 'GK-KARDUS-000177', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 1, '2026-04-30 09:37:00+07', '2026-04-30 09:37:00+07', 'source_inventory_rows=156'),
  ('a415bafc-eac3-3d4f-aa9c-c5842c94bb10', 'GK-KARDUS-000177', 'ATOMY-HEMOHIM', 4, 4, '2026-04-30 09:37:00+07', '2026-04-30 09:37:00+07', 'source_inventory_rows=157'),
  ('a075f587-a476-30a4-ac00-48e8f9eaff70', 'GK-KARDUS-000178', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 09:38:00+07', '2026-04-30 09:38:00+07', 'source_inventory_rows=158'),
  ('a56fd08b-ef7a-3034-a230-1184562e2583', 'GK-KARDUS-000180', 'ATOMY-TRAVEL-KIT', 4, 4, '2026-04-30 09:39:00+07', '2026-04-30 09:39:00+07', 'source_inventory_rows=159'),
  ('cc165c26-73e5-3fb6-918a-20ae5957cf0c', 'GK-KARDUS-000180', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 09:39:00+07', '2026-04-30 09:39:00+07', 'source_inventory_rows=160'),
  ('95c1c7a7-e319-3c58-ae4b-d1ebc67c6a1f', 'GK-KARDUS-000181', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 09:40:00+07', '2026-04-30 09:40:00+07', 'source_inventory_rows=161'),
  ('4ca9d848-3176-336e-9c8b-3474f65f0ef3', 'GK-KARDUS-000183', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 09:41:00+07', '2026-04-30 09:41:00+07', 'source_inventory_rows=162'),
  ('a528d95e-b9c0-3234-acb0-fb7ab3ceb506', 'GK-KARDUS-000184', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 1, '2026-04-30 09:42:00+07', '2026-04-30 09:42:00+07', 'source_inventory_rows=163'),
  ('67aa5a49-6859-392f-9681-9b86c5f388ca', 'GK-KARDUS-000186', 'ATOMY-TRAVEL-KIT', 1, 1, '2026-04-30 09:43:00+07', '2026-04-30 09:43:00+07', 'source_inventory_rows=164'),
  ('cb451624-1f5c-306c-93d1-8b1c89f77d17', 'GK-KARDUS-000188', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 09:45:00+07', '2026-04-30 09:45:00+07', 'source_inventory_rows=165'),
  ('d81f53ff-a2c3-33f9-a6e4-168ef209738d', 'GK-KARDUS-000188', 'ATOMY-TOOTHBRUSH', 4, 4, '2026-04-30 09:46:00+07', '2026-04-30 09:46:00+07', 'source_inventory_rows=166'),
  ('e41a7823-9391-3fa4-8270-72dad0bee6de', 'GK-KARDUS-000188', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 1, '2026-04-30 09:46:00+07', '2026-04-30 09:46:00+07', 'source_inventory_rows=167'),
  ('35cfb0f6-dd83-380a-812c-109bef0ba582', 'GK-KARDUS-000187', 'ATOMY-BB-CREAM', 1, 1, '2026-04-30 09:47:00+07', '2026-04-30 09:47:00+07', 'source_inventory_rows=168'),
  ('c4433eb3-2d9d-3d13-b335-c8a17547de3c', 'GK-KARDUS-000187', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 09:47:00+07', '2026-04-30 09:47:00+07', 'source_inventory_rows=169'),
  ('60cb6770-8dcf-3fc5-8fe7-a6767bea15dd', 'GK-KARDUS-000191', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 09:50:00+07', '2026-04-30 09:50:00+07', 'source_inventory_rows=170'),
  ('05ee9674-f9a9-3d58-9cb4-18414d5273b1', 'GK-KARDUS-000194', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 09:51:00+07', '2026-04-30 09:51:00+07', 'source_inventory_rows=171'),
  ('69821edd-7dcb-3f45-8c0e-c38ad4700072', 'GK-KARDUS-000196', 'ATOMY-TRAVEL-KIT', 1, 1, '2026-04-30 09:53:00+07', '2026-04-30 09:53:00+07', 'source_inventory_rows=172'),
  ('a1805090-bfb5-39be-9702-e1cdbcbde040', 'GK-KARDUS-000197', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 09:53:00+07', '2026-04-30 09:53:00+07', 'source_inventory_rows=173'),
  ('a34f4c94-3679-37bb-be79-b13041225c0d', 'GK-KARDUS-000198', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 09:54:00+07', '2026-04-30 09:54:00+07', 'source_inventory_rows=174'),
  ('1c637756-ec0d-3ba8-ad7a-938edb7cf8c6', 'GK-KARDUS-000199', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 09:55:00+07', '2026-04-30 09:55:00+07', 'source_inventory_rows=175'),
  ('836eeaa3-85fc-3034-ba4d-8b61e5ebd9f1', 'GK-KARDUS-000200', 'ATOMY-PAKET-BERKAH-RAMADAN-B', 1, 1, '2026-04-30 09:56:00+07', '2026-04-30 09:56:00+07', 'source_inventory_rows=176'),
  ('cdc9440f-1ae3-3900-b8d1-f36a9a042558', 'GK-KARDUS-000201', 'ATOMY-TOOTHPASTE-50G', 1, 1, '2026-04-30 09:56:00+07', '2026-04-30 09:56:00+07', 'source_inventory_rows=177'),
  ('2dbe533e-a8cd-352a-8b22-e89e4809f5a1', 'GK-KARDUS-000201', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 09:57:00+07', '2026-04-30 09:57:00+07', 'source_inventory_rows=178'),
  ('8b52c16e-dab4-3767-b523-9a10fcfa1024', 'GK-KARDUS-000201', 'ATOMY-TOOTHBRUSH', 1, 1, '2026-04-30 09:57:00+07', '2026-04-30 09:57:00+07', 'source_inventory_rows=179'),
  ('a8c8b829-c3ee-3c80-90dd-96a4498615f4', 'GK-KARDUS-000202', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 09:58:00+07', '2026-04-30 09:58:00+07', 'source_inventory_rows=180'),
  ('874bbc30-bd3d-35d7-b67d-7d22a057ab52', 'GK-KARDUS-000203', 'ATOMY-AIDAM-CLEANSER', 1, 1, '2026-04-30 09:59:00+07', '2026-04-30 09:59:00+07', 'source_inventory_rows=181'),
  ('a0113223-566c-3ec7-bdd3-3374733cf47a', 'GK-KARDUS-000203', 'ATOMY-TOOTHPASTE-50G', 1, 1, '2026-04-30 09:59:00+07', '2026-04-30 09:59:00+07', 'source_inventory_rows=182'),
  ('af5f57d0-1597-3bf4-97b0-a92b0d284352', 'GK-KARDUS-000203', 'ATOMY-TRAVEL-KIT', 1, 1, '2026-04-30 09:59:00+07', '2026-04-30 09:59:00+07', 'source_inventory_rows=183'),
  ('2fcc7a0f-a519-36fa-83da-05a389677f7e', 'GK-KARDUS-000206', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 10:01:00+07', '2026-04-30 10:01:00+07', 'source_inventory_rows=184'),
  ('a79cde84-8a7c-3fad-8b2c-9bd2b8605d0d', 'GK-KARDUS-000207', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 10:06:00+07', '2026-04-30 10:06:00+07', 'source_inventory_rows=185'),
  ('1db70fe6-cb9a-3a86-841b-5b4e55b65c89', 'GK-KARDUS-000209', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 1, '2026-04-30 10:11:00+07', '2026-04-30 10:11:00+07', 'source_inventory_rows=186'),
  ('331ad833-fb32-3275-afb7-ba027c2a0d8d', 'GK-KARDUS-000209', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 1, 1, '2026-04-30 10:11:00+07', '2026-04-30 10:11:00+07', 'source_inventory_rows=187'),
  ('b7d8c0ec-29ac-3fc5-9c61-dd7b5d066242', 'GK-KARDUS-000210', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 10:12:00+07', '2026-04-30 10:12:00+07', 'source_inventory_rows=188'),
  ('56a6c8c0-8b1a-3317-ba4a-aff9f2dbf38c', 'GK-KARDUS-000211', 'ATOMY-STAINLESS-STEEL-SCRUBBER', 1, 1, '2026-04-30 10:12:00+07', '2026-04-30 10:12:00+07', 'source_inventory_rows=189'),
  ('d55c6dfc-2654-3a0f-89ef-0c70be744448', 'GK-KARDUS-000210', 'ATOMY-DEEP-CLEANSER-150ML', 1, 1, '2026-04-30 10:13:00+07', '2026-04-30 10:13:00+07', 'source_inventory_rows=190'),
  ('75da776c-7d64-3830-b253-09aea30945d4', 'GK-KARDUS-000211', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 1, '2026-04-30 10:13:00+07', '2026-04-30 10:13:00+07', 'source_inventory_rows=191'),
  ('cb86450b-46aa-371e-9853-c01ab9f047a9', 'GK-KARDUS-000210', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 1, '2026-04-30 10:13:00+07', '2026-04-30 10:13:00+07', 'source_inventory_rows=192'),
  ('2b2a5c12-05f7-3527-aa88-ebadf2abaea7', 'GK-KARDUS-000213', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-04-30 10:16:00+07', '2026-04-30 10:16:00+07', 'source_inventory_rows=193'),
  ('a5b4ae6c-0844-3ce6-bda3-baeb304d687e', 'GK-KARDUS-000218', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 10:21:00+07', '2026-04-30 10:21:00+07', 'source_inventory_rows=194'),
  ('6a314dbf-1ec9-3c54-87da-0f0df9179b4b', 'GK-KARDUS-000228', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 10:37:00+07', '2026-04-30 10:37:00+07', 'source_inventory_rows=195'),
  ('b480f55b-ce9d-374f-8833-9b40ef2928eb', 'GK-KARDUS-000230', 'ATOMY-HEMOHIM', 1, 1, '2026-04-30 10:40:00+07', '2026-04-30 10:40:00+07', 'source_inventory_rows=196'),
  ('6dfb4860-4254-386c-9237-073912ccf88b', 'GK-KARDUS-000236', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 1, '2026-05-02 07:48:00+07', '2026-05-02 07:48:00+07', 'source_inventory_rows=197'),
  ('83f95cdf-db12-3f35-9247-03ece89530c9', 'GK-KARDUS-000236', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 1, '2026-05-02 07:48:00+07', '2026-05-02 07:48:00+07', 'source_inventory_rows=198'),
  ('20cc4238-e8d0-32b8-84ec-554bdb80d704', 'GK-KARDUS-000237', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 07:51:00+07', '2026-05-02 07:51:00+07', 'source_inventory_rows=199'),
  ('c4c2cae5-b212-3f56-93fe-e5d6e77ba64e', 'GK-KARDUS-000235', 'ATOMY-HEMOHIM', 7, 7, '2026-05-02 07:56:00+07', '2026-05-02 09:41:00+07', 'source_inventory_rows=200|202|204|206|209|214|224'),
  ('a29713ad-e709-3f89-90b0-3230e23ce860', 'GK-KARDUS-000241', 'ATOMY-CAFE-ARABICA', 1, 1, '2026-05-02 07:58:00+07', '2026-05-02 07:58:00+07', 'source_inventory_rows=201'),
  ('28ed0930-2655-356d-bfb2-9515aec94ecd', 'GK-KARDUS-000264', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 08:21:00+07', '2026-05-02 08:21:00+07', 'source_inventory_rows=203'),
  ('07ec6cd4-73c6-3685-ae40-b4cb77c58717', 'GK-KARDUS-000272', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 08:28:00+07', '2026-05-02 08:28:00+07', 'source_inventory_rows=205'),
  ('3f461812-3dfa-38f9-8685-19174fc4928f', 'GK-KARDUS-000277', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 08:32:00+07', '2026-05-02 08:32:00+07', 'source_inventory_rows=207'),
  ('2c2539db-d4ea-3502-905e-3ec3f848149f', 'GK-KARDUS-000283', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 08:37:00+07', '2026-05-02 08:37:00+07', 'source_inventory_rows=208'),
  ('e7a409c5-eb85-3e4b-b310-e75be7a1e075', 'GK-KARDUS-000287', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 08:46:00+07', '2026-05-02 08:46:00+07', 'source_inventory_rows=210'),
  ('8f4068a0-2f40-306d-a886-89b6837b0504', 'GK-KARDUS-000288', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 08:48:00+07', '2026-05-02 08:48:00+07', 'source_inventory_rows=211'),
  ('23b70d53-2765-33b1-9de8-adfc91140e86', 'GK-KARDUS-000291', 'ATOMY-HEMOHIM', 4, 4, '2026-05-02 08:59:00+07', '2026-05-02 08:59:00+07', 'source_inventory_rows=212'),
  ('01e2a212-ec29-3935-bd2c-39ac6828ac94', 'GK-KARDUS-000292', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 09:02:00+07', '2026-05-02 09:02:00+07', 'source_inventory_rows=213'),
  ('ad7b7b51-3871-3ae2-adac-9619df6d2e41', 'GK-KARDUS-000298', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 09:10:00+07', '2026-05-02 09:10:00+07', 'source_inventory_rows=215'),
  ('e07d8b29-fe50-329e-8004-31cabc46bdf2', 'GK-KARDUS-000299', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 09:11:00+07', '2026-05-02 09:11:00+07', 'source_inventory_rows=216'),
  ('f3086f28-bf05-3180-9fdd-6aeb1fc60dad', 'GK-KARDUS-000301', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 09:14:00+07', '2026-05-02 09:14:00+07', 'source_inventory_rows=217'),
  ('d62db933-a74e-35c4-8149-2a5e4b2b35ff', 'GK-KARDUS-000303', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 09:17:00+07', '2026-05-02 09:17:00+07', 'source_inventory_rows=218'),
  ('f0e916f9-0c21-3bc2-b739-caea197624ad', 'GK-KARDUS-000306', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 09:22:00+07', '2026-05-02 09:22:00+07', 'source_inventory_rows=219'),
  ('aaecaa90-a821-3c5c-a441-1b06822a787f', 'GK-KARDUS-000307', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 09:23:00+07', '2026-05-02 09:23:00+07', 'source_inventory_rows=220'),
  ('2fe25289-9e11-3a9e-a57e-fc376fd78c68', 'GK-KARDUS-000308', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 09:26:00+07', '2026-05-02 09:26:00+07', 'source_inventory_rows=221'),
  ('b1abf453-c174-3edb-aa42-a85a0700c6ab', 'GK-KARDUS-000317', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 09:36:00+07', '2026-05-02 09:36:00+07', 'source_inventory_rows=222'),
  ('9fa7e5b9-bcee-3f9b-b84d-4350bd34f06f', 'GK-KARDUS-000318', 'ATOMY-TOOTHPASTE-50G', 1, 1, '2026-05-02 09:40:00+07', '2026-05-02 09:40:00+07', 'source_inventory_rows=223'),
  ('566c79ae-70c1-38f1-89e3-dbf2aec32e0f', 'GK-KARDUS-000320', 'ATOMY-STAINLESS-STEEL-SCRUBBER', 1, 1, '2026-05-02 09:42:00+07', '2026-05-02 09:42:00+07', 'source_inventory_rows=225'),
  ('86195199-0669-3886-9f8e-0d39e71c590e', 'GK-KARDUS-000321', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 1, '2026-05-02 09:43:00+07', '2026-05-02 09:43:00+07', 'source_inventory_rows=226'),
  ('a6d7df00-9b5a-37ed-b00b-81ead71e07bd', 'GK-KARDUS-000321', 'ATOMY-ABSOLUTE-AMPOULE', 1, 1, '2026-05-02 09:44:00+07', '2026-05-02 09:44:00+07', 'source_inventory_rows=227'),
  ('3f8c0bf2-fab1-3b79-936b-7b2218d7a767', 'GK-KARDUS-000321', 'ATOMY-TRAVEL-KIT', 1, 1, '2026-05-02 09:44:00+07', '2026-05-02 09:44:00+07', 'source_inventory_rows=228'),
  ('b791b862-82d1-390b-85db-41cbad627112', 'GK-KARDUS-000322', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 09:45:00+07', '2026-05-02 09:45:00+07', 'source_inventory_rows=229'),
  ('ace302cb-30ed-3d40-9f31-cb313c566060', 'GK-KARDUS-000323', 'ATOMY-TOOTHPASTE-200G', 1, 1, '2026-05-02 09:46:00+07', '2026-05-02 09:46:00+07', 'source_inventory_rows=230'),
  ('a22703e2-59b0-34c3-94c2-cef441df38ce', 'GK-KARDUS-000235', 'ATOMY-SUNSCREEN-WHITE', 1, 1, '2026-05-02 09:47:00+07', '2026-05-02 09:47:00+07', 'source_inventory_rows=231'),
  ('fccfead8-9639-3cd5-b6d3-7118737fb2dc', 'GK-KARDUS-000323', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 1, '2026-05-02 09:47:00+07', '2026-05-02 09:47:00+07', 'source_inventory_rows=232'),
  ('5ae854f7-efd9-34ba-8e81-f671489ea027', 'GK-KARDUS-000324', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 09:48:00+07', '2026-05-02 09:48:00+07', 'source_inventory_rows=233'),
  ('95fd4202-2328-3b01-90cf-e51337961cbf', 'GK-KARDUS-000323', 'ATOMY-SUNSCREEN-BEIGE', 2, 2, '2026-05-02 09:48:00+07', '2026-05-02 09:48:00+07', 'source_inventory_rows=234|235'),
  ('3cbc04a1-9a8c-3240-aba4-61751f0dcd8c', 'GK-KARDUS-000323', 'ATOMY-TOOTHBRUSH', 1, 1, '2026-05-02 09:49:00+07', '2026-05-02 09:49:00+07', 'source_inventory_rows=236'),
  ('ca02f997-a712-34e4-b612-32c5bdb6ea75', 'GK-KARDUS-000325', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 09:50:00+07', '2026-05-02 09:50:00+07', 'source_inventory_rows=237'),
  ('18564639-98cb-3ea5-b712-707b55f5859c', 'GK-KARDUS-000327', 'ATOMY-BABY-LOTION', 1, 1, '2026-05-02 09:55:00+07', '2026-05-02 09:55:00+07', 'source_inventory_rows=238'),
  ('d57892b4-95f7-3a6e-aec7-33c230cf2cdd', 'GK-KARDUS-000235', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 2, 2, '2026-05-02 10:01:00+07', '2026-05-02 10:30:00+07', 'source_inventory_rows=239|268'),
  ('d8cd6851-28aa-3920-9668-9337885d4ad5', 'GK-KARDUS-000235', 'ATOMY-SLIM-BODY-SHAKE-2-0', 1, 1, '2026-05-02 10:04:00+07', '2026-05-02 10:04:00+07', 'source_inventory_rows=240'),
  ('43ca2bbc-9875-389e-bb1c-39fda3c9d52c', 'GK-KARDUS-000334', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-02 10:04:00+07', '2026-05-02 10:04:00+07', 'source_inventory_rows=241'),
  ('78ae12a0-b84b-387a-bae0-d4c23688938a', 'GK-KARDUS-000332', 'ATOMY-CAFE-ARABICA', 1, 1, '2026-05-02 10:04:00+07', '2026-05-02 10:04:00+07', 'source_inventory_rows=242'),
  ('77291cff-d3d4-3d32-a1ec-a9d90e6c7065', 'GK-KARDUS-000333', 'ATOMY-BB-CREAM', 1, 1, '2026-05-02 10:04:00+07', '2026-05-02 10:04:00+07', 'source_inventory_rows=243'),
  ('b10aba94-d751-3acc-afb4-4f4f09c3709f', 'GK-KARDUS-000329', 'ATOMY-SLIM-BODY-SHAKE-2-0', 1, 1, '2026-05-02 10:05:00+07', '2026-05-02 10:05:00+07', 'source_inventory_rows=244'),
  ('a341fcbc-8a85-39be-b333-6be4727d5582', 'GK-KARDUS-000329', 'ATOMY-TOOTHPASTE-50G', 1, 1, '2026-05-02 10:05:00+07', '2026-05-02 10:05:00+07', 'source_inventory_rows=245'),
  ('debe358a-38f3-359c-8edb-4bb84495dc49', 'GK-KARDUS-000331', 'ATOMY-TOOTHPASTE-50G', 1, 1, '2026-05-02 10:06:00+07', '2026-05-02 10:06:00+07', 'source_inventory_rows=246'),
  ('8e3bef12-3cba-3e42-af2f-81d96bb8a6ed', 'GK-KARDUS-000331', 'ATOMY-TOOTHPASTE-200G', 1, 1, '2026-05-02 10:08:00+07', '2026-05-02 10:08:00+07', 'source_inventory_rows=247'),
  ('58bfb23d-5df6-3deb-a56b-6ff45f06c42d', 'GK-KARDUS-000331', 'ATOMY-SUNSCREEN-WHITE', 1, 1, '2026-05-02 10:08:00+07', '2026-05-02 10:08:00+07', 'source_inventory_rows=248'),
  ('ebad2e02-27d4-3b4c-8847-4546dd79d164', 'GK-KARDUS-000331', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 1, '2026-05-02 10:09:00+07', '2026-05-02 10:09:00+07', 'source_inventory_rows=249'),
  ('724e0a48-2e79-37f3-916c-6da3d88f2d22', 'GK-KARDUS-000331', 'ATOMY-SUNSCREEN-BEIGE', 1, 1, '2026-05-02 10:09:00+07', '2026-05-02 10:09:00+07', 'source_inventory_rows=250'),
  ('218c3dd8-9724-3e4e-aa90-ca66040ff845', 'GK-KARDUS-000331', 'ATOMY-TOOTHBRUSH', 1, 1, '2026-05-02 10:09:00+07', '2026-05-02 10:09:00+07', 'source_inventory_rows=251'),
  ('ad5a4072-5bea-38ee-94b8-52c5b8b9e48c', 'GK-KARDUS-000335', 'ATOMY-BODY-CLEANSER', 1, 1, '2026-05-02 10:13:00+07', '2026-05-02 10:13:00+07', 'source_inventory_rows=252'),
  ('767c455c-a1e1-36b5-b5dd-8a8174c855cc', 'GK-KARDUS-000335', 'ATOMY-TOOTHPASTE-200G', 1, 1, '2026-05-02 10:14:00+07', '2026-05-02 10:14:00+07', 'source_inventory_rows=253'),
  ('4a23da5f-d457-3177-8c3d-088bba281d9c', 'GK-KARDUS-000335', 'ATOMY-SUNSCREEN-WHITE', 1, 1, '2026-05-02 10:14:00+07', '2026-05-02 10:14:00+07', 'source_inventory_rows=254'),
  ('4c00e612-d5e4-3610-aca3-584de3bf7a21', 'GK-KARDUS-000335', 'ATOMY-EVENING-CARE-4-SET', 1, 1, '2026-05-02 10:14:00+07', '2026-05-02 10:14:00+07', 'source_inventory_rows=255'),
  ('5c38a3c7-6da1-301e-8b2c-c250481ac11a', 'GK-KARDUS-000335', 'ATOMY-BODY-LOTION', 1, 1, '2026-05-02 10:14:00+07', '2026-05-02 10:14:00+07', 'source_inventory_rows=256'),
  ('4b077df5-b86a-3596-b0b1-e65992bbc814', 'GK-KARDUS-000335', 'ATOMY-SUNSCREEN-BEIGE', 1, 1, '2026-05-02 10:14:00+07', '2026-05-02 10:14:00+07', 'source_inventory_rows=257'),
  ('7ae800cf-11f5-3ea7-9c8e-425bc6724edf', 'GK-KARDUS-000335', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-05-02 10:15:00+07', '2026-05-02 10:15:00+07', 'source_inventory_rows=258'),
  ('33a45eb0-1d1c-3003-8061-dfff85c910ff', 'GK-KARDUS-000335', 'ATOMY-TOOTHBRUSH', 1, 1, '2026-05-02 10:15:00+07', '2026-05-02 10:15:00+07', 'source_inventory_rows=259'),
  ('3bcffe3f-66dd-3c28-b2be-5b4fba1b1815', 'GK-KARDUS-000336', 'ATOMY-PURE-SPIRULINA', 1, 1, '2026-05-02 10:19:00+07', '2026-05-02 10:19:00+07', 'source_inventory_rows=260'),
  ('0bc1b592-6662-39d6-8858-97cf75803b99', 'GK-KARDUS-000337', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 1, '2026-05-02 10:20:00+07', '2026-05-02 10:20:00+07', 'source_inventory_rows=261'),
  ('a56134fe-e9fb-3382-aec5-1c5b0ca09a98', 'GK-KARDUS-000337', 'ATOMY-ABSOLUTE-AMPOULE', 1, 1, '2026-05-02 10:20:00+07', '2026-05-02 10:20:00+07', 'source_inventory_rows=262'),
  ('5437afd2-2dbc-32a5-acd8-8517bfe502f8', 'GK-KARDUS-000337', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 1, 1, '2026-05-02 10:20:00+07', '2026-05-02 10:20:00+07', 'source_inventory_rows=263'),
  ('755f030c-3338-3270-9aae-05792146f51b', 'GK-KARDUS-000338', 'ATOMY-BODY-CLEANSER', 1, 1, '2026-05-02 10:20:00+07', '2026-05-02 10:20:00+07', 'source_inventory_rows=264'),
  ('186ccb48-5b3e-3db8-bc7f-ccf2c5af25fe', 'GK-KARDUS-000338', 'ATOMY-EVENING-CARE-4-SET', 1, 1, '2026-05-02 10:20:00+07', '2026-05-02 10:20:00+07', 'source_inventory_rows=265'),
  ('deded5ce-38fa-38e3-932b-c4bfcd0c4e4e', 'GK-KARDUS-000338', 'ATOMY-BODY-LOTION', 1, 1, '2026-05-02 10:21:00+07', '2026-05-02 10:21:00+07', 'source_inventory_rows=266'),
  ('9dc6a9fb-a127-3db6-849a-f52e76288505', 'GK-KARDUS-000338', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-05-02 10:21:00+07', '2026-05-02 10:21:00+07', 'source_inventory_rows=267'),
  ('4076651e-1129-3b97-8a26-02c6bf18a699', 'GK-KARDUS-000238', 'ATOMY-HEMOHIM', 1, 1, '2026-05-02 10:31:00+07', '2026-05-02 10:31:00+07', 'source_inventory_rows=269'),
  ('04f71329-5f59-3a23-84fe-e0d9da442b3a', 'GK-KARDUS-000235', 'ATOMY-BODY-CLEANSER', 2, 2, '2026-05-02 10:39:00+07', '2026-05-02 10:48:00+07', 'source_inventory_rows=270|278'),
  ('5c7270a1-26ef-3592-9184-4be95912cbca', 'GK-KARDUS-000235', 'ATOMY-EVENING-CARE-4-SET', 4, 4, '2026-05-02 10:40:00+07', '2026-05-02 11:03:00+07', 'source_inventory_rows=271|281|312'),
  ('14b073ef-03c5-3659-bc0e-363eb47053fc', 'GK-KARDUS-000353', 'ATOMY-SUNSCREEN-WHITE', 2, 2, '2026-05-02 10:42:00+07', '2026-05-02 10:42:00+07', 'source_inventory_rows=272'),
  ('bc06483a-e312-36cb-80aa-d3854d9ecbb4', 'GK-KARDUS-000235', 'ATOMY-BODY-LOTION', 4, 4, '2026-05-02 10:42:00+07', '2026-05-02 10:52:00+07', 'source_inventory_rows=273|285'),
  ('1e28812e-e05f-33a5-98be-467ce558bdfb', 'GK-KARDUS-000235', 'ATOMY-TOOTHPASTE-200G', 2, 2, '2026-05-02 10:43:00+07', '2026-05-02 10:43:00+07', 'source_inventory_rows=274'),
  ('858babd3-d82a-3a4e-b4c3-c059be48651b', 'GK-KARDUS-000235', 'ATOMY-SUNSCREEN-BEIGE', 2, 2, '2026-05-02 10:44:00+07', '2026-05-02 10:44:00+07', 'source_inventory_rows=275'),
  ('741a3686-8277-3b1a-9a08-fa03cf9f1153', 'GK-KARDUS-000235', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-05-02 10:45:00+07', '2026-05-02 10:45:00+07', 'source_inventory_rows=276'),
  ('191e58b6-99de-31a2-9d59-316a75b7e01a', 'GK-KARDUS-000235', 'ATOMY-TOOTHBRUSH', 2, 2, '2026-05-02 10:45:00+07', '2026-05-02 10:45:00+07', 'source_inventory_rows=277'),
  ('2ef415e6-7f43-3aac-b1cd-7a2ddf30c131', 'GK-KARDUS-000365', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-05-02 10:48:00+07', '2026-05-02 10:48:00+07', 'source_inventory_rows=279'),
  ('d21211d3-9f02-3703-874f-6c81683eeefa', 'GK-KARDUS-000365', 'ATOMY-HONGSAMDAN-RED-GINSENG', 1, 1, '2026-05-02 10:48:00+07', '2026-05-02 10:48:00+07', 'source_inventory_rows=280'),
  ('1ab31e26-e446-3295-a103-82e37d9ac920', 'GK-KARDUS-000365', 'ATOMY-BODY-LOTION', 1, 1, '2026-05-02 10:49:00+07', '2026-05-02 10:49:00+07', 'source_inventory_rows=282'),
  ('be2f7bc8-8d7b-3af1-9224-5c8f93d4c79d', 'GK-KARDUS-000365', 'ATOMY-PROBIOTICS-10', 1, 1, '2026-05-02 10:49:00+07', '2026-05-02 10:49:00+07', 'source_inventory_rows=283'),
  ('16b1d785-a162-3893-a02f-928240e8ab3f', 'GK-KARDUS-000365', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 1, '2026-05-02 10:49:00+07', '2026-05-02 10:49:00+07', 'source_inventory_rows=284'),
  ('10b53f3c-2a3f-31ed-98e5-9d44c3c20e2a', 'GK-KARDUS-000235', 'ATOMY-HERBAL-HAIR-TONIC', 4, 4, '2026-05-02 10:54:00+07', '2026-05-02 10:57:00+07', 'source_inventory_rows=286|289'),
  ('4886df08-f80a-30a1-b668-6959747b4711', 'GK-KARDUS-000369', 'ATOMY-DEEP-CLEANSER-150ML', 1, 1, '2026-05-02 10:55:00+07', '2026-05-02 10:55:00+07', 'source_inventory_rows=287'),
  ('978368fa-72f6-3ab5-8e14-5c60147208e2', 'GK-KARDUS-000235', 'ATOMY-TOOTHPASTE-50G', 3, 3, '2026-05-02 10:56:00+07', '2026-05-02 10:56:00+07', 'source_inventory_rows=288'),
  ('57cf6ba7-6ebd-392d-9c17-ba0a662fc8a3', 'GK-KARDUS-000235', 'ATOMY-ABSOLUTE-TONER', 2, 2, '2026-05-02 10:57:00+07', '2026-05-02 10:57:00+07', 'source_inventory_rows=290'),
  ('c4a5ad76-5560-3857-9545-d45dd975df06', 'GK-KARDUS-000369', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 2, '2026-05-02 10:58:00+07', '2026-05-02 10:58:00+07', 'source_inventory_rows=291'),
  ('9d81f339-2730-39d0-afbb-179ae1a7be9b', 'GK-KARDUS-000375', 'ATOMY-HERBAL-HAIR-TONIC', 2, 2, '2026-05-02 10:58:00+07', '2026-05-02 11:00:00+07', 'source_inventory_rows=292|305'),
  ('17845161-be22-35dd-9024-959f8fdd20e1', 'GK-KARDUS-000235', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 1, '2026-05-02 10:58:00+07', '2026-05-02 10:58:00+07', 'source_inventory_rows=293'),
  ('5734ee0b-c2d7-34c2-922d-adc8ac2f39d6', 'GK-KARDUS-000369', 'ATOMY-BODY-CLEANSER', 1, 1, '2026-05-02 10:58:00+07', '2026-05-02 10:58:00+07', 'source_inventory_rows=294'),
  ('52f063b6-6504-375b-8322-f28cef7ffa30', 'GK-KARDUS-000375', 'ATOMY-CAFE-ARABICA', 1, 1, '2026-05-02 10:58:00+07', '2026-05-02 10:58:00+07', 'source_inventory_rows=295'),
  ('f4625112-a3fa-3991-93bd-eb4e7fef9e20', 'GK-KARDUS-000375', 'ATOMY-BODY-CLEANSER', 1, 1, '2026-05-02 10:59:00+07', '2026-05-02 10:59:00+07', 'source_inventory_rows=296'),
  ('58f41e36-bbef-3cc5-9128-09d6dda89934', 'GK-KARDUS-000369', 'ATOMY-HERBAL-HAIR-CONDITIONER', 2, 2, '2026-05-02 10:59:00+07', '2026-05-02 10:59:00+07', 'source_inventory_rows=297'),
  ('f3821686-af05-3c35-b2c9-20e48a993f95', 'GK-KARDUS-000375', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 1, '2026-05-02 10:59:00+07', '2026-05-02 10:59:00+07', 'source_inventory_rows=298'),
  ('eac417e6-a229-3415-8a12-d8383bc57218', 'GK-KARDUS-000375', 'ATOMY-ABSOLUTE-AMPOULE', 1, 1, '2026-05-02 10:59:00+07', '2026-05-02 10:59:00+07', 'source_inventory_rows=299'),
  ('0573a375-f294-353b-8e46-4dbb9748daff', 'GK-KARDUS-000375', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-05-02 10:59:00+07', '2026-05-02 10:59:00+07', 'source_inventory_rows=300'),
  ('3a59e4c8-9478-31bd-9ae6-78687d32d3d4', 'GK-KARDUS-000369', 'ATOMY-ABSOLUTE-LOTION', 2, 2, '2026-05-02 10:59:00+07', '2026-05-02 10:59:00+07', 'source_inventory_rows=301'),
  ('2443353a-0347-3964-8704-b1fb23a4aba4', 'GK-KARDUS-000375', 'ATOMY-EVENING-CARE-4-SET', 1, 1, '2026-05-02 10:59:00+07', '2026-05-02 10:59:00+07', 'source_inventory_rows=302'),
  ('126b096a-def6-32d1-ab2f-85a65365a927', 'GK-KARDUS-000375', 'ATOMY-BODY-LOTION', 1, 1, '2026-05-02 11:00:00+07', '2026-05-02 11:00:00+07', 'source_inventory_rows=303'),
  ('169bb46b-83e1-3a85-a45c-1b543945d311', 'GK-KARDUS-000369', 'ATOMY-ABSOLUTE-AMPOULE', 1, 1, '2026-05-02 11:00:00+07', '2026-05-02 11:00:00+07', 'source_inventory_rows=304'),
  ('fd42fd16-0404-3f2e-81f6-4273365647e1', 'GK-KARDUS-000369', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-05-02 11:00:00+07', '2026-05-02 11:00:00+07', 'source_inventory_rows=306'),
  ('cc02bc6d-8c3f-3033-96f4-ad1214945300', 'GK-KARDUS-000369', 'ATOMY-SUNSCREEN-WHITE', 2, 2, '2026-05-02 11:01:00+07', '2026-05-02 11:01:00+07', 'source_inventory_rows=307'),
  ('58da2b0f-611c-3cd0-afc3-88dcfd87bba5', 'GK-KARDUS-000369', 'ATOMY-EVENING-CARE-4-SET', 2, 2, '2026-05-02 11:02:00+07', '2026-05-02 11:02:00+07', 'source_inventory_rows=308'),
  ('1bec98c1-3c8e-36b9-838f-050a515e9ff9', 'GK-KARDUS-000376', 'ATOMY-BODY-CLEANSER', 1, 1, '2026-05-02 11:03:00+07', '2026-05-02 11:03:00+07', 'source_inventory_rows=309'),
  ('ba954409-5a92-30e7-b75f-82f95435f430', 'GK-KARDUS-000376', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 1, '2026-05-02 11:03:00+07', '2026-05-02 11:03:00+07', 'source_inventory_rows=310'),
  ('593abcd3-ed4f-3845-90be-1559a77d3f07', 'GK-KARDUS-000376', 'ATOMY-FOAM-CLEANSER-150ML', 1, 1, '2026-05-02 11:03:00+07', '2026-05-02 11:03:00+07', 'source_inventory_rows=311'),
  ('ae827d1a-e875-3b1c-9a16-21dc4e60449d', 'GK-KARDUS-000376', 'ATOMY-BODY-LOTION', 1, 1, '2026-05-02 11:03:00+07', '2026-05-02 11:03:00+07', 'source_inventory_rows=313'),
  ('5318b039-4faf-39b2-8b39-9b95b7f0e14e', 'GK-KARDUS-000376', 'ATOMY-HERBAL-HAIR-TONIC', 1, 1, '2026-05-02 11:04:00+07', '2026-05-02 11:04:00+07', 'source_inventory_rows=314'),
  ('258d5b95-e474-37b0-a02f-537cf99fa207', 'GK-KARDUS-000376', 'ATOMY-TOOTHPASTE-50G', 1, 1, '2026-05-02 11:04:00+07', '2026-05-02 11:04:00+07', 'source_inventory_rows=315'),
  ('5a622df6-4cf5-3eb0-b524-ac150d239699', 'GK-KARDUS-000378', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-04 07:08:00+07', '2026-05-04 07:08:00+07', 'source_inventory_rows=316'),
  ('b889b205-de29-3d7a-a2a3-8c1bfdeb6368', 'GK-KARDUS-000382', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 07:23:00+07', '2026-05-04 07:23:00+07', 'source_inventory_rows=317'),
  ('2464914c-5d55-3590-82e6-7594e32f872e', 'GK-KARDUS-000384', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-04 07:26:00+07', '2026-05-04 07:26:00+07', 'source_inventory_rows=318'),
  ('305d489c-2f6b-39a4-90eb-7d280fc382cf', 'GK-KARDUS-000387', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-04 07:31:00+07', '2026-05-04 07:31:00+07', 'source_inventory_rows=319'),
  ('3e0211e2-fd6c-308a-afe2-0d751a7cfd3d', 'GK-KARDUS-000389', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-04 07:35:00+07', '2026-05-04 07:35:00+07', 'source_inventory_rows=320'),
  ('5b67598d-677c-3b3d-92cd-57338b204ee0', 'GK-KARDUS-000392', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-04 07:36:00+07', '2026-05-04 07:36:00+07', 'source_inventory_rows=321'),
  ('1686609d-23f9-3da8-ac15-613b34c2ed0a', 'GK-KARDUS-000393', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 07:38:00+07', '2026-05-04 07:38:00+07', 'source_inventory_rows=322'),
  ('ad0fe5ea-bb79-334f-a709-21e3c636a460', 'GK-KARDUS-000394', 'ATOMY-HEMOHIM', 1, 1, '2026-05-04 07:39:00+07', '2026-05-04 07:39:00+07', 'source_inventory_rows=323'),
  ('8a941291-5c07-3440-886b-e2a144017894', 'GK-KARDUS-000395', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 07:39:00+07', '2026-05-04 07:39:00+07', 'source_inventory_rows=324'),
  ('1ba4faf8-3ead-3093-a505-7f6d18895202', 'GK-KARDUS-000396', 'ATOMY-PROMO-RAMADHAN-2', 1, 1, '2026-05-04 07:44:00+07', '2026-05-04 07:44:00+07', 'source_inventory_rows=325'),
  ('fd916caa-5480-3e7b-b427-88c3ccfc1afe', 'GK-KARDUS-000396', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 1, '2026-05-04 07:44:00+07', '2026-05-04 07:44:00+07', 'source_inventory_rows=326'),
  ('cc79a972-b776-369e-881b-15a6aaaf898b', 'GK-KARDUS-000397', 'ATOMY-HEMOHIM', 1, 1, '2026-05-04 07:45:00+07', '2026-05-04 07:45:00+07', 'source_inventory_rows=327'),
  ('19736505-da25-36f3-a243-00c5a3493fc1', 'GK-KARDUS-000398', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 07:46:00+07', '2026-05-04 07:46:00+07', 'source_inventory_rows=328'),
  ('cb146bfe-585d-3383-ae47-a55482503f82', 'GK-KARDUS-000399', 'ATOMY-HEMOHIM', 1, 1, '2026-05-04 07:48:00+07', '2026-05-04 07:48:00+07', 'source_inventory_rows=329'),
  ('4697f62f-aad8-3c3a-9b7d-58eeb170b1ec', 'GK-KARDUS-000400', 'ATOMY-HEMOHIM', 1, 1, '2026-05-04 07:53:00+07', '2026-05-04 07:53:00+07', 'source_inventory_rows=330'),
  ('13976a37-9467-38c3-a8de-8cf9f7818810', 'GK-KARDUS-000401', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 07:54:00+07', '2026-05-04 07:54:00+07', 'source_inventory_rows=331'),
  ('88d59748-042e-3424-97d8-0e689518d977', 'GK-KARDUS-000402', 'ATOMY-HEMOHIM', 1, 1, '2026-05-04 07:55:00+07', '2026-05-04 07:55:00+07', 'source_inventory_rows=332'),
  ('8ff8773a-d823-3fff-9bf7-fd66544f30fb', 'GK-KARDUS-000403', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 07:58:00+07', '2026-05-04 07:58:00+07', 'source_inventory_rows=333'),
  ('a4447dd7-c554-3f52-8aaa-4f236b5e239c', 'GK-KARDUS-000404', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 1, 1, '2026-05-04 08:01:00+07', '2026-05-04 08:01:00+07', 'source_inventory_rows=334'),
  ('71b2710a-11de-3d25-b75a-55eb8cb55975', 'GK-KARDUS-000404', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 1, '2026-05-04 08:01:00+07', '2026-05-04 08:01:00+07', 'source_inventory_rows=335'),
  ('a5d42232-41e0-3d92-b917-0ea66e14c76b', 'GK-KARDUS-000406', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 1, '2026-05-04 08:06:00+07', '2026-05-04 08:06:00+07', 'source_inventory_rows=336'),
  ('3730b1fd-c85d-33b7-b223-3b160d78703e', 'GK-KARDUS-000409', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 1, '2026-05-04 08:08:00+07', '2026-05-04 08:08:00+07', 'source_inventory_rows=337'),
  ('2a4d1404-1ff6-3e22-964e-20895e697c48', 'GK-KARDUS-000409', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 1, 1, '2026-05-04 08:08:00+07', '2026-05-04 08:08:00+07', 'source_inventory_rows=338'),
  ('e0433fa6-9e3a-3205-882e-499f48f96c59', 'GK-KARDUS-000410', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 1, 1, '2026-05-04 08:10:00+07', '2026-05-04 08:10:00+07', 'source_inventory_rows=339'),
  ('320f0d82-c530-3908-b380-28c0a72b20e3', 'GK-KARDUS-000411', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:11:00+07', '2026-05-04 08:11:00+07', 'source_inventory_rows=340'),
  ('e148fc25-c5b2-3662-a3d0-b3711e96e2c5', 'GK-KARDUS-000412', 'ATOMY-HEMOHIM', 1, 1, '2026-05-04 08:12:00+07', '2026-05-04 08:12:00+07', 'source_inventory_rows=341'),
  ('41ab15ae-d4d8-323c-8b5d-48be1cf2737b', 'GK-KARDUS-000413', 'ATOMY-HEMOHIM', 1, 1, '2026-05-04 08:12:00+07', '2026-05-04 08:12:00+07', 'source_inventory_rows=342'),
  ('7c6a3d9c-0ea4-3535-bd47-8dc23c6eb2d4', 'GK-KARDUS-000414', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 2, 2, '2026-05-04 08:15:00+07', '2026-05-04 08:15:00+07', 'source_inventory_rows=343'),
  ('723ab4e7-4215-3121-857f-a406503c68a8', 'GK-KARDUS-000415', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:15:00+07', '2026-05-04 08:15:00+07', 'source_inventory_rows=344'),
  ('7a02fe7a-db4e-3875-9e92-55f9c6e76131', 'GK-KARDUS-000416', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:16:00+07', '2026-05-04 08:16:00+07', 'source_inventory_rows=345'),
  ('4bda5d24-1238-32a9-9528-829f587e4b4d', 'GK-KARDUS-000418', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:20:00+07', '2026-05-04 08:20:00+07', 'source_inventory_rows=346'),
  ('4813ff9f-22a6-3600-b3db-b5f0e547a049', 'GK-KARDUS-000420', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 1, '2026-05-04 08:20:00+07', '2026-05-04 08:20:00+07', 'source_inventory_rows=347'),
  ('83454d94-3f08-34df-9145-81cae5c4511d', 'GK-KARDUS-000422', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:22:00+07', '2026-05-04 08:22:00+07', 'source_inventory_rows=348'),
  ('4b7b2b09-6a42-393b-a821-4110fdca3f99', 'GK-KARDUS-000421', 'ATOMY-HONGSAMDAN-RED-GINSENG', 2, 2, '2026-05-04 08:23:00+07', '2026-05-04 08:23:00+07', 'source_inventory_rows=349'),
  ('3ad415e7-b954-3ee8-a192-36b04459b464', 'GK-KARDUS-000421', 'ATOMY-SUNSCREEN-WHITE', 2, 2, '2026-05-04 08:23:00+07', '2026-05-04 08:23:00+07', 'source_inventory_rows=350'),
  ('80348835-0b5a-362f-b773-4020c224222d', 'GK-KARDUS-000421', 'ATOMY-PROPOLIS-TOOTHPASTE-200G', 2, 2, '2026-05-04 08:23:00+07', '2026-05-04 08:23:00+07', 'source_inventory_rows=351'),
  ('3160343b-5090-3123-be7d-9c85cfad2f33', 'GK-KARDUS-000421', 'ATOMY-FINEZYME', 2, 2, '2026-05-04 08:23:00+07', '2026-05-04 08:23:00+07', 'source_inventory_rows=352'),
  ('f4042a1a-e26d-36e2-b829-d7ff6011693e', 'GK-KARDUS-000421', 'ATOMY-SUNSCREEN-BEIGE', 2, 2, '2026-05-04 08:23:00+07', '2026-05-04 08:23:00+07', 'source_inventory_rows=353'),
  ('f75d3230-36a4-3bda-8257-73bef1c92c2d', 'GK-KARDUS-000421', 'ATOMY-TOOTHBRUSH', 2, 2, '2026-05-04 08:23:00+07', '2026-05-04 08:23:00+07', 'source_inventory_rows=354'),
  ('be96c040-1106-3133-aabe-0e586612fd0d', 'GK-KARDUS-000421', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 2, '2026-05-04 08:23:00+07', '2026-05-04 08:23:00+07', 'source_inventory_rows=355'),
  ('c93bfdbb-12b7-3637-858a-cde109636d88', 'GK-KARDUS-000423', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:24:00+07', '2026-05-04 08:24:00+07', 'source_inventory_rows=356'),
  ('439eeccb-05e8-3626-ba35-076e1447b66f', 'GK-KARDUS-000424', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:25:00+07', '2026-05-04 08:25:00+07', 'source_inventory_rows=357'),
  ('64707d32-45eb-30f8-853e-0591fa9a5cb9', 'GK-KARDUS-000426', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:28:00+07', '2026-05-04 08:28:00+07', 'source_inventory_rows=358'),
  ('7c85d267-20cd-3e9b-b5b4-74f95778a762', 'GK-KARDUS-000428', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:28:00+07', '2026-05-04 08:28:00+07', 'source_inventory_rows=359'),
  ('aa918a7f-7d9c-3c9b-a88e-8bef34806c6d', 'GK-KARDUS-000429', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:30:00+07', '2026-05-04 08:30:00+07', 'source_inventory_rows=360'),
  ('c8a9f9f7-3e65-308d-8286-734b872fc524', 'GK-KARDUS-000430', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 1, '2026-05-04 08:30:00+07', '2026-05-04 08:30:00+07', 'source_inventory_rows=361'),
  ('7f36d532-eb68-39f1-b152-7d147d5099f6', 'GK-KARDUS-000431', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:31:00+07', '2026-05-04 08:31:00+07', 'source_inventory_rows=362'),
  ('1d934779-fbc5-3982-8774-112e6cd0b0c5', 'GK-KARDUS-000432', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:32:00+07', '2026-05-04 08:32:00+07', 'source_inventory_rows=363'),
  ('c33540e3-8596-31fc-b874-5725dbf76935', 'GK-KARDUS-000434', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:34:00+07', '2026-05-04 08:34:00+07', 'source_inventory_rows=364'),
  ('38249d76-398d-3938-ac34-1d9ed0f896aa', 'GK-KARDUS-000435', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-04 08:35:00+07', '2026-05-04 08:35:00+07', 'source_inventory_rows=365'),
  ('726bfdd7-c6cf-3bc4-8c96-aa55373844f5', 'GK-KARDUS-000433', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-04 08:35:00+07', '2026-05-04 08:35:00+07', 'source_inventory_rows=366'),
  ('18c79765-c72e-3aee-93eb-1cd08ff6718a', 'GK-KARDUS-000436', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:37:00+07', '2026-05-04 08:37:00+07', 'source_inventory_rows=367'),
  ('b24ceb9e-ca70-3203-b15d-f2b48bdbe689', 'GK-KARDUS-000437', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 1, '2026-05-04 08:40:00+07', '2026-05-04 08:40:00+07', 'source_inventory_rows=368'),
  ('8b7b99bd-ee10-3d5a-8886-cbf95c827032', 'GK-KARDUS-000441', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:44:00+07', '2026-05-04 08:44:00+07', 'source_inventory_rows=369'),
  ('96911a5c-9137-31df-b994-8310845b8eab', 'GK-KARDUS-000442', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 1, '2026-05-04 08:45:00+07', '2026-05-04 08:45:00+07', 'source_inventory_rows=370'),
  ('e1a1451c-ad88-35db-8eff-e648ebdaa785', 'GK-KARDUS-000447', 'ATOMY-PROMO-RAMADHAN-1', 3, 3, '2026-05-04 08:49:00+07', '2026-05-04 08:53:00+07', 'source_inventory_rows=371|372|375'),
  ('3e09b946-d917-359f-b236-a2d10c0b11a3', 'GK-KARDUS-000449', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-04 08:52:00+07', '2026-05-04 08:52:00+07', 'source_inventory_rows=373'),
  ('577dfb2c-fd5c-397f-a28a-8f14aa783694', 'GK-KARDUS-000450', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-04 08:53:00+07', '2026-05-04 08:53:00+07', 'source_inventory_rows=374'),
  ('b52af4c8-cb2c-3279-b9c9-e824fc1cccf5', 'GK-KARDUS-000451', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:55:00+07', '2026-05-04 08:55:00+07', 'source_inventory_rows=376'),
  ('a2da13d8-535e-3e55-b436-938d13224ec0', 'GK-KARDUS-000452', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:57:00+07', '2026-05-04 08:57:00+07', 'source_inventory_rows=377'),
  ('2c803a3c-14ff-3858-be6a-c9b069513f35', 'GK-KARDUS-000454', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 08:59:00+07', '2026-05-04 08:59:00+07', 'source_inventory_rows=378'),
  ('0b634354-fcbc-3c98-b56c-9a880b84d533', 'GK-KARDUS-000456', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:01:00+07', '2026-05-04 09:01:00+07', 'source_inventory_rows=379'),
  ('b6e22b90-76b5-3d9f-a43f-66cd14607af7', 'GK-KARDUS-000458', 'ATOMY-HEMOHIM', 2, 2, '2026-05-04 09:05:00+07', '2026-05-04 09:05:00+07', 'source_inventory_rows=380'),
  ('9ab1ea6a-6054-3f7d-a435-7cf233bdf901', 'GK-KARDUS-000460', 'ATOMY-PROMO-RAMADHAN-1', 2, 2, '2026-05-04 09:07:00+07', '2026-05-04 09:07:00+07', 'source_inventory_rows=381'),
  ('7c1e6bae-4e91-389e-b467-b16ba37f0216', 'GK-KARDUS-000462', 'ATOMY-HEMOHIM', 4, 4, '2026-05-04 09:09:00+07', '2026-05-04 09:09:00+07', 'source_inventory_rows=382'),
  ('7ea7704e-ff98-339e-896d-9dfe1885d855', 'GK-KARDUS-000463', 'ATOMY-PROMO-RAMADHAN-1', 2, 2, '2026-05-04 09:09:00+07', '2026-05-04 09:09:00+07', 'source_inventory_rows=383'),
  ('af2d6a33-24f9-37c6-a828-8804b60ed6b6', 'GK-KARDUS-000461', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:10:00+07', '2026-05-04 09:10:00+07', 'source_inventory_rows=384'),
  ('a0b78ab3-6334-30d3-a1a2-a62e1d869db1', 'GK-KARDUS-000464', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 1, '2026-05-04 09:11:00+07', '2026-05-04 09:11:00+07', 'source_inventory_rows=385'),
  ('88653364-6a22-352d-ab3b-4bb2db8e7e72', 'GK-KARDUS-000466', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-04 09:13:00+07', '2026-05-04 09:13:00+07', 'source_inventory_rows=386'),
  ('68c2e152-5562-3c8e-b5a6-852d2ce55810', 'GK-KARDUS-000467', 'ATOMY-PROMO-RAMADHAN-1', 2, 2, '2026-05-04 09:13:00+07', '2026-05-04 09:13:00+07', 'source_inventory_rows=387'),
  ('d5225f4e-1709-3dcb-a243-8758540ff97d', 'GK-KARDUS-000469', 'ATOMY-HEMOHIM-4-SETS', 2, 2, '2026-05-04 09:15:00+07', '2026-05-04 09:15:00+07', 'source_inventory_rows=388|389'),
  ('d06b4189-095b-3741-9779-296c14bc5dd2', 'GK-KARDUS-000470', 'ATOMY-PROMO-RAMADHAN-1', 2, 2, '2026-05-04 09:15:00+07', '2026-05-04 09:15:00+07', 'source_inventory_rows=390'),
  ('6c3bd4db-ff4e-3913-893e-6aac53690803', 'GK-KARDUS-000471', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:17:00+07', '2026-05-04 09:17:00+07', 'source_inventory_rows=391'),
  ('e790c2d3-bd58-3f89-8929-f77483c8fa38', 'GK-KARDUS-000472', 'ATOMY-PROMO-RAMADHAN-1', 2, 2, '2026-05-04 09:17:00+07', '2026-05-04 09:17:00+07', 'source_inventory_rows=392'),
  ('5260ee9e-3e8f-3a18-90c0-339edfae09fa', 'GK-KARDUS-000475', 'ATOMY-HEMOHIM', 4, 4, '2026-05-04 09:21:00+07', '2026-05-04 09:21:00+07', 'source_inventory_rows=393'),
  ('59a95c2d-0109-3528-bf22-f272b04bb2bb', 'GK-KARDUS-000477', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:22:00+07', '2026-05-04 09:22:00+07', 'source_inventory_rows=394'),
  ('bfa04a0a-74fa-300f-a131-34f009335123', 'GK-KARDUS-000478', 'ATOMY-HEMOHIM', 4, 4, '2026-05-04 09:23:00+07', '2026-05-04 09:23:00+07', 'source_inventory_rows=395'),
  ('5a6d067e-e3a6-3ce0-833e-3d057ca7019e', 'GK-KARDUS-000481', 'ATOMY-HEMOHIM', 4, 4, '2026-05-04 09:24:00+07', '2026-05-04 09:24:00+07', 'source_inventory_rows=396'),
  ('08c05797-adf9-3e41-a985-e6294fc3061a', 'GK-KARDUS-000482', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:26:00+07', '2026-05-04 09:26:00+07', 'source_inventory_rows=397'),
  ('73bd1485-bdf8-3bf2-9fb3-1cfac7240060', 'GK-KARDUS-000483', 'ATOMY-PROMO-RAMADHAN-2', 1, 1, '2026-05-04 09:29:00+07', '2026-05-04 09:29:00+07', 'source_inventory_rows=398'),
  ('eefd3edf-42a2-3d16-8f52-03f1f40be596', 'GK-KARDUS-000483', 'ATOMY-SUNSCREEN-WHITE', 2, 2, '2026-05-04 09:29:00+07', '2026-05-04 09:29:00+07', 'source_inventory_rows=399'),
  ('85298bbf-7894-3fe1-a2c1-7e237966de04', 'GK-KARDUS-000483', 'ATOMY-SUNSCREEN-BEIGE', 2, 2, '2026-05-04 09:29:00+07', '2026-05-04 09:29:00+07', 'source_inventory_rows=400'),
  ('2b4aadcc-9c64-351a-bf91-8f8b54e80cfa', 'GK-KARDUS-000483', 'ATOMY-HEALTHY-GLOW-BASE', 1, 1, '2026-05-04 09:29:00+07', '2026-05-04 09:29:00+07', 'source_inventory_rows=401'),
  ('a95a507a-dfe8-3705-9e35-2cd40dc01a15', 'GK-KARDUS-000484', 'ATOMY-PROMO-RAMADHAN-2', 1, 1, '2026-05-04 09:31:00+07', '2026-05-04 09:31:00+07', 'source_inventory_rows=402'),
  ('65eb59ba-6dba-3030-830c-7eb715d3848c', 'GK-KARDUS-000484', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 1, '2026-05-04 09:31:00+07', '2026-05-04 09:31:00+07', 'source_inventory_rows=403'),
  ('ee692117-988c-343e-94e8-bfde0fc12893', 'GK-KARDUS-000485', 'ATOMY-HEMOHIM', 4, 4, '2026-05-04 09:31:00+07', '2026-05-04 09:31:00+07', 'source_inventory_rows=404'),
  ('7b52a413-48c4-3967-89a4-9129b83ea411', 'GK-KARDUS-000487', 'ATOMY-HEMOHIM', 8, 8, '2026-05-04 09:33:00+07', '2026-05-04 09:33:00+07', 'source_inventory_rows=405|406'),
  ('0ab4f79b-fe3b-30a4-9eca-0b658b902e9c', 'GK-KARDUS-000489', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:36:00+07', '2026-05-04 09:36:00+07', 'source_inventory_rows=407'),
  ('66fa2975-9bc2-3625-92a6-56b2d94a29db', 'GK-KARDUS-000486', 'ATOMY-PAKET-BERKAH-RAMADAN-C', 1, 1, '2026-05-04 09:36:00+07', '2026-05-04 09:36:00+07', 'source_inventory_rows=408'),
  ('ec729a05-1f28-3f7d-82d2-04c6b7419906', 'GK-KARDUS-000486', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 2, '2026-05-04 09:36:00+07', '2026-05-04 09:36:00+07', 'source_inventory_rows=409'),
  ('4b739691-ca12-3448-a2c1-37f3736190e5', 'GK-KARDUS-000486', 'ATOMY-FINEZYME', 2, 2, '2026-05-04 09:36:00+07', '2026-05-04 09:36:00+07', 'source_inventory_rows=410'),
  ('ea98c5a3-6a49-32f5-b03c-e50c18f1432b', 'GK-KARDUS-000490', 'ATOMY-HEMOHIM', 4, 4, '2026-05-04 09:37:00+07', '2026-05-04 09:37:00+07', 'source_inventory_rows=411'),
  ('daac213f-3880-3b67-88fd-1723d4561a89', 'GK-KARDUS-000492', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:38:00+07', '2026-05-04 09:38:00+07', 'source_inventory_rows=412'),
  ('f551c8fd-cb95-33b0-96db-8783176d90a8', 'GK-KARDUS-000491', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:39:00+07', '2026-05-04 09:39:00+07', 'source_inventory_rows=413'),
  ('6e97d59f-bd6d-3717-b214-1cfaec43434c', 'GK-KARDUS-000493', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 1, '2026-05-04 09:40:00+07', '2026-05-04 09:40:00+07', 'source_inventory_rows=414'),
  ('6f31bf21-978f-3e15-84a6-fc6e950f1294', 'GK-KARDUS-000494', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:41:00+07', '2026-05-04 09:41:00+07', 'source_inventory_rows=415'),
  ('a48168d1-0f79-3aad-966a-95cd85266488', 'GK-KARDUS-000495', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:41:00+07', '2026-05-04 09:41:00+07', 'source_inventory_rows=416'),
  ('24f4499a-f490-3b6f-85f2-e34b63066c7d', 'GK-KARDUS-000496', 'ATOMY-PROMO-RAMADHAN-2', 1, 1, '2026-05-04 09:44:00+07', '2026-05-04 09:44:00+07', 'source_inventory_rows=417'),
  ('7e7365d4-9230-3e37-8d5d-883de78a5b5c', 'GK-KARDUS-000496', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 2, 2, '2026-05-04 09:44:00+07', '2026-05-04 09:44:00+07', 'source_inventory_rows=418'),
  ('c7eb4574-b195-3db3-aa4e-05fdfe8ae02e', 'GK-KARDUS-000498', 'ATOMY-HEMOHIM', 4, 4, '2026-05-04 09:46:00+07', '2026-05-04 09:46:00+07', 'source_inventory_rows=419'),
  ('aa408666-8324-36ed-bd0c-0b00c99ca07f', 'GK-KARDUS-000499', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:46:00+07', '2026-05-04 09:46:00+07', 'source_inventory_rows=420'),
  ('0bf362e0-88c8-3eaa-b6c8-1e35445b7cfc', 'GK-KARDUS-000500', 'ATOMY-HEMOHIM', 4, 4, '2026-05-04 09:48:00+07', '2026-05-04 09:48:00+07', 'source_inventory_rows=421'),
  ('86820270-8177-3c08-9705-375bccb5230c', 'GK-KARDUS-000501', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:48:00+07', '2026-05-04 09:48:00+07', 'source_inventory_rows=422'),
  ('d30ee272-5fed-3e7e-83f0-adeffde88e76', 'GK-KARDUS-000504', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 09:53:00+07', '2026-05-04 09:53:00+07', 'source_inventory_rows=423'),
  ('f62579ad-0a8a-38da-85ad-f9c62daea42d', 'GK-KARDUS-000503', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-04 09:54:00+07', '2026-05-04 09:54:00+07', 'source_inventory_rows=424'),
  ('f4e3c6a6-207e-32da-a552-a5bce4504dfd', 'GK-KARDUS-000505', 'ATOMY-HEMOHIM', 4, 4, '2026-05-04 09:55:00+07', '2026-05-04 09:55:00+07', 'source_inventory_rows=425'),
  ('5ef521cc-9399-33d8-868d-0691f6ea0b2c', 'GK-KARDUS-000508', 'ATOMY-HEMOHIM', 4, 4, '2026-05-04 09:57:00+07', '2026-05-04 09:57:00+07', 'source_inventory_rows=426'),
  ('0998c5f0-3e90-300e-af50-14fffccdefe4', 'GK-KARDUS-000510', 'ATOMY-HEMOHIM', 4, 4, '2026-05-04 09:58:00+07', '2026-05-04 09:58:00+07', 'source_inventory_rows=427'),
  ('f5181c46-ba5d-3cda-9203-969fb9e01199', 'GK-KARDUS-000504', 'ATOMY-PAKET-BERKAH-RAMADAN-C', 1, 1, '2026-05-04 09:59:00+07', '2026-05-04 09:59:00+07', 'source_inventory_rows=428'),
  ('ad960c9a-d45c-3db1-86d7-261ad99a1521', 'GK-KARDUS-000504', 'ATOMY-FINEZYME', 2, 2, '2026-05-04 09:59:00+07', '2026-05-04 09:59:00+07', 'source_inventory_rows=429'),
  ('75a2ecd9-e0d4-3e64-8d5e-6fd8003aa8e8', 'GK-KARDUS-000504', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 2, '2026-05-04 09:59:00+07', '2026-05-04 09:59:00+07', 'source_inventory_rows=430'),
  ('8f4b4f05-5681-32f4-af8f-35dff66bf774', 'GK-KARDUS-000511', 'ATOMY-HEMOHIM', 4, 4, '2026-05-04 10:00:00+07', '2026-05-04 10:00:00+07', 'source_inventory_rows=431'),
  ('77576e75-3d8a-35a2-b632-d7abcf87c24c', 'GK-KARDUS-000512', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-04 10:01:00+07', '2026-05-04 10:01:00+07', 'source_inventory_rows=432'),
  ('6aad6f41-fcce-348b-8e79-c8cfb2cbd57e', 'GK-KARDUS-000513', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 1, '2026-05-04 10:12:00+07', '2026-05-04 10:12:00+07', 'source_inventory_rows=433'),
  ('42ddd86a-1a75-3893-b514-7e958d086235', 'GK-KARDUS-000514', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-04 10:13:00+07', '2026-05-04 10:13:00+07', 'source_inventory_rows=434'),
  ('bb15c1a5-c83a-3a18-a8ce-04607f06e76d', 'GK-KARDUS-000515', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-04 10:16:00+07', '2026-05-04 10:16:00+07', 'source_inventory_rows=435'),
  ('d47cec74-d378-38e0-89f4-3a603587b440', 'GK-KARDUS-000516', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 08:42:00+07', '2026-05-05 08:42:00+07', 'source_inventory_rows=436'),
  ('0e984767-c768-37cd-8fa2-12b54f2ba34a', 'GK-KARDUS-000517', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 08:44:00+07', '2026-05-05 08:44:00+07', 'source_inventory_rows=437'),
  ('01b7420d-d739-3050-ae3b-df16ec2017fd', 'GK-KARDUS-000518', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 08:46:00+07', '2026-05-05 08:46:00+07', 'source_inventory_rows=438'),
  ('a714c0ec-5700-3ad3-916f-623c13805884', 'GK-KARDUS-000519', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 08:50:00+07', '2026-05-05 08:50:00+07', 'source_inventory_rows=439'),
  ('9e56860f-bd88-3690-8bdb-b88eaf385241', 'GK-KARDUS-000520', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-05 08:51:00+07', '2026-05-05 08:51:00+07', 'source_inventory_rows=440'),
  ('3c88a219-013d-36ed-84e8-206439e0b631', 'GK-KARDUS-000521', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 08:51:00+07', '2026-05-05 08:51:00+07', 'source_inventory_rows=441'),
  ('f8f92ab3-efbc-367c-8228-727a49d19956', 'GK-KARDUS-000523', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-05 09:00:00+07', '2026-05-05 09:00:00+07', 'source_inventory_rows=442'),
  ('fa9ca99e-b9c2-38c1-9209-b17cb4ac2208', 'GK-KARDUS-000524', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:00:00+07', '2026-05-05 09:00:00+07', 'source_inventory_rows=443'),
  ('e4f4dd7f-7ff6-39e8-b831-efabf3140845', 'GK-KARDUS-000525', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:03:00+07', '2026-05-05 09:03:00+07', 'source_inventory_rows=444'),
  ('14664763-f367-36b0-b667-2a37225bdff8', 'GK-KARDUS-000531', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:11:00+07', '2026-05-05 09:11:00+07', 'source_inventory_rows=445'),
  ('4644ced7-1f62-3d71-b5d5-0aae387c8853', 'GK-KARDUS-000530', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-05 09:14:00+07', '2026-05-05 09:14:00+07', 'source_inventory_rows=446'),
  ('1d110eba-bafe-3bfc-a8d5-ebdfd36e0263', 'GK-KARDUS-000532', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-05 09:15:00+07', '2026-05-05 09:15:00+07', 'source_inventory_rows=447'),
  ('0e33ce4d-bca9-36d7-95f1-3a23f2592d92', 'GK-KARDUS-000533', 'ATOMY-HONGSAMDAN-RED-GINSENG', 2, 2, '2026-05-05 09:19:00+07', '2026-05-05 09:19:00+07', 'source_inventory_rows=448'),
  ('e93b2032-0e28-3a87-a1ec-9b4653d23d24', 'GK-KARDUS-000533', 'ATOMY-HEMOHIM', 1, 1, '2026-05-05 09:19:00+07', '2026-05-05 09:19:00+07', 'source_inventory_rows=449'),
  ('c41d5cbf-0ed1-37c6-9662-473bc5c7ac67', 'GK-KARDUS-000533', 'ATOMY-EVENING-CARE-4-SET', 2, 2, '2026-05-05 09:19:00+07', '2026-05-05 09:19:00+07', 'source_inventory_rows=450'),
  ('8007229f-376c-3d80-942a-ed1571cc2ec3', 'GK-KARDUS-000533', 'ATOMY-FINEZYME', 2, 2, '2026-05-05 09:19:00+07', '2026-05-05 09:19:00+07', 'source_inventory_rows=451'),
  ('d9e89fb3-371a-391f-99d9-0361bd964baa', 'GK-KARDUS-000533', 'ATOMY-EVENING-CARE-FOAM-CLEANSER', 1, 1, '2026-05-05 09:19:00+07', '2026-05-05 09:19:00+07', 'source_inventory_rows=452'),
  ('8b5386a7-a5fc-35b6-b366-d3c9afc10f52', 'GK-KARDUS-000534', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-05 09:23:00+07', '2026-05-05 09:23:00+07', 'source_inventory_rows=453'),
  ('556303bd-72c7-3407-a6ff-12941edb7ffe', 'GK-KARDUS-000535', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-05 09:28:00+07', '2026-05-05 09:28:00+07', 'source_inventory_rows=454'),
  ('094f60be-018c-3a60-a47f-6716f0a4a3f4', 'GK-KARDUS-000536', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:29:00+07', '2026-05-05 09:29:00+07', 'source_inventory_rows=455'),
  ('ea62089c-eb0c-32f2-b635-8572311589ca', 'GK-KARDUS-000537', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:30:00+07', '2026-05-05 09:30:00+07', 'source_inventory_rows=456'),
  ('2b99f703-04d5-33f7-a28d-32593ed702e2', 'GK-KARDUS-000540', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:32:00+07', '2026-05-05 09:32:00+07', 'source_inventory_rows=457'),
  ('dfb4b3e1-c99c-3552-893d-bf2172247d0a', 'GK-KARDUS-000541', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:33:00+07', '2026-05-05 09:33:00+07', 'source_inventory_rows=458'),
  ('9c818124-9fab-3d28-8c0e-41c2198342f1', 'GK-KARDUS-000538', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-05 09:33:00+07', '2026-05-05 09:33:00+07', 'source_inventory_rows=459'),
  ('f599e96a-d373-3b07-a779-0b333ed9835a', 'GK-KARDUS-000542', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:35:00+07', '2026-05-05 09:35:00+07', 'source_inventory_rows=460'),
  ('b99f0354-e1d6-34af-8a66-459646b9fbf6', 'GK-KARDUS-000543', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:37:00+07', '2026-05-05 09:37:00+07', 'source_inventory_rows=461'),
  ('fb175aec-777f-3edd-a2f5-010494ecd77f', 'GK-KARDUS-000544', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-05 09:38:00+07', '2026-05-05 09:38:00+07', 'source_inventory_rows=462'),
  ('1a9d7eef-d39a-3468-8f5b-2800ae7c10c8', 'GK-KARDUS-000546', 'ATOMY-HEMOHIM', 8, 8, '2026-05-05 09:40:00+07', '2026-05-05 09:40:00+07', 'source_inventory_rows=463|464'),
  ('ee1a8be4-c084-3866-a475-a02cbebd3908', 'GK-KARDUS-000547', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-05 09:40:00+07', '2026-05-05 09:40:00+07', 'source_inventory_rows=465'),
  ('e6766997-b961-383c-9493-7245aa1f119a', 'GK-KARDUS-000548', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:42:00+07', '2026-05-05 09:42:00+07', 'source_inventory_rows=466'),
  ('c1ae345a-798a-3872-bf26-a6bcf8164138', 'GK-KARDUS-000551', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:47:00+07', '2026-05-05 09:47:00+07', 'source_inventory_rows=467'),
  ('fea7f83b-8b94-3b6f-82ee-83468e428400', 'GK-KARDUS-000552', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-05 09:49:00+07', '2026-05-05 09:49:00+07', 'source_inventory_rows=468'),
  ('e82425c8-baf2-36e2-82fb-b451cfed0ce9', 'GK-KARDUS-000553', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:50:00+07', '2026-05-05 09:50:00+07', 'source_inventory_rows=469'),
  ('7beb5b94-6a48-3e6d-8495-73e83f8f6958', 'GK-KARDUS-000554', 'ATOMY-HEMOHIM', 4, 4, '2026-05-05 09:52:00+07', '2026-05-05 09:52:00+07', 'source_inventory_rows=470'),
  ('a14a92be-7c97-3607-8ab3-67c9cd781e01', 'GK-KARDUS-000556', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-05 09:55:00+07', '2026-05-05 09:55:00+07', 'source_inventory_rows=471'),
  ('99f976a2-f138-3d0e-8811-dd45b0d2425f', 'GK-KARDUS-000557', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-05 09:56:00+07', '2026-05-05 09:56:00+07', 'source_inventory_rows=472'),
  ('369720a2-97c7-3af9-86ec-327f0df74cd7', 'GK-KARDUS-000566', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-20 09:06:00+07', '2026-05-20 09:06:00+07', 'source_inventory_rows=473'),
  ('1f20ffa2-024c-3d8b-be55-43083b9882c6', 'GK-KARDUS-000567', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-20 09:07:00+07', '2026-05-20 09:07:00+07', 'source_inventory_rows=474'),
  ('7c18a15b-8f6f-34a7-ad1b-ff7d77c5dfcc', 'GK-KARDUS-000568', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-20 09:08:00+07', '2026-05-20 09:08:00+07', 'source_inventory_rows=475'),
  ('f8b73637-52bb-309d-850a-2e7ce5700be8', 'GK-KARDUS-000569', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-20 09:09:00+07', '2026-05-20 09:09:00+07', 'source_inventory_rows=476'),
  ('9ad18772-9b48-3245-9f61-6f52bbe92c26', 'GK-KARDUS-000570', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-20 09:11:00+07', '2026-05-20 09:11:00+07', 'source_inventory_rows=477'),
  ('8cfb525e-a814-3afd-9d95-80d9d75fb86b', 'GK-KARDUS-000572', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-20 09:12:00+07', '2026-05-20 09:12:00+07', 'source_inventory_rows=478'),
  ('66196865-0df9-3646-9fc4-a4729813816b', 'GK-KARDUS-000573', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-20 09:14:00+07', '2026-05-20 09:14:00+07', 'source_inventory_rows=479'),
  ('4e1f53ab-55b7-3ab0-8ebc-393d27779013', 'GK-KARDUS-000577', 'ATOMY-PSYLLIUM-HUSK', 1, 1, '2026-05-20 09:19:00+07', '2026-05-20 09:19:00+07', 'source_inventory_rows=480'),
  ('43920043-4073-3770-9da9-782beb4f5965', 'GK-KARDUS-000578', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 2, 2, '2026-05-20 09:23:00+07', '2026-05-20 09:23:00+07', 'source_inventory_rows=481|482'),
  ('1b27b3ae-8d2c-30dc-8cc7-39e8cc52690f', 'GK-KARDUS-000580', 'ATOMY-PSYLLIUM-HUSK', 1, 1, '2026-05-20 09:24:00+07', '2026-05-20 09:24:00+07', 'source_inventory_rows=483'),
  ('37bab354-0180-3994-bbfc-87fc4fb73c50', 'GK-KARDUS-000581', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 1, 1, '2026-05-20 09:26:00+07', '2026-05-20 09:26:00+07', 'source_inventory_rows=484'),
  ('772afe04-37db-3d33-ac90-01aec6297070', 'GK-KARDUS-000582', 'ATOMY-PSYLLIUM-HUSK', 2, 2, '2026-05-20 09:26:00+07', '2026-05-20 09:26:00+07', 'source_inventory_rows=485'),
  ('f3eb86ea-093c-38b2-8408-65cf75bd4568', 'GK-KARDUS-000582', 'ATOMY-TOOTHBRUSH', 2, 2, '2026-05-20 09:26:00+07', '2026-05-20 09:26:00+07', 'source_inventory_rows=486'),
  ('576525e7-d6ce-3822-ad74-3976a20fd716', 'GK-KARDUS-000583', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 2, 2, '2026-05-20 09:27:00+07', '2026-05-20 09:27:00+07', 'source_inventory_rows=487'),
  ('85b115fe-a443-37f0-9a05-177387ca90f5', 'GK-KARDUS-000584', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 2, 1, '2026-05-20 09:28:00+07', '2026-05-27 11:11:00+07', 'source_inventory_rows=488|505'),
  ('d3b985c1-a070-3ced-bb60-b1849396fec4', 'GK-KARDUS-000585', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 2, 2, '2026-05-20 09:31:00+07', '2026-05-20 09:31:00+07', 'source_inventory_rows=489'),
  ('6d2db15f-d67b-3691-b32d-add27ef45f73', 'GK-KARDUS-000585', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 2, 2, '2026-05-20 09:31:00+07', '2026-05-20 09:32:00+07', 'source_inventory_rows=490|491'),
  ('2baa19fc-349b-3287-b1d4-beff02b6bb93', 'GK-KARDUS-000585', 'ATOMY-PU-ER-TEA', 1, 1, '2026-05-20 09:32:00+07', '2026-05-20 09:32:00+07', 'source_inventory_rows=492'),
  ('567af467-3546-3e1d-af91-bf27172aa4dc', 'GK-KARDUS-000586', 'ATOMY-PU-ER-TEA', 1, 1, '2026-05-20 09:33:00+07', '2026-05-20 09:33:00+07', 'source_inventory_rows=493'),
  ('61e360a7-4dff-37bd-9f03-ff7598c67cc0', 'GK-KARDUS-000589', 'ATOMY-HEMOHIM', 2, 2, '2026-05-20 09:36:00+07', '2026-05-20 09:36:00+07', 'source_inventory_rows=494'),
  ('68938996-a96f-3371-b107-d70b93f7fa63', 'GK-KARDUS-000587', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 1, '2026-05-20 09:36:00+07', '2026-05-20 09:36:00+07', 'source_inventory_rows=495'),
  ('283c0298-68fa-3e0e-b492-4a930aa275d5', 'GK-KARDUS-000588', 'ATOMY-PSYLLIUM-HUSK', 6, 6, '2026-05-20 09:37:00+07', '2026-05-20 09:37:00+07', 'source_inventory_rows=496|497|498'),
  ('43c50479-6d31-317d-9b95-fa3944126eb8', 'GK-KARDUS-000591', 'ATOMY-ETHEREAL-OIL-PATCH', 5, 5, '2026-05-20 09:39:00+07', '2026-05-20 09:39:00+07', 'source_inventory_rows=499'),
  ('bb5539f1-5898-350a-ad47-dc103d360d7b', 'GK-KARDUS-000592', 'ATOMY-HEMOHIM-4-SETS', 1, 1, '2026-05-20 09:39:00+07', '2026-05-20 09:39:00+07', 'source_inventory_rows=500'),
  ('50695b75-51b0-396a-95a9-247af22e0b85', 'GK-KARDUS-000592', 'ATOMY-ETHEREAL-OIL-PATCH', 5, 5, '2026-05-20 09:45:00+07', '2026-05-20 09:45:00+07', 'source_inventory_rows=501'),
  ('23ce4979-f8ca-3ecf-8ca5-a8fbef773bd5', 'GK-KARDUS-000594', 'ATOMY-ETHEREAL-OIL-PATCH', 10, 10, '2026-05-20 09:48:00+07', '2026-05-20 09:48:00+07', 'source_inventory_rows=502|503'),
  ('7b0d0d76-6e54-3633-b54f-a1b22ede93dd', 'GK-KARDUS-000595', 'ATOMY-HEMOHIM-SET-4', 1, 1, '2026-05-20 09:48:00+07', '2026-05-20 09:48:00+07', 'source_inventory_rows=504'),
  ('307b76eb-73f9-32b5-816b-5a12eb379a28', 'GK-KARDUS-000596', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-28 11:36:00+07', '2026-05-28 11:36:00+07', 'source_inventory_rows=506'),
  ('220e5f49-5972-33fd-a781-f1017b00b625', 'GK-KARDUS-000301', 'ATOMY-PROMO-RAMADHAN-2', 1, 1, '2026-05-30 09:17:00+07', '2026-05-30 09:17:00+07', 'source_inventory_rows=507'),
  ('7aab0aed-8230-3ad3-bd42-ef96af1a7dc5', 'GK-KARDUS-000301', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 2, 2, '2026-05-30 09:17:00+07', '2026-05-30 09:17:00+07', 'source_inventory_rows=508'),
  ('6e568dbc-6b30-364b-b624-faa7c1c78e91', 'GK-KARDUS-000601', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-30 09:19:00+07', '2026-05-30 09:19:00+07', 'source_inventory_rows=509'),
  ('8fe25709-5df0-3fb6-850b-2279d7c93eae', 'GK-KARDUS-000602', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-30 09:21:00+07', '2026-05-30 09:21:00+07', 'source_inventory_rows=510'),
  ('fdbceaec-1fef-317b-9dbc-c3b081304e0d', 'GK-KARDUS-000602', 'ATOMY-PSYLLIUM-HUSK', 1, 1, '2026-05-30 09:21:00+07', '2026-05-30 09:21:00+07', 'source_inventory_rows=511'),
  ('398f71c8-6f31-31ef-bec4-f988e407d150', 'GK-KARDUS-000600', 'ATOMY-HERBAL-HAIR-CONDITIONER', 2, 2, '2026-05-30 09:22:00+07', '2026-05-30 09:22:00+07', 'source_inventory_rows=512'),
  ('6b3848fc-14f6-3ca6-9139-d6dfe0a4fedf', 'GK-KARDUS-000600', 'ATOMY-SAENGMODAN-HAIR-TONIC', 2, 2, '2026-05-30 09:22:00+07', '2026-05-30 09:22:00+07', 'source_inventory_rows=513'),
  ('445b3a15-7af1-3cc5-89d5-a97aba222011', 'GK-KARDUS-000600', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 2, '2026-05-30 09:22:00+07', '2026-05-30 09:22:00+07', 'source_inventory_rows=514'),
  ('fba48e87-3e59-3c6a-9b0b-0330dddad748', 'GK-KARDUS-000600', 'ATOMY-FINEZYME', 2, 2, '2026-05-30 09:22:00+07', '2026-05-30 09:22:00+07', 'source_inventory_rows=515'),
  ('f6976831-4ce6-3c2b-9ec2-83b887f50613', 'GK-KARDUS-000600', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 2, '2026-05-30 09:22:00+07', '2026-05-30 09:22:00+07', 'source_inventory_rows=516'),
  ('d277473a-8c86-336e-b7df-27475e5a9314', 'GK-KARDUS-000600', 'ATOMY-HAIR-ESSENTIAL-OIL', 2, 2, '2026-05-30 09:22:00+07', '2026-05-30 09:22:00+07', 'source_inventory_rows=517'),
  ('f8987bcc-05fe-3e52-8d01-a435baa19e94', 'GK-KARDUS-000605', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-30 09:26:00+07', '2026-05-30 09:26:00+07', 'source_inventory_rows=518'),
  ('402711b3-0845-3b2a-ab02-0837048e6fd1', 'GK-KARDUS-000604', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 1, '2026-05-30 09:26:00+07', '2026-05-30 09:26:00+07', 'source_inventory_rows=519'),
  ('672c2e6b-3dd5-32af-8aa2-76624563777a', 'GK-KARDUS-000607', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-30 09:27:00+07', '2026-05-30 09:27:00+07', 'source_inventory_rows=520'),
  ('bdadd86d-35aa-397b-b7a8-3f0e2a02085c', 'GK-KARDUS-000604', 'ATOMY-ETHEREAL-OIL-PATCH', 4, 4, '2026-05-30 09:29:00+07', '2026-05-30 09:29:00+07', 'source_inventory_rows=521'),
  ('b57d29d5-da5a-3afb-b628-3cc3f46190a6', 'GK-KARDUS-000609', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-30 09:34:00+07', '2026-05-30 09:34:00+07', 'source_inventory_rows=522'),
  ('7c581590-5f97-3f9c-baa8-a974d2518f73', 'GK-KARDUS-000610', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 2, 2, '2026-05-30 09:36:00+07', '2026-05-30 09:39:00+07', 'source_inventory_rows=523|525'),
  ('e5c7e93e-742f-3a3a-a300-2549c9b08d87', 'GK-KARDUS-000611', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-30 09:38:00+07', '2026-05-30 09:38:00+07', 'source_inventory_rows=524'),
  ('4ff77339-c6b6-3c60-af30-1320ae664d17', 'GK-KARDUS-000612', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-30 09:39:00+07', '2026-05-30 09:39:00+07', 'source_inventory_rows=526'),
  ('54fc09ef-2090-3088-99dd-e8c7c1223ac1', 'GK-KARDUS-000613', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-30 09:40:00+07', '2026-05-30 09:40:00+07', 'source_inventory_rows=527'),
  ('21017f62-2ca7-3c72-8d74-932ea28186c9', 'GK-KARDUS-000614', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-30 09:41:00+07', '2026-05-30 09:41:00+07', 'source_inventory_rows=528'),
  ('d72762cb-6c35-395c-aaad-fae528f6983f', 'GK-KARDUS-000615', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-30 09:42:00+07', '2026-05-30 09:42:00+07', 'source_inventory_rows=529'),
  ('908c2983-73aa-3c11-9d69-ce3a1236844a', 'GK-KARDUS-000616', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-30 09:42:00+07', '2026-05-30 09:42:00+07', 'source_inventory_rows=530'),
  ('1d44859a-db34-3681-b2d8-844add8a230e', 'GK-KARDUS-000617', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, '2026-05-30 09:44:00+07', '2026-05-30 09:44:00+07', 'source_inventory_rows=531'),
  ('4bf74d29-233b-30c0-ae2b-2ea1ed75ddc4', 'GK-KARDUS-000618', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, '2026-05-30 09:45:00+07', '2026-05-30 09:45:00+07', 'source_inventory_rows=532'),
  ('fb3960c8-07e5-3cc8-bf76-8e30d8ed7dc3', 'GK-KARDUS-000619', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 1, 1, '2026-05-30 09:46:00+07', '2026-05-30 09:46:00+07', 'source_inventory_rows=533'),
  ('3d45b8d4-c7c5-35d0-befc-bcb8cd485861', 'GK-KARDUS-000619', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 1, '2026-05-30 09:46:00+07', '2026-05-30 09:46:00+07', 'source_inventory_rows=534')
)
insert into public.box_items(id, box_id, product_id, qty_initial, qty_available, expired_at, batch_no, created_at, updated_at)
select
  source_items.id::uuid,
  boxes.id,
  products.id,
  source_items.qty_initial::numeric,
  source_items.qty_available::numeric,
  null,
  'IMPORT-GUDANGKU-INVENTORY',
  source_items.created_at::timestamptz,
  source_items.updated_at::timestamptz
from source_items
join public.boxes on boxes.id_box = source_items.id_box
join public.products on products.sku = source_items.sku
on conflict (id) do update set
  box_id = excluded.box_id,
  product_id = excluded.product_id,
  qty_initial = excluded.qty_initial,
  qty_available = excluded.qty_available,
  expired_at = excluded.expired_at,
  batch_no = excluded.batch_no,
  updated_at = excluded.updated_at;

with source_movements(id, movement_type, id_box, sku, qty, before_qty, after_qty, reason, notes, created_at) as (
  values
  ('30055a98-e960-330d-bf39-e664a9508250', 'in', 'GK-KARDUS-000001', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=1; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 07:43:00+07'),
  ('335ca8a4-4c44-3dd7-9692-08a0f8cfbad6', 'in', 'GK-KARDUS-000002', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=2; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 07:45:00+07'),
  ('37726a29-4bdc-3ad3-994b-a5fdfeb33539', 'in', 'GK-KARDUS-000007', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=3; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 07:50:00+07'),
  ('9bb7a6a5-ff8f-34ac-aff4-5fb2c1eb5afb', 'in', 'GK-KARDUS-000009', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=4; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 07:52:00+07'),
  ('2a84d975-1479-3559-8be9-259d7253e164', 'in', 'GK-KARDUS-000011', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=5; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 07:55:00+07'),
  ('7b3fda98-2b20-308d-9301-6fea20ea8997', 'in', 'GK-KARDUS-000012', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=6; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 07:56:00+07'),
  ('43a53377-493c-3854-83f1-9f4eee4cb477', 'in', 'GK-KARDUS-000013', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=7; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 07:58:00+07'),
  ('5fc90385-4520-368e-a44d-dfa3d72cdffb', 'in', 'GK-KARDUS-000014', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=8; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:00:00+07'),
  ('64cf211d-6e53-3a30-b1cd-b4d149974d98', 'in', 'GK-KARDUS-000016', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=9; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:05:00+07'),
  ('f63f65c3-652c-353f-9249-15e362cff753', 'in', 'GK-KARDUS-000017', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=10; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:06:00+07'),
  ('33a62186-1f55-3147-95a5-fc6808ee0590', 'in', 'GK-KARDUS-000020', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=11; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:10:00+07'),
  ('8913905a-47c5-3da9-8dee-de74a4baad4a', 'in', 'GK-KARDUS-000021', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=12; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:12:00+07'),
  ('6d3ceb15-27a5-3343-90bc-2293e4cd193f', 'in', 'GK-KARDUS-000023', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=13; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:14:00+07'),
  ('f9e43a8e-9055-3165-8c96-96de07d7d9cd', 'in', 'GK-KARDUS-000026', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=14; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:18:00+07'),
  ('57c07001-7e74-3059-ae47-af2b34f7a348', 'in', 'GK-KARDUS-000028', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=15; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:21:00+07'),
  ('f8e42670-b5df-3a0d-97ab-29eae8c70b57', 'in', 'GK-KARDUS-000029', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=16; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:22:00+07'),
  ('29101165-82f6-32dd-8301-e8186643dceb', 'in', 'GK-KARDUS-000032', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=17; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:25:00+07'),
  ('569f033e-20f5-3d72-a40c-48978572deef', 'in', 'GK-KARDUS-000033', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=18; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:27:00+07'),
  ('60f34b51-f19b-3ae3-b91b-a350f7109c94', 'in', 'GK-KARDUS-000035', 'ATOMY-HONGSAMDAN-RED-GINSENG', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=19; type=MASUK; product_name=Atomy Hongsamdan Red Ginseng; performed_by=Admin', '2026-04-29 08:29:00+07'),
  ('7a751a42-1eee-31b3-8896-c384bde728aa', 'in', 'GK-KARDUS-000035', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=20; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:29:00+07'),
  ('61fa337b-89e9-32a3-b6db-25ac49b23c26', 'in', 'GK-KARDUS-000035', 'ATOMY-PROBIOTICS-10', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=21; type=MASUK; product_name=Atomy Probiotics 10+; performed_by=Admin', '2026-04-29 08:29:00+07'),
  ('503cde93-32ac-3e1b-8726-2438c7c770b4', 'in', 'GK-KARDUS-000035', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=22; type=MASUK; product_name=Atomy Color Food Vitamin C; performed_by=Admin', '2026-04-29 08:29:00+07'),
  ('5f6aeb25-26b8-348e-b7a6-e8f475b37ff6', 'in', 'GK-KARDUS-000036', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=23; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:31:00+07'),
  ('40f34bbf-bc56-3b92-af63-aae4e356a3f0', 'in', 'GK-KARDUS-000040', 'ATOMY-PAKET-RAMADHAN-CARE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=24; type=MASUK; product_name=Atomy Paket Ramadhan Care; performed_by=Admin', '2026-04-29 08:36:00+07'),
  ('33937774-c213-3a52-b3c4-ac6ce664e5ad', 'in', 'GK-KARDUS-000043', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=25; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:49:00+07'),
  ('a2f9c7b3-f88b-3a1f-8d66-0d4673c8500c', 'in', 'GK-KARDUS-000043', 'ATOMY-HEMOHIM', 4, 1, 5, 'Import data client GudangKu inventory', 'source_id=26; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:49:00+07'),
  ('3d996f4b-b183-3f8e-8eb5-298725a1f6a8', 'in', 'GK-KARDUS-000046', 'ATOMY-PAKET-RAMADHAN-CARE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=27; type=MASUK; product_name=Atomy Paket Ramadhan Care; performed_by=Admin', '2026-04-29 08:52:00+07'),
  ('34b96c08-3ec0-3755-b258-aa8d99d9674c', 'in', 'GK-KARDUS-000053', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=28; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:57:00+07'),
  ('bb43eb77-53c0-35ca-b9c8-b0b7efc25aeb', 'in', 'GK-KARDUS-000056', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=29; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 08:59:00+07'),
  ('6877d992-6483-37c0-b8b7-e66ed54d2a2a', 'in', 'GK-KARDUS-000059', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=30; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:02:00+07'),
  ('823535db-1da2-3d26-8ab5-b6d7851bec19', 'in', 'GK-KARDUS-000060', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=31; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:03:00+07'),
  ('f0c0a033-f059-3363-9a5a-eb3bc6e309b7', 'in', 'GK-KARDUS-000062', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=32; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:04:00+07'),
  ('decca367-4e04-3ac7-b551-8db99040cce5', 'in', 'GK-KARDUS-000064', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=33; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:06:00+07'),
  ('62e6c7f6-8e8f-3364-bc06-f4e88da77a7f', 'in', 'GK-KARDUS-000065', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=34; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:06:00+07'),
  ('2ee6f7ac-1de8-3c2a-9c5f-3682c39d165c', 'in', 'GK-KARDUS-000068', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=35; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:10:00+07'),
  ('e227beba-e415-35bd-98a4-2e9acc5f7fd0', 'in', 'GK-KARDUS-000067', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=36; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:11:00+07'),
  ('c0401f20-4067-3ad3-a247-9c1c7041d97f', 'in', 'GK-KARDUS-000070', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=37; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:12:00+07'),
  ('388b8d45-519a-33f6-b961-b6732131eb98', 'in', 'GK-KARDUS-000072', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=38; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:13:00+07'),
  ('1aee6d84-d517-3631-b9d9-c266da27c053', 'in', 'GK-KARDUS-000073', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=39; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:14:00+07'),
  ('51cb94ab-7406-38d4-9d32-5433be78f2b6', 'in', 'GK-KARDUS-000077', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=40; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:17:00+07'),
  ('12b22bf2-69a3-34e4-bfa8-202491122500', 'in', 'GK-KARDUS-000078', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=41; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:18:00+07'),
  ('fd405442-0b80-3891-b23f-0f2d85207fb9', 'in', 'GK-KARDUS-000084', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=42; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:24:00+07'),
  ('df7a6a54-07d5-3f23-90ff-6f49f8825916', 'in', 'GK-KARDUS-000085', 'ATOMY-BODY-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=43; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-04-29 09:25:00+07'),
  ('49feb985-d324-3710-8f23-ffe3a986e683', 'in', 'GK-KARDUS-000085', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=44; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-04-29 09:25:00+07'),
  ('b2b8a657-660b-3850-8e1a-d08310a19daf', 'in', 'GK-KARDUS-000085', 'ATOMY-EVENING-CARE-4-SET', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=45; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-04-29 09:26:00+07'),
  ('bb0a5cd3-1997-3313-ac28-30cb5bdd5b9e', 'in', 'GK-KARDUS-000085', 'ATOMY-BODY-LOTION', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=46; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-04-29 09:26:00+07'),
  ('dda5c640-a884-3b23-a44b-8dc75b2c2e48', 'in', 'GK-KARDUS-000086', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=47; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:26:00+07'),
  ('acd588da-7113-3bae-beec-ff24e852d8b7', 'in', 'GK-KARDUS-000087', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=48; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:40:00+07'),
  ('f3b427bc-d000-3cfe-8d0e-a626dd6ef1a3', 'in', 'GK-KARDUS-000088', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=49; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:43:00+07'),
  ('58017ab2-8582-3d32-9eae-e4a7222e4b5d', 'in', 'GK-KARDUS-000096', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=50; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-29 09:54:00+07'),
  ('bc508a33-824f-32d8-835c-016d54d529ae', 'in', 'GK-KARDUS-000097', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=51; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:55:00+07'),
  ('ffcdad08-fc7b-3124-a712-050dcd4ba3c5', 'in', 'GK-KARDUS-000098', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=52; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-29 09:56:00+07'),
  ('068d25a8-f2f9-3f82-af07-a665b96f326c', 'in', 'GK-KARDUS-000102', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=53; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 09:59:00+07'),
  ('cfb00e2b-3cac-3472-babe-8cfa819364d7', 'in', 'GK-KARDUS-000103', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=54; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:00:00+07'),
  ('3efb085e-a981-3b91-a7ec-2bee6ec5fa8b', 'in', 'GK-KARDUS-000105', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=55; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-29 10:01:00+07'),
  ('6f7b6bcc-d9db-3091-9f56-3ad2b654fcca', 'in', 'GK-KARDUS-000108', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=56; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:04:00+07'),
  ('8d723876-5d8e-3f5e-9bfd-10c6770df22c', 'in', 'GK-KARDUS-000108', 'ATOMY-HEMOHIM', 4, 4, 8, 'Import data client GudangKu inventory', 'source_id=57; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:04:00+07'),
  ('dec9efe0-7070-3387-b399-4c8805b62eb6', 'in', 'GK-KARDUS-000109', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=58; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:05:00+07'),
  ('717f844b-4319-3633-98b1-d80e676a53f5', 'in', 'GK-KARDUS-000111', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=59; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:07:00+07'),
  ('7ba33319-6115-3fb3-8dfa-bf3bcd72f92d', 'in', 'GK-KARDUS-000112', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=60; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:08:00+07'),
  ('0849d04a-798b-3cd5-ad81-88374d13b1f3', 'in', 'GK-KARDUS-000113', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=61; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:09:00+07'),
  ('7f366cc4-c1a9-3565-8687-3e6656b07733', 'in', 'GK-KARDUS-000114', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=62; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:10:00+07'),
  ('54ca40fd-2461-3eb6-ad8b-1e7b1d591544', 'in', 'GK-KARDUS-000115', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=63; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:12:00+07'),
  ('bb68039c-ee86-3e4b-bcc4-20dd931ed68e', 'in', 'GK-KARDUS-000117', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=64; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:13:00+07'),
  ('264b079f-310f-3973-b04d-c5987bf6fefc', 'in', 'GK-KARDUS-000119', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=65; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:16:00+07'),
  ('7006b70a-8c45-35f5-a1db-d328af80701d', 'in', 'GK-KARDUS-000121', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=66; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:17:00+07'),
  ('b5c5ce54-4910-363c-b728-b19520c6abae', 'in', 'GK-KARDUS-000122', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=67; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:19:00+07'),
  ('3c8feb80-b16e-38e1-872f-9f1b84afe834', 'in', 'GK-KARDUS-000122', 'ATOMY-HEMOHIM', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=68; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:20:00+07'),
  ('05755953-8026-3ae1-9ffe-bcbccb4b6a60', 'in', 'GK-KARDUS-000124', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=69; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:20:00+07'),
  ('ac7f56a0-833a-3507-9604-654740d05b31', 'in', 'GK-KARDUS-000125', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=70; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:20:00+07'),
  ('2584fa0e-203f-3861-b115-94e5650e7059', 'in', 'GK-KARDUS-000127', 'ATOMY-ABSOLUTE-LOTION', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=71; type=MASUK; product_name=Atomy Absolute Lotion; performed_by=Admin', '2026-04-29 10:22:00+07'),
  ('d3ba770c-cebb-3874-8670-22a3509e20f4', 'in', 'GK-KARDUS-000129', 'ATOMY-ABSOLUTE-LOTION', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=72; type=MASUK; product_name=Atomy Absolute Lotion; performed_by=Admin', '2026-04-29 10:25:00+07'),
  ('639ab2d4-c45d-3c17-8aa7-9997ed44bc4c', 'in', 'GK-KARDUS-000126', 'ATOMY-SUNSCREEN-WHITE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=73; type=MASUK; product_name=Atomy Sunscreen White; performed_by=Admin', '2026-04-29 10:25:00+07'),
  ('f0c40737-f5c3-364c-bc17-15dd5d457ae5', 'in', 'GK-KARDUS-000130', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=74; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-29 10:26:00+07'),
  ('ace1f57c-b9bb-387f-bb3e-fbb81d4eae1e', 'in', 'GK-KARDUS-000130', 'ATOMY-ABSOLUTE-EYE-COMPLEX', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=75; type=MASUK; product_name=Atomy Absolute Eye-complex; performed_by=Admin', '2026-04-29 10:27:00+07'),
  ('915babc2-b365-3ece-aaca-e227630c3c46', 'in', 'GK-KARDUS-000126', 'ATOMY-CAFE-ARABICA', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=76; type=MASUK; product_name=Atomy Cafe Arabica; performed_by=Admin', '2026-04-29 10:27:00+07'),
  ('9c85adcb-1e95-3ca5-ac29-e5aefb0ef7fb', 'in', 'GK-KARDUS-000131', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=77; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-29 10:28:00+07'),
  ('78006426-a1e2-3e84-8fd5-96657c002616', 'in', 'GK-KARDUS-000132', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=78; type=MASUK; product_name=Atomy Herbal Hair Conditioner; performed_by=Admin', '2026-04-29 10:29:00+07'),
  ('074c7c1c-a44d-3ae7-b599-7b69fd6c417d', 'in', 'GK-KARDUS-000132', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=79; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:30:00+07'),
  ('9a92304c-0adf-3858-91e3-ab69e5dab0e9', 'in', 'GK-KARDUS-000132', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=80; type=MASUK; product_name=Atomy Herbal Hair Conditioner; performed_by=Admin', '2026-04-29 10:30:00+07'),
  ('a5c91e14-c22e-3b24-9f6b-732ea2312003', 'in', 'GK-KARDUS-000132', 'ATOMY-HERBAL-HAIR-TONIC', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=81; type=MASUK; product_name=Atomy Herbal Hair Tonic; performed_by=Admin', '2026-04-29 10:31:00+07'),
  ('1f113d13-7b98-3acd-b375-d5e4929ea407', 'in', 'GK-KARDUS-000132', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=82; type=MASUK; product_name=Atomy Herbal Hair Shampoo; performed_by=Admin', '2026-04-29 10:31:00+07'),
  ('be864743-4f1b-3c30-993a-13212889503e', 'in', 'GK-KARDUS-000132', 'ATOMY-PROBIOTICS-10', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=83; type=MASUK; product_name=Atomy Probiotics 10+; performed_by=Admin', '2026-04-29 10:32:00+07'),
  ('160289c5-d126-3b46-8426-4e3b38032661', 'in', 'GK-KARDUS-000132', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=84; type=MASUK; product_name=Atomy Color Food Vitamin C; performed_by=Admin', '2026-04-29 10:32:00+07'),
  ('4278b7e2-8318-34fa-96da-78ca4d333fc2', 'in', 'GK-KARDUS-000134', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=85; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-29 10:32:00+07'),
  ('d7c81bd7-1432-3aba-9259-e4358e5d064f', 'in', 'GK-KARDUS-000134', 'ATOMY-HERBAL-HAIR-TONIC', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=86; type=MASUK; product_name=Atomy Herbal Hair Tonic; performed_by=Admin', '2026-04-29 10:32:00+07'),
  ('07cd475d-e41f-3fda-9151-a08865d1b41b', 'in', 'GK-KARDUS-000135', 'ATOMY-BODY-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=87; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-04-29 10:35:00+07'),
  ('89b9b51d-b85a-33e1-951d-e88514053470', 'in', 'GK-KARDUS-000135', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=88; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-04-29 10:35:00+07'),
  ('e811283e-8bbc-3863-a9e6-2fa45813efa4', 'in', 'GK-KARDUS-000135', 'ATOMY-EVENING-CARE-4-SET', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=89; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-04-29 10:35:00+07'),
  ('44a6d98c-1aee-34e8-8bd7-bcecec318b84', 'in', 'GK-KARDUS-000135', 'ATOMY-BODY-LOTION', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=90; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-04-29 10:36:00+07'),
  ('85c9997f-0624-31ff-8fcc-556e829aba26', 'in', 'GK-KARDUS-000136', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=91; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:37:00+07'),
  ('e3c41aa2-0954-33e2-82e4-e4323671df63', 'in', 'GK-KARDUS-000137', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=92; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:38:00+07'),
  ('d6c5a3e3-08ce-3621-9ab0-f394a71f2ca7', 'in', 'GK-KARDUS-000138', 'ATOMY-HERBAL-HAIR-CONDITIONER', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=93; type=MASUK; product_name=Atomy Herbal Hair Conditioner; performed_by=Admin', '2026-04-29 10:39:00+07'),
  ('0a46cea0-64bd-3d1c-a2d8-0dcc6a89b56a', 'in', 'GK-KARDUS-000138', 'ATOMY-ABSOLUTE-AMPOULE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=94; type=MASUK; product_name=Atomy Absolute Ampoule; performed_by=Admin', '2026-04-29 10:39:00+07'),
  ('0d5fe801-9e0b-3ed8-8bfd-33ed6908423d', 'in', 'GK-KARDUS-000139', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=95; type=MASUK; product_name=Atomy Absolute CellActive Skincare Set; performed_by=Admin', '2026-04-29 10:39:00+07'),
  ('45fae7f2-49ec-390c-87b6-24b05b2bdc4d', 'in', 'GK-KARDUS-000138', 'ATOMY-HERBAL-HAIR-TONIC', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=96; type=MASUK; product_name=Atomy Herbal Hair Tonic; performed_by=Admin', '2026-04-29 10:40:00+07'),
  ('a767bbfc-9f02-3122-ae5d-6dc1587ed181', 'in', 'GK-KARDUS-000140', 'ATOMY-BODY-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=97; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-04-29 10:42:00+07'),
  ('ede50312-5dd3-3295-897c-d2ec9f30852f', 'in', 'GK-KARDUS-000140', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=98; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-04-29 10:42:00+07'),
  ('8eeba580-a180-34db-a2ef-5e5263f054c9', 'in', 'GK-KARDUS-000140', 'ATOMY-EVENING-CARE-4-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=99; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-04-29 10:42:00+07'),
  ('8562c3d2-7603-3d69-8ad1-fc2b4bfba1e8', 'in', 'GK-KARDUS-000140', 'ATOMY-BODY-LOTION', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=100; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-04-29 10:42:00+07'),
  ('c1643eaf-1ed9-3daa-99db-204cfa682de7', 'in', 'GK-KARDUS-000140', 'ATOMY-PROBIOTICS-10', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=101; type=MASUK; product_name=Atomy Probiotics 10+; performed_by=Admin', '2026-04-29 10:43:00+07'),
  ('cbc661d8-cd14-34be-a827-45b38e46c3a6', 'in', 'GK-KARDUS-000138', 'ATOMY-HERBAL-HAIR-TONIC', 2, 2, 4, 'Import data client GudangKu inventory', 'source_id=102; type=MASUK; product_name=Atomy Herbal Hair Tonic; performed_by=Admin', '2026-04-29 10:43:00+07'),
  ('fdf395dc-d736-39f2-9b51-76960f54b8ff', 'in', 'GK-KARDUS-000141', 'ATOMY-BODY-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=103; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-04-29 10:44:00+07'),
  ('5c1aa6b0-814a-3c38-92b7-b4736de1d13d', 'in', 'GK-KARDUS-000141', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=104; type=MASUK; product_name=Atomy Herbal Hair Shampoo; performed_by=Admin', '2026-04-29 10:44:00+07'),
  ('1da0b0ab-867c-35f9-b602-8a7429083d5d', 'in', 'GK-KARDUS-000141', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=105; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-04-29 10:44:00+07'),
  ('1d653625-aecf-3ee4-8aeb-daf2ec82b02e', 'in', 'GK-KARDUS-000141', 'ATOMY-EVENING-CARE-4-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=106; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-04-29 10:44:00+07'),
  ('d5ca834f-19fb-3702-80fa-7e80c47aa64f', 'in', 'GK-KARDUS-000141', 'ATOMY-BODY-LOTION', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=107; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-04-29 10:44:00+07'),
  ('aa142b4d-ca1a-3180-ad3d-8e32584606d8', 'in', 'GK-KARDUS-000142', 'ATOMY-BODY-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=108; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-04-29 10:46:00+07'),
  ('a90456d1-e868-30d7-b753-4e2ec7fc66ad', 'in', 'GK-KARDUS-000142', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=109; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-04-29 10:46:00+07'),
  ('2c887fc5-8c42-3f71-a7df-6ad028e8a5e2', 'in', 'GK-KARDUS-000142', 'ATOMY-EVENING-CARE-4-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=110; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-04-29 10:46:00+07'),
  ('7bd40fa9-3a66-32b0-a256-2835a49653d1', 'in', 'GK-KARDUS-000142', 'ATOMY-BODY-LOTION', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=111; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-04-29 10:46:00+07'),
  ('15ced9df-ee5f-3919-8a33-a3adfbae550c', 'in', 'GK-KARDUS-000143', 'ATOMY-TRAVEL-KIT', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=112; type=MASUK; product_name=Atomy Travel Kit; performed_by=Admin', '2026-04-29 10:47:00+07'),
  ('a71056cf-548a-36a1-ab0e-6a588c6a8764', 'in', 'GK-KARDUS-000147', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=113; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-29 10:49:00+07'),
  ('c107f75e-b9f5-3f0f-a7b4-395dc7f332cd', 'in', 'GK-KARDUS-000147', 'ATOMY-HEMOHIM', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=114; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:50:00+07'),
  ('1c553621-d017-3827-bd18-40b1dee72e89', 'in', 'GK-KARDUS-000148', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=115; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-29 10:51:00+07'),
  ('2b2d53e7-d965-39cb-96c7-10715e1fdf9b', 'in', 'GK-KARDUS-000148', 'ATOMY-VITAMIN-B-COMPLEX', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=116; type=MASUK; product_name=Atomy Vitamin B-Complex; performed_by=Admin', '2026-04-29 10:51:00+07'),
  ('5f8e4b20-30e4-3958-ba65-72ad022cdd91', 'in', 'GK-KARDUS-000149', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=117; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-29 10:53:00+07'),
  ('e819dafe-00ec-30a0-8dc9-dd84dfef0872', 'in', 'GK-KARDUS-000150', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=118; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-29 10:54:00+07'),
  ('996ab15f-d39d-3a1a-b5b9-84d4a0abc50b', 'in', 'GK-KARDUS-000150', 'ATOMY-TRAVEL-KIT', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=119; type=MASUK; product_name=Atomy Travel Kit; performed_by=Admin', '2026-04-29 10:54:00+07'),
  ('fb89663d-1b58-32c7-8bd3-4a6efad614fd', 'in', 'GK-KARDUS-000152', 'ATOMY-BODY-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=120; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-04-29 10:56:00+07'),
  ('c6a7d235-68b2-32fc-8944-847eff1d718c', 'in', 'GK-KARDUS-000152', 'ATOMY-EVENING-CARE-4-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=121; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-04-29 10:56:00+07'),
  ('20fa1533-ffe6-3509-8ab6-fa75684f4b03', 'in', 'GK-KARDUS-000152', 'ATOMY-BODY-LOTION', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=122; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-04-29 10:56:00+07'),
  ('fca79e7a-4500-3208-8632-972dc50aadfa', 'in', 'GK-KARDUS-000152', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=123; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-04-29 10:56:00+07'),
  ('c17fbf57-44ab-318b-837d-0a7f4633ab3a', 'in', 'GK-KARDUS-000155', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=124; type=MASUK; product_name=Atomy Herbal Hair Conditioner; performed_by=Admin', '2026-04-29 10:59:00+07'),
  ('48edefe1-e065-3039-9e2d-de51bf3d214a', 'in', 'GK-KARDUS-000154', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=125; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-29 10:59:00+07'),
  ('ab9739db-f37f-334b-99b0-8c772ef2db88', 'in', 'GK-KARDUS-000154', 'ATOMY-HERBAL-HAIR-TONIC', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=126; type=MASUK; product_name=Atomy Herbal Hair Tonic; performed_by=Admin', '2026-04-29 10:59:00+07'),
  ('c81ee87e-acd9-3b78-8b33-48d223c9c93c', 'in', 'GK-KARDUS-000154', 'ATOMY-HERBAL-HAIR-TONIC', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=127; type=MASUK; product_name=Atomy Herbal Hair Tonic; performed_by=Admin', '2026-04-29 11:00:00+07'),
  ('d6a9035b-e5dc-37ec-95de-498572deb4a8', 'in', 'GK-KARDUS-000154', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=128; type=MASUK; product_name=Atomy Herbal Hair Shampoo; performed_by=Admin', '2026-04-29 11:00:00+07'),
  ('a64720e3-4806-31b0-982f-2d92afc14470', 'in', 'GK-KARDUS-000154', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=129; type=MASUK; product_name=Atomy Herbal Hair Shampoo; performed_by=Admin', '2026-04-29 11:00:00+07'),
  ('d8294dbf-62aa-3af6-a164-d5887eef845d', 'in', 'GK-KARDUS-000154', 'ATOMY-PROBIOTICS-10', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=130; type=MASUK; product_name=Atomy Probiotics 10+; performed_by=Admin', '2026-04-29 11:00:00+07'),
  ('af7f7191-87cc-3ae4-848d-55b118c87222', 'in', 'GK-KARDUS-000154', 'ATOMY-PROBIOTICS-10', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=131; type=MASUK; product_name=Atomy Probiotics 10+; performed_by=Admin', '2026-04-29 11:00:00+07'),
  ('d0f2d8bf-b5d2-3587-96eb-d5d669300995', 'in', 'GK-KARDUS-000154', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=132; type=MASUK; product_name=Atomy Color Food Vitamin C; performed_by=Admin', '2026-04-29 11:00:00+07'),
  ('350ff9d2-1b33-37e3-be09-d6a8a88bb3d7', 'in', 'GK-KARDUS-000154', 'ATOMY-HERBAL-HAIR-TONIC', 1, 2, 3, 'Import data client GudangKu inventory', 'source_id=133; type=MASUK; product_name=Atomy Herbal Hair Tonic; performed_by=Admin', '2026-04-29 11:00:00+07'),
  ('1a2720ee-271d-37fc-a8b8-5b5acf3acb59', 'in', 'GK-KARDUS-000156', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=134; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 05:55:00+07'),
  ('a28ddaaf-f1bc-35fe-a076-948155b1c470', 'in', 'GK-KARDUS-000157', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=135; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 06:03:00+07'),
  ('3dcec73b-ad93-3a4d-b8a0-17f85c3e4752', 'in', 'GK-KARDUS-000158', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=136; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 06:04:00+07'),
  ('3c11e465-39d8-3185-a13d-1fdfd1dfac01', 'in', 'GK-KARDUS-000159', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=137; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 06:06:00+07'),
  ('f838acab-4964-3b1e-8ddb-cd1646c7fdfd', 'in', 'GK-KARDUS-000160', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=138; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 06:07:00+07'),
  ('c9978edd-b63c-31b2-8ed6-2eb9fe852cb4', 'in', 'GK-KARDUS-000161', 'ATOMY-HEMOHIM', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=139; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 06:09:00+07'),
  ('9a0ee207-1309-3db3-a589-56fdaa500e94', 'in', 'GK-KARDUS-000162', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=140; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 06:12:00+07'),
  ('bf3af862-65c8-3785-b17c-f340af36f083', 'in', 'GK-KARDUS-000163', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=141; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 06:45:00+07'),
  ('884bd7c5-0396-31b6-a6c2-ccde81df8cdc', 'in', 'GK-KARDUS-000164', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=142; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 06:46:00+07'),
  ('74e06047-68ba-3a3d-bdd9-4f6282414091', 'in', 'GK-KARDUS-000165', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=143; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 06:51:00+07'),
  ('f09bd96f-f6da-304f-b57d-8f278dfa051a', 'in', 'GK-KARDUS-000166', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=144; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 06:53:00+07'),
  ('f5ed1393-8a30-3490-8824-7a24827bc00b', 'in', 'GK-KARDUS-000167', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=145; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 06:57:00+07'),
  ('54f31e50-e2eb-31e8-ae1a-687c1b0f5292', 'in', 'GK-KARDUS-000168', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=146; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 07:02:00+07'),
  ('72a703e5-95ca-30d4-8967-9b4288c92929', 'in', 'GK-KARDUS-000169', 'ATOMY-PAKET-RAMADHAN-CARE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=147; type=MASUK; product_name=Atomy Paket Ramadhan Care; performed_by=Admin', '2026-04-30 07:03:00+07'),
  ('66101cc8-1c46-343f-82e7-79a8688ee75f', 'in', 'GK-KARDUS-000170', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=148; type=MASUK; product_name=Atomy Color Food Vitamin C; performed_by=Admin', '2026-04-30 07:04:00+07'),
  ('32442c98-1592-3e65-93de-3e62516a4eda', 'in', 'GK-KARDUS-000170', 'ATOMY-PROBIOTICS-10', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=149; type=MASUK; product_name=Atomy Probiotics 10+; performed_by=Admin', '2026-04-30 07:05:00+07'),
  ('14951a8b-e7bb-3e38-a824-d8bf24efa626', 'in', 'GK-KARDUS-000170', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=150; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 07:05:00+07'),
  ('3fca8928-0c1f-3b11-a295-f3382e9a57e1', 'in', 'GK-KARDUS-000171', 'ATOMY-HONGSAMDAN-RED-GINSENG', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=151; type=MASUK; product_name=Atomy Hongsamdan Red Ginseng; performed_by=Admin', '2026-04-30 07:07:00+07'),
  ('1b8a49f0-6df5-3d4b-80cd-08a90ac2b47c', 'in', 'GK-KARDUS-000172', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=152; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 09:33:00+07'),
  ('95a4ba0a-9fe9-306b-b15c-ec63429fb8f3', 'in', 'GK-KARDUS-000173', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=153; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 09:33:00+07'),
  ('11f58ed8-382e-39c1-acd8-a5ab9728ce58', 'in', 'GK-KARDUS-000174', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=154; type=MASUK; product_name=Atomy Paket Bingkisan Lebaran; performed_by=Admin', '2026-04-30 09:35:00+07'),
  ('9bc3270b-848b-33e9-a531-40bb57eb1acd', 'in', 'GK-KARDUS-000176', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=155; type=MASUK; product_name=Atomy Paket Bingkisan Lebaran; performed_by=Admin', '2026-04-30 09:36:00+07'),
  ('f6163bc0-eac2-345d-9410-ad44324284c7', 'in', 'GK-KARDUS-000177', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=156; type=MASUK; product_name=Atomy Paket Bingkisan Lebaran; performed_by=Admin', '2026-04-30 09:37:00+07'),
  ('81f3925f-c395-325e-b833-6905e044c0c5', 'in', 'GK-KARDUS-000177', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=157; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 09:37:00+07'),
  ('3c53e3c0-43bd-31e0-8059-4918d294d855', 'in', 'GK-KARDUS-000178', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=158; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 09:38:00+07'),
  ('4e30c0a4-eee7-3d0e-a736-da17c1567a3b', 'in', 'GK-KARDUS-000180', 'ATOMY-TRAVEL-KIT', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=159; type=MASUK; product_name=Atomy Travel Kit; performed_by=Admin', '2026-04-30 09:39:00+07'),
  ('9ca87808-4370-3a1b-97a7-6f0daf1ee1d7', 'in', 'GK-KARDUS-000180', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=160; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 09:39:00+07'),
  ('2265d0fd-26b5-334c-96dc-90f73e6f0086', 'in', 'GK-KARDUS-000181', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=161; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 09:40:00+07'),
  ('8f6812c5-0799-32b5-9b8b-2bbfef753bc9', 'in', 'GK-KARDUS-000183', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=162; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 09:41:00+07'),
  ('f154bd94-39e8-308c-b4a3-07add7bf53de', 'in', 'GK-KARDUS-000184', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=163; type=MASUK; product_name=Atomy Paket Bingkisan Lebaran; performed_by=Admin', '2026-04-30 09:42:00+07'),
  ('5b36bb89-0e15-3abd-a3dd-3c0c89224452', 'in', 'GK-KARDUS-000186', 'ATOMY-TRAVEL-KIT', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=164; type=MASUK; product_name=Atomy Travel Kit; performed_by=Admin', '2026-04-30 09:43:00+07'),
  ('9bf3ebc3-b09e-317e-bb65-652384e8305f', 'in', 'GK-KARDUS-000188', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=165; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 09:45:00+07'),
  ('7769992e-4bcd-3600-99e8-30d64ebd317e', 'in', 'GK-KARDUS-000188', 'ATOMY-TOOTHBRUSH', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=166; type=MASUK; product_name=Atomy Toothbrush; performed_by=Admin', '2026-04-30 09:46:00+07'),
  ('b255273c-53e8-32a6-8992-bdc87b7769aa', 'in', 'GK-KARDUS-000188', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=167; type=MASUK; product_name=Atomy Absolute CellActive Skincare Set; performed_by=Admin', '2026-04-30 09:46:00+07'),
  ('93236088-6053-3883-9812-10e57546a875', 'in', 'GK-KARDUS-000187', 'ATOMY-BB-CREAM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=168; type=MASUK; product_name=Atomy BB Cream; performed_by=Admin', '2026-04-30 09:47:00+07'),
  ('59d5c755-87d0-3867-8df2-914c760d1aee', 'in', 'GK-KARDUS-000187', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=169; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 09:47:00+07'),
  ('36116718-4759-3bfa-966c-ab1bf13f2494', 'in', 'GK-KARDUS-000191', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=170; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 09:50:00+07'),
  ('a21db82e-d95e-3b9c-b759-848c070cddd5', 'in', 'GK-KARDUS-000194', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=171; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 09:51:00+07'),
  ('30752c6f-38b1-3413-a9a1-52cfda234e2f', 'in', 'GK-KARDUS-000196', 'ATOMY-TRAVEL-KIT', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=172; type=MASUK; product_name=Atomy Travel Kit; performed_by=Admin', '2026-04-30 09:53:00+07'),
  ('ebe790ed-8281-34b3-9a2d-51033048eba6', 'in', 'GK-KARDUS-000197', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=173; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 09:53:00+07'),
  ('abfedce7-5a0f-3ed3-825a-46d21488a80c', 'in', 'GK-KARDUS-000198', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=174; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 09:54:00+07'),
  ('5e8a26b0-56b4-348c-94c7-293ffbb7ff8b', 'in', 'GK-KARDUS-000199', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=175; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 09:55:00+07'),
  ('a8a7d442-03a2-3b43-aa89-b1a76971ef96', 'in', 'GK-KARDUS-000200', 'ATOMY-PAKET-BERKAH-RAMADAN-B', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=176; type=MASUK; product_name=Atomy Paket Berkah Ramadan B; performed_by=Admin', '2026-04-30 09:56:00+07'),
  ('89d0d103-18db-324d-8944-4844aa8153f1', 'in', 'GK-KARDUS-000201', 'ATOMY-TOOTHPASTE-50G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=177; type=MASUK; product_name=Atomy Toothpaste 50g; performed_by=Admin', '2026-04-30 09:56:00+07'),
  ('cdea2948-47c8-3f2b-adf7-2b0b46b655f1', 'in', 'GK-KARDUS-000201', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=178; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 09:57:00+07'),
  ('bf8e8d1d-fe07-32b8-b2b0-6f6c7c0b34fc', 'in', 'GK-KARDUS-000201', 'ATOMY-TOOTHBRUSH', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=179; type=MASUK; product_name=Atomy Toothbrush; performed_by=Admin', '2026-04-30 09:57:00+07'),
  ('c19a9c39-6674-3d02-a914-0c2a69e29dfc', 'in', 'GK-KARDUS-000202', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=180; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 09:58:00+07'),
  ('0ecf9737-9a68-3409-a827-a0fd27e774c2', 'in', 'GK-KARDUS-000203', 'ATOMY-AIDAM-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=181; type=MASUK; product_name=Atomy Aidam Cleanser; performed_by=Admin', '2026-04-30 09:59:00+07'),
  ('b4bdcf0e-d326-3862-a04b-b86ea7ad3639', 'in', 'GK-KARDUS-000203', 'ATOMY-TOOTHPASTE-50G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=182; type=MASUK; product_name=Atomy Toothpaste 50g; performed_by=Admin', '2026-04-30 09:59:00+07'),
  ('9301dcd8-ba3c-3677-90f5-7bd45a211467', 'in', 'GK-KARDUS-000203', 'ATOMY-TRAVEL-KIT', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=183; type=MASUK; product_name=Atomy Travel Kit; performed_by=Admin', '2026-04-30 09:59:00+07'),
  ('1b963a43-4095-36bd-a5b1-067dfd7e2c5a', 'in', 'GK-KARDUS-000206', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=184; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 10:01:00+07'),
  ('a70288f1-5569-3f9a-8606-9ea7baf712d6', 'in', 'GK-KARDUS-000207', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=185; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 10:06:00+07'),
  ('fd1d6758-b0e5-3402-9b91-41622ffeef4d', 'in', 'GK-KARDUS-000209', 'ATOMY-PAKET-BINGKISAN-LEBARAN', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=186; type=MASUK; product_name=Atomy Paket Bingkisan Lebaran; performed_by=Admin', '2026-04-30 10:11:00+07'),
  ('fb158ab9-c7aa-3165-b3dd-c4e3168f7bb1', 'in', 'GK-KARDUS-000209', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=187; type=MASUK; product_name=Atomy Hydra Brightening Care Set; performed_by=Admin', '2026-04-30 10:11:00+07'),
  ('c48c17c2-4277-3780-b64b-7cdae8ca4b89', 'in', 'GK-KARDUS-000210', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=188; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 10:12:00+07'),
  ('e34d453f-9a8b-3c19-8c37-57a5ccb351ef', 'in', 'GK-KARDUS-000211', 'ATOMY-STAINLESS-STEEL-SCRUBBER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=189; type=MASUK; product_name=Atomy Stainless Steel Scrubber; performed_by=Admin', '2026-04-30 10:12:00+07'),
  ('a0c9f765-25d7-3d00-a46f-f0df544fb084', 'in', 'GK-KARDUS-000210', 'ATOMY-DEEP-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=190; type=MASUK; product_name=Atomy Deep Cleanser 150ml; performed_by=Admin', '2026-04-30 10:13:00+07'),
  ('2ad47d46-0ecc-3df4-9e30-dd4423ebb6d7', 'in', 'GK-KARDUS-000211', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=191; type=MASUK; product_name=Atomy Color Food Vitamin C; performed_by=Admin', '2026-04-30 10:13:00+07'),
  ('74ba1d0b-896a-33c6-ac95-b2c029a3639d', 'in', 'GK-KARDUS-000210', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=192; type=MASUK; product_name=Atomy Color Food Vitamin C; performed_by=Admin', '2026-04-30 10:13:00+07'),
  ('ea7bcdd0-bfb3-310b-b69c-a987a0a16343', 'in', 'GK-KARDUS-000213', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=193; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-04-30 10:16:00+07'),
  ('134cc9ae-bbaf-3145-bbb2-03c8bfe37bd1', 'in', 'GK-KARDUS-000218', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=194; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 10:21:00+07'),
  ('83a36ebc-904c-3a01-bdb3-209f1ef54f62', 'in', 'GK-KARDUS-000228', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=195; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 10:37:00+07'),
  ('10718ce0-8744-3272-9862-50767bfcc7ec', 'in', 'GK-KARDUS-000230', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=196; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-04-30 10:40:00+07'),
  ('b5700838-4e5e-343c-98af-5f61249f6e53', 'in', 'GK-KARDUS-000236', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=197; type=MASUK; product_name=Atomy Absolute CellActive Skincare Set; performed_by=Admin', '2026-05-02 07:48:00+07'),
  ('4a46b614-4807-3132-ad49-04c80caf40ba', 'in', 'GK-KARDUS-000236', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=198; type=MASUK; product_name=Atomy Herbal Hair Shampoo; performed_by=Admin', '2026-05-02 07:48:00+07'),
  ('bdc0b319-8f75-30fe-aa65-173ca1d49dd5', 'in', 'GK-KARDUS-000237', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=199; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 07:51:00+07'),
  ('befedf7d-3566-394c-be91-a48966981d60', 'in', 'GK-KARDUS-000235', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=200; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 07:56:00+07'),
  ('cc85bc78-a35b-38d6-b5c9-1a00ff1d7e7f', 'in', 'GK-KARDUS-000241', 'ATOMY-CAFE-ARABICA', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=201; type=MASUK; product_name=Atomy Cafe Arabica; performed_by=Admin', '2026-05-02 07:58:00+07'),
  ('9814cf0d-1c6a-3e14-b501-2b161624b6d5', 'in', 'GK-KARDUS-000235', 'ATOMY-HEMOHIM', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=202; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 08:11:00+07'),
  ('23516115-5523-38be-9f8c-890b6a357e26', 'in', 'GK-KARDUS-000264', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=203; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 08:21:00+07'),
  ('38e75fb6-f3a1-3b4e-8e57-bf9242b557a9', 'in', 'GK-KARDUS-000235', 'ATOMY-HEMOHIM', 1, 2, 3, 'Import data client GudangKu inventory', 'source_id=204; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 08:25:00+07'),
  ('2ca16248-3b42-367e-9dc3-d1d1916cd9ec', 'in', 'GK-KARDUS-000272', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=205; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 08:28:00+07'),
  ('415e5b28-4a06-3a56-826f-7c98d9619a61', 'in', 'GK-KARDUS-000235', 'ATOMY-HEMOHIM', 1, 3, 4, 'Import data client GudangKu inventory', 'source_id=206; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 08:29:00+07'),
  ('b9b0bd99-c44f-3a71-b526-13b637d45f09', 'in', 'GK-KARDUS-000277', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=207; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 08:32:00+07'),
  ('2836913d-43c6-3a7c-a581-0e28600a07f4', 'in', 'GK-KARDUS-000283', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=208; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 08:37:00+07'),
  ('00bb232b-573b-3554-8131-72337e5e6970', 'in', 'GK-KARDUS-000235', 'ATOMY-HEMOHIM', 1, 4, 5, 'Import data client GudangKu inventory', 'source_id=209; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 08:40:00+07'),
  ('832576c7-db8e-33bc-a376-55c067ab7a6d', 'in', 'GK-KARDUS-000287', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=210; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 08:46:00+07'),
  ('a6ebe2a9-07b2-3126-857e-02293fade1b1', 'in', 'GK-KARDUS-000288', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=211; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 08:48:00+07'),
  ('ffd34c24-c37f-3a6d-ada0-9060c7952200', 'in', 'GK-KARDUS-000291', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=212; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 08:59:00+07'),
  ('208b0d07-8181-37ae-acb3-945aecd2a188', 'in', 'GK-KARDUS-000292', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=213; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:02:00+07'),
  ('8bff4866-23dd-3fee-a4ed-5aab4184a760', 'in', 'GK-KARDUS-000235', 'ATOMY-HEMOHIM', 1, 5, 6, 'Import data client GudangKu inventory', 'source_id=214; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:06:00+07'),
  ('2f5cb789-bbad-3e84-acee-fcd091ae89ca', 'in', 'GK-KARDUS-000298', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=215; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:10:00+07'),
  ('5f7e6d51-86aa-3562-9829-14834c0eb3a8', 'in', 'GK-KARDUS-000299', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=216; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:11:00+07'),
  ('074f526e-923c-3437-98d6-334d7461a5ba', 'in', 'GK-KARDUS-000301', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=217; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:14:00+07'),
  ('711f0117-f2da-32b3-981e-4ebff8ae112b', 'in', 'GK-KARDUS-000303', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=218; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:17:00+07'),
  ('280d830f-e8f6-3052-a2d7-e6dc842c2528', 'in', 'GK-KARDUS-000306', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=219; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:22:00+07'),
  ('58bd0468-fefa-33bf-a99e-397bdd3603e6', 'in', 'GK-KARDUS-000307', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=220; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:23:00+07'),
  ('85116edc-9f30-3383-81f9-7f64cc5ff07f', 'in', 'GK-KARDUS-000308', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=221; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:26:00+07'),
  ('5194a588-014e-34b0-809f-d949b8f22ebb', 'in', 'GK-KARDUS-000317', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=222; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:36:00+07'),
  ('127940cc-17bf-3f8f-b4de-6b365ca2406b', 'in', 'GK-KARDUS-000318', 'ATOMY-TOOTHPASTE-50G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=223; type=MASUK; product_name=Atomy Toothpaste 50g; performed_by=Admin', '2026-05-02 09:40:00+07'),
  ('294fecdc-659c-3db2-9911-c02d4a37c7cc', 'in', 'GK-KARDUS-000235', 'ATOMY-HEMOHIM', 1, 6, 7, 'Import data client GudangKu inventory', 'source_id=224; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:41:00+07'),
  ('3b62f1e4-d49d-35c2-ae5a-809540b3b6ff', 'in', 'GK-KARDUS-000320', 'ATOMY-STAINLESS-STEEL-SCRUBBER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=225; type=MASUK; product_name=Atomy Stainless Steel Scrubber; performed_by=Admin', '2026-05-02 09:42:00+07'),
  ('ef735a21-9094-3ff9-93be-5e0d8ebb5874', 'in', 'GK-KARDUS-000321', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=226; type=MASUK; product_name=Atomy Absolute CellActive Skincare Set; performed_by=Admin', '2026-05-02 09:43:00+07'),
  ('4338bd39-0302-3ce8-9616-85cd919ebe62', 'in', 'GK-KARDUS-000321', 'ATOMY-ABSOLUTE-AMPOULE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=227; type=MASUK; product_name=Atomy Absolute Ampoule; performed_by=Admin', '2026-05-02 09:44:00+07'),
  ('a807257c-efe0-37b1-b67c-6eebc699e845', 'in', 'GK-KARDUS-000321', 'ATOMY-TRAVEL-KIT', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=228; type=MASUK; product_name=Atomy Travel Kit; performed_by=Admin', '2026-05-02 09:44:00+07'),
  ('d681330a-4855-33f6-b492-c8ac208874c9', 'in', 'GK-KARDUS-000322', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=229; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:45:00+07'),
  ('7e58ca30-fa7e-30d0-a865-f1741c01f897', 'in', 'GK-KARDUS-000323', 'ATOMY-TOOTHPASTE-200G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=230; type=MASUK; product_name=Atomy Toothpaste 200g; performed_by=Admin', '2026-05-02 09:46:00+07'),
  ('0ee2cac9-8de5-3d79-93f7-cbb5419b97b5', 'in', 'GK-KARDUS-000235', 'ATOMY-SUNSCREEN-WHITE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=231; type=MASUK; product_name=Atomy Sunscreen White; performed_by=Admin', '2026-05-02 09:47:00+07'),
  ('12842d1d-1df7-36e0-ab6f-b40183e82106', 'in', 'GK-KARDUS-000323', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=232; type=MASUK; product_name=Atomy Herbal Hair Shampoo; performed_by=Admin', '2026-05-02 09:47:00+07'),
  ('6372c0f4-ec52-3ee0-90d0-f0b289fd3f47', 'in', 'GK-KARDUS-000324', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=233; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:48:00+07'),
  ('af16ffba-3b2d-3842-84cb-80c12f4a2965', 'in', 'GK-KARDUS-000323', 'ATOMY-SUNSCREEN-BEIGE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=234; type=MASUK; product_name=Atomy Sunscreen Beige; performed_by=Admin', '2026-05-02 09:48:00+07'),
  ('01c06355-537d-342f-b43a-0af49b120398', 'in', 'GK-KARDUS-000323', 'ATOMY-SUNSCREEN-BEIGE', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=235; type=MASUK; product_name=Atomy Sunscreen Beige; performed_by=Admin', '2026-05-02 09:48:00+07'),
  ('2d2891e4-55c5-3dbe-b036-534f7bc2abc2', 'in', 'GK-KARDUS-000323', 'ATOMY-TOOTHBRUSH', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=236; type=MASUK; product_name=Atomy Toothbrush; performed_by=Admin', '2026-05-02 09:49:00+07'),
  ('b1bca22e-7c5d-3468-8877-855a1244b130', 'in', 'GK-KARDUS-000325', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=237; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-02 09:50:00+07'),
  ('1a0580c6-a992-31d4-8732-1970f425f7fe', 'in', 'GK-KARDUS-000327', 'ATOMY-BABY-LOTION', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=238; type=MASUK; product_name=Atomy Baby Lotion; performed_by=Admin', '2026-05-02 09:55:00+07'),
  ('3f762eae-3859-376d-a9fb-200345f13286', 'in', 'GK-KARDUS-000235', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=239; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-02 10:01:00+07'),
  ('b900b687-90af-3d0e-aeaa-4b75d9026746', 'in', 'GK-KARDUS-000235', 'ATOMY-SLIM-BODY-SHAKE-2-0', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=240; type=MASUK; product_name=Atomy Slim Body Shake 2.0; performed_by=Admin', '2026-05-02 10:04:00+07'),
  ('e365d8bd-0ad7-35e5-aff1-824aa2ce1473', 'in', 'GK-KARDUS-000334', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=241; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-02 10:04:00+07'),
  ('a1566f98-9a14-31dc-b7e0-d20df3e5df32', 'in', 'GK-KARDUS-000332', 'ATOMY-CAFE-ARABICA', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=242; type=MASUK; product_name=Atomy Cafe Arabica; performed_by=Admin', '2026-05-02 10:04:00+07'),
  ('a20114c3-946c-36db-9e9f-bea5f48607f0', 'in', 'GK-KARDUS-000333', 'ATOMY-BB-CREAM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=243; type=MASUK; product_name=Atomy BB Cream; performed_by=Admin', '2026-05-02 10:04:00+07'),
  ('ade10c7e-ae33-3103-a95b-a743fbe05f58', 'in', 'GK-KARDUS-000329', 'ATOMY-SLIM-BODY-SHAKE-2-0', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=244; type=MASUK; product_name=Atomy Slim Body Shake 2.0; performed_by=Admin', '2026-05-02 10:05:00+07'),
  ('495055b9-4348-35d6-ba9a-ec9b82091224', 'in', 'GK-KARDUS-000329', 'ATOMY-TOOTHPASTE-50G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=245; type=MASUK; product_name=Atomy Toothpaste 50g; performed_by=Admin', '2026-05-02 10:05:00+07'),
  ('d913c9e0-e98e-3b4f-b838-69e6d6229615', 'in', 'GK-KARDUS-000331', 'ATOMY-TOOTHPASTE-50G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=246; type=MASUK; product_name=Atomy Toothpaste 50g; performed_by=Admin', '2026-05-02 10:06:00+07'),
  ('61f3b4ab-f0cf-3649-8140-6571d50cf786', 'in', 'GK-KARDUS-000331', 'ATOMY-TOOTHPASTE-200G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=247; type=MASUK; product_name=Atomy Toothpaste 200g; performed_by=Admin', '2026-05-02 10:08:00+07'),
  ('7f99e647-e611-30aa-b22a-72e5291af304', 'in', 'GK-KARDUS-000331', 'ATOMY-SUNSCREEN-WHITE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=248; type=MASUK; product_name=Atomy Sunscreen White; performed_by=Admin', '2026-05-02 10:08:00+07'),
  ('d7530128-da75-33c1-9388-7990c6a31fc3', 'in', 'GK-KARDUS-000331', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=249; type=MASUK; product_name=Atomy Herbal Hair Shampoo; performed_by=Admin', '2026-05-02 10:09:00+07'),
  ('d8b66899-ade5-39b7-ad32-6feccfd6605d', 'in', 'GK-KARDUS-000331', 'ATOMY-SUNSCREEN-BEIGE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=250; type=MASUK; product_name=Atomy Sunscreen Beige; performed_by=Admin', '2026-05-02 10:09:00+07'),
  ('cf34a2bb-9621-359b-937f-161f4d39e565', 'in', 'GK-KARDUS-000331', 'ATOMY-TOOTHBRUSH', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=251; type=MASUK; product_name=Atomy Toothbrush; performed_by=Admin', '2026-05-02 10:09:00+07'),
  ('d0656678-d9a4-3a31-aedc-2c2f9661691b', 'in', 'GK-KARDUS-000335', 'ATOMY-BODY-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=252; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-05-02 10:13:00+07'),
  ('d51748bc-66f3-3af5-b47f-d193bca1ca71', 'in', 'GK-KARDUS-000335', 'ATOMY-TOOTHPASTE-200G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=253; type=MASUK; product_name=Atomy Toothpaste 200g; performed_by=Admin', '2026-05-02 10:14:00+07'),
  ('1f70693a-9aaf-3fbe-aadf-d66303207ba3', 'in', 'GK-KARDUS-000335', 'ATOMY-SUNSCREEN-WHITE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=254; type=MASUK; product_name=Atomy Sunscreen White; performed_by=Admin', '2026-05-02 10:14:00+07'),
  ('e75f2846-164b-3547-bb33-6b5a55ba75a5', 'in', 'GK-KARDUS-000335', 'ATOMY-EVENING-CARE-4-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=255; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-05-02 10:14:00+07'),
  ('857beb0c-c490-3cfc-90ed-81acf309e275', 'in', 'GK-KARDUS-000335', 'ATOMY-BODY-LOTION', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=256; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-05-02 10:14:00+07'),
  ('85607159-620d-3b98-a2b8-b84c0bdaeb08', 'in', 'GK-KARDUS-000335', 'ATOMY-SUNSCREEN-BEIGE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=257; type=MASUK; product_name=Atomy Sunscreen Beige; performed_by=Admin', '2026-05-02 10:14:00+07'),
  ('c01fea9e-6b05-39fd-bd53-2e7b9f572c89', 'in', 'GK-KARDUS-000335', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=258; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-05-02 10:15:00+07'),
  ('5e52f9e6-1cb1-3de7-a98d-61f91d770397', 'in', 'GK-KARDUS-000335', 'ATOMY-TOOTHBRUSH', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=259; type=MASUK; product_name=Atomy Toothbrush; performed_by=Admin', '2026-05-02 10:15:00+07'),
  ('ace31768-e6e9-3a48-bd14-d4efbc5b5bf4', 'in', 'GK-KARDUS-000336', 'ATOMY-PURE-SPIRULINA', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=260; type=MASUK; product_name=Atomy Pure Spirulina; performed_by=Admin', '2026-05-02 10:19:00+07'),
  ('3b4139b2-0cbd-31e5-9adf-fc88d600db9c', 'in', 'GK-KARDUS-000337', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=261; type=MASUK; product_name=Atomy Absolute CellActive Skincare Set; performed_by=Admin', '2026-05-02 10:20:00+07'),
  ('fe0abdb9-4149-34c4-970a-0d9e7317c5fc', 'in', 'GK-KARDUS-000337', 'ATOMY-ABSOLUTE-AMPOULE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=262; type=MASUK; product_name=Atomy Absolute Ampoule; performed_by=Admin', '2026-05-02 10:20:00+07'),
  ('7dd918e4-ecf6-371e-b639-4b2a92d7d185', 'in', 'GK-KARDUS-000337', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=263; type=MASUK; product_name=Atomy Hydra Brightening Care Set; performed_by=Admin', '2026-05-02 10:20:00+07'),
  ('dad8ff39-022b-3826-955e-8891af7e01a9', 'in', 'GK-KARDUS-000338', 'ATOMY-BODY-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=264; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-05-02 10:20:00+07'),
  ('b113a7c9-ef66-3a12-8967-2f2f06f0e84f', 'in', 'GK-KARDUS-000338', 'ATOMY-EVENING-CARE-4-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=265; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-05-02 10:20:00+07'),
  ('157272f9-eb2e-311a-9843-b2cfc170f6fb', 'in', 'GK-KARDUS-000338', 'ATOMY-BODY-LOTION', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=266; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-05-02 10:21:00+07'),
  ('ac789b9c-07fc-33c4-8a70-c92084145e40', 'in', 'GK-KARDUS-000338', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=267; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-05-02 10:21:00+07'),
  ('5553c43f-1f12-3807-8af8-ffca64fb0d54', 'in', 'GK-KARDUS-000235', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=268; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=OWEN', '2026-05-02 10:30:00+07'),
  ('1f0c116a-e2b6-3e04-83cf-520048766973', 'in', 'GK-KARDUS-000238', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=269; type=MASUK; product_name=Atomy HemoHim; performed_by=OWEN', '2026-05-02 10:31:00+07'),
  ('548df1eb-6131-31ff-b736-3439eb5e95d9', 'in', 'GK-KARDUS-000235', 'ATOMY-BODY-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=270; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-05-02 10:39:00+07'),
  ('1e37dcf1-7814-3217-8663-a5e1387ac672', 'in', 'GK-KARDUS-000235', 'ATOMY-EVENING-CARE-4-SET', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=271; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-05-02 10:40:00+07'),
  ('08b04af2-2bd3-3c0a-abb1-6740c01ea720', 'in', 'GK-KARDUS-000353', 'ATOMY-SUNSCREEN-WHITE', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=272; type=MASUK; product_name=Atomy Sunscreen White; performed_by=Admin', '2026-05-02 10:42:00+07'),
  ('043e4685-c8cf-3d16-9372-e660903cbc98', 'in', 'GK-KARDUS-000235', 'ATOMY-BODY-LOTION', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=273; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-05-02 10:42:00+07'),
  ('672d1a9c-a6c5-3d16-af58-fa1a628136ce', 'in', 'GK-KARDUS-000235', 'ATOMY-TOOTHPASTE-200G', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=274; type=MASUK; product_name=Atomy Toothpaste 200g; performed_by=Admin', '2026-05-02 10:43:00+07'),
  ('f214c57b-c29f-369d-8873-0219fb0c23b0', 'in', 'GK-KARDUS-000235', 'ATOMY-SUNSCREEN-BEIGE', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=275; type=MASUK; product_name=Atomy Sunscreen Beige; performed_by=Admin', '2026-05-02 10:44:00+07'),
  ('917c7b0f-6838-393e-b69b-bc8a2f2a7480', 'in', 'GK-KARDUS-000235', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=276; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-05-02 10:45:00+07'),
  ('89024737-2808-30bc-9f4b-5afedcf92ff9', 'in', 'GK-KARDUS-000235', 'ATOMY-TOOTHBRUSH', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=277; type=MASUK; product_name=Atomy Toothbrush; performed_by=Admin', '2026-05-02 10:45:00+07'),
  ('1b437e93-7d54-3561-a8d7-e97c07b56732', 'in', 'GK-KARDUS-000235', 'ATOMY-BODY-CLEANSER', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=278; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-05-02 10:48:00+07'),
  ('9f7afc6c-9981-3266-9235-ad8bb05ce9e7', 'in', 'GK-KARDUS-000365', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=279; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-05-02 10:48:00+07'),
  ('aac1d5b1-0d61-3e35-ae47-242357bf7f97', 'in', 'GK-KARDUS-000365', 'ATOMY-HONGSAMDAN-RED-GINSENG', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=280; type=MASUK; product_name=Atomy Hongsamdan Red Ginseng; performed_by=Admin', '2026-05-02 10:48:00+07'),
  ('78879a7d-f3b3-3965-92f7-8db9555ba6ad', 'in', 'GK-KARDUS-000235', 'ATOMY-EVENING-CARE-4-SET', 1, 2, 3, 'Import data client GudangKu inventory', 'source_id=281; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-05-02 10:49:00+07'),
  ('e6017bf6-a314-3921-8245-0d93452afb58', 'in', 'GK-KARDUS-000365', 'ATOMY-BODY-LOTION', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=282; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-05-02 10:49:00+07'),
  ('14c6f21c-16af-34cf-9054-a60a8a0dded7', 'in', 'GK-KARDUS-000365', 'ATOMY-PROBIOTICS-10', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=283; type=MASUK; product_name=Atomy Probiotics 10+; performed_by=Admin', '2026-05-02 10:49:00+07'),
  ('30be37da-12f5-3f1a-a3f3-3dc233a5eed2', 'in', 'GK-KARDUS-000365', 'ATOMY-COLOR-FOOD-VITAMIN-C', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=284; type=MASUK; product_name=Atomy Color Food Vitamin C; performed_by=Admin', '2026-05-02 10:49:00+07'),
  ('fcbeef70-b0e5-3b7e-afc1-e42b11bf7ba5', 'in', 'GK-KARDUS-000235', 'ATOMY-BODY-LOTION', 2, 2, 4, 'Import data client GudangKu inventory', 'source_id=285; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-05-02 10:52:00+07'),
  ('dae58428-eeed-394c-8b4a-140be40afb59', 'in', 'GK-KARDUS-000235', 'ATOMY-HERBAL-HAIR-TONIC', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=286; type=MASUK; product_name=Atomy Herbal Hair Tonic; performed_by=Admin', '2026-05-02 10:54:00+07'),
  ('7c2d642e-3b7f-3591-b775-8b94f45403f9', 'in', 'GK-KARDUS-000369', 'ATOMY-DEEP-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=287; type=MASUK; product_name=Atomy Deep Cleanser 150ml; performed_by=Admin', '2026-05-02 10:55:00+07'),
  ('2f66278f-40c9-3232-84d5-5b0d13def889', 'in', 'GK-KARDUS-000235', 'ATOMY-TOOTHPASTE-50G', 3, 0, 3, 'Import data client GudangKu inventory', 'source_id=288; type=MASUK; product_name=Atomy Toothpaste 50g; performed_by=Admin', '2026-05-02 10:56:00+07'),
  ('5846b49d-0e0d-3696-8980-907973838a58', 'in', 'GK-KARDUS-000235', 'ATOMY-HERBAL-HAIR-TONIC', 2, 2, 4, 'Import data client GudangKu inventory', 'source_id=289; type=MASUK; product_name=Atomy Herbal Hair Tonic; performed_by=Admin', '2026-05-02 10:57:00+07'),
  ('d1c5f7d1-1286-3eca-b9d8-1765e27b2fa6', 'in', 'GK-KARDUS-000235', 'ATOMY-ABSOLUTE-TONER', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=290; type=MASUK; product_name=Atomy Absolute Toner; performed_by=Admin', '2026-05-02 10:57:00+07'),
  ('0d31f1ae-23bf-3201-b7c3-3d627db56048', 'in', 'GK-KARDUS-000369', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=291; type=MASUK; product_name=Atomy Herbal Hair Shampoo; performed_by=Admin', '2026-05-02 10:58:00+07'),
  ('b7f6ccfb-4c48-3935-b9be-2dc41939ecf0', 'in', 'GK-KARDUS-000375', 'ATOMY-HERBAL-HAIR-TONIC', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=292; type=MASUK; product_name=Atomy Herbal Hair Tonic; performed_by=Admin', '2026-05-02 10:58:00+07'),
  ('397c41cc-b30b-3014-b375-ed7f0e44b1ff', 'in', 'GK-KARDUS-000235', 'ATOMY-HERBAL-HAIR-SHAMPOO', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=293; type=MASUK; product_name=Atomy Herbal Hair Shampoo; performed_by=Admin', '2026-05-02 10:58:00+07'),
  ('1e33b69e-520e-3a8a-b948-1dd49a8244b1', 'in', 'GK-KARDUS-000369', 'ATOMY-BODY-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=294; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-05-02 10:58:00+07'),
  ('877a7929-57a9-3e3c-8e5a-1119909bf035', 'in', 'GK-KARDUS-000375', 'ATOMY-CAFE-ARABICA', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=295; type=MASUK; product_name=Atomy Cafe Arabica; performed_by=Admin', '2026-05-02 10:58:00+07'),
  ('b4e1b29e-28a8-3a88-952d-a84d9c230ad2', 'in', 'GK-KARDUS-000375', 'ATOMY-BODY-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=296; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-05-02 10:59:00+07'),
  ('eb05a194-375c-3033-b671-b33c6bf603a0', 'in', 'GK-KARDUS-000369', 'ATOMY-HERBAL-HAIR-CONDITIONER', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=297; type=MASUK; product_name=Atomy Herbal Hair Conditioner; performed_by=Admin', '2026-05-02 10:59:00+07'),
  ('65df67fb-66b3-3d45-9a19-1f425b76a66b', 'in', 'GK-KARDUS-000375', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=298; type=MASUK; product_name=Atomy Herbal Hair Conditioner; performed_by=Admin', '2026-05-02 10:59:00+07'),
  ('47e47b4c-fc2c-3ef5-9612-bb6fb6e5962a', 'in', 'GK-KARDUS-000375', 'ATOMY-ABSOLUTE-AMPOULE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=299; type=MASUK; product_name=Atomy Absolute Ampoule; performed_by=Admin', '2026-05-02 10:59:00+07'),
  ('c77d8f0f-1847-3572-b3ba-ebdb5c5afdc2', 'in', 'GK-KARDUS-000375', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=300; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-05-02 10:59:00+07'),
  ('eaa50975-379b-3a7c-ac1d-ef2f928894eb', 'in', 'GK-KARDUS-000369', 'ATOMY-ABSOLUTE-LOTION', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=301; type=MASUK; product_name=Atomy Absolute Lotion; performed_by=Admin', '2026-05-02 10:59:00+07'),
  ('ddcc1344-c92d-3a43-a17c-62d8330819d6', 'in', 'GK-KARDUS-000375', 'ATOMY-EVENING-CARE-4-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=302; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-05-02 10:59:00+07'),
  ('2389cf74-3576-304a-a92e-f2ac3cff6aea', 'in', 'GK-KARDUS-000375', 'ATOMY-BODY-LOTION', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=303; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-05-02 11:00:00+07'),
  ('5705e662-aed2-34bb-bc88-6b7c0c9a478b', 'in', 'GK-KARDUS-000369', 'ATOMY-ABSOLUTE-AMPOULE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=304; type=MASUK; product_name=Atomy Absolute Ampoule; performed_by=Admin', '2026-05-02 11:00:00+07'),
  ('ef50c427-598f-39f1-b8d4-55c759f538f5', 'in', 'GK-KARDUS-000375', 'ATOMY-HERBAL-HAIR-TONIC', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=305; type=MASUK; product_name=Atomy Herbal Hair Tonic; performed_by=Admin', '2026-05-02 11:00:00+07'),
  ('282ca59c-b7d3-3c3f-a56c-c5c70b9d36d5', 'in', 'GK-KARDUS-000369', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=306; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-05-02 11:00:00+07'),
  ('4da00762-2e7e-3ee8-8b89-2a92f8207e21', 'in', 'GK-KARDUS-000369', 'ATOMY-SUNSCREEN-WHITE', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=307; type=MASUK; product_name=Atomy Sunscreen White; performed_by=Admin', '2026-05-02 11:01:00+07'),
  ('4d70f360-9248-3690-9cf0-8bc6dd247d63', 'in', 'GK-KARDUS-000369', 'ATOMY-EVENING-CARE-4-SET', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=308; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-05-02 11:02:00+07'),
  ('4a0b108b-6b22-3b66-ac6d-65b529709c33', 'in', 'GK-KARDUS-000376', 'ATOMY-BODY-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=309; type=MASUK; product_name=Atomy Body Cleanser; performed_by=Admin', '2026-05-02 11:03:00+07'),
  ('23fd7087-4d55-329c-994e-007fb0756d2e', 'in', 'GK-KARDUS-000376', 'ATOMY-HERBAL-HAIR-CONDITIONER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=310; type=MASUK; product_name=Atomy Herbal Hair Conditioner; performed_by=Admin', '2026-05-02 11:03:00+07'),
  ('98de2f4e-2cd0-3756-9517-78321b60847d', 'in', 'GK-KARDUS-000376', 'ATOMY-FOAM-CLEANSER-150ML', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=311; type=MASUK; product_name=Atomy Foam Cleanser 150ml; performed_by=Admin', '2026-05-02 11:03:00+07'),
  ('0bf16ee7-a4cf-3048-87a3-da351b51976d', 'in', 'GK-KARDUS-000235', 'ATOMY-EVENING-CARE-4-SET', 1, 3, 4, 'Import data client GudangKu inventory', 'source_id=312; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-05-02 11:03:00+07'),
  ('7982bd76-b681-3869-848e-08f00140cdc4', 'in', 'GK-KARDUS-000376', 'ATOMY-BODY-LOTION', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=313; type=MASUK; product_name=Atomy Body Lotion; performed_by=Admin', '2026-05-02 11:03:00+07'),
  ('83a7aea4-5d66-31d5-9e35-7d9868ee1719', 'in', 'GK-KARDUS-000376', 'ATOMY-HERBAL-HAIR-TONIC', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=314; type=MASUK; product_name=Atomy Herbal Hair Tonic; performed_by=Admin', '2026-05-02 11:04:00+07'),
  ('f59b057a-6dd2-3789-8244-d9c70e049823', 'in', 'GK-KARDUS-000376', 'ATOMY-TOOTHPASTE-50G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=315; type=MASUK; product_name=Atomy Toothpaste 50g; performed_by=Admin', '2026-05-02 11:04:00+07'),
  ('51fd1556-9e7f-3d23-a739-ff1089f1dc71', 'in', 'GK-KARDUS-000378', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=316; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-04 07:08:00+07'),
  ('090e7635-2905-3871-9178-9a5ceac780b8', 'in', 'GK-KARDUS-000382', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=317; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Oktavia', '2026-05-04 07:23:00+07'),
  ('60a6f0f4-904a-32f6-947f-11ce255469ef', 'in', 'GK-KARDUS-000384', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=318; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Oktavia', '2026-05-04 07:26:00+07'),
  ('894d5ad8-9367-3010-a509-5d3c9e6fd1f8', 'in', 'GK-KARDUS-000387', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=319; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Oktavia', '2026-05-04 07:31:00+07'),
  ('76e47d29-0071-344d-bcfd-14757d32b3d4', 'in', 'GK-KARDUS-000389', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=320; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-04 07:35:00+07'),
  ('011dc9b9-92cd-34cc-8de9-fdc04651a9d3', 'in', 'GK-KARDUS-000392', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=321; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Oktavia', '2026-05-04 07:36:00+07'),
  ('f5b2f4d5-c892-3bfd-adff-770cea31203c', 'in', 'GK-KARDUS-000393', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=322; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Oktavia', '2026-05-04 07:38:00+07'),
  ('02f7df47-c2b0-30ea-83d2-31c2ae9fc75b', 'in', 'GK-KARDUS-000394', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=323; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 07:39:00+07'),
  ('6222aaad-301b-3dfe-9e46-6236653e2dd3', 'in', 'GK-KARDUS-000395', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=324; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 07:39:00+07'),
  ('21e0ef30-e90e-302c-b1e4-4d4755abc66a', 'in', 'GK-KARDUS-000396', 'ATOMY-PROMO-RAMADHAN-2', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=325; type=MASUK; product_name=Atomy Promo Ramadhan 2; performed_by=Oktavia', '2026-05-04 07:44:00+07'),
  ('dd213e81-f1a1-3b68-b41f-52d43c9dd49e', 'in', 'GK-KARDUS-000396', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=326; type=MASUK; product_name=Atomy Propolis Toothpaste 50g; performed_by=Oktavia', '2026-05-04 07:44:00+07'),
  ('e64701ac-38b5-3614-b63c-297af71a8b2f', 'in', 'GK-KARDUS-000397', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=327; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 07:45:00+07'),
  ('fd2b0fc1-5199-3fde-8145-212c8a7645c3', 'in', 'GK-KARDUS-000398', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=328; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Oktavia', '2026-05-04 07:46:00+07'),
  ('adca6a31-b848-3509-87c7-8ba7e46decd7', 'in', 'GK-KARDUS-000399', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=329; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 07:48:00+07'),
  ('caa20fd9-903a-3f82-93b4-ea135b7b4456', 'in', 'GK-KARDUS-000400', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=330; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 07:53:00+07'),
  ('18b3e1cf-e0e5-3f89-8223-5a88c078d3dc', 'in', 'GK-KARDUS-000401', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=331; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Oktavia', '2026-05-04 07:54:00+07'),
  ('c40a60bb-d072-331a-9fc2-361faeea8843', 'in', 'GK-KARDUS-000402', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=332; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 07:55:00+07'),
  ('c0b8b5a4-91d9-3e55-9de0-df0eb25aa587', 'in', 'GK-KARDUS-000403', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=333; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Oktavia', '2026-05-04 07:58:00+07'),
  ('d7999b3e-59da-3eb6-8218-b3adc2796d68', 'in', 'GK-KARDUS-000404', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=334; type=MASUK; product_name=Atomy Absolute CellActive Ampoule; performed_by=Admin', '2026-05-04 08:01:00+07'),
  ('8b095515-7556-3fc4-8e29-aee406e75373', 'in', 'GK-KARDUS-000404', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=335; type=MASUK; product_name=Atomy Absolute CellActive Skincare Set; performed_by=Admin', '2026-05-04 08:01:00+07'),
  ('84f51d82-587a-32dd-9b91-e8fb48547563', 'in', 'GK-KARDUS-000406', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=336; type=MASUK; product_name=Atomy Paket Lebaran A (Health Care); performed_by=Admin', '2026-05-04 08:06:00+07'),
  ('0434f86c-d41c-3507-a470-abdfb7c81a86', 'in', 'GK-KARDUS-000409', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=337; type=MASUK; product_name=Atomy Absolute CellActive Skincare Set; performed_by=Admin', '2026-05-04 08:08:00+07'),
  ('3b5ba190-8789-3dcb-a798-0a83cb6c1d5b', 'in', 'GK-KARDUS-000409', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=338; type=MASUK; product_name=Atomy Absolute CellActive Ampoule; performed_by=Admin', '2026-05-04 08:08:00+07'),
  ('a570a86a-c460-37d1-a188-93e8c458d758', 'in', 'GK-KARDUS-000410', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=339; type=MASUK; product_name=Atomy Hydra Brightening Care Set; performed_by=Admin', '2026-05-04 08:10:00+07'),
  ('5ea949f9-ba52-3e95-b036-a10eff5f21e2', 'in', 'GK-KARDUS-000411', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=340; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Oktavia', '2026-05-04 08:11:00+07'),
  ('e774e415-0caa-3f18-ba29-1ad97f28b15f', 'in', 'GK-KARDUS-000412', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=341; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 08:12:00+07'),
  ('07263591-1e19-31cf-953b-9bcec5159c97', 'in', 'GK-KARDUS-000413', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=342; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 08:12:00+07'),
  ('f2e28531-81f7-344b-997a-a3fc06e338ba', 'in', 'GK-KARDUS-000414', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=343; type=MASUK; product_name=Atomy Hydra Brightening Care Set; performed_by=Admin', '2026-05-04 08:15:00+07'),
  ('5f7e7d78-3f12-37e0-9910-2ad96e27c3a3', 'in', 'GK-KARDUS-000415', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=344; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Oktavia', '2026-05-04 08:15:00+07'),
  ('bffb799e-79af-391e-abef-9c9eb6b48c2a', 'in', 'GK-KARDUS-000416', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=345; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:16:00+07'),
  ('fa721011-d9b8-306d-8c00-d790642e3f1c', 'in', 'GK-KARDUS-000418', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=346; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:20:00+07'),
  ('c81b08ec-04d2-3652-8310-b5dbac2af8ea', 'in', 'GK-KARDUS-000420', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=347; type=MASUK; product_name=Atomy Paket Lebaran A (Health Care); performed_by=Oktavia', '2026-05-04 08:20:00+07'),
  ('a3fe7dc4-277d-3c3c-ae67-102dbcab12fd', 'in', 'GK-KARDUS-000422', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=348; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:22:00+07'),
  ('f785a7d6-99dd-335d-bfb2-1b5866390014', 'in', 'GK-KARDUS-000421', 'ATOMY-HONGSAMDAN-RED-GINSENG', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=349; type=MASUK; product_name=Atomy Hongsamdan Red Ginseng; performed_by=Admin', '2026-05-04 08:23:00+07'),
  ('ceb17196-2780-305c-b635-634cae579227', 'in', 'GK-KARDUS-000421', 'ATOMY-SUNSCREEN-WHITE', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=350; type=MASUK; product_name=Atomy Sunscreen White; performed_by=Admin', '2026-05-04 08:23:00+07'),
  ('96359f2d-3faf-34d5-8325-010ef19f2ac1', 'in', 'GK-KARDUS-000421', 'ATOMY-PROPOLIS-TOOTHPASTE-200G', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=351; type=MASUK; product_name=Atomy Propolis Toothpaste 200g; performed_by=Admin', '2026-05-04 08:23:00+07'),
  ('377c3672-851c-3d63-bcd7-e11bd1a8bf68', 'in', 'GK-KARDUS-000421', 'ATOMY-FINEZYME', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=352; type=MASUK; product_name=Atomy Finezyme; performed_by=Admin', '2026-05-04 08:23:00+07'),
  ('cd862ecd-403c-39da-8161-3e73b97cc503', 'in', 'GK-KARDUS-000421', 'ATOMY-SUNSCREEN-BEIGE', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=353; type=MASUK; product_name=Atomy Sunscreen Beige; performed_by=Admin', '2026-05-04 08:23:00+07'),
  ('2a18849f-393e-3023-a513-7206d25533a5', 'in', 'GK-KARDUS-000421', 'ATOMY-TOOTHBRUSH', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=354; type=MASUK; product_name=Atomy Toothbrush; performed_by=Admin', '2026-05-04 08:23:00+07'),
  ('8290ab45-78b0-33cf-bb25-46566a0a6c5e', 'in', 'GK-KARDUS-000421', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=355; type=MASUK; product_name=Atomy Color Food Vitamin C; performed_by=Admin', '2026-05-04 08:23:00+07'),
  ('2f828ae8-fee8-3f5c-8bf5-70eb5508b78c', 'in', 'GK-KARDUS-000423', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=356; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:24:00+07'),
  ('ee2db475-331c-30e9-a9df-c368b0df2445', 'in', 'GK-KARDUS-000424', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=357; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Oktavia', '2026-05-04 08:25:00+07'),
  ('70be2a32-f5b2-346c-8ab7-24bcbb558e39', 'in', 'GK-KARDUS-000426', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=358; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:28:00+07'),
  ('e8ebe96b-d053-38ed-9449-496be4b345b2', 'in', 'GK-KARDUS-000428', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=359; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Oktavia', '2026-05-04 08:28:00+07'),
  ('7aff1c18-7c9a-3ef7-9bbf-61e79c4da84a', 'in', 'GK-KARDUS-000429', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=360; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:30:00+07'),
  ('45ae2382-977b-39d8-8159-5ab7eb809e3d', 'in', 'GK-KARDUS-000430', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=361; type=MASUK; product_name=Atomy Paket Lebaran A (Health Care); performed_by=Oktavia', '2026-05-04 08:30:00+07'),
  ('b428710f-8862-327b-b4c0-c8eb24dc2a35', 'in', 'GK-KARDUS-000431', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=362; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:31:00+07'),
  ('de9d02f0-5514-3260-8871-1693568ba0f0', 'in', 'GK-KARDUS-000432', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=363; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:32:00+07'),
  ('844f75b4-3e5c-3421-bff7-5daea3f9994d', 'in', 'GK-KARDUS-000434', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=364; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:34:00+07'),
  ('72c59486-0846-35a8-9546-51913f5a7980', 'in', 'GK-KARDUS-000435', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=365; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Oktavia', '2026-05-04 08:35:00+07'),
  ('e83bc869-dcb4-3893-adb8-abb56152cf67', 'in', 'GK-KARDUS-000433', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=366; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-04 08:35:00+07'),
  ('5d6c7cd8-305b-3212-9ff1-12a592929285', 'in', 'GK-KARDUS-000436', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=367; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Oktavia', '2026-05-04 08:37:00+07'),
  ('d9ae0ab4-ae43-3267-93db-ef2b6ec4c273', 'in', 'GK-KARDUS-000437', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=368; type=MASUK; product_name=Atomy Paket Lebaran A (Health Care); performed_by=Oktavia', '2026-05-04 08:40:00+07'),
  ('b23c5ba4-ac0b-3c15-961b-cf981af52b33', 'in', 'GK-KARDUS-000441', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=369; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:44:00+07'),
  ('b0c21803-78aa-3aae-a348-c211bd1f6381', 'in', 'GK-KARDUS-000442', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=370; type=MASUK; product_name=Atomy Paket Lebaran A (Health Care); performed_by=Admin', '2026-05-04 08:45:00+07'),
  ('8891e1ae-ee52-3998-8877-3e1e286b9e10', 'in', 'GK-KARDUS-000447', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=371; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:49:00+07'),
  ('de8e7110-f80b-3047-af2d-f12ad378be1a', 'in', 'GK-KARDUS-000447', 'ATOMY-PROMO-RAMADHAN-1', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=372; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:49:00+07'),
  ('1ff61b73-9fcd-34d0-a201-fe8ca6b3a7f6', 'in', 'GK-KARDUS-000449', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=373; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-04 08:52:00+07'),
  ('6f49df39-7c29-33d2-9558-ac9e6e8b6cc3', 'in', 'GK-KARDUS-000450', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=374; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-04 08:53:00+07'),
  ('e9e03bb4-9bf1-3084-9eba-9934487d092e', 'in', 'GK-KARDUS-000447', 'ATOMY-PROMO-RAMADHAN-1', 1, 2, 3, 'Import data client GudangKu inventory', 'source_id=375; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:53:00+07'),
  ('b6132e68-7bd3-3e87-8b3e-79f8a51a8f7d', 'in', 'GK-KARDUS-000451', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=376; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:55:00+07'),
  ('ede81f94-7bd5-35cb-abe6-50591dab4fd7', 'in', 'GK-KARDUS-000452', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=377; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:57:00+07'),
  ('dcb55905-1e56-38a9-966c-c4b1ce0ae62f', 'in', 'GK-KARDUS-000454', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=378; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 08:59:00+07'),
  ('b4edaa30-9d3b-36f3-9fe1-9a9f8638e421', 'in', 'GK-KARDUS-000456', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=379; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:01:00+07'),
  ('d4a84d86-b132-3b0c-b573-1f54a415527c', 'in', 'GK-KARDUS-000458', 'ATOMY-HEMOHIM', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=380; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:05:00+07'),
  ('fd4ba7fe-7334-384f-806a-b6da9e8a1db1', 'in', 'GK-KARDUS-000460', 'ATOMY-PROMO-RAMADHAN-1', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=381; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:07:00+07'),
  ('49612933-094a-3022-82aa-d06c6826f24a', 'in', 'GK-KARDUS-000462', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=382; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:09:00+07'),
  ('501a5cee-5508-3614-95ca-7b32516c5976', 'in', 'GK-KARDUS-000463', 'ATOMY-PROMO-RAMADHAN-1', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=383; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:09:00+07'),
  ('e97a2d8a-8616-3cfd-a36f-26d10acc90cf', 'in', 'GK-KARDUS-000461', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=384; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:10:00+07'),
  ('4e0fbb77-5a48-39a9-8d81-780aef50dffb', 'in', 'GK-KARDUS-000464', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=385; type=MASUK; product_name=Atomy Paket Lebaran A (Health Care); performed_by=Admin', '2026-05-04 09:11:00+07'),
  ('993871a2-6a20-3576-92ca-a16218ba1bc9', 'in', 'GK-KARDUS-000466', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=386; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-04 09:13:00+07'),
  ('21320ab8-7ddf-36b2-b603-e51c699f57ce', 'in', 'GK-KARDUS-000467', 'ATOMY-PROMO-RAMADHAN-1', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=387; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:13:00+07'),
  ('932f8338-d272-3ae9-aa8d-915bece8436e', 'in', 'GK-KARDUS-000469', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=388; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Oktavia', '2026-05-04 09:15:00+07'),
  ('b0d643f0-377e-3f50-99df-d3e13e000837', 'in', 'GK-KARDUS-000469', 'ATOMY-HEMOHIM-4-SETS', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=389; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Oktavia', '2026-05-04 09:15:00+07'),
  ('fa54ae9b-12f8-309d-ad78-6b95629b52ee', 'in', 'GK-KARDUS-000470', 'ATOMY-PROMO-RAMADHAN-1', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=390; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:15:00+07'),
  ('906c9c85-4a6a-333e-8cdb-23ad7bf1193c', 'in', 'GK-KARDUS-000471', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=391; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Oktavia', '2026-05-04 09:17:00+07'),
  ('512e8fa9-7c1c-34f0-94b0-0d8abbb5e1d4', 'in', 'GK-KARDUS-000472', 'ATOMY-PROMO-RAMADHAN-1', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=392; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:17:00+07'),
  ('8ade5cd8-b979-3257-b4d8-72dc082b2062', 'in', 'GK-KARDUS-000475', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=393; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:21:00+07'),
  ('dd84389a-746a-38f9-bf3b-3da2415b9cae', 'in', 'GK-KARDUS-000477', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=394; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:22:00+07'),
  ('50ea8d0a-7e6f-3c3e-8b72-81287455693b', 'in', 'GK-KARDUS-000478', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=395; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:23:00+07'),
  ('fb462d29-fe73-3700-b518-393320b5c4f4', 'in', 'GK-KARDUS-000481', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=396; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:24:00+07'),
  ('5b118232-8f7f-3ba2-b2be-bc18b775d256', 'in', 'GK-KARDUS-000482', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=397; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:26:00+07'),
  ('557bb367-48f6-3834-8c72-f091d9889aee', 'in', 'GK-KARDUS-000483', 'ATOMY-PROMO-RAMADHAN-2', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=398; type=MASUK; product_name=Atomy Promo Ramadhan 2; performed_by=Admin', '2026-05-04 09:29:00+07'),
  ('a4e95b3d-54dd-343c-a249-876197761bf3', 'in', 'GK-KARDUS-000483', 'ATOMY-SUNSCREEN-WHITE', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=399; type=MASUK; product_name=Atomy Sunscreen White; performed_by=Admin', '2026-05-04 09:29:00+07'),
  ('f8c7d1cb-1f9a-3f75-98af-788f20e70cb8', 'in', 'GK-KARDUS-000483', 'ATOMY-SUNSCREEN-BEIGE', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=400; type=MASUK; product_name=Atomy Sunscreen Beige; performed_by=Admin', '2026-05-04 09:29:00+07'),
  ('80ea9b11-33fb-3130-ac0d-d8b62d95f02b', 'in', 'GK-KARDUS-000483', 'ATOMY-HEALTHY-GLOW-BASE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=401; type=MASUK; product_name=Atomy Healthy Glow Base; performed_by=Admin', '2026-05-04 09:29:00+07'),
  ('cf5316f4-f4ce-3ec6-952e-5b514b9ae13e', 'in', 'GK-KARDUS-000484', 'ATOMY-PROMO-RAMADHAN-2', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=402; type=MASUK; product_name=Atomy Promo Ramadhan 2; performed_by=Admin', '2026-05-04 09:31:00+07'),
  ('7125db03-8fe9-3c13-9c70-3b8407489301', 'in', 'GK-KARDUS-000484', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=403; type=MASUK; product_name=Atomy Propolis Toothpaste 50g; performed_by=Admin', '2026-05-04 09:31:00+07'),
  ('fb45e3fa-8515-38b1-a351-a95fcf8c302a', 'in', 'GK-KARDUS-000485', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=404; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:31:00+07'),
  ('cbd3261f-164c-3907-aee6-bd0224af1f33', 'in', 'GK-KARDUS-000487', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=405; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:33:00+07'),
  ('d6105885-ae4c-3735-82c6-88851e61867d', 'in', 'GK-KARDUS-000487', 'ATOMY-HEMOHIM', 4, 4, 8, 'Import data client GudangKu inventory', 'source_id=406; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:33:00+07'),
  ('41ccb05e-7ed2-3d5b-90e6-f27dcd7b8b0c', 'in', 'GK-KARDUS-000489', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=407; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:36:00+07'),
  ('bae76c56-8a2f-340f-a0f8-4df55d8c7327', 'in', 'GK-KARDUS-000486', 'ATOMY-PAKET-BERKAH-RAMADAN-C', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=408; type=MASUK; product_name=Atomy Paket Berkah Ramadan C; performed_by=Admin', '2026-05-04 09:36:00+07'),
  ('e194bc22-77dd-33ef-9d18-eced59d63e65', 'in', 'GK-KARDUS-000486', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=409; type=MASUK; product_name=Atomy Color Food Vitamin C; performed_by=Admin', '2026-05-04 09:36:00+07'),
  ('b5f3fd2b-4af1-36a2-aa6d-799b333de660', 'in', 'GK-KARDUS-000486', 'ATOMY-FINEZYME', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=410; type=MASUK; product_name=Atomy Finezyme; performed_by=Admin', '2026-05-04 09:36:00+07'),
  ('4de9cf54-919a-365c-a1fa-bb2134f25431', 'in', 'GK-KARDUS-000490', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=411; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:37:00+07'),
  ('5e674fed-b41f-38f8-8e63-eb43556a1584', 'in', 'GK-KARDUS-000492', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=412; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:38:00+07'),
  ('1306de65-b9ce-338e-b8a5-8c1ba35cc309', 'in', 'GK-KARDUS-000491', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=413; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:39:00+07'),
  ('1fe0ec60-75aa-3872-8d54-0c51858413e9', 'in', 'GK-KARDUS-000493', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=414; type=MASUK; product_name=Atomy Paket Lebaran A (Health Care); performed_by=Admin', '2026-05-04 09:40:00+07'),
  ('9f2b31d5-41c8-34cc-9f1f-39f4583de76b', 'in', 'GK-KARDUS-000494', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=415; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:41:00+07'),
  ('daf2c122-f3cd-3644-bccd-0012a5eade89', 'in', 'GK-KARDUS-000495', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=416; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:41:00+07'),
  ('220bc3f9-5556-3569-b177-a36ae6f47a0e', 'in', 'GK-KARDUS-000496', 'ATOMY-PROMO-RAMADHAN-2', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=417; type=MASUK; product_name=Atomy Promo Ramadhan 2; performed_by=Admin', '2026-05-04 09:44:00+07'),
  ('199712a7-f56d-3a6d-abf1-4ef93649ddb8', 'in', 'GK-KARDUS-000496', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=418; type=MASUK; product_name=Atomy Propolis Toothpaste 50g; performed_by=Admin', '2026-05-04 09:44:00+07'),
  ('af4fb5ce-ad5f-3e50-b88a-90c0d69c0e13', 'in', 'GK-KARDUS-000498', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=419; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:46:00+07'),
  ('9f6c8a00-3e64-38e9-b262-3c20a5fd0048', 'in', 'GK-KARDUS-000499', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=420; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:46:00+07'),
  ('63c4ce0d-6358-3b15-9367-db58bd796820', 'in', 'GK-KARDUS-000500', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=421; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:48:00+07'),
  ('936688b4-c0e4-3015-9d8a-813e00cbe9ed', 'in', 'GK-KARDUS-000501', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=422; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:48:00+07'),
  ('b9eb5a7e-588a-32a3-9c6d-7a08fe50e22e', 'in', 'GK-KARDUS-000504', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=423; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 09:53:00+07'),
  ('4b19cb37-7235-37dd-a23b-d1198ab73f22', 'in', 'GK-KARDUS-000503', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=424; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-04 09:54:00+07'),
  ('9848742e-efa3-329a-8220-226a4c27c855', 'in', 'GK-KARDUS-000505', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=425; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:55:00+07'),
  ('f6dd1c02-7950-39bb-a7e6-8f0ae879ab98', 'in', 'GK-KARDUS-000508', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=426; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:57:00+07'),
  ('9612e40a-5b49-3cb1-9bfe-29df1e1fdaf9', 'in', 'GK-KARDUS-000510', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=427; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 09:58:00+07'),
  ('5d392307-9737-3ba5-ab4e-75cc06145431', 'in', 'GK-KARDUS-000504', 'ATOMY-PAKET-BERKAH-RAMADAN-C', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=428; type=MASUK; product_name=Atomy Paket Berkah Ramadan C; performed_by=Admin', '2026-05-04 09:59:00+07'),
  ('25a3a7df-b6d1-3c9e-9119-a959640225dc', 'in', 'GK-KARDUS-000504', 'ATOMY-FINEZYME', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=429; type=MASUK; product_name=Atomy Finezyme; performed_by=Admin', '2026-05-04 09:59:00+07'),
  ('bd8a02ca-b571-3d13-a8a4-2c6caa46a717', 'in', 'GK-KARDUS-000504', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=430; type=MASUK; product_name=Atomy Color Food Vitamin C; performed_by=Admin', '2026-05-04 09:59:00+07'),
  ('ebd90c15-b7f2-3508-9f89-2516f58ab95d', 'in', 'GK-KARDUS-000511', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=431; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-04 10:00:00+07'),
  ('357451f2-3c3c-3b7f-9cd3-4e407dc25aa5', 'in', 'GK-KARDUS-000512', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=432; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-04 10:01:00+07'),
  ('9215a59a-8587-37ee-8792-2bd400e3276e', 'in', 'GK-KARDUS-000513', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=433; type=MASUK; product_name=Atomy Paket Lebaran A (Health Care); performed_by=Admin', '2026-05-04 10:12:00+07'),
  ('1f48f3bd-be32-3826-9521-bc9c8ea94190', 'in', 'GK-KARDUS-000514', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=434; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-04 10:13:00+07'),
  ('d6f0fcc0-b44a-30b9-acfb-ba4833ed44f1', 'in', 'GK-KARDUS-000515', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=435; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-04 10:16:00+07'),
  ('fe568d17-1a3f-3323-9278-0b2768652e7d', 'in', 'GK-KARDUS-000516', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=436; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 08:42:00+07'),
  ('177d9949-615a-3e00-886a-b0faa6f5ca85', 'in', 'GK-KARDUS-000517', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=437; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 08:44:00+07'),
  ('53552ad8-180e-3295-ab40-c25c7aa484e1', 'in', 'GK-KARDUS-000518', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=438; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 08:46:00+07'),
  ('f1e001cb-9c83-341e-8f6c-ca8915a123b3', 'in', 'GK-KARDUS-000519', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=439; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 08:50:00+07'),
  ('ce23b35b-80cc-3079-8708-f434fc30176a', 'in', 'GK-KARDUS-000520', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=440; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-05 08:51:00+07'),
  ('c2a76414-fb47-3c73-bfcd-4fdbe218f331', 'in', 'GK-KARDUS-000521', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=441; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 08:51:00+07'),
  ('c813f3c1-cb30-32fa-9b0c-a46c3ff248b6', 'in', 'GK-KARDUS-000523', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=442; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-05 09:00:00+07'),
  ('1cc04d88-45b5-3edd-9573-e5ad45450c4a', 'in', 'GK-KARDUS-000524', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=443; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:00:00+07'),
  ('08c8ef19-989a-32f2-9f7d-603aae9221fd', 'in', 'GK-KARDUS-000525', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=444; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:03:00+07'),
  ('c6c438e4-24ee-3ce9-bff4-3e8bbba3cdd1', 'in', 'GK-KARDUS-000531', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=445; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:11:00+07'),
  ('2d8da4b6-b9bb-3e08-b95a-78ca2c558126', 'in', 'GK-KARDUS-000530', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=446; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-05 09:14:00+07'),
  ('d89b78ad-e172-373f-a876-01512500b280', 'in', 'GK-KARDUS-000532', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=447; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-05 09:15:00+07'),
  ('96ea7853-d466-32ce-8ce9-0a9d6341d388', 'in', 'GK-KARDUS-000533', 'ATOMY-HONGSAMDAN-RED-GINSENG', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=448; type=MASUK; product_name=Atomy Hongsamdan Red Ginseng; performed_by=Admin', '2026-05-05 09:19:00+07'),
  ('0a0973b2-03b9-343f-b5b8-3fa826556ceb', 'in', 'GK-KARDUS-000533', 'ATOMY-HEMOHIM', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=449; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:19:00+07'),
  ('e217a541-2b4d-3abe-88a3-e1fb2dec3a5b', 'in', 'GK-KARDUS-000533', 'ATOMY-EVENING-CARE-4-SET', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=450; type=MASUK; product_name=Atomy Evening Care 4 Set; performed_by=Admin', '2026-05-05 09:19:00+07'),
  ('7b667a9b-0490-303c-8fce-c46e22ddaf29', 'in', 'GK-KARDUS-000533', 'ATOMY-FINEZYME', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=451; type=MASUK; product_name=Atomy Finezyme; performed_by=Admin', '2026-05-05 09:19:00+07'),
  ('8a96643b-3999-3144-b54b-d99caca2e6e6', 'in', 'GK-KARDUS-000533', 'ATOMY-EVENING-CARE-FOAM-CLEANSER', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=452; type=MASUK; product_name=Atomy Evening Care Foam Cleanser; performed_by=Admin', '2026-05-05 09:19:00+07'),
  ('2d2f071e-6fb3-3b84-99d2-392871cca8f4', 'in', 'GK-KARDUS-000534', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=453; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-05 09:23:00+07'),
  ('bc6b1ac2-f220-311f-bff8-5f6ba56b1d9f', 'in', 'GK-KARDUS-000535', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=454; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-05 09:28:00+07'),
  ('fc373ebb-a3d1-38cb-beb2-af182735c988', 'in', 'GK-KARDUS-000536', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=455; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:29:00+07'),
  ('84787713-cd79-31f3-b0df-7df338a4d6c1', 'in', 'GK-KARDUS-000537', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=456; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:30:00+07'),
  ('b076c6ae-4ca2-346a-80e7-c4d8ee7ddfd1', 'in', 'GK-KARDUS-000540', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=457; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:32:00+07'),
  ('8bc8a80e-79b1-3801-949c-8f850f49cf7d', 'in', 'GK-KARDUS-000541', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=458; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:33:00+07'),
  ('699375ee-cf66-39c1-9231-b26864433f04', 'in', 'GK-KARDUS-000538', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=459; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-05 09:33:00+07'),
  ('ec7fc29d-ed6b-3a40-a7ea-802a80c297f5', 'in', 'GK-KARDUS-000542', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=460; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:35:00+07'),
  ('72be9257-eeb6-3dc7-82f9-12c976e8d60f', 'in', 'GK-KARDUS-000543', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=461; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:37:00+07'),
  ('b2321010-26c3-39ec-b78d-9469eb1a0cd9', 'in', 'GK-KARDUS-000544', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=462; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-05 09:38:00+07'),
  ('f6d8a4c9-1c82-3d48-9c35-d923fcd3da87', 'in', 'GK-KARDUS-000546', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=463; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:40:00+07'),
  ('e7351d2e-9381-3cb9-8134-9811232931f3', 'in', 'GK-KARDUS-000546', 'ATOMY-HEMOHIM', 4, 4, 8, 'Import data client GudangKu inventory', 'source_id=464; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:40:00+07'),
  ('438e8743-a310-3d3b-ada8-83523846ae38', 'in', 'GK-KARDUS-000547', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=465; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-05 09:40:00+07'),
  ('d31e33e1-19ab-3192-a979-8042edec3c44', 'in', 'GK-KARDUS-000548', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=466; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:42:00+07'),
  ('5bb2e52b-bb87-3be1-b6a4-9356c2e8b768', 'in', 'GK-KARDUS-000551', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=467; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:47:00+07'),
  ('19d8f0ec-3721-3fd8-92a5-9fbd2a7d9992', 'in', 'GK-KARDUS-000552', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=468; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-05 09:49:00+07'),
  ('49ec4cd8-3db2-3180-b527-0211682141c7', 'in', 'GK-KARDUS-000553', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=469; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:50:00+07'),
  ('aaa4598d-b111-38ec-a8c9-d63aa798abe9', 'in', 'GK-KARDUS-000554', 'ATOMY-HEMOHIM', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=470; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-05 09:52:00+07'),
  ('c66d0773-9519-312d-8c09-cf6e7395a1cf', 'in', 'GK-KARDUS-000556', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=471; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-05 09:55:00+07'),
  ('5c8f0aca-9569-3bd3-aca2-62e1c7a77cd2', 'in', 'GK-KARDUS-000557', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=472; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-05 09:56:00+07'),
  ('4d775435-9271-3c02-b5f5-018680285a0d', 'in', 'GK-KARDUS-000566', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=473; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-20 09:06:00+07'),
  ('206ea700-334f-3724-8715-9587ea82b8e7', 'in', 'GK-KARDUS-000567', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=474; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-20 09:07:00+07'),
  ('f6b75ecd-a67d-3f4f-a63e-8dd0589b2052', 'in', 'GK-KARDUS-000568', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=475; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-20 09:08:00+07'),
  ('f1335950-012b-3529-8e59-e89eb9280500', 'in', 'GK-KARDUS-000569', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=476; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-20 09:09:00+07'),
  ('d96ebdb3-27e1-3acf-865b-de3ece51e9fd', 'in', 'GK-KARDUS-000570', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=477; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-20 09:11:00+07'),
  ('3793914c-d120-356c-b641-2c877f413ee4', 'in', 'GK-KARDUS-000572', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=478; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-20 09:12:00+07'),
  ('9c36e9b9-d09d-3304-af6c-56b141cb040b', 'in', 'GK-KARDUS-000573', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=479; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-20 09:14:00+07'),
  ('ecf5fb50-04e9-3031-a7c3-1878aa0072a9', 'in', 'GK-KARDUS-000577', 'ATOMY-PSYLLIUM-HUSK', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=480; type=MASUK; product_name=Atomy Psyllium Husk; performed_by=Admin', '2026-05-20 09:19:00+07'),
  ('19a8a7b0-ee2c-309c-914c-cd4093e826d3', 'in', 'GK-KARDUS-000578', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=481; type=MASUK; product_name=Atomy Propolis Toothpaste 50g; performed_by=Admin', '2026-05-20 09:23:00+07'),
  ('c473909b-18c9-305b-a6cd-245fa3fe26b8', 'in', 'GK-KARDUS-000578', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=482; type=MASUK; product_name=Atomy Propolis Toothpaste 50g; performed_by=Admin', '2026-05-20 09:23:00+07'),
  ('febd8c8a-606a-3f5e-9f99-f0a31e857397', 'in', 'GK-KARDUS-000580', 'ATOMY-PSYLLIUM-HUSK', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=483; type=MASUK; product_name=Atomy Psyllium Husk; performed_by=Admin', '2026-05-20 09:24:00+07'),
  ('9192f962-d240-3416-916c-eb657b579d53', 'in', 'GK-KARDUS-000581', 'ATOMY-HYDRA-BRIGHTENING-CARE-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=484; type=MASUK; product_name=Atomy Hydra Brightening Care Set; performed_by=Admin', '2026-05-20 09:26:00+07'),
  ('27689af0-1cbf-30b6-aeb8-971c437b4a87', 'in', 'GK-KARDUS-000582', 'ATOMY-PSYLLIUM-HUSK', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=485; type=MASUK; product_name=Atomy Psyllium Husk; performed_by=Admin', '2026-05-20 09:26:00+07'),
  ('4eaeb2f0-03d9-3e5c-8311-88b06cd5c587', 'in', 'GK-KARDUS-000582', 'ATOMY-TOOTHBRUSH', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=486; type=MASUK; product_name=Atomy Toothbrush; performed_by=Admin', '2026-05-20 09:26:00+07'),
  ('d33246a0-3c5a-3a1c-8b63-e4c7a012f3c0', 'in', 'GK-KARDUS-000583', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=487; type=MASUK; product_name=Atomy Absolute CellActive Ampoule; performed_by=Admin', '2026-05-20 09:27:00+07'),
  ('842da4ec-922c-3069-ada2-6a331f705d01', 'in', 'GK-KARDUS-000584', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=488; type=MASUK; product_name=Atomy Absolute CellActive Skincare Set; performed_by=Admin', '2026-05-20 09:28:00+07'),
  ('a5412118-8ba1-3d9a-9238-ca372669723e', 'in', 'GK-KARDUS-000585', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=489; type=MASUK; product_name=Atomy Absolute CellActive Skincare Set; performed_by=Admin', '2026-05-20 09:31:00+07'),
  ('11e63e20-d4d0-3cbd-a89f-0ceecd55c6b0', 'in', 'GK-KARDUS-000585', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=490; type=MASUK; product_name=Atomy Propolis Toothpaste 50g; performed_by=Admin', '2026-05-20 09:31:00+07'),
  ('40f7a1c8-2767-3267-8d12-821e526b44e5', 'in', 'GK-KARDUS-000585', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=491; type=MASUK; product_name=Atomy Propolis Toothpaste 50g; performed_by=Admin', '2026-05-20 09:32:00+07'),
  ('edbf4918-fbef-3fba-9aa0-0f46d8f6841a', 'in', 'GK-KARDUS-000585', 'ATOMY-PU-ER-TEA', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=492; type=MASUK; product_name=Atomy Pu''er Tea; performed_by=Admin', '2026-05-20 09:32:00+07'),
  ('d2811a09-4fc3-3604-a616-c2736d0063be', 'in', 'GK-KARDUS-000586', 'ATOMY-PU-ER-TEA', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=493; type=MASUK; product_name=Atomy Pu''er Tea; performed_by=Admin', '2026-05-20 09:33:00+07'),
  ('bbebf72f-5367-3e81-ad5c-6e538bf24257', 'in', 'GK-KARDUS-000589', 'ATOMY-HEMOHIM', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=494; type=MASUK; product_name=Atomy HemoHim; performed_by=Admin', '2026-05-20 09:36:00+07'),
  ('1d3c09bb-a511-3ab2-b030-c86657e35be5', 'in', 'GK-KARDUS-000587', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=495; type=MASUK; product_name=Atomy Propolis Toothpaste 50g; performed_by=Admin', '2026-05-20 09:36:00+07'),
  ('515bfad6-7668-36fc-9de7-d63791ebb714', 'in', 'GK-KARDUS-000588', 'ATOMY-PSYLLIUM-HUSK', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=496; type=MASUK; product_name=Atomy Psyllium Husk; performed_by=Admin', '2026-05-20 09:37:00+07'),
  ('77724d67-47cc-3557-b3cd-41807203feac', 'in', 'GK-KARDUS-000588', 'ATOMY-PSYLLIUM-HUSK', 2, 2, 4, 'Import data client GudangKu inventory', 'source_id=496; type=MASUK; product_name=Atomy Psyllium Husk; performed_by=Admin', '2026-05-20 09:37:00+07'),
  ('739ff937-76e1-3470-a638-03671267e8e9', 'in', 'GK-KARDUS-000588', 'ATOMY-PSYLLIUM-HUSK', 2, 4, 6, 'Import data client GudangKu inventory', 'source_id=497; type=MASUK; product_name=Atomy Psyllium Husk; performed_by=Admin', '2026-05-20 09:37:00+07'),
  ('976728f3-686f-323b-8359-36ea63095be6', 'in', 'GK-KARDUS-000591', 'ATOMY-ETHEREAL-OIL-PATCH', 5, 0, 5, 'Import data client GudangKu inventory', 'source_id=498; type=MASUK; product_name=Atomy Ethereal Oil Patch; performed_by=Admin', '2026-05-20 09:39:00+07'),
  ('1555c71b-3072-3f36-8129-45651ae0674b', 'in', 'GK-KARDUS-000592', 'ATOMY-HEMOHIM-4-SETS', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=499; type=MASUK; product_name=Atomy HemoHim 4 Sets; performed_by=Admin', '2026-05-20 09:39:00+07'),
  ('e66beb4d-1444-3ee1-82dd-783d65b23821', 'in', 'GK-KARDUS-000592', 'ATOMY-ETHEREAL-OIL-PATCH', 5, 0, 5, 'Import data client GudangKu inventory', 'source_id=500; type=MASUK; product_name=Atomy Ethereal Oil Patch; performed_by=Admin', '2026-05-20 09:45:00+07'),
  ('4f6fbb2c-00c1-33c3-9aeb-da4eebc02ca7', 'in', 'GK-KARDUS-000594', 'ATOMY-ETHEREAL-OIL-PATCH', 5, 0, 5, 'Import data client GudangKu inventory', 'source_id=501; type=MASUK; product_name=Atomy Ethereal Oil Patch; performed_by=Admin', '2026-05-20 09:48:00+07'),
  ('0a1d4f30-1950-364f-94ef-f1c60491efa2', 'in', 'GK-KARDUS-000594', 'ATOMY-ETHEREAL-OIL-PATCH', 5, 5, 10, 'Import data client GudangKu inventory', 'source_id=502; type=MASUK; product_name=Atomy Ethereal Oil Patch; performed_by=Admin', '2026-05-20 09:48:00+07'),
  ('8593b407-afe6-3623-9840-93751fdb8e31', 'in', 'GK-KARDUS-000595', 'ATOMY-HEMOHIM-SET-4', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=503; type=MASUK; product_name=Atomy HemoHim Set 4; performed_by=Admin', '2026-05-20 09:48:00+07'),
  ('c443e49e-8bd3-3914-aa2b-55a3f2ddc1db', 'out_partial_item', 'GK-KARDUS-000584', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 2, 1, 'Import penjualan client GudangKu inventory', 'source_id=504; type=PENJUALAN; product_name=Atomy Absolute CellActive Skincare Set; buyer=johnson; transfer_to=AMI ANTIKA SARI; performed_by=Admin', '2026-05-27 11:11:00+07'),
  ('00445b93-8a74-346c-8ebe-1846981a50e0', 'in', 'GK-KARDUS-000596', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=505; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-28 11:36:00+07'),
  ('dc568b2c-0a26-3517-a643-229d03fe7cde', 'in', 'GK-KARDUS-000301', 'ATOMY-PROMO-RAMADHAN-2', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=506; type=MASUK; product_name=Atomy Promo Ramadhan 2; performed_by=Admin', '2026-05-30 09:17:00+07'),
  ('4e0d09e3-55ee-395d-b7fd-4e8d8d95a012', 'in', 'GK-KARDUS-000301', 'ATOMY-PROPOLIS-TOOTHPASTE-50G', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=507; type=MASUK; product_name=Atomy Propolis Toothpaste 50g; performed_by=Admin', '2026-05-30 09:17:00+07'),
  ('0cbaf5f3-582a-3930-8a87-f7310bb94a11', 'in', 'GK-KARDUS-000601', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=508; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-30 09:19:00+07'),
  ('1c21b4b7-8f1f-33c2-8a7a-71068f6e3e0b', 'in', 'GK-KARDUS-000602', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=509; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-30 09:21:00+07'),
  ('42eb1c13-02da-3d3d-97df-b15e0934ed39', 'in', 'GK-KARDUS-000602', 'ATOMY-PSYLLIUM-HUSK', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=510; type=MASUK; product_name=Atomy Psyllium Husk; performed_by=Admin', '2026-05-30 09:21:00+07'),
  ('07cd2a12-e391-3128-8ab3-ddc94d8ff464', 'in', 'GK-KARDUS-000600', 'ATOMY-HERBAL-HAIR-CONDITIONER', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=511; type=MASUK; product_name=Atomy Herbal Hair Conditioner; performed_by=Admin', '2026-05-30 09:22:00+07'),
  ('d13750c1-5f52-38a4-85cd-89a708b10318', 'in', 'GK-KARDUS-000600', 'ATOMY-SAENGMODAN-HAIR-TONIC', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=512; type=MASUK; product_name=Atomy Saengmodan Hair Tonic; performed_by=Admin', '2026-05-30 09:22:00+07'),
  ('e26ff63c-7711-3540-9ee5-14762acecfc0', 'in', 'GK-KARDUS-000600', 'ATOMY-HERBAL-HAIR-SHAMPOO', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=513; type=MASUK; product_name=Atomy Herbal Hair Shampoo; performed_by=Admin', '2026-05-30 09:22:00+07'),
  ('d05b8356-a636-3846-9f50-adbee835331d', 'in', 'GK-KARDUS-000600', 'ATOMY-FINEZYME', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=514; type=MASUK; product_name=Atomy Finezyme; performed_by=Admin', '2026-05-30 09:22:00+07'),
  ('74511a5a-2649-341a-87db-a0e49f624c1e', 'in', 'GK-KARDUS-000600', 'ATOMY-COLOR-FOOD-VITAMIN-C', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=515; type=MASUK; product_name=Atomy Color Food Vitamin C; performed_by=Admin', '2026-05-30 09:22:00+07'),
  ('8229c9ec-cda1-3081-922a-b911c160a243', 'in', 'GK-KARDUS-000600', 'ATOMY-HAIR-ESSENTIAL-OIL', 2, 0, 2, 'Import data client GudangKu inventory', 'source_id=516; type=MASUK; product_name=Atomy Hair Essential Oil; performed_by=Admin', '2026-05-30 09:22:00+07'),
  ('ee79f0ea-0e0a-30e8-8273-156196a0fd6d', 'in', 'GK-KARDUS-000605', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=517; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-30 09:26:00+07'),
  ('2b1f33fb-33ca-3962-97a0-634671be5483', 'in', 'GK-KARDUS-000604', 'ATOMY-PAKET-LEBARAN-A-HEALTH-CARE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=518; type=MASUK; product_name=Atomy Paket Lebaran A (Health Care); performed_by=Admin', '2026-05-30 09:26:00+07'),
  ('73126d47-690d-3e15-a860-241f70160681', 'in', 'GK-KARDUS-000607', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=519; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-30 09:27:00+07'),
  ('0032f09f-2cc9-36c7-809e-56eaa4df55cf', 'in', 'GK-KARDUS-000604', 'ATOMY-ETHEREAL-OIL-PATCH', 4, 0, 4, 'Import data client GudangKu inventory', 'source_id=520; type=MASUK; product_name=Atomy Ethereal Oil Patch; performed_by=Admin', '2026-05-30 09:29:00+07'),
  ('cd04167e-8405-3d77-b722-3583a240867d', 'in', 'GK-KARDUS-000609', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=521; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-30 09:34:00+07'),
  ('4983a359-bf66-3c9e-a1cc-62bc1347b6c9', 'in', 'GK-KARDUS-000610', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=522; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-30 09:36:00+07'),
  ('d0591800-069e-34d4-9f74-1c39c644b370', 'in', 'GK-KARDUS-000611', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=523; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-30 09:38:00+07'),
  ('ace06bfa-e128-343c-8fd4-ef8e85a9f9a0', 'in', 'GK-KARDUS-000610', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 1, 2, 'Import data client GudangKu inventory', 'source_id=524; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-30 09:39:00+07'),
  ('7d11cba6-578a-31a7-9213-2111ce38ef38', 'in', 'GK-KARDUS-000612', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=525; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-30 09:39:00+07'),
  ('f2714f45-b5ce-303d-97dc-fab9378dfe4e', 'in', 'GK-KARDUS-000613', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=526; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-30 09:40:00+07'),
  ('9ac9744a-3fb4-3f26-bbc4-9ef0422d3527', 'in', 'GK-KARDUS-000614', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=527; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-30 09:41:00+07'),
  ('16f05f44-d8d2-3ec7-9a56-ffc2e9983079', 'in', 'GK-KARDUS-000615', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=528; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-30 09:42:00+07'),
  ('3cec8ced-9795-37e7-8834-3c392b337158', 'in', 'GK-KARDUS-000616', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=529; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-30 09:42:00+07'),
  ('cf1c0a67-ce07-3129-aea8-9576518e6118', 'in', 'GK-KARDUS-000617', 'ATOMY-PROMO-RAMADHAN-1', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=530; type=MASUK; product_name=Atomy Promo Ramadhan 1; performed_by=Admin', '2026-05-30 09:44:00+07'),
  ('ef4a31e3-14bf-3c0e-8020-6f99182e5ca1', 'in', 'GK-KARDUS-000618', 'ATOMY-PAKET-BERKAH-RAMADAN-A', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=531; type=MASUK; product_name=Atomy Paket Berkah Ramadan A; performed_by=Admin', '2026-05-30 09:45:00+07'),
  ('892aa91f-5297-35a7-875d-9bcfaf33a7a3', 'in', 'GK-KARDUS-000619', 'ATOMY-ABSOLUTE-CELLACTIVE-AMPOULE', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=532; type=MASUK; product_name=Atomy Absolute CellActive Ampoule; performed_by=Admin', '2026-05-30 09:46:00+07'),
  ('5c96f369-8a5c-3719-8bc9-de59dbe6a583', 'in', 'GK-KARDUS-000619', 'ATOMY-ABSOLUTE-CELLACTIVE-SKINCARE-SET', 1, 0, 1, 'Import data client GudangKu inventory', 'source_id=533; type=MASUK; product_name=Atomy Absolute CellActive Skincare Set; performed_by=Admin', '2026-05-30 09:46:00+07')
)
insert into public.stock_movements(
  id,
  movement_type,
  box_id,
  owner_id,
  product_id,
  qty,
  before_qty,
  after_qty,
  scanned_barcode,
  reason,
  notes,
  created_at
)
select
  source_movements.id::uuid,
  source_movements.movement_type,
  boxes.id,
  boxes.owner_id,
  products.id,
  source_movements.qty::numeric,
  source_movements.before_qty::numeric,
  source_movements.after_qty::numeric,
  boxes.barcode_value,
  source_movements.reason,
  source_movements.notes,
  source_movements.created_at::timestamptz
from source_movements
join public.boxes on boxes.id_box = source_movements.id_box
join public.products on products.sku = source_movements.sku
on conflict (id) do update set
  box_id = excluded.box_id,
  owner_id = excluded.owner_id,
  product_id = excluded.product_id,
  qty = excluded.qty,
  before_qty = excluded.before_qty,
  after_qty = excluded.after_qty,
  scanned_barcode = excluded.scanned_barcode,
  reason = excluded.reason,
  notes = excluded.notes,
  created_at = excluded.created_at;

insert into public.import_batches(
  id,
  import_type,
  file_name,
  status,
  total_rows,
  success_rows,
  failed_rows,
  error_summary,
  completed_at
)
values
  ('e509cc2e-be3b-3fcc-a421-a7618aeef140', 'client_kardus', 'GudangKu Database - kardus.csv', 'success', 658, 345, 1, 'Ada 1 baris CSV kardus dengan id box yang sama tetapi metadata berbeda. Master box memakai baris pertama, raw tetap disimpan.', now()),
  ('c9723f2b-3aa0-31a3-b479-55a18aa36f2a', 'client_inventory', 'GudangKu Database - inventory.csv', 'success', 534, 499, 0, null, now()),
  ('18717b58-aafc-328a-a430-3399359a2bba', 'client_package', 'GudangKu Database - paket.csv', 'success', 48, 41, 0, 'Skipped empty rows: 42, 43, 44, 45, 46, 47, 48', now())
on conflict (id) do update set
  status = excluded.status,
  total_rows = excluded.total_rows,
  success_rows = excluded.success_rows,
  failed_rows = excluded.failed_rows,
  error_summary = excluded.error_summary,
  completed_at = excluded.completed_at;

commit;


-- ============================================================
-- 5. Fix checkout barcode regex (terima id_box GK-KARDUS-*, dll)
--    Override fungsi strict dari section 1. Checksum tetap menjaga integritas.
-- ============================================================

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
