const SECRET_KEY = /(^|_)(api[_-]?key|apikey|authorization|auth|token|access[_-]?token|refresh[_-]?token|secret|password|passwd|signature|credential|credentials|cookie|session)(_|$)/i;
const SENSITIVE_QUERY = /^(api[_-]?key|apikey|key|token|access[_-]?token|auth|authorization|signature|sig|expires|expiry|x-amz-|x-goog-|policy|credential|password|secret|session)$/i;

export function isSensitiveKey(key: string): boolean {
  return SECRET_KEY.test(key);
}

export function isSignedUrl(value: string): boolean {
  try {
    const parsed = new URL(value);
    for (const name of parsed.searchParams.keys()) {
      if (SENSITIVE_QUERY.test(name) || name.toLowerCase().startsWith("x-amz-") || name.toLowerCase().startsWith("x-goog-")) {
        return true;
      }
    }
    return false;
  } catch {
    return false;
  }
}

export function sanitizeUrl(value: string): string | undefined {
  if (!value) {
    return undefined;
  }
  return isSignedUrl(value) ? undefined : value;
}

export function redactUrl(value: string): string {
  try {
    const parsed = new URL(value);
    parsed.search = "";
    parsed.username = "";
    parsed.password = "";
    return parsed.toString();
  } catch {
    return value.split("?")[0] ?? value;
  }
}

function sanitizeValue(value: unknown, key: string, depth: number): unknown {
  if (depth > 12) {
    return undefined;
  }
  if (isSensitiveKey(key)) {
    return undefined;
  }
  if (typeof value === "string") {
    const trimmed = value.length > 20_000 ? value.slice(0, 20_000) : value;
    if (/^https?:\/\//i.test(trimmed)) {
      return sanitizeUrl(trimmed);
    }
    return trimmed;
  }
  if (typeof value === "number" || typeof value === "boolean" || value === null) {
    return value;
  }
  if (Array.isArray(value)) {
    const result: unknown[] = [];
    for (const item of value.slice(0, 500)) {
      const sanitized = sanitizeValue(item, key, depth + 1);
      if (sanitized !== undefined) {
        result.push(sanitized);
      }
    }
    return result;
  }
  if (typeof value === "object") {
    const result: Record<string, unknown> = {};
    for (const [childKey, childValue] of Object.entries(value as Record<string, unknown>)) {
      const sanitized = sanitizeValue(childValue, childKey, depth + 1);
      if (sanitized !== undefined) {
        result[childKey] = sanitized;
      }
    }
    return result;
  }
  return undefined;
}

export function sanitizeRecord(value: unknown): Record<string, unknown> {
  const sanitized = sanitizeValue(value, "", 0);
  return sanitized && typeof sanitized === "object" && !Array.isArray(sanitized)
    ? sanitized as Record<string, unknown>
    : {};
}

export function redactMessage(value: string): string {
  return value
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, "Bearer [redacted]")
    .replace(/([?&](?:api[_-]?key|token|key|signature|sig|expires)=)[^&\s]+/gi, "$1[redacted]")
    .replace(/(3DTEXEL_API_KEY|TEXEL_API_KEY|TEXEL|ASSET_LIBRARY_TOKEN)=([^\s]+)/g, "$1=[redacted]")
    .slice(0, 1000);
}

export function assertHttpsUrl(value: string): string {
  const parsed = new URL(value);
  if (parsed.protocol !== "https:") {
    throw new Error("Only HTTPS URLs are supported.");
  }
  return value;
}

export function assertPublicUrl(value: string): string {
  assertHttpsUrl(value);
  if (isSignedUrl(value)) {
    throw new Error("Signed URLs are not accepted as persisted metadata.");
  }
  return value;
}
