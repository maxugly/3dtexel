import { createAsset } from "../asset.js";
import { normalizeLicense } from "../license.js";
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

const API = "https://api.openverse.org/v1";
const PAGE_SIZE = 24;

interface OpenverseItem extends Record<string, unknown> {
  id?: string | number;
  title?: string;
  creator?: string;
  creator_url?: string;
  tags?: Array<{ name?: string } | string>;
  url?: string;
  thumbnail?: string;
  foreign_landing_url?: string;
  license?: string;
  license_version?: string;
  license_url?: string;
  provider?: string;
  source?: string;
  media_type?: string;
}

interface OpenverseResponse {
  result_count?: number;
  page_count?: number;
  page_size?: number;
  results?: OpenverseItem[];
}

export class OpenverseProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "openverse",
      name: "Openverse",
      website: "https://openverse.org/",
      key_env: [],
      capabilities: ["image", "audio"],
      description: "Federated CC-licensed images and audio from Openverse."
    };
  }

  credentialStatus(): string {
    return "No key required.";
  }

  private normalize(raw: OpenverseItem, fetched: boolean): Asset {
    const rawId = String(raw.id ?? "");
    const type = String(raw.media_type ?? "").toLowerCase() === "audio" ? "audio" : "image";
    const creator = asString(raw.creator);
    const licenses = normalizeLicense(raw.license, asString(raw.license_version), asString(raw.license_url));
    const tags = asArray(raw.tags).map((tag) => {
      if (typeof tag === "string") {
        return tag;
      }
      if (tag && typeof tag === "object") {
        return String((tag as Record<string, unknown>).name ?? "");
      }
      return "";
    }).filter(Boolean);
    const source = asString(raw.source, asString(raw.provider, "Openverse"));
    if (source) {
      tags.push(source);
    }
    const landing = asString(raw.foreign_landing_url, asString(raw.url));
    const original = asString(raw.url);
    const preview = asString(raw.thumbnail);
    const variants: AssetVariant[] = [];
    const files: SourceFile[] = [];
    const downloadData: Record<string, unknown> = {};

    if (original) {
      const fallback = `${rawId}_${type}.${type === "audio" ? "mp3" : "jpg"}`;
      const file = {
        filename: filenameFromUrl(original, fallback),
        url: original,
        role: type === "audio" ? "audio" : "original"
      } satisfies SourceFile;
      const id = type === "audio" ? "audio" : "orig";
      variants.push(variant(id, type === "audio" ? "Original audio" : "Original image", "files"));
      files.push(file);
      downloadData[id] = { kind: "files", files: [file] };
    }
    if (preview && preview !== original) {
      const file = {
        filename: filenameFromUrl(preview, `${rawId}_preview.jpg`),
        url: preview,
        role: "preview"
      } satisfies SourceFile;
      variants.push(variant("preview", "Preview image", "files"));
      files.push(file);
      downloadData.preview = { kind: "files", files: [file] };
    }

    return createAsset({
      provider_id: "openverse",
      provider_name: "Openverse",
      id: rawId,
      title: asString(raw.title, `Openverse item ${rawId}`),
      type,
      url: landing,
      thumbnail_url: preview,
      description: `${asString(raw.title, `Openverse item ${rawId}`)} by ${creator || "creator not supplied"} via Openverse (${source}).`,
      tags,
      categories: [source].filter(Boolean),
      price: { free: true, credits: 0 },
      authors: creator ? [{ name: creator, url: asString(raw.creator_url) || undefined }] : [],
      license: licenses,
      licenses: [licenses],
      selected_license: licenses,
      attribution_text: `${asString(raw.title, rawId)} by ${creator || "creator not supplied"}, ${licenses.name}. Source: ${landing}`,
      metadata_source_url: landing,
      retrieved_utc: fetched ? this.ctx.now().toISOString() : undefined,
      variants,
      files,
      download_data: downloadData,
      source_metadata: sanitizeRecord(raw)
    });
  }

  async search(params: SearchParams): Promise<SearchPage> {
    if (params.category === "material") {
      return this.searchType("image", params);
    }
    if (params.category === "model") {
      return { items: [], next_cursor: null };
    }
    if (params.category === "audio") {
      return this.searchType("audio", params);
    }
    if (params.category === "image") {
      return this.searchType("image", params);
    }
    const [images, audio] = await Promise.all([
      this.searchType("image", params),
      this.searchType("audio", params)
    ]);
    const combined = [...images.items, ...audio.items]
      .sort((left, right) => left.title.localeCompare(right.title));
    return { items: combined.slice(0, params.limit), next_cursor: audio.next_cursor ?? images.next_cursor };
  }

  private async searchType(type: "image" | "audio", params: SearchParams): Promise<SearchPage> {
    const page = Math.max(1, Number.parseInt(params.cursor ?? "1", 10) || 1);
    const url = new URL(`${API}/${type}s/`);
    if (params.query.trim()) {
      url.searchParams.set("q", params.query.trim());
    }
    url.searchParams.set("page", String(page));
    url.searchParams.set("page_size", String(PAGE_SIZE));
    const response = await this.ctx.http.json<OpenverseResponse>(url.toString(), {
      refresh: params.refresh,
      signal: params.signal
    });
    const items = (response.results ?? [])
      .map((raw) => this.normalize({ ...raw, media_type: type }, true))
      .filter((asset) => matchesText(asset, params.query))
      .slice(0, params.limit);
    const total = Number(response.result_count ?? 0);
    const next = page * PAGE_SIZE < total ? String(page + 1) : null;
    return { items, next_cursor: next };
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
    const selected = asset.variants.find((candidate) => candidate.id === variantId);
    const entry = asset.download_data?.[variantId] as Record<string, unknown> | undefined;
    if (!selected || !entry) {
      throw new Error(`Unknown variant for ${asset.provider_id}:${asset.id}: ${variantId}`);
    }
    return {
      kind: "files",
      asset,
      variant: variantId,
      files: entry.files as SourceFile[]
    } satisfies FilesPlan;
  }
}

export const openverseFactory = (context: ProviderContext): Provider => new OpenverseProvider(context);
