import { createAsset, mergeAsset, normalizeAssetType } from "../asset.js";
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

const API = "https://images-api.nasa.gov";
const PAGE_SIZE = 24;

interface NasaManifest {
  collection?: {
    items?: Array<{ href?: string }>;
    links?: Array<{ rel?: string; href?: string }>;
  };
}

interface NasaSearch {
  collection?: {
    items?: Array<{
      href?: string;
      data?: Array<Record<string, unknown>>;
      links?: Array<Record<string, unknown>>;
    }>;
    links?: Array<Record<string, unknown>>;
    metadata?: { total_hits?: number };
  };
}

function nasaType(value: string): Asset["type"] {
  const lower = value.toLowerCase();
  if (lower === "audio") {
    return "audio";
  }
  if (lower === "3d" || lower === "model") {
    return "model";
  }
  return normalizeAssetType(lower);
}

function mediaVariant(path: string, type: Asset["type"]): { id: string; label: string; format: string } {
  const filename = path.split("/").pop()?.split("?")[0] ?? "";
  const ext = filename.split(".").pop()?.toLowerCase() ?? "";
  const size = /~(orig|large|medium|small)(?=\.)/i.exec(filename)?.[1]?.toLowerCase();
  if (type === "image" && size) {
    return { id: size, label: `${size.toUpperCase()} image`, format: ext };
  }
  if (type === "audio" && size === "orig") {
    return { id: ext || "orig", label: `${ext.toUpperCase()} original`, format: ext };
  }
  if (type === "audio" && filename.includes("~")) {
    const quality = /~([^./]+)(?=\.)/.exec(filename)?.[1] ?? "";
    const id = slug(quality || ext);
    return { id, label: `${quality.toUpperCase()} ${ext.toUpperCase()}`, format: ext };
  }
  if (type === "model" && ext === "glb") {
    return { id: "glb", label: "GLB model", format: ext };
  }
  if (type === "model" && ext === "gltf") {
    return { id: "gltf", label: "glTF model", format: ext };
  }
  if (type === "model" && ext === "zip") {
    const base = filename.replace(/\.zip$/i, "");
    return { id: `${slug(base)}-zip`, label: `${base.replace(/[_-]/g, " ")} (ZIP)`, format: ext };
  }
  const base = filename.replace(/\.[^.]+$/, "");
  return { id: slug(base) || ext || "file", label: filename, format: ext };
}

export class NasaProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "nasa",
      name: "NASA Multimedia",
      website: "https://images.nasa.gov/",
      key_env: [],
      capabilities: ["image", "audio", "model"],
      description: "NASA images, audio, and 3D models from the NASA Image and Video Library."
    };
  }

  credentialStatus(): string {
    return "No key required.";
  }

  private normalize(raw: Record<string, unknown>, fetched: boolean): Asset {
    const id = asString(raw.nasa_id, asString(raw.id));
    const type = nasaType(asString(raw.media_type, asString(raw.type, "image")));
    const center = asString(raw.center, "NASA");
    const creator = asString(raw.photographer, asString(raw.secondary_creator));
    const authors = creator
      ? [{ name: creator }]
      : [{ name: `NASA / ${center}`, url: "https://www.nasa.gov/" }];
    const credit = type === "audio" ? "Audio" : type === "model" ? "3D model" : "Image";
    return createAsset({
      provider_id: "nasa",
      provider_name: "NASA Multimedia",
      id,
      title: asString(raw.title, `NASA asset ${id}`),
      type,
      url: `https://images.nasa.gov/details/${encodeURIComponent(id)}`,
      thumbnail_url: asString(raw.thumbnail),
      description: asString(raw.description),
      tags: raw.keywords ?? raw.tags,
      categories: center ? [center] : [],
      price: { free: true, credits: 0 },
      authors,
      license: {
        id: "nasa-media-guidelines",
        name: "NASA Media Guidelines",
        url: "https://www.nasa.gov/nasa-brand-center/images-and-media/",
        attribution_required: true
      },
      attribution_text: `${credit} credit: ${creator || `NASA / ${center}`}`,
      metadata_source_url: `${API}/asset/${encodeURIComponent(id)}`,
      retrieved_utc: fetched ? this.ctx.now().toISOString() : undefined,
      variants: [],
      source_metadata: sanitizeRecord(raw)
    });
  }

  async search(params: SearchParams): Promise<SearchPage> {
    const page = Math.max(1, Number.parseInt(params.cursor ?? "1", 10) || 1);
    const media = params.category === "image" || params.category === "material"
      ? "image"
      : params.category === "audio"
        ? "audio"
        : params.category === "model"
          ? "3d"
          : "image,audio,3d";
    let query = params.query.trim();
    if (!query) {
      query = params.category === "audio"
        ? "apollo"
        : params.category === "model"
          ? "rover"
          : params.category === "material"
            ? "surface texture"
            : "earth";
    }
    const url = new URL(`${API}/search`);
    url.searchParams.set("q", query);
    url.searchParams.set("media_type", media);
    url.searchParams.set("page", String(page));
    const response = await this.ctx.http.json<NasaSearch>(url.toString(), {
      refresh: params.refresh,
      signal: params.signal
    });
    const items: Asset[] = [];
    for (const item of response.collection?.items ?? []) {
      const meta = asRecord(item.data?.[0]);
      if (!meta.nasa_id) {
        continue;
      }
      const thumb = (item.links ?? []).find((link) => {
        const record = asRecord(link);
        return record.rel === "preview" || String(record.href ?? "").includes("~thumb");
      });
      const asset = this.normalize({
        ...meta,
        thumbnail: asString(asRecord(thumb).href)
      }, true);
      if (params.category !== "all" && asset.type !== params.category && params.category !== "material") {
        continue;
      }
      if (!matchesText(asset, params.query)) {
        continue;
      }
      items.push(asset);
    }
    const nextLink = (response.collection?.links ?? []).find((link) => asRecord(link).rel === "next");
    const nextPage = nextLink
      ? /[?&]page=([0-9]+)/.exec(asString(asRecord(nextLink).href))?.[1]
      : undefined;
    const total = Number(response.collection?.metadata?.total_hits ?? 0);
    const next = nextPage ?? (total > page * PAGE_SIZE ? String(page + 1) : null);
    return { items: items.slice(0, params.limit), next_cursor: next };
  }

  private parseManifest(asset: Asset, manifest: NasaManifest): Asset {
    const variants: AssetVariant[] = [];
    const files: SourceFile[] = [];
    const downloadData: Record<string, unknown> = {};
    const seen = new Set<string>();
    for (const rawItem of manifest.collection?.items ?? []) {
      const href = asString(rawItem.href);
      if (!href.startsWith("https://")) {
        continue;
      }
      if (/~thumb\./i.test(href) || /metadata\.json$/i.test(href)) {
        continue;
      }
      const filename = filenameFromUrl(href, `${asset.id}.bin`);
      const meta = mediaVariant(href, asset.type);
      const id = seen.has(meta.id) ? `${meta.id}-${seen.size + 1}` : meta.id;
      seen.add(id);
      const file: SourceFile = { filename, url: href };
      const entry = variant(id, meta.label, "files", {
        format: meta.format,
        filter_key: `format:${slug(meta.format)}`,
        filter_label: meta.format.toUpperCase()
      });
      variants.push(entry);
      files.push(file);
      downloadData[entry.id] = { kind: "files", files: [file] };
    }
    if (!variants.length) {
      throw new Error(`No downloadable files in NASA manifest for ${asset.id}`);
    }
    return mergeAsset(asset, {
      ...asset,
      variants,
      files,
      download_data: downloadData
    });
  }

  async details(asset: Asset, options: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<Asset> {
    if (!options.refresh && this.isDetailed(asset)) {
      return asset;
    }
    const manifest = await this.ctx.http.json<NasaManifest>(`${API}/asset/${encodeURIComponent(asset.id)}`, {
      refresh: options.refresh,
      signal: options.signal
    });
    return this.parseManifest(asset, manifest);
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
      files: asArray(entry.files) as SourceFile[]
    } satisfies FilesPlan;
  }
}

export const nasaFactory = (context: ProviderContext): Provider => new NasaProvider(context);
