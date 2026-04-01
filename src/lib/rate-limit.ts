import { NextRequest } from "next/server";

type Bucket = {
  count: number;
  resetAt: number;
};

type BucketStore = Map<string, Bucket>;

declare global {
  var __vfRateLimitStore: BucketStore | undefined;
}

const store: BucketStore = globalThis.__vfRateLimitStore ?? new Map<string, Bucket>();
globalThis.__vfRateLimitStore = store;

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

export function getRequestIp(req: NextRequest): string {
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) {
    const [ip] = forwarded.split(",").map((part) => part.trim());
    if (ip) return ip;
  }

  const realIp = req.headers.get("x-real-ip");
  if (realIp) return realIp.trim();

  return `anon:${crypto.randomUUID()}`;
}
