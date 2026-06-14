insert into public.owners(owner_code, owner_name, phone, atomy_member_id, notes)
values
  ('OWN-000001', 'Joshua Warehouse', '081234567890', 'ATOMY-001', 'Owner contoh'),
  ('OWN-000002', 'Budi Santoso', null, null, 'Pemilik contoh')
on conflict (owner_code) do nothing;

insert into public.products(sku, product_name, category, unit, default_barcode)
values
  ('ATMY-TONER', 'Atomy Toner', 'Skincare', 'pcs', null),
  ('ATMY-LOTION', 'Atomy Lotion', 'Skincare', 'pcs', null),
  ('ATMY-CREAM', 'Atomy Cream', 'Skincare', 'pcs', null),
  ('ATMY-CLEANSER', 'Atomy Cleanser', 'Skincare', 'pcs', null),
  ('ATMY-SUNSCREEN', 'Atomy Sunscreen', 'Skincare', 'pcs', null)
on conflict (sku) do nothing;

insert into public.package_templates(package_code, package_name, description)
values ('PKG-SKINCARE-BASIC', 'Skincare Basic', 'Paket contoh berisi 5 produk skincare')
on conflict (package_code) do nothing;

insert into public.package_template_items(package_id, product_id, qty_per_package)
select pt.id, p.id, 1
from public.package_templates pt
cross join public.products p
where pt.package_code = 'PKG-SKINCARE-BASIC'
  and p.sku in ('ATMY-TONER', 'ATMY-LOTION', 'ATMY-CREAM', 'ATMY-CLEANSER', 'ATMY-SUNSCREEN')
on conflict (package_id, product_id) do nothing;
