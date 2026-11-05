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

const API_BASE = "https://api.sketchfab.com/v3";

interface SketchfabUser {
  username?: string;
  displayName?: string;
  profileUrl?: string;
}

interface SketchfabLicense {
  label?: string;
  fullName?: string;
  slug?: string;
  url?: string;
}

interface SketchfabThumbnail {
  url?: string;
  width?: number;
  height?: number;
}

interface SketchfabRawAsset extends Record<string, unknown> {
  uid?: string;
  name?: string;
  description?: string;
  viewerUrl?: string;
  publishedAt?: string;
  user?: SketchfabUser;
  license?: SketchfabLicense;
  isDownloadable?: boolean;
  thumbnails?: { images?: SketchfabThumbnail[] };
}

interface SketchfabSearchResponse {
  results?: SketchfabRawAsset[];
  next?: string | null;
  previous?: string | null;
}

interface SketchfabDownloadFormat {
  url?: string;
  size?: number;
  expires?: number;
}

interface SketchfabDownloadResponse {
  glb?: SketchfabDownloadFormat;
  gltf?: SketchfabDownloadFormat;
  source?: SketchfabDownloadFormat;
  usdz?: SketchfabDownloadFormat;
}

export class SketchfabProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "sketchfab",
      name: "Sketchfab",
      website: "https://sketchfab.com",
      key_env: ["SKETCHFAB_API_KEY", "SKETCHFAB_API_TOKEN"],
      capabilities: ["model"],
      description: "Downloadable Creative Commons 3D models from Sketchfab."
    };
  }

  private apiKey(): string | undefined {
    return this.ctx.env.SKETCHFAB_API_KEY || this.ctx.env.SKETCHFAB_API_TOKEN;
  }

  credentialStatus(): string {
    return this.apiKey() ? "API key configured." : "API key required to search and download. Set SKETCHFAB_API_KEY.";
  }

  private normalize(raw: SketchfabRawAsset, fetched: boolean): Asset {
    const rawUid = asString(raw.uid, "asset");
    const id = rawUid;
    const title = asString(raw.name, id);
    const variants: AssetVariant[] = [];
    const files: SourceFile[] = [];

    // Sketchfab standard downloadable formats
    const glbVar = variant("glb", "GLB Model", "files", { format: "glb" });
    const gltfVar = variant("gltf", "glTF Archive", "files", { format: "gltf" });
    const sourceVar = variant("source", "Original Source", "files", { format: "source" });
    variants.push(glbVar, gltfVar, sourceVar);

    const lRecord = asRecord(raw.license);
    const lSlug = asString(lRecord.slug, "").toLowerCase();
    const lLabel = asString(lRecord.label, "Creative Commons");
    const lUrl = asString(lRecord.url, "https://creativecommons.org/");

    let licId = "cc-by-4.0";
    if (lSlug === "by") licId = "cc-by-4.0";
    else if (lSlug === "by-sa") licId = "cc-by-sa-4.0";
    else if (lSlug === "cc0") licId = "cc0-1.0";
    else if (lSlug.includes("nc") || lSlug.includes("nd")) licId = "proprietary";

    const license: LicenseRecord = {
      id: licId,
      name: lLabel,
      url: lUrl,
      attribution_required: licId.startsWith("cc-by")
    };

    const user = asRecord(raw.user);
    const authorName = asString(user.displayName) || asString(user.username, "Sketchfab Artist");
    const authorUrl = asString(user.profileUrl, "https://sketchfab.com");

    const thumbs = asArray(asRecord(raw.thumbnails).images);
    let previewUrl = "";
    if (thumbs.length > 0) {
      const best = thumbs.find((t) => asRecord(t).width === 720 || asRecord(t).width === 1024) || thumbs[0];
      previewUrl = asString(asRecord(best).url);
    }

    const modelUrl = asString(raw.viewerUrl, `https://sketchfab.com/3d-models/${id}`);

    return createAsset({
      provider_id: "sketchfab",
      provider_name: "Sketchfab",
      id,
      title,
      type: normalizeAssetType("model"),
      url: modelUrl,
      thumbnail_url: previewUrl || undefined,
      description: asString(raw.description, `${title} on Sketchfab`),
      tags: [],
      categories: ["models", "3d"],
      price: { free: true, credits: 0 },
      authors: [{ name: authorName, url: authorUrl }],
      license,
      attribution_text: `${title} by ${authorName} via Sketchfab (${license.name}).`,
      metadata_source_url: modelUrl,
      retrieved_utc: fetched ? this.ctx.now().toISOString() : undefined,
      variants,
      files,
      download_data: { uid: id }
    });
  }

  async search(params: SearchParams): Promise<SearchPage> {
    const key = this.apiKey();
    if (!key) {
      return { items: [], next_cursor: null };
    }

    const query = params.query?.trim() || "model";
    const cursor = params.cursor ? `&cursor=${encodeURIComponent(params.cursor)}` : "";
    const url = `${API_BASE}/search?type=models&downloadable=true&q=${encodeURIComponent(query)}${cursor}`;

    const headers: Record<string, string> = {
      Accept: "application/json",
      Authorization: `Token ${key}`
    };

    const json = await this.ctx.http.json<SketchfabSearchResponse>(url, { headers });
    const items = (json.results ?? []).map((r) => this.normalize(r, false));
    const nextCursor = json.next ? new URL(json.next).searchParams.get("cursor") || null : null;

    return {
      items,
      next_cursor: nextCursor
    };
  }

  async details(asset: Asset): Promise<Asset> {
    const key = this.apiKey();
    if (!key) {
      return asset;
    }

    const uid = asString(asset.download_data?.uid, asset.id);
    const url = `${API_BASE}/models/${encodeURIComponent(uid)}`;
    const headers: Record<string, string> = {
      Accept: "application/json",
      Authorization: `Token ${key}`
    };

    const json = await this.ctx.http.json<SketchfabRawAsset>(url, { headers });
    return this.normalize(json, true);
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

  async resolveDownload(
    asset: Asset,
    variantId?: string,
    options: { signal?: AbortSignal; preview?: boolean } = {}
  ): Promise<DownloadPlan> {
    const key = this.apiKey();
    if (!key) {
      throw new Error("Sketchfab API key required.");
    }

    const uid = asString(asset.download_data?.uid, asset.id);
    const dlUrl = `${API_BASE}/models/${encodeURIComponent(uid)}/download`;
    const headers: Record<string, string> = {
      Accept: "application/json",
      Authorization: `Token ${key}`
    };

    const dlJson = await this.ctx.http.json<SketchfabDownloadResponse>(dlUrl, {
      headers,
      signal: options.signal
    });

    const targetFormat = variantId === "gltf" ? "gltf" : variantId === "source" ? "source" : "glb";
    const selected = dlJson[targetFormat] || dlJson.glb || dlJson.gltf || dlJson.source;

    if (!selected?.url) {
      throw new Error(`Requested format ${variantId ?? "glb"} is not available for model ${asset.id}`);
    }

    const ext = targetFormat === "source" ? "zip" : targetFormat;
    const filename = `${slug(asset.title)}_${asset.id.slice(0, 8)}.${ext}`;

    const files: SourceFile[] = [
      {
        filename,
        url: selected.url,
        size: selected.size
      }
    ];

    return {
      kind: "files",
      asset,
      variant: targetFormat,
      files
    };
  }
}

export const sketchfabFactory = (context: ProviderContext): Provider => new SketchfabProvider(context);
