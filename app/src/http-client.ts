import { createHash, randomBytes } from "node:crypto";
import { mkdir, open, rename, rm } from "node:fs/promises";
import path from "node:path";
import type {
  DownloadOptions,
  DownloadResult,
  HttpTransport,
  JsonRequestOptions,
  TextRequestOptions
} from "./types.js";
import { readJson, sha256Text, writeJsonAtomic } from "./util/fs.js";
import { redactUrl } from "./util/sanitize.js";

interface CacheEntry {
  schema_version: 1;
  url: string;
  fetched_at: string;
  content_type: string;
  etag?: string;
  last_modified?: string;
  body: string;
}

export interface HttpClientOptions {
  cacheDir: string;
  offline?: boolean;
  timeoutMs?: number;
  maxBytes?: number;
  minIntervalMs?: number;
  userAgent?: string;
  fetchImpl?: typeof fetch;
}

export class OfflineError extends Error {
  constructor(url: string) {
    super(`Offline mode: no cached response for ${redactUrl(url)}`);
    this.name = "OfflineError";
  }
}

export class HttpError extends Error {
  readonly status?: number;
  constructor(message: string, status?: number) {
    super(message);
    this.name = "HttpError";
    this.status = status;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRedirect(status: number): boolean {
  return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
}

function retryDelay(value: string | null): number {
  if (!value) {
    return 1000;
  }
  const seconds = Number(value);
  if (Number.isFinite(seconds)) {
    return Math.max(250, Math.min(seconds * 1000, 5000));
  }
  return 1000;
}

export class HttpClient implements HttpTransport {
  private readonly cacheDir: string;
  private readonly offline: boolean;
  private readonly timeoutMs: number;
  private readonly maxBytes: number;
  private readonly minIntervalMs: number;
  private readonly userAgent: string;
  private readonly fetchImpl: typeof fetch;
  private readonly hostPace = new Map<string, number>();

  constructor(options: HttpClientOptions) {
    this.cacheDir = path.resolve(options.cacheDir);
    this.offline = options.offline ?? false;
    this.timeoutMs = options.timeoutMs ?? 30_000;
    this.maxBytes = options.maxBytes ?? 32 * 1024 * 1024;
    this.minIntervalMs = options.minIntervalMs ?? 500;
    this.userAgent = options.userAgent ?? "asset-library/0.1";
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  private cachePath(url: string): string {
    return path.join(this.cacheDir, "http", `${sha256Text(url)}.json`);
  }

  private async readCache(url: string): Promise<CacheEntry | null> {
    const entry = await readJson<CacheEntry>(this.cachePath(url));
    if (!entry || entry.schema_version !== 1 || typeof entry.body !== "string") {
      return null;
    }
    return entry;
  }

  private async writeCache(url: string, response: Response, body: string): Promise<void> {
    const entry: CacheEntry = {
      schema_version: 1,
      url: redactUrl(url),
      fetched_at: new Date().toISOString(),
      content_type: response.headers.get("content-type") ?? "application/octet-stream",
      etag: response.headers.get("etag") ?? undefined,
      last_modified: response.headers.get("last-modified") ?? undefined,
      body
    };
    await writeJsonAtomic(this.cachePath(url), entry);
  }

  private async pace(url: string, requested?: number): Promise<void> {
    const interval = Math.max(this.minIntervalMs, requested ?? 0);
    const host = new URL(url).host;
    const previous = this.hostPace.get(host) ?? 0;
    const wait = previous + interval - Date.now();
    if (wait > 0) {
      await sleep(wait);
    }
    this.hostPace.set(host, Date.now());
  }

  private async request(
    url: string,
    options: {
      method: "GET" | "POST";
      headers?: Record<string, string>;
      body?: unknown;
      conditional?: boolean;
      cached?: CacheEntry | null;
      timeout_ms?: number;
      signal?: AbortSignal;
      pace_ms?: number;
      allow_redirect?: boolean;
    }
  ): Promise<{ response: Response; finalUrl: string }> {
    let current = url;
    let method = options.method;
    let body = options.body;
    let headers = new Headers({
      "User-Agent": this.userAgent,
      Accept: "application/json, text/html;q=0.9, */*;q=0.1"
    });
    for (const [name, value] of Object.entries(options.headers ?? {})) {
      headers.set(name, value);
    }
    if (options.conditional && options.cached?.etag) {
      headers.set("If-None-Match", options.cached.etag);
    }
    if (options.conditional && options.cached?.last_modified) {
      headers.set("If-Modified-Since", options.cached.last_modified);
    }
    if (body !== undefined) {
      headers.set("Content-Type", "application/json");
    }
    let origin = new URL(url).origin;
    const redirects = options.allow_redirect === false ? 0 : 5;

    for (let hop = 0; hop <= redirects; hop += 1) {
      const parsed = new URL(current);
      if (parsed.protocol !== "https:") {
        throw new HttpError("Only HTTPS requests are permitted.");
      }
      if (this.offline) {
        throw new OfflineError(current);
      }
      await this.pace(current, options.pace_ms);
      const timeout = AbortSignal.timeout(options.timeout_ms ?? this.timeoutMs);
      const signal = options.signal ? AbortSignal.any([options.signal, timeout]) : timeout;
      const response = await this.fetchImpl(current, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        redirect: "manual",
        signal
      });

      if (isRedirect(response.status)) {
        const location = response.headers.get("location");
        if (!location) {
          throw new HttpError(`Redirect without a location from ${redactUrl(current)}`, response.status);
        }
        if (hop === redirects) {
          throw new HttpError(`Too many redirects for ${redactUrl(url)}`);
        }
        const next = new URL(location, current);
        if (next.protocol !== "https:") {
          throw new HttpError("Refused a non-HTTPS redirect.");
        }
        if (next.origin !== origin) {
          headers = new Headers(headers);
          headers.delete("Authorization");
          headers.delete("Cookie");
          origin = next.origin;
        }
        if (response.status === 303 || ((response.status === 301 || response.status === 302) && method === "POST")) {
          method = "GET";
          body = undefined;
          headers.delete("Content-Type");
        }
        current = next.toString();
        continue;
      }
      return { response, finalUrl: current };
    }
    throw new HttpError(`Too many redirects for ${redactUrl(url)}`);
  }

  private async readText(response: Response, url: string): Promise<string> {
    const length = Number(response.headers.get("content-length") ?? 0);
    if (length > this.maxBytes) {
      throw new HttpError(`Response is too large (${length} bytes) from ${redactUrl(url)}`);
    }
    const body = await response.text();
    if (Buffer.byteLength(body, "utf8") > this.maxBytes) {
      throw new HttpError(`Response is too large from ${redactUrl(url)}`);
    }
    return body;
  }

  private async textInternal(url: string, options: TextRequestOptions & { pace_ms?: number } = {}): Promise<string> {
    const cached = await this.readCache(url);
    if (cached && !options.refresh) {
      return cached.body;
    }
    if (this.offline) {
      if (cached) {
        return cached.body;
      }
      throw new OfflineError(url);
    }
    let result = await this.request(url, {
      method: "GET",
      headers: options.headers,
      conditional: Boolean(cached),
      cached,
      timeout_ms: options.timeout_ms,
      signal: options.signal,
      pace_ms: options.pace_ms
    });
    if (result.response.status === 429) {
      const delay = retryDelay(result.response.headers.get("retry-after"));
      await result.response.arrayBuffer();
      await sleep(delay);
      result = await this.request(url, {
        method: "GET",
        headers: options.headers,
        conditional: false,
        timeout_ms: options.timeout_ms,
        signal: options.signal,
        pace_ms: options.pace_ms
      });
    }
    const { response, finalUrl } = result;
    if (response.status === 304 && cached) {
      return cached.body;
    }
    if (!response.ok) {
      throw new HttpError(`HTTP ${response.status} from ${redactUrl(finalUrl)}`, response.status);
    }
    const text = await this.readText(response, finalUrl);
    await this.writeCache(url, response, text);
    return text;
  }

  async text(url: string, options: TextRequestOptions & { pace_ms?: number } = {}): Promise<string> {
    return this.textInternal(url, options);
  }

  async json<T>(url: string, options: JsonRequestOptions & { pace_ms?: number } = {}): Promise<T> {
    const method = options.method ?? "GET";
    if (method === "GET") {
      const body = await this.textInternal(url, {
        headers: options.headers,
        refresh: options.refresh,
        timeout_ms: options.timeout_ms,
        signal: options.signal,
        pace_ms: options.pace_ms
      });
      try {
        return JSON.parse(body) as T;
      } catch {
        throw new HttpError(`Expected JSON from ${redactUrl(url)}`);
      }
    }

    const cached = await this.readCache(url);
    if (this.offline) {
      throw new OfflineError(url);
    }
    const { response, finalUrl } = await this.request(url, {
      method: "POST",
      headers: options.headers,
      body: options.body,
      timeout_ms: options.timeout_ms,
      signal: options.signal,
      pace_ms: options.pace_ms,
      allow_redirect: false
    });
    if (response.status === 429) {
      await response.arrayBuffer();
      await sleep(retryDelay(response.headers.get("retry-after")));
      const retry = await this.request(url, {
        method: "POST",
        headers: options.headers,
        body: options.body,
        timeout_ms: options.timeout_ms,
        signal: options.signal,
        pace_ms: options.pace_ms,
        allow_redirect: false
      });
      if (!retry.response.ok) {
        throw new HttpError(`HTTP ${retry.response.status} from ${redactUrl(retry.finalUrl)}`, retry.response.status);
      }
      const text = await this.readText(retry.response, retry.finalUrl);
      try {
        return JSON.parse(text) as T;
      } catch {
        throw new HttpError(`Expected JSON from ${redactUrl(url)}`);
      }
    }
    if (!response.ok) {
      throw new HttpError(`HTTP ${response.status} from ${redactUrl(finalUrl)}`, response.status);
    }
    const text = await this.readText(response, finalUrl);
    if (cached) {
      await this.writeCache(url, response, text);
    }
    try {
      return JSON.parse(text) as T;
    } catch {
      throw new HttpError(`Expected JSON from ${redactUrl(url)}`);
    }
  }

  async download(url: string, destination: string, options: DownloadOptions & { pace_ms?: number } = {}): Promise<DownloadResult> {
    if (this.offline) {
      throw new OfflineError(url);
    }
    const parsed = new URL(url);
    if (parsed.protocol !== "https:") {
      throw new HttpError("Only HTTPS downloads are supported.");
    }
    await mkdir(path.dirname(destination), { recursive: true });
    const temporary = `${destination}.${process.pid}.${randomBytes(6).toString("hex")}.pending`;
    const headers = new Headers({
      "User-Agent": this.userAgent,
      Accept: "*/*"
    });
    for (const [name, value] of Object.entries(options.headers ?? {})) {
      if (!/^(authorization|cookie)$/i.test(name)) {
        headers.set(name, value);
      }
    }

    let current = url;
    let origin = parsed.origin;
    try {
      for (let hop = 0; hop <= 5; hop += 1) {
        const target = new URL(current);
        if (target.protocol !== "https:") {
          throw new HttpError("Refused a non-HTTPS download redirect.");
        }
        await this.pace(current, options.pace_ms);
        const timeout = AbortSignal.timeout(options.timeout_ms ?? 120_000);
        const signal = options.signal ? AbortSignal.any([options.signal, timeout]) : timeout;
        const response = await this.fetchImpl(current, {
          method: "GET",
          headers,
          redirect: "manual",
          signal
        });
        if (isRedirect(response.status)) {
          const location = response.headers.get("location");
          if (!location || hop === 5) {
            throw new HttpError(`Download redirect failed for ${redactUrl(url)}`, response.status);
          }
          const next = new URL(location, current);
          if (next.protocol !== "https:") {
            throw new HttpError("Refused a non-HTTPS download redirect.");
          }
          if (next.origin !== origin) {
            headers.delete("Authorization");
            headers.delete("Cookie");
            origin = next.origin;
          }
          current = next.toString();
          continue;
        }
        if (!response.ok || !response.body) {
          throw new HttpError(`Download failed with HTTP ${response.status} from ${redactUrl(current)}`, response.status);
        }
        const contentLength = Number(response.headers.get("content-length") ?? 0);
        const limit = options.max_bytes ?? this.maxBytes;
        if (contentLength > limit) {
          throw new HttpError(`Download exceeds the ${limit} byte limit.`);
        }
        const handle = await open(temporary, "w");
        const hash = createHash("sha256");
        let bytes = 0;
        try {
          for await (const chunk of response.body as unknown as AsyncIterable<Uint8Array>) {
            bytes += chunk.byteLength;
            if (bytes > limit) {
              throw new HttpError(`Download exceeds the ${limit} byte limit.`);
            }
            hash.update(chunk);
            await handle.write(chunk);
          }
        } finally {
          await handle.close();
        }
        if (!bytes) {
          throw new HttpError(`Downloaded an empty file from ${redactUrl(current)}`);
        }
        await rename(temporary, destination);
        return {
          bytes,
          sha256: hash.digest("hex"),
          content_type: response.headers.get("content-type") ?? undefined,
          final_url: redactUrl(current)
        };
      }
      throw new HttpError(`Too many redirects for ${redactUrl(url)}`);
    } catch (error) {
      await rm(temporary, { force: true });
      throw error;
    }
  }
}
