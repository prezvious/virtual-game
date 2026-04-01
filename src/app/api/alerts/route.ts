import { NextRequest, NextResponse } from "next/server";
import { getSupabaseConfig } from "@/lib/supabase";
import { consumeRateLimit, getRequestIp } from "@/lib/rate-limit";

const ALERT_RATE_LIMIT = 10;
const ALERT_WINDOW_MS = 60 * 1000;
const ALERT_SIGNATURE_LIMIT = 3;

type AlertBody = {
  type: string;
  user: string;
  userEmail: string | null;
  details: string;
  source: string | null;
  line: number | null;
  column: number | null;
  stack: string | null;
  page: string | null;
  userAgent: string | null;
  sessionActive: boolean | null;
  online: boolean | null;
  timestamp: string;
};

function sanitizeText(value: unknown, maxLength: number): string {
  if (value === null || value === undefined) return "";
  const text = String(value).trim();
  if (!text) return "";
  return text.slice(0, maxLength);
}

function sanitizeBoolean(value: unknown): boolean | null {
  if (typeof value === "boolean") return value;
  return null;
}

function sanitizeNumber(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return Math.trunc(value);
}

function normalizeAlertBody(payload: Record<string, unknown>): AlertBody {
  return {
    type: sanitizeText(payload.type, 64).toUpperCase() || "UNKNOWN",
    user: sanitizeText(payload.user, 128) || "anonymous",
    userEmail: sanitizeText(payload.userEmail, 256) || null,
    details: sanitizeText(payload.details, 3000),
    source: sanitizeText(payload.source, 256) || null,
    line: sanitizeNumber(payload.line),
    column: sanitizeNumber(payload.column),
    stack: sanitizeText(payload.stack, 5000) || null,
    page: sanitizeText(payload.page, 1000) || null,
    userAgent: sanitizeText(payload.userAgent, 1000) || null,
    sessionActive: sanitizeBoolean(payload.sessionActive),
    online: sanitizeBoolean(payload.online),
    timestamp: sanitizeText(payload.timestamp, 80) || new Date().toISOString(),
  };
}

function signatureFor(body: AlertBody): string {
  return `${body.type}|${body.source || ""}|${body.line || ""}|${body.column || ""}|${body.details.slice(0, 220)}`;
}

function getAlertsEdgeUrl(): string {
  if (process.env.SUPABASE_SEND_ALERT_URL) return process.env.SUPABASE_SEND_ALERT_URL;
  const { url } = getSupabaseConfig();
  return `${url}/functions/v1/send-alert`;
}

function getAlertsEdgeKey(): string {
  return (
    process.env.SUPABASE_FUNCTIONS_KEY ||
    process.env.SUPABASE_SERVICE_ROLE_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
    ""
  );
}

function unavailableAlertResponse(reason: string, error: string) {
  return NextResponse.json(
    {
      ok: false,
      skipped: true,
      reason,
      error,
    },
    { status: 202 },
  );
}

export async function POST(req: NextRequest) {
  const ip = getRequestIp(req);
  const ipRate = consumeRateLimit({
    key: `alerts:ip:${ip}`,
    limit: ALERT_RATE_LIMIT,
    windowMs: ALERT_WINDOW_MS,
  });

  if (!ipRate.allowed) {
    return NextResponse.json(
      { ok: false, error: "Too many alert requests. Please retry shortly." },
      { status: 429 },
    );
  }

  let rawPayload: Record<string, unknown>;
  try {
    rawPayload = (await req.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid JSON payload." }, { status: 400 });
  }

  const alertBody = normalizeAlertBody(rawPayload);
  if (!alertBody.details) {
    return NextResponse.json({ ok: false, error: "Alert details are required." }, { status: 400 });
  }

  const signatureRate = consumeRateLimit({
    key: `alerts:sig:${ip}:${signatureFor(alertBody)}`,
    limit: ALERT_SIGNATURE_LIMIT,
    windowMs: ALERT_WINDOW_MS,
  });

  if (!signatureRate.allowed) {
    return NextResponse.json(
      { ok: false, error: "Duplicate alert throttled." },
      { status: 429 },
    );
  }

  const edgeUrl = getAlertsEdgeUrl();
  const edgeKey = getAlertsEdgeKey();

  if (!edgeKey) {
    console.error("[alerts] missing key for edge forwarding");
    return unavailableAlertResponse(
      "alert_forwarding_not_configured",
      "Server is not configured to forward alerts.",
    );
  }

  try {
    console.info("[alerts] forwarding request", {
      ip,
      type: alertBody.type,
      user: alertBody.user,
      source: alertBody.source,
    });

    const upstream = await fetch(edgeUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: edgeKey,
        Authorization: `Bearer ${edgeKey}`,
      },
      body: JSON.stringify(alertBody),
      cache: "no-store",
    });

    const upstreamText = await upstream.text();
    if (!upstream.ok) {
      const upstreamLower = upstreamText.toLowerCase();

      if (
        upstream.status === 404 ||
        upstreamLower.includes("function not found") ||
        upstreamLower.includes("not found")
      ) {
        console.warn("[alerts] send-alert function unavailable", {
          ip,
          status: upstream.status,
          body: upstreamText.slice(0, 500),
        });

        return unavailableAlertResponse(
          "alert_function_unavailable",
          "Alert forwarding unavailable. Deploy the send-alert function or set SUPABASE_SEND_ALERT_URL.",
        );
      }

      console.warn("[alerts] upstream failed", {
        ip,
        status: upstream.status,
        body: upstreamText.slice(0, 500),
      });

      return NextResponse.json(
        {
          ok: false,
          error: `Alert delivery failed (${upstream.status}).`,
        },
        { status: 502 },
      );
    }

    console.info("[alerts] forwarded successfully", {
      ip,
      type: alertBody.type,
    });

    try {
      const json = JSON.parse(upstreamText) as Record<string, unknown>;
      return NextResponse.json({ ok: true, upstream: json });
    } catch {
      return NextResponse.json({ ok: true, upstreamText });
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected alert forwarding error.";
    console.error("[alerts] unexpected failure", { ip, message });
    return NextResponse.json({ ok: false, error: message }, { status: 500 });
  }
}
