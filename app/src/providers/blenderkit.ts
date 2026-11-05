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
import { slug } from "../util/fs.js";
import { asArray, asRecord, asString, canDownload, variant } from "./helpers.js";

const API_BASE = "https://www.blendkit.com/api/v1";

interface BlenderKitAuthor {
  id?: number;
  fullName?: string;
  firstName?: string;
  lastName?: string;
  aboutMeUrl?: string;
}

interface BlenderKitFile {
  fileType?: string;
  downloadUrl?: string;
  fileUploadSize?: number;
}

interface BlenderKitRawAsset extends Record<string, unknown> {
  id?: string;
  assetBaseId?: string;
  name?: string;
  displayName?: string;
  description?: string;
  isFree?: boolean;
  license?: string;
  author?: BlenderKitAuthor;
  thumbnailSmallUrl?: string;
  thumbnailMiddleUrl?: string;
  thumbnailLargeUrl?: string;
  files?: BlenderKitFile[];
}

interface BlenderKitSearchResponse {
  results?: BlenderKitRawAsset[];
  count?: number;
  next?: string | null;
  previous?: string | null;
}

interface BlenderKitDownloadResponse {
  filePath?: string;
}

export class BlenderKitProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "blenderkit",
      name: "BlenderKit",
      website: "https://www.blendkit.com",
      key_env: ["BLENDERKIT_API_KEY", "BLENDERKIT_TOKEN"],
      capabilities: ["model"],
      description: "Confirmed-free 3D models and assets from BlenderKit."
    };
  }

  private apiKey(): string | undefined {
    return this.ctx.env.BLENDERKIT_API_KEY || this.ctx.env.BLENDERKIT_TOKEN;
  }

  credentialStatus(): string {
    return this.apiKey()
      ? "API token configured."
      : "Public free mode (no token needed for free assets).";
  }

  private normalize(raw: BlenderKitRawAsset, fetched: boolean): Asset {
    const rawId = asString(raw.id, "asset");
    const id = rawId;
    const title = asString(raw.name) || asString(raw.displayName, id);
    const variants: AssetVariant[] = [];
    const files: SourceFile[] = [];

    const rawFiles = asArray(raw.files);
    for (const f of rawFiles) {
      const rec = asRecord(f);
      const ftype = asString(rec.fileType);
      const dlUrl = asString(rec.downloadUrl);
      const sizeBytes = Number(rec.fileUploadSize || 0);

      if (ftype === "gltf_godot") {
        variants.push(variant("gltf_godot", "GLTF (Godot)", "files", { format: "glb" }));
      } else if (ftype === "gltf") {
        variants.push(variant("gltf", "GLTF", "files", { format: "glb" }));
      } else if (ftype === "blend") {
        variants.push(variant("blend", "Blender (.blend)", "files", { format: "blend" }));
      }
    }

    if (variants.length === 0) {
      variants.push(
        variant("gltf_godot", "GLTF (Godot)", "files", {}),
        variant("blend", "Blender (.blend)", "files", {})
      );
    }

    const licStr = asString(raw.license, "royalty_free").toLowerCase();
    let licId = "royalty_free";
    let licName = "Royalty Free (BlenderKit Standard Free)";
    let licUrl = "https://www.blendkit.com/license/";
    let attrRequired = false;

    if (licStr === "cc0" || licStr === "public_domain") {
      licId = "cc0-1.0";
      licName = "Creative Commons CC0 1.0 Universal";
      licUrl = "https://creativecommons.org/publicdomain/zero/1.0/";
    } else if (licStr.includes("cc_by") || licStr.includes("cc-by")) {
      licId = "cc-by-4.0";
      licName = "Creative Commons Attribution 4.0 International";
      licUrl = "https://creativecommons.org/licenses/by/4.0/";
      attrRequired = true;
    }

    const license: LicenseRecord = {
      id: licId,
      name: licName,
      url: licUrl,
      attribution_required: attrRequired
    };

    const author = asRecord(raw.author);
    const authorName = asString(author.fullName) || asString(author.firstName, "BlenderKit Artist");
    let authorUrl = asString(author.aboutMeUrl);
    if (!authorUrl && author.id) {
      authorUrl = `https://www.blendkit.com/?query=author_id:${author.id}`;
    }
    if (!authorUrl) {
      authorUrl = "https://www.blendkit.com";
    }

    const previewUrl =
      asString(raw.thumbnailMiddleUrl) ||
      asString(raw.thumbnailSmallUrl) ||
      asString(raw.thumbnailLargeUrl) ||
      "";

    const baseId = asString(raw.assetBaseId, id);
    const modelUrl = `https://www.blendkit.com/asset-gallery-detail/${baseId}/`;
    const isFree = Boolean(raw.isFree);

    return createAsset({
      provider_id: "blenderkit",
      provider_name: "BlenderKit",
      id,
      title,
      type: normalizeAssetType("model"),
      url: modelUrl,
      thumbnail_url: previewUrl || undefined,
      description: asString(raw.description, `${title} on BlenderKit`),
      tags: [],
      categories: ["models", "3d"],
      price: { free: isFree, credits: 0 },
      authors: [{ name: authorName, url: authorUrl }],
      license,
      attribution_text: `${title} by ${authorName} via BlenderKit (${license.name}).`,
      metadata_source_url: modelUrl,
      retrieved_utc: fetched ? this.ctx.now().toISOString() : undefined,
      variants,
      files,
      download_data: { id, files: rawFiles }
    });
  }

  async search(params: SearchParams): Promise<SearchPage> {
    const query = params.query?.trim() || "";
    const headers: Record<string, string> = {
      Accept: "application/json",
      "User-Agent": "3dtexel-AssetLibrary/1.0"
    };
    const key = this.apiKey();
    if (key) {
      headers.Authorization = `Bearer ${key}`;
    }

    // Check for UUID in query
    const uuidMatch = query.match(/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})/i);
    if (uuidMatch) {
      const candidateUuid = uuidMatch[1];
      try {
        const directAsset = await this.ctx.http.json<BlenderKitRawAsset>(
          `${API_BASE}/assets/${encodeURIComponent(candidateUuid)}/`,
          { headers }
        );
        if (directAsset?.id) {
          return {
            items: [this.normalize(directAsset, false)],
            next_cursor: null
          };
        }
      } catch {
        // Fall back to gallery page HTML scraping
        try {
          const galleryHtml = await this.ctx.http.text(
            `https://www.blendkit.com/asset-gallery-detail/${candidateUuid}/`
          );
          const idMatch = galleryHtml.match(/data-asset-id="([a-f0-9-]+)"/);
          if (idMatch) {
            const resolvedAsset = await this.ctx.http.json<BlenderKitRawAsset>(
              `${API_BASE}/assets/${encodeURIComponent(idMatch[1])}/`,
              { headers }
            );
            if (resolvedAsset?.id) {
              return {
                items: [this.normalize(resolvedAsset, false)],
                next_cursor: null
              };
            }
          }
        } catch {
          // Continue to regular search
        }
      }
    }

    const page = params.cursor ? parseInt(params.cursor, 10) || 1 : 1;
    const url = `${API_BASE}/search/?asset_type=model&page=${page}${query ? `&query=${encodeURIComponent(query)}` : ""}`;

    const json = await this.ctx.http.json<BlenderKitSearchResponse>(url, { headers });
    const items = (json.results ?? []).map((r) => this.normalize(r, false));
    const nextCursor = json.next ? String(page + 1) : null;

    return {
      items,
      next_cursor: nextCursor
    };
  }

  async details(asset: Asset): Promise<Asset> {
    const headers: Record<string, string> = {
      Accept: "application/json",
      "User-Agent": "3dtexel-AssetLibrary/1.0"
    };
    const key = this.apiKey();
    if (key) {
      headers.Authorization = `Bearer ${key}`;
    }

    const rawId = asString(asset.download_data?.id, asset.id);
    const url = `${API_BASE}/assets/${encodeURIComponent(rawId)}/`;
    const json = await this.ctx.http.json<BlenderKitRawAsset>(url, { headers });
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
    const headers: Record<string, string> = {
      Accept: "application/json",
      "User-Agent": "BlenderKit/3.21",
      "Platform-Version": "Linux",
      "Client-Version": "1.0.0",
      "Origin-Name": "Blender"
    };
    const key = this.apiKey();
    if (key) {
      headers.Authorization = `Bearer ${key}`;
    }

    const rawFiles = asArray(asset.download_data?.files);
    let chosen: Record<string, unknown> | undefined;

    if (variantId) {
      chosen = rawFiles.find((f) => asRecord(f).fileType === variantId) as Record<string, unknown> | undefined;
    }
    if (!chosen) {
      chosen = rawFiles.find((f) => {
        const t = asString(asRecord(f).fileType);
        return t === "gltf_godot" || t === "gltf" || t === "blend";
      }) as Record<string, unknown> | undefined;
    }
    if (!chosen && rawFiles.length > 0) {
      chosen = asRecord(rawFiles[0]);
    }

    if (!chosen?.downloadUrl) {
      throw new Error(`Download endpoint not found for asset ${asset.id}`);
    }

    const baseDlUrl = asString(chosen.downloadUrl);
    const dlEndpoint = baseDlUrl.includes("?")
      ? `${baseDlUrl}&scene_uuid=00000000-0000-0000-0000-000000000000`
      : `${baseDlUrl}?scene_uuid=00000000-0000-0000-0000-000000000000`;

    // The endpoint returns a transient signed URL. A preview must not issue it,
    // and the HTTP cache must never persist it.
    if (options.preview) return { kind: "files", asset, variant: variantId || asString(chosen.fileType), files: [] } as FilesPlan;
    const dlJson = await this.ctx.http.json<BlenderKitDownloadResponse>(dlEndpoint, {
      headers,
      cache: false,
      signal: options.signal
    });

    if (!dlJson?.filePath) {
      throw new Error(`Failed to obtain signed download URL from BlenderKit for ${asset.id}`);
    }

    const ftype = asString(chosen.fileType, variantId || "gltf");
    const ext = ftype.startsWith("gltf") ? "glb" : ftype === "blend" ? "blend" : "zip";
    const filename = `${slug(asset.title)}_${asset.id.slice(0, 8)}.${ext}`;

    const files: SourceFile[] = [
      {
        filename,
        url: dlJson.filePath,
        size: Number(chosen.fileUploadSize || 0)
      }
    ];

    return {
      kind: "files",
      asset,
      variant: variantId || ftype,
      files
    } as FilesPlan;
  }
}

export const blenderkitFactory = (context: ProviderContext): Provider => new BlenderKitProvider(context);
