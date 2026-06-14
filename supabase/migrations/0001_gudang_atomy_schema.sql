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
