import { createAsset, mergeAsset } from "../asset.js";
import type {
  Asset,
  AssetVariant,
  DownloadPlan,
  FilesPlan,
  Provider,
  ProviderContext,
  ProviderDescriptor,
  SearchPage,
  SearchParams,
  SourceFile
} from "../types.js";
import { filenameFromUrl } from "../util/fs.js";
import { sanitizeRecord } from "../util/sanitize.js";
import { asArray, asString, canDownload, matchesText, variant } from "./helpers.js";

const API = "https://collectionapi.metmuseum.org/public/collection/v1";
const PAGE_SIZE = 10;

interface MetRaw extends Record<string, unknown> {
  objectID?: number | string;
  title?: string;
  artistDisplayName?: string;
  objectDate?: string;
  medium?: string;
  isPublicDomain?: boolean;
  objectURL?: string;
  primaryImage?: string;
  primaryImageSmall?: string;
  tags?: Array<string | { term?: string }>;
  files?: Array<Record<string, unknown>>;
}

interface MetSearchResponse {
  total?: number;
  objectIDs?: number[] | null;
  items?: MetRaw[];
}

export class MetMuseumProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "met_museum",
      name: "The Metropolitan Museum of Art",
      website: "https://www.metmuseum.org/",
      key_env: [],
      capabilities: ["image"],
      description: "Public-domain artworks from The Metropolitan Museum of Art."
    };
  }

  credentialStatus(): string {
    return "No key required.";
  }

  private filesFrom(raw: MetRaw, id: string): SourceFile[] {
    const files: SourceFile[] = [];
    if (Array.isArray(raw.files)) {
      for (const entry of raw.files) {
        const url = asString(entry.url);
        if (!url.startsWith("https://")) {
          continue;
        }
        const file: SourceFile = {
          filename: asString(entry.filename, filenameFromUrl(url, `${id}.jpg`)),
          url
        };
        const resolution = asString(entry.resolution);
        if (resolution) {
          file.role = resolution;
        }
        files.push(file);
      }
    }
    if (!files.length) {
      const original = asString(raw.primaryImage);
      const small = asString(raw.primaryImageSmall);
      if (original.startsWith("https://")) {
        files.push({ filename: `${id}_orig.jpg`, url: original, role: "orig" });
      }
      if (small.startsWith("https://") && small !== original) {
        files.push({ filename: `${id}_small.jpg`, url: small, role: "small" });
      }
    }
    return files;
  }

  private normalize(raw: MetRaw, fetched: boolean): Asset {
    const id = String(raw.objectID ?? raw.id ?? "");
    const files = this.filesFrom(raw, id);
    const variants: AssetVariant[] = [];
    const downloadData: Record<string, unknown> = {};
    for (const [index, file] of files.entries()) {
      const role = asString(file.role, index === 0 ? "orig" : "small");
      const existing = variants.find((entry) => entry.id === role);
      if (existing) {
        continue;
      }
      const entry = variant(role, `${role.toUpperCase()} resolution`, "files", {
        resolution: role
      });
      variants.push(entry);
      downloadData[entry.id] = { kind: "files", files: [file] };
    }
    const tags = asArray(raw.tags).map((tag) => {
      if (typeof tag === "string") {
        return tag;
      }
      if (tag && typeof tag === "object") {
        return String((tag as Record<string, unknown>).term ?? "");
      }
      return "";
    }).filter(Boolean);
    const publicDomain = raw.isPublicDomain === true;
    const creator = asString(raw.artistDisplayName);
    const title = asString(raw.title, `Met object ${id}`);
    const medium = asString(raw.medium);
    return createAsset({
      provider_id: "met_museum",
      provider_name: "The Metropolitan Museum of Art",
      id,
      title,
      type: "image",
      url: asString(raw.objectURL, `https://www.metmuseum.org/art/collection/search/${id}`),
      thumbnail_url: asString(raw.primaryImageSmall, asString(raw.primaryImage)),
      description: [medium, asString(raw.objectDate)].filter(Boolean).join(", "),
      tags,
      categories: [],
      price: { free: publicDomain, credits: 0 },
      authors: creator ? [{ name: creator, url: "https://www.metmuseum.org/" }] : [],
      license: {
        id: publicDomain ? "cc0" : "unknown",
        name: publicDomain ? "CC0 1.0" : "Unknown",
        url: publicDomain ? "https://creativecommons.org/publicdomain/zero/1.0/" : undefined,
        attribution_required: publicDomain ? false : null
      },
      attribution_text: creator
        ? `${title} by ${creator} - The Metropolitan Museum of Art${publicDomain ? " (CC0)" : " (license unknown)"}`
        : `${title} - The Metropolitan Museum of Art${publicDomain ? " (CC0)" : " (license unknown)"}`,
      metadata_source_url: asString(raw.objectURL, `${API}/objects/${id}`),
      retrieved_utc: fetched ? this.ctx.now().toISOString() : undefined,
      variants,
      files,
      download_data: downloadData,
      source_metadata: sanitizeRecord(raw)
    });
  }

  async search(params: SearchParams): Promise<SearchPage> {
    if (params.category === "audio" || params.category === "model") {
      return { items: [], next_cursor: null };
    }
    const offset = Number.parseInt(params.cursor ?? "0", 10) || 0;
    const url = new URL(`${API}/search`);
    url.searchParams.set("q", params.query.trim() || "*");
    url.searchParams.set("hasImages", "true");
    const response = await this.ctx.http.json<MetSearchResponse>(url.toString(), {
      refresh: params.refresh,
      signal: params.signal
    });
    let assets: Asset[] = [];
    if (Array.isArray(response.items)) {
      assets = response.items.map((raw) => this.normalize(raw, true));
    } else {
      const ids = (response.objectIDs ?? []).slice(offset, offset + PAGE_SIZE);
      const details = await Promise.all(ids.map(async (id) => {
        try {
          return await this.fetchObject(id, optionsFrom(params));
        } catch {
          return null;
        }
      }));
      assets = details.filter((asset): asset is Asset => Boolean(asset));
    }
    const items = assets
      .filter((asset) => params.category === "all" || params.category === "image" || params.category === "material")
      .filter((asset) => matchesText(asset, params.query))
      .slice(0, params.limit);
    const total = Number(response.total ?? 0);
    const next = Array.isArray(response.items)
      ? (assets.length === PAGE_SIZE ? String(offset + PAGE_SIZE) : null)
      : (offset + PAGE_SIZE < total ? String(offset + PAGE_SIZE) : null);
    return { items, next_cursor: next };
  }

  private async fetchObject(id: number | string, options: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<Asset> {
    const raw = await this.ctx.http.json<MetRaw>(`${API}/objects/${encodeURIComponent(String(id))}`, {
      refresh: options.refresh,
      signal: options.signal
    });
    if (!raw || raw.objectID === undefined) {
      throw new Error(`Met object not found: ${id}`);
    }
    return this.normalize(raw, true);
  }

  async details(asset: Asset, options: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<Asset> {
    if (!options.refresh && this.isDetailed(asset)) {
      return asset;
    }
    const fresh = await this.fetchObject(asset.id, options);
    return mergeAsset(asset, fresh);
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

function optionsFrom(params: SearchParams): { refresh?: boolean; signal?: AbortSignal } {
  return { refresh: params.refresh, signal: params.signal };
}

export const metMuseumFactory = (context: ProviderContext): Provider => new MetMuseumProvider(context);
