import type { Asset, Author, LicenseRecord, Price } from "./types.js";

export const LICENSE_STATUS = {
  PERMISSIVE: 0,
  UNKNOWN: 1,
  ATTRIBUTION: 2,
  BLOCKED: 3
} as const;

export type LicenseStatus = (typeof LICENSE_STATUS)[keyof typeof LICENSE_STATUS];

export interface LicenseEvaluation {
  status: LicenseStatus;
  review_required: boolean;
  reason: string;
}

const LICENSE_LINKS: Record<string, string> = {
  "cc0": "https://creativecommons.org/publicdomain/zero/1.0/",
  "cc-by": "https://creativecommons.org/licenses/by/4.0/",
  "cc-by-sa": "https://creativecommons.org/licenses/by-sa/4.0/",
  "cc-by-nd": "https://creativecommons.org/licenses/by-nd/4.0/",
  "cc-by-nc": "https://creativecommons.org/licenses/by-nc/4.0/",
  "cc-by-nc-sa": "https://creativecommons.org/licenses/by-nc-sa/4.0/",
  "cc-by-nc-nd": "https://creativecommons.org/licenses/by-nc-nd/4.0/",
  "oga-by": "https://static.opengameart.org/OGA-BY-3.0.txt",
  "mit": "https://opensource.org/licenses/MIT",
  "apache-2.0": "https://www.apache.org/licenses/LICENSE-2.0",
  "bsd": "https://opensource.org/licenses/BSD-3-Clause"
};

function licenseKey(value: string): string {
  return value
    .toLowerCase()
    .replace(/creative commons/i, "cc")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function titleFromKey(key: string): string {
  if (key === "cc0") {
    return "CC0 1.0";
  }
  if (key.startsWith("cc-")) {
    return `CC ${key.slice(3).toUpperCase().replace(/-/g, " ")}`;
  }
  if (key === "public-domain") {
    return "Public Domain";
  }
  return key.replace(/-/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function fromText(text: string, version?: string, url?: string): LicenseRecord {
  const cleaned = text.trim();
  const lower = cleaned.toLowerCase();
  if (!cleaned) {
    return { name: "Unknown", url, attribution_required: null };
  }
  if (lower.includes("cc0") || lower.includes("public domain zero")) {
    return {
      id: version ? `cc0-${version}` : "cc0",
      name: version ? `CC0 ${version}` : "CC0 1.0",
      url: url || LICENSE_LINKS.cc0,
      attribution_required: false
    };
  }
  if (lower.includes("public domain") || lower === "pd" || lower === "pdm" || lower.includes("no known copyright")) {
    return {
      id: "public-domain",
      name: "Public Domain",
      url: url || "https://creativecommons.org/publicdomain/mark/1.0/",
      attribution_required: false
    };
  }
  if (lower.includes("oga-by")) {
    return {
      id: "oga-by",
      name: version ? `OGA-BY ${version}` : "OGA-BY",
      url: url || LICENSE_LINKS["oga-by"],
      attribution_required: true
    };
  }
  const compact = lower.replace(/[_\s]+/g, "-").replace(/-+/g, "-");
  const has = (suffix: string) => new RegExp(`(^|-)${suffix}(-|$)`).test(compact);
  const detectedVersion = version || /(?:^|[^0-9])([0-9]+(?:\.[0-9]+)?)/.exec(cleaned)?.[1];
  const ordered = ["by-nc-sa", "by-nc-nd", "by-sa", "by-nd", "by-nc", "by"];
  for (const suffix of ordered) {
    if (has(suffix) || has(`cc-${suffix}`)) {
      const id = `cc-${suffix}${detectedVersion ? `-${detectedVersion}` : ""}`;
      const base = `cc-${suffix}`;
      return {
        id,
        name: `CC ${suffix.toUpperCase().replace(/-/g, " ")}${detectedVersion ? ` ${detectedVersion}` : ""}`,
        url: url || LICENSE_LINKS[base],
        attribution_required: !suffix.includes("nc") && !suffix.includes("nd")
      };
    }
  }
  if (lower.includes("gpl") || lower.includes("general public license")) {
    return {
      id: version ? `gpl-${version}` : "gpl",
      name: `GPL${version ? ` ${version}` : ""}`,
      url: url || "https://www.gnu.org/licenses/gpl-3.0.html",
      attribution_required: true
    };
  }
  if (lower.includes("apache")) {
    return { id: "apache-2.0", name: "Apache 2.0", url: url || LICENSE_LINKS["apache-2.0"], attribution_required: true };
  }
  if (lower.includes("mit license") || lower === "mit") {
    return { id: "mit", name: "MIT", url: url || LICENSE_LINKS.mit, attribution_required: true };
  }
  if (lower.includes("bsd")) {
    return { id: "bsd", name: cleaned, url, attribution_required: true };
  }
  if (lower.includes("all rights reserved") || lower.includes("proprietary") || lower.includes("editorial")) {
    return { id: licenseKey(cleaned), name: cleaned, url, attribution_required: null };
  }
  return { id: licenseKey(cleaned), name: cleaned, url, attribution_required: null };
}

export function normalizeLicense(value: unknown, version?: string, url?: string): LicenseRecord {
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    const name = String(record.name ?? record.id ?? "Unknown").trim() || "Unknown";
    const normalized = fromText(name, version, url ?? (typeof record.url === "string" ? record.url : undefined));
    if (typeof record.id === "string" && record.id.trim()) {
      normalized.id = record.id.trim();
    }
    if (typeof record.name === "string" && record.name.trim()) {
      normalized.name = record.name.trim();
    }
    if (typeof record.url === "string" && record.url.trim()) {
      normalized.url = record.url.trim();
    }
    if (record.attribution_required === true || record.attribution_required === false) {
      normalized.attribution_required = record.attribution_required;
    }
    return normalized;
  }
  return fromText(String(value ?? ""), version, url);
}

export function normalizePrice(value: unknown): Price {
  if (typeof value === "boolean") {
    return { free: value, credits: 0 };
  }
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    const credits = Number(record.credits ?? 0);
    return {
      free: record.free === true && (!Number.isFinite(credits) || credits === 0),
      credits: Number.isFinite(credits) && credits > 0 ? credits : 0
    };
  }
  return { free: false, credits: 0 };
}

export function normalizeAuthors(value: unknown): Author[] {
  const result: Author[] = [];
  const push = (name: unknown, url?: unknown) => {
    const cleaned = String(name ?? "").replace(/\s+/g, " ").trim();
    if (!cleaned) {
      return;
    }
    const record: Author = { name: cleaned };
    if (typeof url === "string" && url.startsWith("https://")) {
      record.url = url;
    }
    if (!result.some((author) => author.name.toLowerCase() === cleaned.toLowerCase())) {
      result.push(record);
    }
  };

  if (Array.isArray(value)) {
    for (const author of value) {
      if (typeof author === "string") {
        push(author);
      } else if (author && typeof author === "object") {
        const record = author as Record<string, unknown>;
        push(record.name ?? record.author ?? record.creator, record.url ?? record.profile_url);
      }
    }
  } else if (value && typeof value === "object") {
    for (const [name, url] of Object.entries(value as Record<string, unknown>)) {
      push(name, url);
    }
  } else if (typeof value === "string") {
    for (const name of value.split(/\s*(?:,|;|\band\b)\s*/i)) {
      push(name);
    }
  }
  return result;
}

export function evaluateLicense(asset: Asset): LicenseEvaluation {
  if (asset.price.credits > 0) {
    return {
      status: LICENSE_STATUS.BLOCKED,
      review_required: true,
      reason: "The provider reports a paid download."
    };
  }
  if (asset.price.free !== true) {
    return {
      status: LICENSE_STATUS.UNKNOWN,
      review_required: true,
      reason: "The provider has not confirmed that the asset is free."
    };
  }

  const license = asset.license;
  const haystack = `${license.id ?? ""} ${license.name ?? ""}`.toLowerCase().replace(/_/g, "-");
  if (!haystack.trim() || haystack.includes("unknown")) {
    return {
      status: LICENSE_STATUS.UNKNOWN,
      review_required: true,
      reason: "The license is missing or unknown."
    };
  }
  const blocked = [
    "cc-by-nc", "cc-by-nd", "by-nc", "by-nd", "noncommercial", "non-commercial",
    "no derivatives", "no-derivatives", "all rights reserved", "proprietary",
    "editorial use", "permission required", "copyrighted"
  ];
  if (blocked.some((term) => haystack.includes(term)) || license.attribution_required === null && haystack.includes("unknown")) {
    return {
      status: LICENSE_STATUS.BLOCKED,
      review_required: true,
      reason: "The license restricts commercial use, derivatives, or reuse."
    };
  }
  const permissive = [
    "cc0", "public-domain", "public domain", "pdm", "no known copyright",
    "us government", "nasa media guidelines", "cc-pd"
  ];
  if (permissive.some((term) => haystack.includes(term))) {
    return {
      status: LICENSE_STATUS.PERMISSIVE,
      review_required: false,
      reason: "The license permits reuse without attribution."
    };
  }
  const attribution = [
    "cc-by", "by attribution", "attribution", "oga-by", "mit", "apache", "bsd"
  ];
  if (attribution.some((term) => haystack.includes(term)) && !haystack.includes("share-alike") && !haystack.includes("sa")) {
    return {
      status: LICENSE_STATUS.ATTRIBUTION,
      review_required: false,
      reason: "The license requires attribution."
    };
  }
  if (haystack.includes("share-alike") || haystack.includes("cc-by-sa") || haystack.includes("gpl") || haystack.includes("lgpl")) {
    return {
      status: LICENSE_STATUS.UNKNOWN,
      review_required: true,
      reason: "Share-alike or copyleft terms require project-specific review."
    };
  }
  return {
    status: LICENSE_STATUS.UNKNOWN,
    review_required: true,
    reason: "The license does not match a known permissive or attribution-only pattern."
  };
}

export function attributionText(asset: Asset): string {
  const names = asset.authors.map((author) => author.name).join(", ");
  const creator = names || "Creator not supplied";
  const license = asset.license.name || "Unknown license";
  return `${asset.title} by ${creator}, ${license}. Source: ${asset.url}`;
}

export interface CreditRecord {
  schema_version: 1;
  provider: string;
  provider_id: string;
  asset_id: string;
  title: string;
  source_url: string;
  authors: Author[];
  author_status: "reported" | "not_supplied";
  license: LicenseRecord;
  licenses: LicenseRecord[];
  selected_license: LicenseRecord;
  license_status: LicenseStatus;
  license_reason: string;
  review_required: boolean;
  attribution_text: string;
  metadata_source_url?: string;
  retrieved_utc?: string;
}

export function creditRecord(asset: Asset): CreditRecord {
  const evaluation = evaluateLicense(asset);
  return {
    schema_version: 1,
    provider: asset.provider_name,
    provider_id: asset.provider_id,
    asset_id: asset.id,
    title: asset.title,
    source_url: asset.url,
    authors: asset.authors,
    author_status: asset.authors.length ? "reported" : "not_supplied",
    license: asset.license,
    licenses: asset.licenses ?? [asset.license],
    selected_license: asset.selected_license ?? asset.license,
    license_status: evaluation.status,
    license_reason: evaluation.reason,
    review_required: evaluation.review_required,
    attribution_text: asset.attribution_text || attributionText(asset),
    metadata_source_url: asset.metadata_source_url,
    retrieved_utc: asset.retrieved_utc
  };
}

export function creditsMarkdown(records: CreditRecord[]): string {
  const lines = ["# Asset credits", ""];
  for (const record of records) {
    lines.push(`## ${record.title}`, "");
    lines.push(`- Provider: ${record.provider} (${record.provider_id}:${record.asset_id})`);
    lines.push(`- Source: ${record.source_url}`);
    lines.push(`- Creator: ${record.authors.map((author) => author.name).join(", ") || "Not supplied"}`);
    lines.push(`- License: ${record.license.name}${record.license.url ? ` (${record.license.url})` : ""}`);
    lines.push(`- Status: ${["Permissive", "Unknown", "Attribution required", "Blocked"][record.license_status] ?? "Unknown"}`);
    lines.push(`- Attribution: ${record.attribution_text}`);
    lines.push("");
  }
  return `${lines.join("\n").trimEnd()}\n`;
}
