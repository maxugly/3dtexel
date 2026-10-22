import { timingSafeEqual } from "node:crypto";
import http, { type IncomingMessage, type ServerResponse } from "node:http";
import type { AssetCategory } from "./types.js";
import type { AssetLibrary } from "./index.js";
import { ASSET_CATEGORIES } from "./types.js";
import { redactMessage } from "./util/sanitize.js";

const MAX_BODY_BYTES = 1024 * 1024;

class HttpStatusError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function json(response: ServerResponse, status: number, value: unknown): void {
  const body = `${JSON.stringify(value, null, 2)}\n`;
  response.statusCode = status;
  response.setHeader("Content-Type", "application/json; charset=utf-8");
  response.setHeader("Content-Length", Buffer.byteLength(body));
  response.setHeader("Cache-Control", "no-store");
  response.end(body);
}

function safeEqual(left: string, right: string): boolean {
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}

function authorized(request: IncomingMessage, token?: string): boolean {
  if (!token) {
    return true;
  }
  const header = request.headers.authorization ?? "";
  return header.startsWith("Bearer ") && safeEqual(header.slice(7), token);
}

async function body(request: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > MAX_BODY_BYTES) {
      throw new HttpStatusError(413, "Request body is too large.");
    }
    chunks.push(buffer);
  }
  if (!chunks.length) {
    return {};
  }
  try {
    const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("Body must be a JSON object.");
    }
    return parsed as Record<string, unknown>;
  } catch {
    throw new HttpStatusError(400, "Request body must be valid JSON.");
  }
}

function category(value: string | null): AssetCategory | undefined {
  if (!value) {
    return undefined;
  }
  if (!(ASSET_CATEGORIES as readonly string[]).includes(value)) {
    throw new HttpStatusError(400, `Unknown category: ${value}`);
  }
  return value as AssetCategory;
}

function number(value: string | null): number | undefined {
  if (!value) {
    return undefined;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new HttpStatusError(400, `Invalid number: ${value}`);
  }
  return parsed;
}

function list(value: unknown): string[] | undefined {
  if (Array.isArray(value)) {
    return value.map(String).map((entry) => entry.trim()).filter(Boolean);
  }
  if (typeof value === "string") {
    return value.split(",").map((entry) => entry.trim()).filter(Boolean);
  }
  return undefined;
}

function pathParts(pathname: string): string[] {
  return pathname.split("/").filter(Boolean).map((part) => decodeURIComponent(part));
}

async function route(library: AssetLibrary, request: IncomingMessage, response: ServerResponse): Promise<void> {
  const url = new URL(request.url ?? "/", "http://localhost");
  const parts = pathParts(url.pathname);
  const method = request.method ?? "GET";

  if (method === "GET" && url.pathname === "/health") {
    json(response, 200, { ok: true, version: "0.1.0" });
    return;
  }
  if (method === "GET" && url.pathname === "/v1/providers") {
    json(response, 200, { providers: await library.providers() });
    return;
  }
  if (method === "GET" && url.pathname === "/v1/stats") {
    json(response, 200, { catalog: library.catalogStats() });
    return;
  }
  if (method === "GET" && url.pathname === "/v1/review") {
    json(response, 200, { assets: library.reviewQueue() });
    return;
  }
  if (method === "GET" && url.pathname === "/v1/search") {
    const result = await library.search({
      query: url.searchParams.get("q") ?? url.searchParams.get("query") ?? "",
      category: category(url.searchParams.get("category")),
      providers: list(url.searchParams.get("providers")),
      limit: number(url.searchParams.get("limit")),
      free_only: ["1", "true", "yes"].includes((url.searchParams.get("free") ?? "").toLowerCase()),
      license: url.searchParams.get("license") ?? undefined,
      refresh: ["1", "true", "yes"].includes((url.searchParams.get("refresh") ?? "").toLowerCase()),
      mode: url.searchParams.get("mode") === "catalog" ? "catalog" : "network"
    });
    json(response, 200, result);
    return;
  }
  if (method === "GET" && url.pathname === "/v1/imports") {
    json(response, 200, {
      imports: await library.imports({
        provider_id: url.searchParams.get("provider_id") ?? undefined,
        asset_id: url.searchParams.get("asset_id") ?? undefined
      })
    });
    return;
  }
  if (parts[0] === "v1" && parts[1] === "providers" && parts[3] === "check" && method === "POST") {
    const result = await library.checkProvider(parts[2]!);
    json(response, result.ok ? 200 : 502, result);
    return;
  }
  if (parts[0] === "v1" && parts[1] === "credits" && parts[2] && parts[3] && method === "GET") {
    json(response, 200, {
      credits: await library.credits(parts[2], parts[3], url.searchParams.get("variant") ?? undefined)
    });
    return;
  }
  if (parts[0] === "v1" && parts[1] === "assets" && parts[2] && parts[3]) {
    const providerId = parts[2];
    const assetId = parts[3];
    if (method === "GET" && parts.length === 4) {
      json(response, 200, await library.getAsset(providerId, assetId, {
        refresh: ["1", "true", "yes"].includes((url.searchParams.get("refresh") ?? "").toLowerCase())
      }));
      return;
    }
    if (method === "GET" && parts[4] === "variants" && parts.length === 5) {
      json(response, 200, await library.variants(providerId, assetId, {
        refresh: ["1", "true", "yes"].includes((url.searchParams.get("refresh") ?? "").toLowerCase())
      }));
      return;
    }
    if (method === "POST" && parts[4] === "plan" && parts.length === 5) {
      const payload = await body(request);
      json(response, 200, await library.planDownload(providerId, assetId, typeof payload.variant === "string" ? payload.variant : undefined));
      return;
    }
  }
  if (method === "POST" && url.pathname === "/v1/downloads") {
    const payload = await body(request);
    if (typeof payload.provider_id !== "string" || typeof payload.asset_id !== "string") {
      throw new HttpStatusError(400, "provider_id and asset_id are required.");
    }
    const result = await library.download(
      payload.provider_id,
      payload.asset_id,
      typeof payload.variant === "string" ? payload.variant : undefined
    );
    json(response, 200, result);
    return;
  }
  if (method === "POST" && url.pathname === "/v1/downloads/batch") {
    const payload = await body(request);
    if (!Array.isArray(payload.jobs)) {
      throw new HttpStatusError(400, "jobs must be an array.");
    }
    const jobs = payload.jobs.map((entry) => {
      if (!entry || typeof entry !== "object") {
        throw new HttpStatusError(400, "Each job must be an object.");
      }
      const job = entry as Record<string, unknown>;
      if (typeof job.provider_id !== "string" || typeof job.asset_id !== "string") {
        throw new HttpStatusError(400, "Each job requires provider_id and asset_id.");
      }
      return {
        provider_id: job.provider_id,
        asset_id: job.asset_id,
        variant: typeof job.variant === "string" ? job.variant : ""
      };
    });
    json(response, 200, await library.downloadMany(jobs));
    return;
  }
  throw new HttpStatusError(404, "Not found.");
}

export interface HttpServerOptions {
  host?: string;
  port?: number;
}

export interface RunningHttpServer {
  host: string;
  port: number;
  url: string;
  close(): Promise<void>;
}

export async function startHttpServer(library: AssetLibrary, options: HttpServerOptions = {}): Promise<RunningHttpServer> {
  const host = options.host ?? library.config.http_host;
  const port = options.port ?? library.config.http_port;
  const loopback = host === "127.0.0.1" || host === "localhost" || host === "::1";
  if (!loopback && !library.config.http_token) {
    throw new Error("Refusing a non-loopback HTTP bind without ASSET_LIBRARY_TOKEN.");
  }
  const server = http.createServer((request, response) => {
    const origin = library.config.cors_origin;
    if (origin) {
      response.setHeader("Access-Control-Allow-Origin", origin);
      response.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");
      response.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    }
    if (request.method === "OPTIONS") {
      response.statusCode = origin ? 204 : 403;
      response.end();
      return;
    }
    if (!authorized(request, library.config.http_token)) {
      response.setHeader("WWW-Authenticate", "Bearer");
      json(response, 401, { error: "Unauthorized." });
      return;
    }
    void route(library, request, response).catch((error: unknown) => {
      if (response.headersSent) {
        response.end();
        return;
      }
      const status = error instanceof HttpStatusError ? error.status : 500;
      const message = error instanceof Error ? redactMessage(error.message) : "Request failed.";
      json(response, status, { error: message });
    });
  });
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, () => {
      server.off("error", reject);
      resolve();
    });
  });
  const address = server.address();
  const actualPort = address && typeof address === "object" ? address.port : port;
  return {
    host,
    port: actualPort,
    url: `http://${host}:${actualPort}`,
    close: () => new Promise<void>((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    })
  };
}
