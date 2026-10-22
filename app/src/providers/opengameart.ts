import { createAsset, mergeAsset } from "../asset.js";
import type {
  Asset,
  AssetType,
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
import { slug } from "../util/fs.js";
import { sanitizeRecord } from "../util/sanitize.js";
import { canDownload, variant } from "./helpers.js";
import { parseAssetPage, parseSearchPage, preferredLicense, type OgaDetails } from "./opengameart-parser.js";

const BASE = "https://opengameart.org";

export class OpenGameArtProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "opengameart",
      name: "OpenGameArt.org",
      website: "https://opengameart.org/",
      key_env: [],
      capabilities: ["material", "model", "audio", "image"],
      description: "Community-created game art, textures, models, and audio from OpenGameArt.org."
    };
  }

  credentialStatus(): string {
    return "No key required.";
  }

  private normalize(raw: {
    id: string;
    title: string;
    type: AssetType;
    url: string;
    thumbnail: string;
    art_type: string;
    authors: Array<{ name: string; url?: string }>;
    licenses: LicenseRecord[];
    selected: LicenseRecord;
  }, fetched: boolean): Asset {
    return createAsset({
      provider_id: "opengameart",
      provider_name: "OpenGameArt.org",
      id: raw.id,
      title: raw.title,
      type: raw.type,
      url: raw.url,
      thumbnail_url: raw.thumbnail,
      description: `${raw.title} (${raw.art_type || raw.type}) on OpenGameArt.org.`,
      tags: [],
      categories: raw.art_type ? [raw.art_type] : [],
      price: { free: true, credits: 0 },
      authors: raw.authors,
      license: raw.selected,
      licenses: raw.licenses,
      selected_license: raw.selected,
      attribution_text: `${raw.title} by ${raw.authors.map((author) => author.name).join(", ") || "creator not supplied"}, ${raw.selected.name}. Source: ${raw.url}`,
      metadata_source_url: raw.url,
      retrieved_utc: fetched ? this.ctx.now().toISOString() : undefined,
      variants: [],
      source_metadata: { details_loaded: false }
    });
  }

  async search(params: SearchParams): Promise<SearchPage> {
    const page = Math.max(0, Number.parseInt(params.cursor ?? "0", 10) || 0);
    const url = new URL(`${BASE}/art-search`);
    url.searchParams.set("keys", params.query.trim());
    if (page > 0) {
      url.searchParams.set("page", String(page));
    }
    const html = await this.ctx.http.text(url.toString(), {
      refresh: params.refresh,
      signal: params.signal
    });
    const parsed = parseSearchPage(html);
    const items = parsed.items
      .map((item) => this.normalize({
        ...item,
        thumbnail: item.thumbnail
      }, true))
      .filter((asset) => params.category === "all" || asset.type === params.category)
      .slice(0, params.limit);
    return { items, next_cursor: parsed.next_cursor };
  }

  private buildFiles(details: OgaDetails): {
    variants: AssetVariant[];
    download_data: Record<string, unknown>;
  } {
    const variants: AssetVariant[] = [];
    const downloadData: Record<string, unknown> = {};
    const used = new Set<string>();
    for (const file of details.files ?? []) {
      const extension = file.filename.split(".").pop()?.toLowerCase() ?? "file";
      const base = file.filename.replace(/\.[^.]+$/, "");
      let id = slug(base) || extension;
      if (used.has(id)) {
        id = `${id}-${extension}`;
      }
      let counter = 2;
      while (used.has(id)) {
        id = `${slug(base) || extension}-${extension}-${counter}`;
        counter += 1;
      }
      used.add(id);
      const entry = variant(id, file.filename, "files", {
        format: extension,
        filter_key: `format:${slug(extension)}`,
        filter_label: extension.toUpperCase()
      });
      variants.push(entry);
      downloadData[entry.id] = { kind: "files", files: [file] };
    }
    return { variants, download_data: downloadData };
  }

  async details(asset: Asset, options: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<Asset> {
    if (!options.refresh && this.isDetailed(asset)) {
      return asset;
    }
    const html = await this.ctx.http.text(asset.url, {
      refresh: options.refresh,
      signal: options.signal
    });
    const details = parseAssetPage(html, asset.url);
    const licenses = details.licenses?.length ? details.licenses : asset.licenses ?? [asset.license];
    const license = details.selected ?? preferredLicense(licenses);
    const files = this.buildFiles(details);
    const type: AssetType = asset.type === "material" && details.type === "image"
      ? "material"
      : details.type ?? asset.type;
    const authors = details.authors?.length ? details.authors : asset.authors;
    const title = details.title || asset.title;
    const description = details.description || asset.description;
    const tags = details.tags?.length ? details.tags : asset.tags;
    return mergeAsset(asset, {
      ...asset,
      title,
      type,
      description,
      tags,
      authors,
      license,
      licenses,
      selected_license: license,
      attribution_text: details.attribution_text
        || `${title} by ${authors.map((author) => author.name).join(", ") || "creator not supplied"}, ${license.name}. Source: ${asset.url}`,
      variants: files.variants,
      files: (details.files ?? []) as SourceFile[],
      download_data: files.download_data,
      source_metadata: {
        ...(asset.source_metadata ?? {}),
        ...sanitizeRecord({ details }),
        details_loaded: true
      }
    });
  }

  variants(asset: Asset): AssetVariant[] {
    return asset.variants;
  }

  isDetailed(asset: Asset): boolean {
    return asset.source_metadata?.details_loaded === true || asset.variants.length > 0;
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

  async checkConnection(options: { signal?: AbortSignal } = {}): Promise<{ ok: boolean; message: string }> {
    try {
      await this.ctx.http.text(`${BASE}/art-search?keys=`, { signal: options.signal });
      return { ok: true, message: "OpenGameArt search reachable." };
    } catch (error) {
      return { ok: false, message: error instanceof Error ? error.message : String(error) };
    }
  }
}

export const openGameArtFactory = (context: ProviderContext): Provider => new OpenGameArtProvider(context);
