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
import { filenameFromUrl, slug } from "../util/fs.js";
import { sanitizeRecord } from "../util/sanitize.js";
import { asArray, asRecord, asString, canDownload, matchesText, stripHtml, variant } from "./helpers.js";

const API = "https://commons.wikimedia.org/w/api.php";
const PAGE_SIZE = 24;

interface CommonsPage extends Record<string, unknown> {
  pageid?: number;
  title?: string;
  imageinfo?: Array<Record<string, unknown>>;
  tags?: string[];
  files?: Array<Record<string, unknown>>;
}

interface CommonsResponse {
  query?: {
    pages?: Record<string, CommonsPage> | CommonsPage[];
  };
  continue?: { gsroffset?: number };
  items?: CommonsPage[];
}

export class WikimediaProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "wikimedia",
      name: "Wikimedia Commons",
      website: "https://commons.wikimedia.org/",
      key_env: [],
      capabilities: ["image", "material"],
      description: "Freely licensed images from Wikimedia Commons."
    };
  }

  credentialStatus(): string {
    return "No key required.";
  }

  private filesFrom(raw: CommonsPage, info: Record<string, unknown>, id: string): SourceFile[] {
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
    if (files.length) {
      return files;
    }
    const original = asString(info.url);
    const thumb = asString(info.thumburl);
    if (original.startsWith("https://")) {
      files.push({
        filename: filenameFromUrl(original, `${id}.jpg`),
        url: original,
        role: "orig"
      });
    }
    if (thumb.startsWith("https://") && thumb !== original) {
      files.push({
        filename: filenameFromUrl(thumb, `${id}_preview.jpg`),
        url: thumb,
        role: "preview"
      });
    }
    return files;
  }

  private normalize(raw: CommonsPage, fetched: boolean): Asset {
    const id = String(raw.pageid ?? raw.id ?? "");
    const infos = asArray(raw.imageinfo);
    const info = asRecord(infos[0]);
    const meta = asRecord(info.extmetadata);
    const titleRaw = asString(raw.title, `File:${id}`);
    const title = titleRaw.replace(/^File:/i, "").replace(/\.[a-z0-9]{2,6}$/i, "").replace(/_/g, " ");
    const creator = stripHtml(asString(asRecord(meta.Artist).value, asString(raw.artist)));
    const licenseName = stripHtml(asString(asRecord(meta.LicenseShortName).value));
    const licenseUrl = stripHtml(asString(asRecord(meta.LicenseUrl).value));
    const license = normalizeLicense(licenseName || "Unknown", undefined, licenseUrl || undefined);
    const description = stripHtml(asString(asRecord(meta.ImageDescription).value));
    const files = this.filesFrom(raw, info, id);
    const variants: AssetVariant[] = [];
    const downloadData: Record<string, unknown> = {};
    const seen = new Set<string>();
    for (const [index, file] of files.entries()) {
      const role = asString(file.role, index === 0 ? "orig" : `file-${index}`);
      if (seen.has(role)) {
        continue;
      }
      seen.add(role);
      const entry = variant(role, /^\d+$/.test(role) ? `${role}px resolution` : `${role.toUpperCase()} resolution`, "files", {
        resolution: slug(role)
      });
      variants.push(entry);
      downloadData[entry.id] = { kind: "files", files: [file] };
    }
    const landing = asString(info.descriptionurl, `https://commons.wikimedia.org/wiki/${encodeURIComponent(titleRaw)}`);
    return createAsset({
      provider_id: "wikimedia",
      provider_name: "Wikimedia Commons",
      id,
      title: title || `Commons file ${id}`,
      type: "image",
      url: landing,
      thumbnail_url: asString(info.thumburl, asString(info.url)),
      description: description || `${title || id} at Wikimedia Commons`,
      tags: raw.tags,
      categories: [],
      price: { free: true, credits: 0 },
      authors: creator ? [{ name: creator, url: landing }] : [],
      license,
      licenses: [license],
      selected_license: license,
      attribution_text: `${title || id} by ${creator || "creator not supplied"}, ${license.name}. Source: ${landing}`,
      metadata_source_url: landing,
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
    const url = new URL(API);
    url.searchParams.set("action", "query");
    url.searchParams.set("format", "json");
    url.searchParams.set("generator", "search");
    url.searchParams.set("gsrsearch", `filetype:bitmap ${params.query.trim()}`.trim());
    url.searchParams.set("gsrnamespace", "6");
    url.searchParams.set("gsrlimit", String(PAGE_SIZE));
    url.searchParams.set("gsroffset", String(offset));
    url.searchParams.set("prop", "imageinfo");
    url.searchParams.set("iiprop", "url|size|mime|extmetadata");
    url.searchParams.set("iiurlwidth", "1024");
    const response = await this.ctx.http.json<CommonsResponse>(url.toString(), {
      refresh: params.refresh,
      signal: params.signal
    });
    let pages: CommonsPage[] = [];
    if (Array.isArray(response.items)) {
      pages = response.items;
    } else if (Array.isArray(response.query?.pages)) {
      pages = response.query.pages;
    } else if (response.query?.pages) {
      pages = Object.values(response.query.pages);
    }
    const items = pages
      .map((page) => this.normalize(page, true))
      .filter((asset) => matchesText(asset, params.query))
      .slice(0, params.limit);
    const next = response.continue?.gsroffset ? String(response.continue.gsroffset) : null;
    return { items, next_cursor: next };
  }

  async details(asset: Asset, options: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<Asset> {
    if (!options.refresh && this.isDetailed(asset)) {
      return asset;
    }
    const url = new URL(API);
    url.searchParams.set("action", "query");
    url.searchParams.set("format", "json");
    url.searchParams.set("pageids", asset.id);
    url.searchParams.set("prop", "imageinfo");
    url.searchParams.set("iiprop", "url|size|mime|extmetadata");
    url.searchParams.set("iiurlwidth", "1024");
    const response = await this.ctx.http.json<CommonsResponse>(url.toString(), {
      refresh: options.refresh,
      signal: options.signal
    });
    const pages = Array.isArray(response.query?.pages)
      ? response.query.pages
      : Object.values(response.query?.pages ?? {});
    const page = pages[0];
    if (!page) {
      throw new Error(`Wikimedia page not found: ${asset.id}`);
    }
    return this.normalize(page, true);
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

export const wikimediaFactory = (context: ProviderContext): Provider => new WikimediaProvider(context);
