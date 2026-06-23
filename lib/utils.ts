import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
import type { UserRole } from "@/lib/types";

export const APP_TIME_ZONE = "Asia/Jakarta";
const JAKARTA_UTC_OFFSET_MS = 7 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatDate(value?: string | null) {
  if (!value) return "-";
  return new Intl.DateTimeFormat("id-ID", {
    timeZone: APP_TIME_ZONE,
    day: "2-digit",
    month: "short",
    year: "numeric"
  }).format(new Date(value));
}

export function formatDateTime(value?: string | null) {
  if (!value) return "-";
  return new Intl.DateTimeFormat("id-ID", {
    timeZone: APP_TIME_ZONE,
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

export function jakartaDateToUtcRange(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const [, year, month, day] = match;
  const startMs = Date.UTC(Number(year), Number(month) - 1, Number(day)) - JAKARTA_UTC_OFFSET_MS;
  return {
    startIso: new Date(startMs).toISOString(),
    endIso: new Date(startMs + DAY_MS - 1).toISOString()
  };
}

export function jakartaTodayUtcRange(reference = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: APP_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).formatToParts(reference);
  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? "";
  return jakartaDateToUtcRange(`${get("year")}-${get("month")}-${get("day")}`);
}

export function toNumber(value: FormDataEntryValue | null, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function csvEscape(value: unknown) {
  const text = value == null ? "" : String(value);
  if (/[",\n]/.test(text)) return `"${text.replaceAll('"', '""')}"`;
  return text;
}

export function roleLabel(role?: UserRole | string | null) {
  if (role === "super_admin") return "Super User";
  if (role === "admin_gudang") return "Admin";
  if (role === "viewer") return "Viewer";
  return "-";
}
