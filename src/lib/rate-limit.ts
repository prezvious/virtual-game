import { NextRequest } from "next/server";
import { createHash } from "node:crypto";
import { isIP } from "node:net";

type Bucket = {
  count: number;
  resetAt: number;
};

type BucketStore = Map<string, Bucket>;

declare global {
  var __vfRateLimitStore: BucketStore | undefined;
  var __vfRateLimitCleanup: ReturnType<typeof setInterval> | undefined;
}

const store: BucketStore = globalThis.__vfRateLimitStore ?? new Map<string, Bucket>();
globalThis.__vfRateLimitStore = store;

// Fix C-3: Periodic cleanup of expired buckets to prevent memory leak
if (!globalThis.__vfRateLimitCleanup) {
  globalThis.__vfRateLimitCleanup = setInterval(() => {
    const now = Date.now();
    for (const [key, bucket] of store.entries()) {
      if (bucket.resetAt <= now) {
        store.delete(key);
      }
    }
  }, 60_000); // Clean up every minute
}

type ConsumeParams = {
  key: string;
  limit: number;
  windowMs: number;
};

export type RateLimitResult = {
  allowed: boolean;
  remaining: number;
  resetAt: number;
};

export function consumeRateLimit({ key, limit, windowMs }: ConsumeParams): RateLimitResult {
  const now = Date.now();
  const cached = store.get(key);

  if (!cached || cached.resetAt <= now) {
    const next: Bucket = {
      count: 1,
      resetAt: now + windowMs,
    };
    store.set(key, next);
    return {
      allowed: true,
      remaining: Math.max(0, limit - 1),
      resetAt: next.resetAt,
    };
  }

  cached.count += 1;
  store.set(key, cached);
  const allowed = cached.count <= limit;
  return {
    allowed,
    remaining: Math.max(0, limit - cached.count),
    resetAt: cached.resetAt,
  };
}

const TRUSTED_PRODUCTION_IP_HEADERS = [
  "x-vercel-forwarded-for",
  "cf-connecting-ip",
  "fly-client-ip",
  "x-real-ip",
];

const TRUSTED_NON_PRODUCTION_IP_HEADERS = [
  ...TRUSTED_PRODUCTION_IP_HEADERS,
  "x-forwarded-for",
];

function normalizeIpCandidate(value: string | null): string | null {
  if (!value) return null;
  const candidate = value.split(",")[0]?.trim() || "";
  return isIP(candidate) ? candidate : null;
}

function getTrustedRequestIp(req: NextRequest): string | null {
  const trustedHeaders = process.env.NODE_ENV === "production"
    ? TRUSTED_PRODUCTION_IP_HEADERS
    : TRUSTED_NON_PRODUCTION_IP_HEADERS;

  for (const header of trustedHeaders) {
    const ip = normalizeIpCandidate(req.headers.get(header));
    if (ip) {
      return ip;
    }
  }

  return null;
}

function createStableFingerprint(parts: string[]) {
  return createHash("sha256")
    .update(parts.join("\n"))
    .digest("hex")
    .slice(0, 24);
}

function getAnonymousFallbackKey(req: NextRequest) {
  const host = req.headers.get("host")?.trim().toLowerCase() || "unknown-host";
  const userAgent = req.headers.get("user-agent")?.trim().toLowerCase() || "unknown-agent";
  return `fallback:${createStableFingerprint([host, userAgent])}`;
}

export function getRequestIp(req: NextRequest): string {
  return getTrustedRequestIp(req) || getAnonymousFallbackKey(req);
}

export function buildRateLimitKey(
  scope: string,
  req: NextRequest,
  options: {
    userId?: string | null;
  } = {},
): string {
  const userId = typeof options.userId === "string" ? options.userId.trim() : "";
  const clientKey = getRequestIp(req);

  if (userId) {
    return `${scope}:user:${userId}:${clientKey}`;
  }

  return `${scope}:${clientKey}`;
}
