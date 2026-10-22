import { createAsset, mergeAsset, normalizeAssetType } from "../asset.js";
import type {
  Asset,
  DownloadPlan,
  FilesPlan,
  Provider,
  ProviderContext,
  ProviderDescriptor,
  SearchPage,
  SearchParams,
  AssetVariant,
  SourceFile
} from "../types.js";
import { filenameFromUrl, slug } from "../util/fs.js";
import { canDownload, matchesText, pageSlice, variant } from "./helpers.js";
import { sanitizeRecord } from "../util/sanitize.js";

const API = "https://ambientcg.com/api/v3";
const PAGE_SIZE = 30;

interface RawAsset extends Record<string, unknown> {
  assetId?: string;
  languageIndependentName?: string;
  dataType?: string;
  category?: string;
  tags?: string[];
  previewImage?: string;
  downloadData?: Record<string, unknown>;
}

interface RawResponse {
  assets?: RawAsset[];
  results?: RawAsset[];
  foundAssets?: number | RawAsset[];
}

export class AmbientCgProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "ambientcg",
      name: "ambientCG",
      website: "https://ambientcg.com/",
      key_env: [],
      capabilities: ["material", "model"],
      description: "CC0 PBR materials and a growing collection of 3D models."
    };
  }

  credentialStatus(): string {
    return "No key required.";
  }

  private normalize(raw: RawAsset, fetched: boolean): Asset {
    const id = String(raw.assetId ?? raw.id ?? "");
    const rawType = String(raw.dataType ?? "").toLowerCase();
    const type = rawType.includes("model")
      ? "model"
      : rawType.includes("hdri") || rawType.includes("image")
        ? "image"
        : normalizeAssetType(rawType || "material");
    const downloads = raw.downloadData && typeof raw.downloadData === "object"
      ? raw.downloadData
      : {};
    const files: SourceFile[] = [];
    const variants: AssetVariant[] = [];
    const variantFiles: SourceFile[] = [];
    for (const [name, value] of Object.entries(downloads)) {
      const record = value && typeof value === "object" ? value as Record<string, unknown> : {};
      const url = typeof record.downloadLink === "string"
        ? record.downloadLink
        : typeof record.rawLink === "string"
          ? record.rawLink
          : "";
      if (!url.startsWith("https://")) {
        continue;
      }
      const idPart = slug(name);
      const fallback = `${id}_${idPart}.zip`;
      const file: SourceFile = {
        filename: filenameFromUrl(url, fallback),
        url
      };
      if (typeof record.size === "number") {
        file.size = record.size;
      }
      files.push(file);
      variantFiles.push(file);
      variants.push(variant(idPart, name.replace(/-/g, " "), "files", {
        resolution: /^\d+k/i.test(name) ? name.split("-")[0]?.toLowerCase() : undefined,
        format: name.split("-")[1]?.toLowerCase(),
        filter_key: `resolution:${idPart.split("_")[0]}`,
        filter_label: name.split("-")[0]
      }));
    }
    const downloadData: Record<string, unknown> = {};
    for (const [index, entry] of variants.entries()) {
      const file = variantFiles[index];
      if (file) {
        downloadData[entry.id] = { kind: "files", files: [file] };
      }
    }
    return createAsset({
      provider_id: "ambientcg",
      provider_name: "ambientCG",
      id,
      title: typeof raw.languageIndependentName === "string" ? raw.languageIndependentName : id,
      type,
      url: `https://ambientcg.com/a/${encodeURIComponent(id)}`,
      thumbnail_url: typeof raw.previewImage === "string" ? raw.previewImage : "",
      description: `${id} by ambientCG`,
      tags: raw.tags,
      categories: raw.category ? [String(raw.category)] : [],
      price: { free: true, credits: 0 },
      authors: [{ name: "Lennart Demes", url: "https://ambientcg.com/" }],
      license: {
        id: "cc0",
        name: "CC0 1.0",
        url: "https://creativecommons.org/publicdomain/zero/1.0/",
        attribution_required: false
      },
      attribution_text: `ambientCG asset ${id} (CC0).`,
      metadata_source_url: `https://ambientcg.com/a/${encodeURIComponent(id)}`,
      retrieved_utc: fetched ? this.ctx.now().toISOString() : undefined,
      variants,
      files,
      download_data: downloadData,
      source_metadata: sanitizeRecord(raw)
    });
  }

  async search(params: SearchParams): Promise<SearchPage> {
    if (params.category !== "all" && params.category !== "material" && params.category !== "model") {
      return { items: [], next_cursor: null };
    }
    const offset = Number.parseInt(params.cursor ?? "0", 10) || 0;
    const url = new URL(`${API}/assets`);
    url.searchParams.set("limit", String(PAGE_SIZE));
    url.searchParams.set("offset", String(offset));
    if (params.query.trim()) {
      url.searchParams.set("q", params.query.trim());
    }
    if (params.category === "material") {
      url.searchParams.set("type", "Material");
    } else if (params.category === "model") {
      url.searchParams.set("type", "3DModel");
    }
    const response = await this.ctx.http.json<RawResponse | RawAsset[]>(url.toString(), {
      refresh: params.refresh,
      signal: params.signal
    });
    const rawItems = Array.isArray(response)
      ? response
      : response.assets
        ?? response.results
        ?? (Array.isArray(response.foundAssets) ? response.foundAssets : []);
    const items = rawItems
      .map((raw) => this.normalize(raw, true))
      .filter((asset) => params.category === "all" || asset.type === params.category)
      .filter((asset) => matchesText(asset, params.query))
      .slice(0, params.limit);
    const total = Array.isArray(response) || Array.isArray(response.foundAssets)
      ? undefined
      : response.foundAssets;
    const next = typeof total === "number"
      ? (offset + PAGE_SIZE < total ? String(offset + PAGE_SIZE) : null)
      : (rawItems.length === PAGE_SIZE ? String(offset + PAGE_SIZE) : null);
    return { items, next_cursor: next };
  }

  async details(asset: Asset, options: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<Asset> {
    if (!options.refresh && this.isDetailed(asset)) {
      return asset;
    }
    const url = new URL(`${API}/assets`);
    url.searchParams.set("q", asset.id);
    url.searchParams.set("limit", "10");
    const response = await this.ctx.http.json<RawResponse | RawAsset[]>(url.toString(), {
      refresh: options.refresh,
      signal: options.signal
    });
    const rawItems = Array.isArray(response)
      ? response
      : response.assets
        ?? response.results
        ?? (Array.isArray(response.foundAssets) ? response.foundAssets : []);
    const raw = rawItems.find((item) => String(item.assetId ?? item.id ?? "") === asset.id);
    if (!raw) {
      throw new Error(`ambientCG asset not found: ${asset.id}`);
    }
    return mergeAsset(asset, this.normalize(raw, true));
  }

  variants(asset: Asset): Asset["variants"] {
    return asset.variants;
  }

  isDetailed(asset: Asset): boolean {
    return Boolean(asset.variants.length && Object.keys(asset.download_data ?? {}).length);
  }

  canDownload(asset: Asset): boolean {
    return canDownload(asset);
  }

  async resolveDownload(asset: Asset, variantId: string, options: { signal?: AbortSignal } = {}): Promise<DownloadPlan> {
    const detailed = this.isDetailed(asset) ? asset : await this.details(asset, { signal: options.signal });
    const entry = detailed.download_data?.[variantId] as Record<string, unknown> | undefined;
    if (!entry || !detailed.variants.some((candidate) => candidate.id === variantId)) {
      throw new Error(`Unknown variant for ${detailed.provider_id}:${detailed.id}: ${variantId}`);
    }
    return {
      kind: "files",
      asset: detailed,
      variant: variantId,
      files: entry.files as SourceFile[]
    } satisfies FilesPlan;
  }
}

export const ambientCgFactory = (context: ProviderContext): Provider => new AmbientCgProvider(context);
