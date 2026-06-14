export type UserRole = "super_admin" | "admin_gudang" | "viewer";
export type BoxStatus = "active" | "partial" | "empty" | "taken" | "void";
export type SourceType = "custom" | "package" | "mixed";

export type Profile = {
  id: string;
  full_name: string;
  email: string | null;
  role: UserRole;
  is_active: boolean;
};

export type Owner = {
  id: string;
  owner_code: string;
  owner_name: string;
  phone: string | null;
  atomy_member_id: string | null;
  notes: string | null;
  is_active: boolean;
};

export type Product = {
  id: string;
  sku: string | null;
  product_name: string;
  category: string | null;
  unit: string | null;
  default_barcode: string | null;
  is_active: boolean;
};

export type PackageTemplate = {
  id: string;
  package_code: string;
  package_name: string;
  description: string | null;
  is_active: boolean;
};

export type PackageTemplateItem = {
  id: string;
  package_id: string;
  product_id: string;
  qty_per_package: number;
  products?: Pick<Product, "sku" | "product_name" | "unit"> | null;
};

export type BoxRecord = {
  id: string;
  id_box: string;
  pemilik_id_box: string;
  barcode_value: string;
  box_name: string;
  owner_id: string;
  source_type: SourceType;
  package_id: string | null;
  package_qty: number | null;
  expired_at: string | null;
  location_code: string | null;
  status: BoxStatus;
  created_by: string | null;
  checked_out_by: string | null;
  created_at: string;
  updated_at: string;
  checked_out_at: string | null;
  notes: string | null;
  owners?: Pick<Owner, "owner_code" | "owner_name"> | null;
};

export type BoxItem = {
  id: string;
  box_id: string;
  product_id: string;
  qty_initial: number;
  qty_available: number;
  expired_at: string | null;
  batch_no: string | null;
  products?: Pick<Product, "sku" | "product_name" | "unit"> | null;
};

export type ActionState = {
  ok: boolean;
  message: string;
  id?: string;
  data?: unknown;
};
