import { createAsset, normalizeAssetType } from "../asset.js";
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
import { filenameFromUrl, slug } from "../util/fs.js";
import { sanitizeRecord } from "../util/sanitize.js";
import { asArray, asRecord, asString, canDownload, matchesText, variant } from "./helpers.js";

const API = "https://kenney.nl/assets.json";
const PAGE_SIZE = 30;

interface KenneyPack extends Record<string, unknown> {
  id?: string;
  slug?: string;
  title?: string;
  category?: string;
  type?: string;
  description?: string;
  thumbnail?: string;
  url?: string;
  tags?: string[];
  download_url?: string;
  files?: Array<Record<string, unknown>>;
}

export class KenneyProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "kenney",
      name: "Kenney",
      website: "https://kenney.nl/assets",
      key_env: [],
      capabilities: ["model", "audio", "material", "image"],
      description: "CC0 game asset packs from Kenney."
    };
  }

  credentialStatus(): string {
    return "No key required.";
  }

  private normalize(raw: KenneyPack, fetched: boolean): Asset {
    const id = slug(asString(raw.id, asString(raw.slug)));
    let type = asString(raw.type);
    if (!type || type === "3d" || type === "2d") {
      const category = asString(raw.category).toLowerCase();
      type = category === "audio" ? "audio" : category === "3d" ? "model" : category === "2d" ? "image" : type || "model";
    }
    const title = asString(raw.title, id);
    const variants: AssetVariant[] = [];
    const files: SourceFile[] = [];
    const downloadData: Record<string, unknown> = {};
    for (const [index, entry] of asArray(raw.files).entries()) {
      const record = asRecord(entry);
      const url = asString(record.url);
      if (!url.startsWith("https://")) {
        continue;
      }
      const filename = asString(record.filename, filenameFromUrl(url, `${id}.zip`));
      const vid = slug(filename.replace(/\.[^.]+$/, "")) || `file-${index}`;
      const file: SourceFile = { filename, url };
      const format = asString(record.format, filename.split(".").pop() ?? "");
      const item = variant(vid, filename, "files", {
        format,
        filter_key: `format:${slug(format)}`,
        filter_label: format.toUpperCase()
      });
      variants.push(item);
      files.push(file);
      downloadData[item.id] = { kind: "files", files: [file] };
    }
    if (!variants.length) {
      const url = asString(raw.download_url);
      if (url.startsWith("https://")) {
        const filename = filenameFromUrl(url, `${id}.zip`);
        const file: SourceFile = { filename, url };
        const item = variant("zip", "Full asset pack (ZIP)", "files", {
          format: "zip",
          filter_key: "format:zip",
          filter_label: "ZIP"
        });
        variants.push(item);
        files.push(file);
        downloadData[item.id] = { kind: "files", files: [file] };
      }
    }
    return createAsset({
      provider_id: "kenney",
      provider_name: "Kenney",
      id,
      title,
      type: normalizeAssetType(type),
      url: asString(raw.url, `https://kenney.nl/assets/${id}`),
      thumbnail_url: asString(raw.thumbnail, `https://kenney.nl/media/pages/assets/${id}/thumbnail.png`),
      description: asString(raw.description, `${title} by Kenney`),
      tags: raw.tags,
      categories: raw.category ? [String(raw.category)] : [],
      price: { free: true, credits: 0 },
      authors: [{ name: "Kenney", url: "https://kenney.nl/" }],
      license: {
        id: "cc0",
        name: "CC0 1.0",
        url: "https://creativecommons.org/publicdomain/zero/1.0/",
        attribution_required: false
      },
      attribution_text: "Assets by Kenney (https://kenney.nl), CC0.",
      metadata_source_url: asString(raw.url, `https://kenney.nl/assets/${id}`),
      retrieved_utc: fetched ? this.ctx.now().toISOString() : undefined,
      variants,
      files,
      download_data: downloadData,
      source_metadata: sanitizeRecord(raw)
    });
  }

  private async load(): Promise<KenneyPack[]> {
    const response = await this.ctx.http.json<KenneyPack[] | { items?: KenneyPack[]; data?: KenneyPack[] }>(API);
    if (Array.isArray(response)) {
      return response;
    }
    return response.items ?? response.data ?? [];
  }

  async search(params: SearchParams): Promise<SearchPage> {
    const packs = await this.load();
    const assets = packs
      .map((pack) => this.normalize(pack, true))
      .filter((asset) => params.category === "all" || asset.type === params.category)
      .filter((asset) => matchesText(asset, params.query))
      .sort((left, right) => left.title.localeCompare(right.title));
    const offset = Number.parseInt(params.cursor ?? "0", 10) || 0;
    const page = assets.slice(offset, offset + PAGE_SIZE).slice(0, params.limit);
    const next = offset + PAGE_SIZE < assets.length ? String(offset + PAGE_SIZE) : null;
    return { items: page, next_cursor: next };
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
      await this.ctx.http.json<unknown>(API, { signal: options.signal });
      return { ok: true, message: "Kenney asset index reachable." };
    } catch (error) {
      return { ok: false, message: error instanceof Error ? error.message : String(error) };
    }
  }
}

export const kenneyFactory = (context: ProviderContext): Provider => new KenneyProvider(context);
