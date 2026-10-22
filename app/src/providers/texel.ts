import { createAsset, mergeAsset } from "../asset.js";
import { normalizeLicense, normalizePrice } from "../license.js";
import type {
  Asset,
  AssetVariant,
  DownloadPlan,
  MaterialPlan,
  MaterialRole,
  MaterialSource,
  Provider,
  ProviderContext,
  ProviderDescriptor,
  SearchPage,
  SearchParams
} from "../types.js";
import { MATERIAL_ROLES } from "../types.js";
import { slug } from "../util/fs.js";
import { sanitizeRecord } from "../util/sanitize.js";
import { asArray, asRecord, asString, canDownload, matchesText, variant } from "./helpers.js";

const BASE = "https://3dtexel.com/wp-json/3dtexel-api/v1";
const KEY_NAMES = ["3DTEXEL_API_KEY", "TEXEL_API_KEY", "TEXEL"] as const;
const PAGE_SIZE = 30;

interface TexelRaw extends Record<string, unknown> {
  id?: number | string;
  asset_id?: number | string;
  title?: string;
  name?: string;
  thumbnail?: string;
  description?: string;
  url?: string;
  source_url?: string;
  license?: unknown;
  price?: unknown;
  charged_credits?: number;
  authors?: unknown;
  author?: unknown;
  resolutions?: unknown;
  available_resolutions?: unknown;
  formats?: unknown;
  download?: Record<string, unknown>;
  returned_resolution?: string;
  normal_format?: string;
  material_props?: Record<string, unknown>;
}

interface TexelSearch {
  items?: TexelRaw[];
  total?: number;
  data?: TexelRaw[];
}

export class TexelProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "texel",
      name: "3D Texel",
      website: "https://3dtexel.com/pbr-material/",
      key_env: [...KEY_NAMES],
      capabilities: ["material"],
      description: "PBR materials from the official 3DTexel REST API. Downloads require an environment key."
    };
  }

  private key(): string {
    for (const name of KEY_NAMES) {
      const value = this.ctx.env[name]?.trim();
      if (value) {
        return value;
      }
    }
    return "";
  }

  credentialStatus(): string {
    return this.key()
      ? "Key available in the environment."
      : "Browsing needs no key. Downloads need 3DTEXEL_API_KEY, TEXEL_API_KEY, or TEXEL.";
  }

  private authHeaders(): Record<string, string> {
    const key = this.key();
    return key ? { Authorization: `Bearer ${key}` } : {};
  }

  private resolutions(raw: TexelRaw): string[] {
    const values: unknown[] = [raw.resolutions, raw.available_resolutions, raw.formats];
    if (raw.download && typeof raw.download === "object") {
      values.push(raw.download.resolutions, raw.download.available_resolutions, raw.download.formats);
    }
    const found = new Set<string>();
    for (const value of values) {
      for (const match of JSON.stringify(value ?? "").matchAll(/(?<![0-9])(1|2|4|8|16)\s*k\b/gi)) {
        found.add(`${match[1]}k`);
      }
    }
    return [...found].sort((left, right) => Number.parseInt(left, 10) - Number.parseInt(right, 10));
  }

  private normalize(raw: TexelRaw, fetched: boolean): Asset {
    const id = String(raw.id ?? raw.asset_id ?? "");
    const resolutions = this.resolutions(raw);
    const variants = resolutions.map((size) => variant(size, size.toUpperCase(), "material", {
      resolution: size,
      filter_key: `resolution:${size}`,
      filter_label: size.toUpperCase()
    }));
    const price = raw.price !== undefined
      ? normalizePrice(raw.price)
      : typeof raw.charged_credits === "number"
        ? { free: raw.charged_credits === 0, credits: Math.max(0, raw.charged_credits) }
        : { free: false, credits: 0 };
    const license = normalizeLicense(raw.license ?? "Unknown");
    const title = asString(raw.title, asString(raw.name, `3DTexel material ${id}`));
    const url = asString(raw.url, asString(raw.source_url, `https://3dtexel.com/product/${id}/`));
    const authors = Array.isArray(raw.authors)
      ? raw.authors
      : raw.author
        ? [raw.author]
        : [];
    return createAsset({
      provider_id: "texel",
      provider_name: "3DTexel",
      id,
      title,
      type: "material",
      url,
      thumbnail_url: asString(raw.thumbnail),
      description: asString(raw.description),
      tags: [],
      categories: [],
      price,
      authors,
      license,
      licenses: [license],
      selected_license: license,
      attribution_text: `${title} by ${authors.length ? "the reported creator" : "creator not supplied"}, ${license.name}. Source: ${url}`,
      metadata_source_url: `${BASE}/assets/${encodeURIComponent(id)}`,
      retrieved_utc: fetched ? this.ctx.now().toISOString() : undefined,
      variants,
      source_metadata: { ...sanitizeRecord(raw), details_loaded: false }
    });
  }

  private async enrich(asset: Asset, options: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<Asset> {
    if (asset.authors.length && asset.variants.length) {
      return asset;
    }
    if (!asset.url.startsWith("https://3dtexel.com/product/")) {
      return asset;
    }
    try {
      const html = await this.ctx.http.text(asset.url, {
        refresh: options.refresh,
        signal: options.signal,
        headers: { Accept: "text/html" }
      });
      const extra = parseProductPage(html);
      const merged = mergeAsset(asset, {
        ...asset,
        authors: extra.authors.length ? extra.authors : asset.authors,
        variants: extra.resolutions.length
          ? extra.resolutions.map((size) => variant(size, size.toUpperCase(), "material", {
            resolution: size,
            filter_key: `resolution:${size}`,
            filter_label: size.toUpperCase()
          }))
          : asset.variants
      });
      return merged;
    } catch {
      return asset;
    }
  }

  async search(params: SearchParams): Promise<SearchPage> {
    if (params.category !== "all" && params.category !== "material") {
      return { items: [], next_cursor: null };
    }
    const page = Math.max(1, Number.parseInt(params.cursor ?? "1", 10) || 1);
    const url = new URL(`${BASE}/assets/search`);
    url.searchParams.set("q", params.query.trim());
    url.searchParams.set("type", "pbr");
    url.searchParams.set("page", String(page));
    url.searchParams.set("per_page", String(PAGE_SIZE));
    const response = await this.ctx.http.json<TexelSearch>(url.toString(), {
      refresh: params.refresh,
      signal: params.signal
    });
    const rawItems = Array.isArray(response) ? response : response.items ?? response.data ?? [];
    const assets = rawItems
      .map((raw) => this.normalize(raw, true))
      .filter((asset) => matchesText(asset, params.query))
      .slice(0, params.limit);
    const total = Array.isArray(response) ? assets.length : Number(response.total ?? 0);
    const next = page * PAGE_SIZE < total ? String(page + 1) : null;
    return { items: assets, next_cursor: next };
  }

  async details(asset: Asset, options: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<Asset> {
    if (!options.refresh && this.isDetailed(asset)) {
      return this.enrich(asset, options);
    }
    const fresh = await this.ctx.http.json<TexelRaw>(`${BASE}/assets/${encodeURIComponent(asset.id)}`, {
      refresh: options.refresh,
      signal: options.signal
    });
    const normalized = this.normalize(fresh, true);
    normalized.source_metadata = { ...normalized.source_metadata, details_loaded: true };
    return this.enrich(mergeAsset(asset, normalized), options);
  }

  variants(asset: Asset): AssetVariant[] {
    return asset.variants;
  }

  isDetailed(asset: Asset): boolean {
    return asset.source_metadata?.details_loaded === true && asset.variants.length > 0;
  }

  canDownload(asset: Asset): boolean {
    return Boolean(
      canDownload(asset)
      && this.key()
      && asset.download_data?.via_api !== false
    );
  }

  async resolveDownload(asset: Asset, variantId: string, options: { signal?: AbortSignal; preview?: boolean } = {}): Promise<DownloadPlan> {
    const key = this.key();
    if (!key) {
      throw new Error("3DTexel downloads require 3DTEXEL_API_KEY, TEXEL_API_KEY, or TEXEL.");
    }
    const detailed = this.isDetailed(asset) ? asset : await this.details(asset, { signal: options.signal });
    if (!detailed.variants.some((candidate) => candidate.id === variantId)) {
      throw new Error(`Unknown variant for ${detailed.provider_id}:${detailed.id}: ${variantId}`);
    }
    if (options.preview) {
      return {
        kind: "material",
        asset: detailed,
        variant: variantId,
        maps: {},
        normal_format: "opengl"
      } satisfies MaterialPlan;
    }
    const response = await this.ctx.http.json<TexelRaw & {
      files?: Record<string, unknown>;
      charged_credits?: number;
      returned_resolution?: string;
      normal_format?: string;
      material_props?: Record<string, unknown>;
      license?: unknown;
    }>(`${BASE}/assets/${encodeURIComponent(detailed.id)}/download`, {
      method: "POST",
      headers: {
        ...this.authHeaders(),
        "Idempotency-Key": `asset-library-${Date.now()}-${Math.random().toString(16).slice(2)}`
      },
      body: { max_credits: 0, resolution: variantId },
      refresh: true,
      signal: options.signal,
      pace_ms: 1000
    });
    if (Number(response.charged_credits ?? 0) !== 0) {
      throw new Error("3DTexel returned a non-zero charge; download aborted.");
    }
    const files = asRecord(response.files);
    const maps: Partial<Record<MaterialRole, MaterialSource>> = {};
    for (const role of MATERIAL_ROLES) {
      const url = asString(files[role]);
      if (url.startsWith("https://")) {
        maps[role] = { url };
      }
    }
    if (!Object.keys(maps).length) {
      throw new Error("3DTexel returned no material maps.");
    }
    const returned = asString(response.returned_resolution, variantId);
    const updated = mergeAsset(detailed, {
      ...detailed,
      license: response.license ? normalizeLicense(response.license) : detailed.license,
      variants: detailed.variants.some((entry) => entry.id === returned)
        ? detailed.variants
        : [...detailed.variants, variant(returned, returned.toUpperCase(), "material", { resolution: returned })]
    });
    return {
      kind: "material",
      asset: updated,
      variant: returned,
      maps,
      normal_format: asString(response.normal_format, "opengl") === "directx" ? "directx" : "opengl",
      material_props: response.material_props
    } satisfies MaterialPlan;
  }

  async checkConnection(options: { signal?: AbortSignal } = {}): Promise<{ ok: boolean; message: string }> {
    try {
      await this.ctx.http.json<unknown>(`${BASE}/me`, {
        headers: this.authHeaders(),
        signal: options.signal
      });
      return { ok: true, message: "3DTexel API reachable." };
    } catch (error) {
      return { ok: false, message: error instanceof Error ? error.message : String(error) };
    }
  }
}

function parseProductPage(html: string): { authors: Array<{ name: string; url?: string }>; resolutions: string[] } {
  const authors: Array<{ name: string; url?: string }> = [];
  const scripts = html.matchAll(/<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi);
  for (const match of scripts) {
    try {
      const data = JSON.parse(match[1] ?? "") as Record<string, unknown>;
      const found = findAuthor(data);
      if (found) {
        if (typeof found === "string") {
          authors.push({ name: found });
        } else {
          const record = asRecord(found);
          const name = asString(record.name);
          if (name) {
            authors.push({ name, url: asString(record.url) || undefined });
          }
        }
      }
      if (authors.length) {
        break;
      }
    } catch {
      continue;
    }
  }
  if (!authors.length) {
    const text = html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");
    const match = /\bAuthor\s+(.{1,120}?)\s+(?:Resolution|Downloads|Style|Textures|Available Formats)\b/i.exec(text);
    if (match?.[1]?.trim()) {
      authors.push({ name: match[1].trim() });
    }
  }
  const found = new Set<string>();
  const text = html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");
  for (const match of text.matchAll(/(?<![0-9])(1|2|4|8|16)\s*k\b/gi)) {
    found.add(`${match[1]}k`);
  }
  return {
    authors,
    resolutions: [...found].sort((left, right) => Number.parseInt(left, 10) - Number.parseInt(right, 10))
  };
}

function findAuthor(value: unknown): unknown {
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findAuthor(item);
      if (found) {
        return found;
      }
    }
    return null;
  }
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    if (record.author) {
      return record.author;
    }
    if (record.creator) {
      return record.creator;
    }
    for (const child of Object.values(record)) {
      const found = findAuthor(child);
      if (found) {
        return found;
      }
    }
  }
  return null;
}

export const texelFactory = (context: ProviderContext): Provider => new TexelProvider(context);
