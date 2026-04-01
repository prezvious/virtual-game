export const BAN_NOTICE_STORAGE_KEY = "vh:ban-notice";

const TEN_YEARS_MS = 1000 * 60 * 60 * 24 * 365 * 10;

export type BanStatusResponse =
  | {
      ok: true;
      banned: false;
    }
  | {
      ok: true;
      banned: true;
      bannedUntil: string | null;
      isPermanent: boolean;
      reason?: string;
    };

export type BanNotice = {
  bannedUntil: string | null;
  isPermanent: boolean;
  reason?: string;
};

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

export function extractBannedUntil(user: unknown): string | null {
  if (!isRecord(user)) return null;
  const bannedUntil = user.banned_until;
  if (typeof bannedUntil === "string" && bannedUntil.trim()) {
    return bannedUntil;
  }
  return null;
}

export function isPermanentBan(bannedUntil: string | null): boolean {
  if (!bannedUntil) return true;
  const bannedAt = Date.parse(bannedUntil);
  return Number.isFinite(bannedAt) && bannedAt > Date.now() + TEN_YEARS_MS;
}

export function extractAuthErrorCode(error: unknown): string | null {
  if (!isRecord(error)) return null;
  const code = error.code;
  return typeof code === "string" && code.trim() ? code : null;
}

export function extractUserIdFromAccessToken(token: string): string | null {
  const parts = token.split(".");
  if (parts.length < 2) return null;

  try {
    const normalized = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    const decoded = typeof globalThis.atob === "function"
      ? globalThis.atob(padded)
      : Buffer.from(padded, "base64").toString("utf-8");
    const payload = JSON.parse(decoded) as Record<string, unknown>;
    const subject = payload.sub;
    return typeof subject === "string" && subject.trim() ? subject : null;
  } catch {
    return null;
  }
}
