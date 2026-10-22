import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type {
  DownloadOptions,
  DownloadResult,
  HttpTransport,
  JsonRequestOptions,
  ProviderContext,
  TextRequestOptions
} from "../src/types.js";

export const FIXTURES = fileURLToPath(new URL("./fixtures/", import.meta.url));
export const FIXED_NOW = new Date("2026-10-21T12:00:00.000Z");

export function fixturePath(...parts: string[]): string {
  return path.join(FIXTURES, ...parts);
}

export async function fixtureText(...parts: string[]): Promise<string> {
  return readFile(fixturePath(...parts), "utf8");
}

export async function fixtureJson<T>(...parts: string[]): Promise<T> {
  return JSON.parse(await fixtureText(...parts)) as T;
}

export function fixtureJsonSync<T>(...parts: string[]): T {
  return JSON.parse(readFileSync(fixturePath(...parts), "utf8")) as T;
}

export type RouteValue = unknown | ((url: string, options: unknown) => unknown);

export interface JsonRoute {
  match: string | RegExp;
  method?: "GET" | "POST";
  value: RouteValue;
}

export interface TextRoute {
  match: string | RegExp;
  value: string | ((url: string, options: unknown) => string);
}

function matches(match: string | RegExp, url: string): boolean {
  return typeof match === "string"
    ? url === match || url.startsWith(`${match}?`) || url.startsWith(`${match}/`)
    : match.test(url);
}

export class FakeHttp implements HttpTransport {
  readonly jsonRoutes: JsonRoute[];
  readonly textRoutes: TextRoute[];
  readonly calls: Array<{ method: string; url: string; body?: unknown }> = [];
  readonly downloads: string[] = [];

  constructor(options: { json?: JsonRoute[]; text?: TextRoute[] } = {}) {
    this.jsonRoutes = options.json ?? [];
    this.textRoutes = options.text ?? [];
  }

  async json<T>(url: string, options: JsonRequestOptions = {}): Promise<T> {
    const method = options.method ?? "GET";
    this.calls.push({ method, url, body: options.body });
    const route = this.jsonRoutes.find((candidate) =>
      (candidate.method ?? "GET") === method && matches(candidate.match, url)
    );
    if (!route) {
      throw new Error(`No fake JSON route for ${method} ${url}`);
    }
    const value = typeof route.value === "function"
      ? (route.value as (url: string, options: unknown) => unknown)(url, options)
      : route.value;
    return structuredClone(value) as T;
  }

  async text(url: string, options: TextRequestOptions = {}): Promise<string> {
    this.calls.push({ method: "GET", url });
    const route = this.textRoutes.find((candidate) => matches(candidate.match, url));
    if (!route) {
      throw new Error(`No fake text route for ${url}`);
    }
    return typeof route.value === "function"
      ? (route.value as (url: string, options: unknown) => string)(url, options)
      : route.value;
  }

  async download(url: string, destination: string, _options: DownloadOptions = {}): Promise<DownloadResult> {
    this.downloads.push(url);
    await mkdir(path.dirname(destination), { recursive: true });
    const body = Buffer.from(`fixture bytes for ${url}\n`, "utf8");
    await writeFile(destination, body);
    return {
      bytes: body.byteLength,
      sha256: createHash("sha256").update(body).digest("hex"),
      content_type: url.endsWith(".png") ? "image/png" : "application/octet-stream",
      final_url: url
    };
  }
}

export function context(http: HttpTransport, env: Record<string, string | undefined> = {}): ProviderContext {
  return {
    http,
    env,
    now: () => FIXED_NOW
  };
}

export async function tempHome(): Promise<{ home: string; cleanup: () => Promise<void> }> {
  const home = await mkdtemp(path.join(os.tmpdir(), "asset-library-test-"));
  return {
    home,
    cleanup: () => rm(home, { recursive: true, force: true })
  };
}

export async function readJsonFile<T>(file: string): Promise<T> {
  return JSON.parse(await readFile(file, "utf8")) as T;
}
