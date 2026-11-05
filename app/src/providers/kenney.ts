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

const API = "https://kenney.nl/assets";
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

  async search(params: SearchParams): Promise<SearchPage> {
    const page = Math.max(1, Number.parseInt(params.cursor ?? "1", 10) || 1);
    const kind = { model: "3D", image: "2D", audio: "Audio", material: "Textures" }[params.category as "model" | "image" | "audio" | "material"];
    const url = new URL(API + (kind ? `/category:${kind}` : "") + (page > 1 ? `/page:${page}` : ""));
    if (params.query.trim()) url.searchParams.set("search", params.query.trim());
    const html = await this.ctx.http.text(url.toString(), { signal: params.signal, refresh: params.refresh });
    const cards = html.split(/<div\s+class=['"]asset['"]\s*>/i).slice(1);
    const items: Asset[] = [];
    for (const card of cards) {
      const target = card.match(/href=['"](https:\/\/kenney\.nl\/assets\/[^'"?#]+)['"]/i)?.[1];
      if (!target) continue;
      const name = card.match(/<h2[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i)?.[1]?.replace(/<[^>]+>/g, "").trim() ?? "";
      const categories = [...card.matchAll(/category:([^'"?#/]+)/gi)].map(m => decodeURIComponent(m[1]!));
      const type = kind === "3D" || categories.includes("3D") ? "model" : kind === "Textures" || categories.includes("Textures") ? "material" : kind === "Audio" || categories.includes("Audio") ? "audio" : "image";
      const thumbnail = card.match(/background-image:url\(["']?([^"')]+)["']?\)/i)?.[1];
      items.push(this.normalize({ id: target.split("/").pop(), title: name, url: target, thumbnail, type }, true));
    }
    return { items: items.slice(0, params.limit), next_cursor: html.includes(`page:${page + 1}`) ? String(page + 1) : null };
  }

  async details(asset: Asset, options: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<Asset> {
    if (!options.refresh && this.isDetailed(asset)) return asset;
    const url = new URL(asset.url ?? "");
    if (url.protocol !== "https:" || url.hostname !== "kenney.nl" || !url.pathname.startsWith("/assets/")) throw new Error("Invalid Kenney asset page.");
    const html = await this.ctx.http.text(url.toString(), { refresh: options.refresh, signal: options.signal });
    if (!/creativecommons\.org\/publicdomain\/zero\/1\.0/i.test(html)) throw new Error("Kenney page did not confirm CC0 licensing.");
    const archive = html.match(/href=['"](https:\/\/kenney\.nl\/media\/[^'"?#]+\.zip)['"]/i)?.[1];
    if (archive) return this.normalize({ id: asset.id, title: asset.title, url: asset.url, thumbnail: asset.thumbnail_url, type: asset.type, download_url: archive }, true);
    const downloadId = html.match(/data-download-id=['"]([0-9a-f]+)['"]/i)?.[1];
    if (!downloadId) throw new Error("Kenney did not provide a download on this page.");
    return { ...asset, variants: [variant("zip", "Full asset pack (ZIP)", "files", { format:"zip" })], download_data: { zip: { kind:"files", download_id:downloadId } } };
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

  async resolveDownload(asset: Asset, variantId: string, options: { signal?: AbortSignal; preview?: boolean } = {}): Promise<DownloadPlan> {
    asset = await this.details(asset, { signal: options.signal });
    const entry = asset.download_data?.[variantId] as Record<string, unknown> | undefined;
    if (!entry || !asset.variants.some((candidate) => candidate.id === variantId)) throw new Error(`Unknown variant for ${asset.provider_id}:${asset.id}: ${variantId}`);
    if (typeof entry.download_id === "string") {
      if (options.preview) return { kind:"files", asset, variant:variantId, files:[] } satisfies FilesPlan;
      const result = await this.ctx.http.json<{url?: string}>(`https://kenney.nl/download-link/${entry.download_id}`, { headers: { Referer: asset.url ?? "https://kenney.nl/assets", Origin: "https://kenney.nl", "User-Agent": "Mozilla/5.0" }, cache:false, refresh:true, signal:options.signal });
      if (!result.url?.startsWith("https://")) throw new Error("Kenney did not issue a secure download link.");
      return {kind:"files", asset, variant:variantId, files:[{filename:`${asset.id}.zip`,url:result.url}]} satisfies FilesPlan;
    }
    return { kind: "files", asset, variant: variantId, files: entry.files as SourceFile[] } satisfies FilesPlan;
  }

  async checkConnection(options: { signal?: AbortSignal } = {}): Promise<{ ok: boolean; message: string }> {
    try {
      await this.ctx.http.text(API, { signal: options.signal });
      return { ok: true, message: "Kenney asset index reachable." };
    } catch (error) {
      return { ok: false, message: error instanceof Error ? error.message : String(error) };
    }
  }
}

export const kenneyFactory = (context: ProviderContext): Provider => new KenneyProvider(context);
