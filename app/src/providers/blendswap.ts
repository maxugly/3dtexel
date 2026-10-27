import { createAsset, normalizeAssetType } from "../asset.js";
import type {
  Asset,
  AssetVariant,
  DownloadPlan,
  FilesPlan,
  LicenseRecord,
  Provider,
  ProviderContext,
  ProviderDescriptor,
  SearchPage,
  SearchParams,
  SourceFile
} from "../types.js";
import { filenameFromUrl, slug } from "../util/fs.js";
import { sanitizeRecord } from "../util/sanitize.js";
import { asArray, asRecord, asString, canDownload, matchesText, variant } from "./helpers.js";

const API_BASE = "https://blendswap.com/api/v1";

interface BlendSwapRawAsset extends Record<string, unknown> {
  id?: number | string;
  title?: string;
  url?: string;
  description?: string;
  thumbnail_url?: string;
  tags?: string[];
  license?: { key?: string; name?: string; url?: string } | string;
  author?: { id?: number; username?: string; name?: string; url?: string };
  files?: Array<Record<string, unknown>>;
  download_url?: string;
}

interface BlendSwapSearchResponse {
  data?: BlendSwapRawAsset[];
  items?: BlendSwapRawAsset[];
  results?: BlendSwapRawAsset[];
  pagination?: {
    page?: number;
    pages?: number;
    count?: number;
    per_page?: number;
  };
}

export class BlendSwapProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "blendswap",
      name: "Blend Swap",
      website: "https://blendswap.com",
      key_env: ["BLENDSWAP_KEY", "BLENDSWAP_API_KEY"],
      capabilities: ["model"],
      description: "Community 3D Blender models from Blend Swap."
    };
  }

  private apiKey(): string | undefined {
    return this.ctx.env.BLENDSWAP_KEY || this.ctx.env.BLENDSWAP_API_KEY;
  }

  credentialStatus(): string {
    return this.apiKey() ? "API key configured." : "Public browse mode. Set BLENDSWAP_KEY or BLENDSWAP_API_KEY.";
  }

  private normalize(raw: BlendSwapRawAsset, fetched: boolean): Asset {
    const rawId = raw.id != null ? String(raw.id) : "asset";
    const id = slug(rawId) || "blendswap-asset";
    const title = asString(raw.title, id);
    const variants: AssetVariant[] = [];
    const files: SourceFile[] = [];
    const downloadData: Record<string, unknown> = {};

    const rawFiles = asArray(raw.files);
    for (const [index, entry] of rawFiles.entries()) {
      const record = asRecord(entry);
      const fileId = asString(record.id);
      const url = asString(record.download_url, asString(record.url, raw.download_url));
      const filename = asString(record.filename, filenameFromUrl(url, `${id}.blend`));
      const vid = fileId && rawFiles.length > 1 ? `file_${slug(fileId)}` : "blend";
      const size = Number(record.size_bytes ?? record.size ?? 0) || undefined;
      const file: SourceFile = { filename, url, size };
      const item = variant(vid, filename, "files", {
        format: "blend",
        filter_key: "format:blend",
        filter_label: "BLEND"
      });
      variants.push(item);
      files.push(file);
      downloadData[item.id] = { kind: "files", files: [file] };
    }

    if (!variants.length) {
      const url = asString(raw.download_url);
      const filename = filenameFromUrl(url, `${id}.blend`);
      const file: SourceFile = { filename, url };
      const item = variant("blend", "Blender .blend Model", "files", {
        format: "blend",
        filter_key: "format:blend",
        filter_label: "BLEND"
      });
      variants.push(item);
      files.push(file);
      downloadData[item.id] = { kind: "files", files: [file] };
    }

    const authorRec = asRecord(raw.author);
    const authorName = asString(authorRec.username, asString(authorRec.name, "Blend Swap Artist"));
    const authorUrl = asString(authorRec.url, "https://blendswap.com");

    const rawLicense = typeof raw.license === "object" && raw.license !== null
      ? asString(raw.license.key, asString(raw.license.name)).toLowerCase()
      : asString(raw.license, "cc-by").toLowerCase();

    let license: LicenseRecord;
    if (rawLicense.includes("cc0") || rawLicense.includes("cc-0") || rawLicense.includes("zero")) {
      license = {
        id: "cc0",
        name: "CC0 1.0 Universal",
        url: "https://creativecommons.org/publicdomain/zero/1.0/",
        attribution_required: false
      };
    } else if (rawLicense.includes("nc")) {
      license = {
        id: "cc-by-nc-4.0",
        name: "CC-BY-NC 4.0",
        url: "https://creativecommons.org/licenses/by-nc/4.0/",
        attribution_required: true
      };
    } else if (rawLicense.includes("sa")) {
      license = {
        id: "cc-by-sa-4.0",
        name: "CC-BY-SA 4.0",
        url: "https://creativecommons.org/licenses/by-sa/4.0/",
        attribution_required: true
      };
    } else {
      license = {
        id: "cc-by-4.0",
        name: "CC-BY 4.0",
        url: "https://creativecommons.org/licenses/by/4.0/",
        attribution_required: true
      };
    }

    return createAsset({
      provider_id: "blendswap",
      provider_name: "Blend Swap",
      id,
      title,
      type: normalizeAssetType("model"),
      url: asString(raw.url, `https://blendswap.com/blend/${id}`),
      thumbnail_url: asString(raw.thumbnail_url),
      description: asString(raw.description, `${title} on Blend Swap`),
      tags: raw.tags ?? [],
      categories: [],
      price: { free: true, credits: 0 },
      authors: [{ name: authorName, url: authorUrl }],
      license,
      attribution_text: `${title} by ${authorName} via Blend Swap (${license.name}).`,
      metadata_source_url: asString(raw.url, `https://blendswap.com/blend/${id}`),
      retrieved_utc: fetched ? this.ctx.now().toISOString() : undefined,
      variants,
      files,
      download_data: downloadData,
      source_metadata: sanitizeRecord(raw)
    });
  }

  async search(params: SearchParams): Promise<SearchPage> {
    if (params.category !== "all" && params.category !== "model") {
      return { items: [], next_cursor: null };
    }

    const page = Number.parseInt(params.cursor ?? "1", 10) || 1;
    const limit = Math.min(params.limit ?? 25, 100);
    const query = params.query.trim();

    const headers: Record<string, string> = {
      Accept: "application/json"
    };
    const key = this.apiKey();
    if (key) {
      headers.Authorization = `Bearer ${key}`;
    }

    let url = `${API_BASE}/assets?page=${page}&per_page=${limit}`;
    if (query) {
      url += `&q=${encodeURIComponent(query)}`;
    }

    const response = await this.ctx.http.json<BlendSwapSearchResponse>(url, { headers });
    const rawList = response.data ?? response.items ?? response.results ?? [];
    const assets = rawList
      .map((entry) => this.normalize(entry, true))
      .filter((asset) => matchesText(asset, params.query));

    const totalCount = response.pagination?.count ?? rawList.length;
    const nextCursor = page * limit < totalCount ? String(page + 1) : null;

    return {
      items: assets,
      next_cursor: nextCursor
    };
  }

  async details(asset: Asset): Promise<Asset> {
    return asset;
  }

  variants(asset: Asset): AssetVariant[] {
    return asset.variants;
  }

  isDetailed(asset: Asset): boolean {
    return asset.variants.length > 0;
  }

  canDownload(asset: Asset): boolean {
    return canDownload(asset);
  }

  async resolveDownload(asset: Asset, variantId: string): Promise<DownloadPlan> {
    const entry = asset.download_data?.[variantId] as Record<string, unknown> | undefined;
    if (!entry || !asset.variants.some((candidate) => candidate.id === variantId)) {
      throw new Error(`Unknown variant for ${asset.provider_id}:${asset.id}: ${variantId}`);
    }
    return {
      kind: "files",
      asset,
      variant: variantId,
      files: entry.files as SourceFile[]
    } satisfies FilesPlan;
  }

  async checkConnection(options: { signal?: AbortSignal } = {}): Promise<{ ok: boolean; message: string }> {
    try {
      await this.ctx.http.json<unknown>(`${API_BASE}/assets?page=1&per_page=1`, { signal: options.signal });
      return { ok: true, message: "Blend Swap API reachable." };
    } catch (error) {
      return { ok: false, message: error instanceof Error ? error.message : String(error) };
    }
  }
}

export const blendswapFactory = (context: ProviderContext): Provider => new BlendSwapProvider(context);
