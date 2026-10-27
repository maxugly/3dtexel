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

const API_BASE = "https://api.cgtrader.com/v1";

interface CGTraderRawFile extends Record<string, unknown> {
  id?: number | string;
  format?: string;
  filename?: string;
  size?: number;
  download_url?: string;
}

interface CGTraderRawAsset extends Record<string, unknown> {
  id?: number | string;
  title?: string;
  slug?: string;
  category?: string;
  user?: { username?: string; profile_url?: string };
  price?: number;
  free?: boolean;
  polygons?: number;
  vertices?: number;
  description?: string;
  tags?: string[];
  thumbnail?: string;
  license?: { type?: string; name?: string; url?: string };
  files?: CGTraderRawFile[];
}

interface CGTraderSearchResponse {
  total?: number;
  page?: number;
  per_page?: number;
  data?: CGTraderRawAsset[];
  items?: CGTraderRawAsset[];
}

export class CGTraderProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "cgtrader",
      name: "CGTrader",
      website: "https://www.cgtrader.com",
      key_env: ["CGTRADER_API_TOKEN", "CGTRADER_CLIENT_ID"],
      capabilities: ["model"],
      description: "Free and royalty-free 3D models from CGTrader."
    };
  }

  private apiKey(): string | undefined {
    return this.ctx.env.CGTRADER_API_TOKEN || this.ctx.env.CGTRADER_CLIENT_ID;
  }

  credentialStatus(): string {
    return this.apiKey() ? "API key configured." : "Public browse mode. Set CGTRADER_API_TOKEN or CGTRADER_CLIENT_ID.";
  }

  private normalize(raw: CGTraderRawAsset, fetched: boolean): Asset {
    const rawId = raw.id != null ? String(raw.id) : (raw.slug ?? "asset");
    const id = slug(rawId) || "cgtrader-asset";
    const title = asString(raw.title, id);
    const variants: AssetVariant[] = [];
    const files: SourceFile[] = [];
    const downloadData: Record<string, unknown> = {};

    const rawFiles = asArray(raw.files);
    for (const entry of rawFiles) {
      const record = asRecord(entry);
      const fileId = asString(record.id);
      const format = asString(record.format, "obj").toLowerCase();
      const url = asString(record.download_url);
      const filename = asString(record.filename, filenameFromUrl(url, `${id}.${format}`));
      const vid = fileId ? `file_${slug(fileId)}` : slug(format);
      const size = Number(record.size ?? 0) || undefined;
      const file: SourceFile = { filename, url, size };
      const item = variant(vid, `${format.toUpperCase()} Model`, "files", {
        format,
        filter_key: `format:${format}`,
        filter_label: format.toUpperCase()
      });
      variants.push(item);
      files.push(file);
      downloadData[item.id] = { kind: "files", files: [file] };
    }

    if (!variants.length) {
      const fallbackUrl = asString(raw.download_url);
      const filename = filenameFromUrl(fallbackUrl, `${id}.obj`);
      const file: SourceFile = { filename, url: fallbackUrl };
      const item = variant("model", "3D Model", "files", {
        format: "obj",
        filter_key: "format:obj",
        filter_label: "OBJ"
      });
      variants.push(item);
      files.push(file);
      downloadData[item.id] = { kind: "files", files: [file] };
    }

    const userRec = asRecord(raw.user);
    const authorName = asString(userRec.username, "CGTrader Artist");
    const authorUrl = asString(userRec.profile_url, "https://www.cgtrader.com");

    const license: LicenseRecord = {
      id: "royalty-free",
      name: "CGTrader Royalty Free",
      url: "https://www.cgtrader.com/pages/terms-and-conditions#royalty-free-license",
      attribution_required: true
    };

    const rawSlug = asString(raw.slug, id);
    const modelUrl = `https://www.cgtrader.com/3d-models/${rawSlug}`;

    return createAsset({
      provider_id: "cgtrader",
      provider_name: "CGTrader",
      id,
      title,
      type: normalizeAssetType("model"),
      url: modelUrl,
      thumbnail_url: asString(raw.thumbnail),
      description: asString(raw.description, `${title} on CGTrader`),
      tags: raw.tags ?? [],
      categories: raw.category ? [raw.category] : [],
      price: { free: true, credits: 0 },
      authors: [{ name: authorName, url: authorUrl }],
      license,
      attribution_text: `${title} by ${authorName} via CGTrader (${license.name}).`,
      metadata_source_url: modelUrl,
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

    let url = `${API_BASE}/models?page=${page}&per_page=${limit}&free=1`;
    if (query) {
      url += `&q=${encodeURIComponent(query)}`;
    }

    const response = await this.ctx.http.json<CGTraderSearchResponse>(url, { headers });
    const rawList = response.data ?? response.items ?? [];
    const assets = rawList
      .map((entry) => this.normalize(entry, true))
      .filter((asset) => matchesText(asset, params.query));

    const totalCount = response.total ?? rawList.length;
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

  isDetailed(_asset: Asset): boolean {
    return true;
  }

  canDownload(asset: Asset): boolean {
    return canDownload(asset);
  }

  async resolveDownload(asset: Asset, variantId?: string): Promise<DownloadPlan> {
    const target = variantId ?? asset.variants[0]?.id;
    if (!target) {
      throw new Error(`Asset ${asset.id} offers no downloadable variants.`);
    }

    const data = asset.download_data?.[target] as FilesPlan | undefined;
    if (data?.kind === "files" && data.files?.length) {
      return data;
    }

    throw new Error(`Variant ${target} is not recognized for asset ${asset.id}`);
  }
}

export const cgtraderFactory = (ctx: ProviderContext): Provider => new CGTraderProvider(ctx);
