-- Clear data gudang Gudang Atomy tanpa menghapus schema/tabel.
-- Jalankan dari Supabase SQL Editor.
-- auth.users dan public.profiles sengaja tidak dihapus supaya admin tetap bisa login.

begin;

do $$
declare
  v_tables text;
begin
  select string_agg(format('%I.%I', schemaname, tablename), ', ')
  into v_tables
  from pg_tables
  where schemaname = 'public'
    and tablename in (
      'audit_logs',
      'scan_logs',
      'stock_movements',
      'box_items',
      'boxes',
      'package_template_items',
      'package_templates',
      'products',
      'owners',
      'import_batches',
      'client_gudangku_kardus_raw',
      'client_gudangku_inventory_raw'
    );

  if v_tables is not null then
    execute 'truncate table ' || v_tables || ' restart identity cascade';
  end if;
end $$;

alter sequence if exists public.box_number_seq restart with 1;
alter sequence if exists public.owner_number_seq restart with 1;

commit;
