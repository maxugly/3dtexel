import { normalizeLicense, normalizeAuthors } from "../license.js";
import type { Author, LicenseRecord, SourceFile } from "../types.js";
import { absoluteUrl, asNumber, decodeHtml, stripHtml } from "./helpers.js";

export interface OgaSearchItem {
  id: string;
  title: string;
  type: "material" | "model" | "audio" | "image";
  url: string;
  thumbnail: string;
  authors: Author[];
  licenses: LicenseRecord[];
  selected: LicenseRecord;
  art_type: string;
}

export interface OgaDetails {
  title?: string;
  description?: string;
  authors?: Author[];
  licenses?: LicenseRecord[];
  selected?: LicenseRecord;
  attribution_text?: string;
  files?: SourceFile[];
  tags?: string[];
  type?: "material" | "model" | "audio" | "image";
}

const BASE = "https://opengameart.org";

export function mapArtType(value: string): "material" | "model" | "audio" | "image" {
  const lower = value.toLowerCase();
  if (lower.includes("3d") || lower.includes("model")) {
    return "model";
  }
  if (lower.includes("texture") || lower.includes("material")) {
    return "material";
  }
  if (lower.includes("sound") || lower.includes("music") || lower.includes("audio") || lower.includes("sfx")) {
    return "audio";
  }
  return "image";
}

export function preferredLicense(licenses: LicenseRecord[]): LicenseRecord {
  const cc0 = licenses.find((entry) => `${entry.id ?? ""} ${entry.name}`.toLowerCase().includes("cc0"));
  if (cc0) {
    return cc0;
  }
  const attribution = licenses.find((entry) => {
    const value = `${entry.id ?? ""} ${entry.name}`.toLowerCase();
    return value.includes("cc-by") && !value.includes("sa") && !value.includes("nc") && !value.includes("nd");
  });
  if (attribution) {
    return attribution;
  }
  const oga = licenses.find((entry) => `${entry.id ?? ""} ${entry.name}`.toLowerCase().includes("oga-by"));
  return oga ?? licenses[0] ?? { name: "Unknown", attribution_required: null };
}

function attribute(html: string, name: string): string {
  const match = new RegExp(`\\b${name}\\s*=\\s*["']([^"']+)["']`, "i").exec(html);
  return match ? decodeHtml(match[1] ?? "") : "";
}

function anchors(html: string): Array<{ href: string; text: string }> {
  const result: Array<{ href: string; text: string }> = [];
  const pattern = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
  for (const match of html.matchAll(pattern)) {
    const href = attribute(match[1] ?? "", "href");
    if (!href) {
      continue;
    }
    result.push({ href: absoluteUrl(href, BASE), text: stripHtml(match[2] ?? "") });
  }
  return result;
}

function fieldBlock(html: string, className: string): string {
  const marker = new RegExp(`<div[^>]+class=["'][^"']*${className}[^"']*["'][^>]*>`, "i");
  const match = marker.exec(html);
  if (!match) {
    return "";
  }
  const start = (match.index ?? 0) + match[0].length;
  const rest = html.slice(start);
  const end = rest.search(/<div[^>]+class=["'][^"']*(?:views-field|field-name-|views-row|item-list|pager|art-|submitted)[^"']*["']/i);
  return end >= 0 ? rest.slice(0, end) : rest.slice(0, 12_000);
}

function parseLicenses(html: string): LicenseRecord[] {
  const result: LicenseRecord[] = [];
  for (const anchor of anchors(html)) {
    if (!/creativecommons|gnu\.org|opengameart\.org/i.test(anchor.href)) {
      continue;
    }
    const license = normalizeLicense(anchor.text, undefined, anchor.href);
    if (!result.some((entry) => (entry.id ?? entry.name).toLowerCase() === (license.id ?? license.name).toLowerCase())) {
      result.push(license);
    }
  }
  if (!result.length) {
    const text = stripHtml(html);
    for (const part of text.replace(/^License\(s\):\s*/i, "").split(",")) {
      if (part.trim()) {
        result.push(normalizeLicense(part.trim()));
      }
    }
  }
  return result;
}

function parseAuthors(html: string): Author[] {
  const linked = anchors(html)
    .filter((anchor) => /\/(?:users?|user)\//i.test(anchor.href))
    .map((anchor) => ({ name: anchor.text, url: anchor.href }))
    .filter((author) => author.name);
  if (linked.length) {
    return normalizeAuthors(linked);
  }
  const text = stripHtml(html)
    .replace(/^Author:?\s*/i, "")
    .replace(/^Posted by\s*/i, "")
    .replace(/^Submitted by\s*/i, "")
    .replace(/^Artist:?\s*/i, "");
  return normalizeAuthors(text);
}

function parseSize(value: string): number | undefined {
  const match = /(?:length=)?([0-9]+)\s*(KB|MB|GB)?/i.exec(value);
  if (!match) {
    return undefined;
  }
  const amount = Number(match[1]);
  const unit = (match[2] ?? "").toUpperCase();
  if (unit === "KB") {
    return amount * 1024;
  }
  if (unit === "MB") {
    return amount * 1024 * 1024;
  }
  if (unit === "GB") {
    return amount * 1024 * 1024 * 1024;
  }
  return amount;
}

function parseFiles(html: string): SourceFile[] {
  const sections: string[] = [];
  for (const className of ["field-name-field-art-files", "art-downloads", "file-list"]) {
    const block = fieldBlock(html, className);
    if (block) {
      sections.push(block);
    }
  }
  if (!sections.length) {
    sections.push(html);
  }

  const result: SourceFile[] = [];
  const seen = new Set<string>();
  for (const section of sections) {
    const pattern = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
    for (const match of section.matchAll(pattern)) {
      const href = absoluteUrl(attribute(match[1] ?? "", "href"), BASE);
      if (!href || /\.(?:png|jpe?g|gif|webp)(?:\?|$)/i.test(href) && /field-art-preview|thumbnail|preview/i.test(match[1] ?? "")) {
        continue;
      }
      const surrounding = section.slice(Math.max(0, (match.index ?? 0) - 120), (match.index ?? 0) + match[0].length + 160);
      const text = stripHtml(match[2] ?? "");
      const filename = text || href.split("/").pop() || "download";
      if (!/\.[a-z0-9]{2,6}(?:\?|$)/i.test(filename) && !/\.[a-z0-9]{2,6}(?:\?|$)/i.test(href)) {
        continue;
      }
      const type = attribute(match[1] ?? "", "type");
      const sizeText = /\(([\d.]+\s*(?:KB|MB|GB))\)/i.exec(surrounding)?.[1] ?? type;
      const file: SourceFile = {
        filename,
        url: href
      };
      const size = parseSize(sizeText ?? "");
      if (size) {
        file.size = size;
      }
      if (type && /^(?:model|image|audio|application)\//i.test(type)) {
        file.content_type = type.split(";")[0];
      }
      const key = `${file.filename}:${file.url}`;
      if (!seen.has(key)) {
        seen.add(key);
        result.push(file);
      }
    }
  }
  return result;
}

export function parseSearchPage(html: string): { items: OgaSearchItem[]; next_cursor: string | null } {
  const chunks = html.split(/<div[^>]+class=["'][^"']*views-row[^"']*["'][^>]*>/i).slice(1);
  const items: OgaSearchItem[] = [];
  for (const chunk of chunks) {
    const titleBlock = fieldBlock(chunk, "views-field-title");
    const titleAnchor = anchors(titleBlock)[0];
    if (!titleAnchor || !titleAnchor.href.includes("/content/")) {
      continue;
    }
    const id = titleAnchor.href.split("/content/")[1]?.split(/[/?#]/)[0] ?? "";
    if (!id) {
      continue;
    }
    const preview = fieldBlock(chunk, "views-field-field-art-preview");
    const thumbnail = anchors(preview).find((anchor) => /\.(?:png|jpe?g|gif|webp)(?:\?|$)/i.test(anchor.href))?.href
      ?? /<img\b[^>]*\bsrc=["']([^"']+)["']/i.exec(preview)?.[1]
      ?? "";
    const artType = stripHtml(fieldBlock(chunk, "views-field-field-art-type")).replace(/^Art Type:\s*/i, "");
    const licenses = parseLicenses(fieldBlock(chunk, "views-field-field-art-licenses"));
    const authors = parseAuthors(fieldBlock(chunk, "views-field-name"));
    items.push({
      id,
      title: titleAnchor.text,
      type: mapArtType(artType),
      url: titleAnchor.href,
      thumbnail: absoluteUrl(thumbnail, BASE),
      authors,
      licenses,
      selected: preferredLicense(licenses),
      art_type: artType
    });
  }

  const next = /<li[^>]+class=["'][^"']*pager-next[^"']*["'][^>]*>[\s\S]*?<a\b[^>]*href=["']([^"']+)["']/i.exec(html);
  const page = next ? /[?&]page=([0-9]+)/.exec(decodeHtml(next[1] ?? ""))?.[1] : undefined;
  return { items, next_cursor: page ?? null };
}

export function parseAssetPage(html: string, assetUrl: string): OgaDetails {
  const result: OgaDetails = { files: [], tags: [] };
  const title = /<h1\b[^>]*(?:id=["']page-title["']|class=["'][^"']*title[^"']*["'])[^>]*>([\s\S]*?)<\/h1>/i.exec(html)
    ?? /<h1\b[^>]*>([\s\S]*?)<\/h1>/i.exec(html);
  if (title) {
    result.title = stripHtml(title[1] ?? "");
  }

  const description = fieldBlock(html, "field-name-body")
    || fieldBlock(html, "art-description");
  if (description) {
    result.description = stripHtml(description).slice(0, 12_000);
  }

  const authorBlock = fieldBlock(html, "field-name-field-art-author")
    || fieldBlock(html, "art-author-info");
  let authors = authorBlock ? parseAuthors(authorBlock) : [];
  if (!authors.length) {
    const submitted = /(?:Submitted|Posted)\s+by\s*<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/i.exec(html);
    if (submitted) {
      authors = normalizeAuthors([{ name: stripHtml(submitted[2] ?? ""), url: absoluteUrl(submitted[1] ?? "", BASE) }]);
    }
  }
  if (authors.length) {
    result.authors = authors;
  }

  const licenseBlock = fieldBlock(html, "field-name-field-art-licenses")
    || fieldBlock(html, "art-license-info");
  const licenses = parseLicenses(licenseBlock);
  if (licenses.length) {
    result.licenses = licenses;
    result.selected = preferredLicense(licenses);
  }

  const attribution = fieldBlock(html, "field-name-field-art-attribution")
    || fieldBlock(html, "art-attribution-notice");
  if (attribution) {
    result.attribution_text = stripHtml(attribution)
      .replace(/^Copyright\/Attribution Notice:\s*/i, "");
  }

  const tagsBlock = fieldBlock(html, "field-name-field-art-tags");
  if (tagsBlock) {
    result.tags = anchors(tagsBlock).map((anchor) => anchor.text).filter(Boolean);
  }

  const files = parseFiles(html);
  result.files = files;

  const zip = files.find((file) => /\.zip$/i.test(file.filename));
  if (zip) {
    result.type = "model";
  } else if (files.some((file) => /\.(?:wav|ogg|mp3|flac)$/i.test(file.filename))) {
    result.type = "audio";
  } else if (files.some((file) => /\.(?:glb|gltf|fbx|blend|obj|dae|stl|usdz?)$/i.test(file.filename))) {
    result.type = "model";
  } else if (files.some((file) => /\.(?:png|jpe?g|webp|tga|exr|hdr)$/i.test(file.filename))) {
    result.type = "image";
  }

  result.files = files;
  return result;
}

export function detailSizeScore(value: string): number {
  return asNumber(/length=([0-9]+)/.exec(value)?.[1], 0);
}
