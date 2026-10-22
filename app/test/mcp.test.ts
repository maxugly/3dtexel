import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import path from "node:path";
import readline from "node:readline";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { tempHome } from "./support.js";

const appRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

interface RpcResponse {
  id?: number;
  result?: Record<string, unknown>;
  error?: { message: string };
}

async function withTimeout<T>(promise: Promise<T>, message: string): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(message)), 10_000);
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

test("MCP stdio exposes local tools without provider network access", async () => {
  const temporary = await tempHome();
  const child = spawn(process.execPath, ["--import", "tsx", "src/mcp.ts"], {
    cwd: appRoot,
    env: {
      ...process.env,
      ASSET_LIBRARY_HOME: temporary.home,
      ASSET_LIBRARY_OUTPUT: path.join(temporary.home, "library"),
      ASSET_LIBRARY_OFFLINE: "1"
    },
    stdio: ["pipe", "pipe", "pipe"]
  });
  const stderr: string[] = [];
  child.stderr.on("data", (chunk) => stderr.push(String(chunk)));
  const lines = readline.createInterface({ input: child.stdout });
  const pending = new Map<number, (response: RpcResponse) => void>();
  lines.on("line", (line) => {
    let parsed: RpcResponse;
    try {
      parsed = JSON.parse(line) as RpcResponse;
    } catch {
      return;
    }
    if (typeof parsed.id === "number") {
      pending.get(parsed.id)?.(parsed);
      pending.delete(parsed.id);
    }
  });
  let nextId = 1;
  const request = (method: string, params: Record<string, unknown> = {}): Promise<RpcResponse> => {
    const id = nextId++;
    return withTimeout(new Promise<RpcResponse>((resolve) => {
      pending.set(id, resolve);
      child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    }), `MCP request timed out: ${method}`);
  };
  try {
    const initialized = await request("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "asset-library-test", version: "1.0.0" }
    });
    assert.ok(initialized.result);
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" })}\n`);

    const listed = await request("tools/list");
    const tools = (listed.result?.tools ?? []) as Array<{ name: string }>;
    assert.ok(tools.some((tool) => tool.name === "search_assets"));
    assert.ok(tools.some((tool) => tool.name === "download_asset"));
    assert.ok(tools.some((tool) => tool.name === "get_credits"));

    const providers = await request("tools/call", { name: "list_providers", arguments: {} });
    const content = (providers.result?.content ?? []) as Array<{ text: string }>;
    const body = JSON.parse(content[0]!.text) as { providers: Array<{ id: string }> };
    assert.equal(body.providers.length, 9);

    const imports = await request("tools/call", { name: "list_imports", arguments: {} });
    const importContent = (imports.result?.content ?? []) as Array<{ text: string }>;
    assert.deepEqual(JSON.parse(importContent[0]!.text), { imports: [] });
    assert.equal(stderr.join("").trim(), "");
  } finally {
    child.kill("SIGTERM");
    await withTimeout(new Promise<void>((resolve) => child.once("exit", () => resolve())), "MCP process did not exit");
    lines.close();
    await temporary.cleanup();
  }
});

test("CLI providers and stats run offline", async () => {
  const temporary = await tempHome();
  const run = async (args: string[]): Promise<{ code: number | null; stdout: string; stderr: string }> => {
    const child = spawn(process.execPath, ["--import", "tsx", "src/cli.ts", ...args], {
      cwd: appRoot,
      env: {
        ...process.env,
        ASSET_LIBRARY_HOME: temporary.home,
        ASSET_LIBRARY_OUTPUT: path.join(temporary.home, "library"),
        ASSET_LIBRARY_OFFLINE: "1"
      },
      stdio: ["ignore", "pipe", "pipe"]
    });
    const stdout: string[] = [];
    const stderr: string[] = [];
    child.stdout.on("data", (chunk) => stdout.push(String(chunk)));
    child.stderr.on("data", (chunk) => stderr.push(String(chunk)));
    const code = await withTimeout(new Promise<number | null>((resolve) => child.once("exit", resolve)), "CLI timed out");
    return { code, stdout: stdout.join(""), stderr: stderr.join("") };
  };
  try {
    const providers = await run(["providers", "--json"]);
    assert.equal(providers.code, 0);
    assert.equal(providers.stderr, "");
    const body = JSON.parse(providers.stdout) as { providers: Array<{ id: string }> };
    assert.equal(body.providers.length, 9);

    const stats = await run(["stats", "--json"]);
    assert.equal(stats.code, 0);
    assert.equal(stats.stderr, "");
    assert.deepEqual(JSON.parse(stats.stdout), { catalog: { assets: 0, by_provider: {}, by_type: {} } });
  } finally {
    await temporary.cleanup();
  }
});
