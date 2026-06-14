import { csvEscape } from "@/lib/utils";

export function rowsToCsv<T extends Record<string, unknown>>(rows: T[], headers: Array<keyof T>) {
  const headerLine = headers.map((header) => csvEscape(String(header))).join(",");
  const lines = rows.map((row) => headers.map((header) => csvEscape(row[header])).join(","));
  return [headerLine, ...lines].join("\n");
}

export function parseSimpleCsv(text: string) {
  const [headerLine, ...lines] = text.trim().split(/\r?\n/);
  const headers = headerLine.split(",").map((value) => value.trim());
  return lines
    .filter(Boolean)
    .map((line) => {
      const values = line.split(",").map((value) => value.trim());
      return Object.fromEntries(headers.map((header, index) => [header, values[index] ?? ""]));
    });
}
