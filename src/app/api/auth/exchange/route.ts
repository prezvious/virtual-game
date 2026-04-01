import { NextRequest, NextResponse } from "next/server";
import type { EmailOtpType } from "@supabase/supabase-js";
import { createAnonServerClient } from "@/lib/supabase";
import { buildRateLimitKey, consumeRateLimit, getRequestIp } from "@/lib/rate-limit";

const AUTH_EXCHANGE_RATE_LIMIT = 20;
const AUTH_EXCHANGE_WINDOW_MS = 5 * 60 * 1000;

const ALLOWED_OTP_TYPES = new Set([
  "signup",
  "invite",
  "magiclink",
  "recovery",
  "email_change",
  "email",
]);

function badRequest(message: string, status = 400) {
  return NextResponse.json({ ok: false, error: message }, { status });
}

function formatSessionPayload(session: {
  access_token?: string;
  refresh_token?: string;
  expires_at?: number | null;
  token_type?: string;
  user?: { id?: string; email?: string | null };
}) {
  return {
    access_token: session.access_token || "",
    refresh_token: session.refresh_token || "",
    expires_at: Number.isFinite(session.expires_at ?? NaN) ? Number(session.expires_at) : null,
    token_type: session.token_type || "bearer",
    user: {
      id: session.user?.id || "",
      email: session.user?.email || null,
    },
  };
}

export async function POST(req: NextRequest) {
  const ip = getRequestIp(req);
  const rate = consumeRateLimit({
    key: buildRateLimitKey("auth-exchange", req),
    limit: AUTH_EXCHANGE_RATE_LIMIT,
    windowMs: AUTH_EXCHANGE_WINDOW_MS,
  });

  if (!rate.allowed) {
    return NextResponse.json(
      { ok: false, error: "Too many auth exchange requests. Please retry shortly." },
      { status: 429 },
    );
  }

  let payload: Record<string, unknown>;
  try {
    payload = (await req.json()) as Record<string, unknown>;
  } catch {
    return badRequest("Invalid JSON payload.");
  }

  const code = typeof payload.code === "string" ? payload.code.trim() : "";
  const tokenHash = typeof payload.token_hash === "string" ? payload.token_hash.trim() : "";
  const otpType = typeof payload.type === "string" ? payload.type.trim() : "";

  if (!code && (!tokenHash || !otpType)) {
    return badRequest("Provide either `code` or (`token_hash` and `type`).");
  }

  const supabase = createAnonServerClient();

  try {
    if (code) {
      const { data, error } = await supabase.auth.exchangeCodeForSession(code);
      if (error || !data?.session) {
        console.warn("[auth-exchange] code exchange failed", {
          ip,
          error: error?.message || "No session returned",
        });
        return badRequest(error?.message || "Code exchange failed.", 401);
      }

      console.info("[auth-exchange] code exchange success", {
        ip,
        userId: data.session.user?.id || "unknown",
      });
      return NextResponse.json({
        ok: true,
        method: "code",
        session: formatSessionPayload(data.session),
      });
    }

    if (!ALLOWED_OTP_TYPES.has(otpType)) {
      return badRequest("Invalid OTP type.");
    }

    const { data, error } = await supabase.auth.verifyOtp({
      token_hash: tokenHash,
      type: otpType as EmailOtpType,
    });

    if (error || !data?.session) {
      console.warn("[auth-exchange] otp verification failed", {
        ip,
        otpType,
        error: error?.message || "No session returned",
      });
      return badRequest(error?.message || "OTP verification failed.", 401);
    }

    console.info("[auth-exchange] otp verification success", {
      ip,
      otpType,
      userId: data.session.user?.id || "unknown",
    });
    return NextResponse.json({
      ok: true,
      method: "otp",
      session: formatSessionPayload(data.session),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected exchange error.";
    console.error("[auth-exchange] unexpected error", { ip, message });
    return NextResponse.json({ ok: false, error: message }, { status: 500 });
  }
}
