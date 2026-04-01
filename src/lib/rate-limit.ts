import { NextRequest } from "next/server";

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

// Fix H-1: Use x-forwarded-for with validation instead of trusting blindly
// Fix N-12: Fall back to a stable key instead of random UUID per request
export function getRequestIp(req: NextRequest): string {
  // Use x-forwarded-for but validate it looks like an IP
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) {
    const [ip] = forwarded.split(",").map((part) => part.trim());
    // Validate it looks like an IP address (basic check)
    if (ip && /^(?:\d{1,3}\.){3}\d{1,3}$/.test(ip)) {
      return ip;
    }
  }

  const realIp = req.headers.get("x-real-ip");
  if (realIp && /^(?:\d{1,3}\.){3}\d{1,3}$/.test(realIp.trim())) {
    return realIp.trim();
  }

  // Fix N-12: Use a fallback that doesn't create a unique key per request
  // Use the host header + a fixed suffix to create a consistent key for unknown IPs
  const host = req.headers.get("host") || "unknown";
  return `fallback:${host}`;
}
