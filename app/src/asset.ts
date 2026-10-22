import { attributionText, normalizeAuthors, normalizeLicense, normalizePrice } from "./license.js";
import type { Asset, AssetType, AssetVariant, Author, LicenseRecord, Price, SourceFile } from "./types.js";

export interface AssetInput {
  provider_id: string;
  provider_name: string;
  id: string;
  title: string;
  type: AssetType;
  url: string;
  thumbnail_url?: string;
  description?: string;
  tags?: unknown;
  categories?: unknown;
  price?: unknown;
  authors?: unknown;
  license?: unknown;
  licenses?: unknown;
  selected_license?: unknown;
  attribution_text?: string;
  metadata_source_url?: string;
  retrieved_utc?: string;
  variants?: AssetVariant[];
  files?: SourceFile[];
  download_data?: Record<string, unknown>;
  dimensions?: Asset["dimensions"];
  source_metadata?: Record<string, unknown>;
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return [...new Set(value.map((entry) => String(entry).trim()).filter(Boolean))];
}

export function normalizeAssetType(value: unknown): AssetType {
  const lower = String(value ?? "").toLowerCase();
  if (lower === "material" || lower === "texture" || lower === "textures" || lower === "pbr") {
    return "material";
  }
  if (lower === "model" || lower === "3d" || lower === "3d-model") {
    return "model";
  }
  if (lower === "audio" || lower === "sound" || lower === "music") {
    return "audio";
  }
  return "image";
}

export function createAsset(input: AssetInput): Asset {
  const authors: Author[] = normalizeAuthors(input.authors);
  const license: LicenseRecord = normalizeLicense(input.license);
  const price: Price = normalizePrice(input.price);
  const licenses = Array.isArray(input.licenses)
    ? input.licenses.map((entry) => normalizeLicense(entry))
    : [license];
  const selected = input.selected_license ? normalizeLicense(input.selected_license) : license;
  const asset: Asset = {
    provider_id: input.provider_id,
    provider_name: input.provider_name,
    id: input.id,
    title: input.title.trim() || input.id,
    type: input.type,
    url: input.url,
    thumbnail_url: input.thumbnail_url || undefined,
    description: input.description || undefined,
    tags: stringList(input.tags),
    categories: stringList(input.categories),
    price,
    authors,
    author_status: authors.length ? "reported" : "not_supplied",
    license,
    licenses,
    selected_license: selected,
    attribution_text: input.attribution_text || "",
    metadata_source_url: input.metadata_source_url || undefined,
    retrieved_utc: input.retrieved_utc || undefined,
    variants: input.variants ?? [],
    files: input.files,
    download_data: input.download_data,
    dimensions: input.dimensions,
    source_metadata: input.source_metadata
  };
  if (!asset.attribution_text) {
    asset.attribution_text = attributionText(asset);
  }
  return asset;
}

export function mergeAsset(previous: Asset | undefined, next: Asset): Asset {
  if (!previous) {
    return next;
  }
  return {
    ...previous,
    ...next,
    tags: next.tags.length ? next.tags : previous.tags,
    categories: next.categories.length ? next.categories : previous.categories,
    authors: next.authors.length ? next.authors : previous.authors,
    author_status: next.authors.length ? "reported" : previous.author_status,
    files: next.files?.length ? next.files : previous.files,
    download_data: next.download_data ?? previous.download_data,
    variants: next.variants.length ? next.variants : previous.variants,
    source_metadata: next.source_metadata ?? previous.source_metadata
  };
}

export function uniqueById<T extends { id: string }>(items: T[]): T[] {
  const seen = new Set<string>();
  const result: T[] = [];
  for (const item of items) {
    if (!seen.has(item.id)) {
      seen.add(item.id);
      result.push(item);
    }
  }
  return result;
}

import { sanitizeRecord, sanitizeUrl } from "./util/sanitize.js";

export function publicAsset(asset: Asset): Asset {
  const copy = structuredClone(asset);
  copy.url = sanitizeUrl(copy.url) ?? "";
  copy.thumbnail_url = sanitizeUrl(copy.thumbnail_url ?? "") ?? undefined;
  copy.metadata_source_url = sanitizeUrl(copy.metadata_source_url ?? "") ?? undefined;
  copy.files = copy.files
    ?.map((file) => ({ ...file, url: sanitizeUrl(file.url) ?? "" }))
    .filter((file) => Boolean(file.url));
  copy.source_metadata = sanitizeRecord(copy.source_metadata);
  copy.download_data = sanitizeRecord(copy.download_data);
  return copy;
}
