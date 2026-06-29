import { z } from "zod";
import { isValidBarcodeValue } from "@/lib/barcode/generate";
import { isUuidValue } from "@/lib/validation/uuid";

const blankToUndefined = (value: unknown) => (typeof value === "string" && value.trim() === "" ? undefined : value);

export const uuidSchema = z.string().trim().refine(isUuidValue, "ID tidak valid.");

const productIdSchema = z.string().trim().refine(isUuidValue, "Produk tidak valid. Pilih ulang produk.");
const optionalUuidSchema = (message: string) => z.preprocess(blankToUndefined, z.string().trim().refine(isUuidValue, message).optional());

export const ownerSchema = z.object({
  owner_code: z.string().trim().optional(),
  owner_name: z.string().trim().min(1, "Nama pemilik wajib diisi"),
  phone: z.string().trim().optional(),
  atomy_member_id: z.string().trim().optional(),
  notes: z.string().trim().optional(),
  is_active: z.boolean().default(true)
});

export const productSchema = z.object({
  sku: z.string().trim().optional(),
  product_name: z.string().trim().min(1, "Nama produk wajib diisi"),
  category: z.string().trim().optional(),
  unit: z.string().trim().default("pcs"),
  default_barcode: z.string().trim().optional(),
  is_active: z.boolean().default(true)
});

export const packageSchema = z.object({
  package_code: z.string().trim().min(1, "Kode paket wajib diisi"),
  package_name: z.string().trim().min(1, "Nama paket wajib diisi"),
  description: z.string().trim().optional(),
  is_active: z.boolean().default(true),
  items: z
    .array(
      z.object({
        product_id: productIdSchema,
        qty_per_package: z.coerce.number().positive("Qty paket harus lebih dari 0")
      })
    )
    .min(1, "Minimal pilih 1 produk untuk paket")
    .default([])
});

export const receiveBoxSchema = z
  .object({
    owner_id: optionalUuidSchema("Pemilik tidak valid. Pilih ulang pemilik."),
    quick_owner_name: z.string().trim().optional(),
    id_box: z
      .string()
      .trim()
      .min(1, "ID Box wajib diisi")
      .transform((value) => value.toUpperCase())
      .refine((value) => /^[A-Z0-9][A-Z0-9-]{1,48}$/.test(value), "ID Box hanya boleh huruf/angka/strip, contoh: BSTR-HEMO-0045"),
    box_name: z.string().trim().min(1, "Nama produk wajib dipilih"),
    expired_at: z.string().trim().optional(),
    location_code: z.string().trim().optional(),
    source_type: z.enum(["custom", "package", "mixed"]),
    package_id: optionalUuidSchema("Paket tidak valid. Pilih ulang paket."),
    package_qty: z.coerce.number().min(0).default(0),
    notes: z.string().trim().optional(),
    items: z.array(
      z.object({
        product_id: productIdSchema,
        qty: z.coerce.number().positive("Qty harus lebih dari 0"),
        expired_at: z.string().trim().optional(),
        batch_no: z.string().trim().optional()
      })
    )
  })
  .refine((data) => data.owner_id || data.quick_owner_name, "Pilih pemilik atau isi pemilik cepat")
  .refine((data) => data.source_type !== "custom" || data.items.length > 0, "Produk manual wajib untuk custom")
  .refine((data) => data.source_type === "custom" || Boolean(data.package_id), "Paket wajib dipilih")
  .refine((data) => data.source_type === "custom" || data.package_qty > 0, "Jumlah paket harus lebih dari 0");

export const editBoxSchema = z.object({
  box_name: z.string().trim().min(1, "Nama box wajib diisi"),
  expired_at: z.string().trim().optional(),
  location_code: z.string().trim().optional(),
  notes: z.string().trim().optional(),
  items: z
    .array(
      z.object({
        id: optionalUuidSchema("Item box tidak valid. Muat ulang halaman lalu coba lagi."),
        product_id: productIdSchema,
        qty: z.coerce.number().positive("Qty harus lebih dari 0"),
        expired_at: z.string().trim().optional(),
        batch_no: z.string().trim().optional()
      })
    )
    .default([])
});

export const barcodeSchema = z.string().trim().refine(isValidBarcodeValue, "Format barcode tidak valid");

export const partialCheckoutSchema = z.object({
  barcode_value: barcodeSchema,
  product_id: uuidSchema,
  qty: z.coerce.number().positive("Qty harus lebih dari 0")
});
