import type { Asset, AssetVariant, SourceFile } from "../types.js";
import { filenameFromUrl, slug } from "../util/fs.js";

const ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: "\"",
  apos: "'",
  nbsp: " ",
  ndash: "–",
  mdash: "—",
  hellip: "…"
};

export function decodeHtml(value: string): string {
  return value
    .replace(/&#x([0-9a-f]+);/gi, (_, hex: string) => String.fromCodePoint(Number.parseInt(hex, 16)))
    .replace(/&#([0-9]+);/g, (_, number: string) => String.fromCodePoint(Number.parseInt(number, 10)))
    .replace(/&([a-z]+);/gi, (match, name: string) => ENTITIES[name.toLowerCase()] ?? match);
}

export function stripHtml(value: string): string {
  return decodeHtml(
    value
      .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, " ")
      .replace(/<[^>]+>/g, " ")
  ).replace(/\s+/g, " ").trim();
}

export function absoluteUrl(value: string, base: string): string {
  const trimmed = decodeHtml(value).trim();
  if (!trimmed) {
    return "";
  }
  if (trimmed.startsWith("//")) {
    return `https:${trimmed}`;
  }
  try {
    const parsed = new URL(trimmed, base);
    if (parsed.protocol === "http:") {
      parsed.protocol = "https:";
    }
    return parsed.protocol === "https:" ? parsed.toString() : "";
  } catch {
    return "";
  }
}

export function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

export function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

export function asString(value: unknown, fallback = ""): string {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

export function asNumber(value: unknown, fallback = 0): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function firstString(record: Record<string, unknown>, keys: string[], fallback = ""): string {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return fallback;
}

export function fileFromUrl(url: string, fallbackName: string, role?: string, size?: number): SourceFile {
  const file: SourceFile = {
    filename: filenameFromUrl(url, fallbackName),
    url
  };
  if (role) {
    file.role = role;
  }
  if (size && size > 0) {
    file.size = size;
  }
  return file;
}

export function variant(
  id: string,
  label: string,
  kind: "material" | "files",
  extra: Partial<AssetVariant> = {}
): AssetVariant {
  return {
    id: slug(id),
    label,
    confirmed: true,
    kind,
    ...extra
  };
}

export function canDownload(asset: Asset): boolean {
  return asset.price.free && asset.price.credits === 0 && asset.variants.length > 0;
}

export function pageSlice<T>(items: T[], cursor: string | null | undefined, size: number): { items: T[]; next_cursor: string | null } {
  const offset = Number.parseInt(cursor ?? "0", 10);
  const start = Number.isFinite(offset) && offset > 0 ? offset : 0;
  const page = items.slice(start, start + size);
  const next = start + size < items.length ? String(start + size) : null;
  return { items: page, next_cursor: next };
}

export function matchesText(asset: Asset, query: string): boolean {
  const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (!terms.length) {
    return true;
  }
  const haystack = [
    asset.id,
    asset.title,
    asset.description ?? "",
    asset.tags.join(" "),
    asset.categories.join(" ")
  ].join(" ").toLowerCase();
  return terms.every((term) => haystack.includes(term));
}
