"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Check, ChevronDown, Search } from "lucide-react";
import { cn } from "@/lib/utils";

export type SearchableSelectOption = {
  value: string;
  label: string;
  description?: string;
};

type SearchableSelectProps = {
  id?: string;
  name?: string;
  value: string;
  onValueChange: (value: string) => void;
  options: SearchableSelectOption[];
  placeholder: string;
  searchPlaceholder?: string;
  emptyText?: string;
  disabled?: boolean;
};

export function SearchableSelect({
  id,
  name,
  value,
  onValueChange,
  options,
  placeholder,
  searchPlaceholder = "Ketik untuk mencari...",
  emptyText = "Tidak ada data",
  disabled
}: SearchableSelectProps) {
  const rootRef = useRef<HTMLDivElement | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const selected = options.find((option) => option.value === value);

  const filteredOptions = useMemo(() => {
    const keyword = query.trim().toLowerCase();
    if (!keyword) return options.slice(0, 80);
    return options
      .filter((option) => `${option.label} ${option.description ?? ""}`.toLowerCase().includes(keyword))
      .slice(0, 80);
  }, [options, query]);

  useEffect(() => {
    function handlePointerDown(event: PointerEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    }

    document.addEventListener("pointerdown", handlePointerDown);
    return () => document.removeEventListener("pointerdown", handlePointerDown);
  }, []);

  useEffect(() => {
    if (!open) return;
    window.setTimeout(() => inputRef.current?.focus(), 0);
  }, [open]);

  return (
    <div ref={rootRef} className="relative min-w-0">
      {name ? <input type="hidden" name={name} value={value} /> : null}
      <button
        id={id}
        type="button"
        disabled={disabled}
        aria-expanded={open}
        onClick={() => {
          if (!open) setQuery("");
          setOpen((current) => !current);
        }}
        className={cn(
          "flex h-10 w-full min-w-0 items-center gap-2 rounded-md border bg-card px-3 text-sm shadow-soft outline-none transition-all duration-200",
          "focus-visible:border-primary/50 focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-60",
          open && "border-primary/60 ring-2 ring-ring"
        )}
      >
        <span className={cn("min-w-0 flex-1 truncate text-left", !selected && "text-muted-foreground")}>{selected?.label ?? placeholder}</span>
        <ChevronDown className={cn("h-4 w-4 shrink-0 text-muted-foreground transition-transform duration-200", open && "rotate-180")} />
      </button>

      {open ? (
        <div className="absolute left-0 right-0 top-full z-50 mt-2 overflow-hidden rounded-lg border bg-card shadow-lift">
          <div className="border-b p-2">
            <div className="relative">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <input
                ref={inputRef}
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder={searchPlaceholder}
                className="h-10 w-full rounded-md border bg-background py-2 pl-9 pr-3 text-sm outline-none transition-all focus:border-primary/50 focus:ring-2 focus:ring-ring"
              />
            </div>
          </div>
          <div className="max-h-64 overflow-y-auto p-1">
            {filteredOptions.length ? (
              filteredOptions.map((option) => {
                const active = option.value === value;
                return (
                  <button
                    key={option.value}
                    type="button"
                    title={option.label}
                    onClick={() => {
                      onValueChange(option.value);
                      setOpen(false);
                    }}
                    className={cn(
                      "flex w-full min-w-0 items-start gap-2 rounded-md px-3 py-2 text-left text-sm transition-colors hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                      active && "bg-primary/10 text-primary"
                    )}
                  >
                    <Check className={cn("mt-0.5 h-4 w-4 shrink-0", active ? "opacity-100" : "opacity-0")} />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-medium">{option.label}</span>
                      {option.description ? <span className="block truncate text-xs text-muted-foreground">{option.description}</span> : null}
                    </span>
                  </button>
                );
              })
            ) : (
              <div className="px-3 py-4 text-center text-sm text-muted-foreground">{emptyText}</div>
            )}
          </div>
        </div>
      ) : null}
    </div>
  );
}
