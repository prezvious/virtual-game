import { NextRequest, NextResponse } from "next/server";
import { createAnonServerClient, createServiceSupabaseClient, stripBearer } from "@/lib/supabase";
import { buildRateLimitKey, consumeRateLimit } from "@/lib/rate-limit";

const DEFAULT_LIMIT = 12;
const MAX_LIMIT = 24;

// Fix N-13: Rate limiting for profile discover to prevent enumeration
const DISCOVER_RATE_LIMIT = 20;
const DISCOVER_WINDOW_MS = 60_000;

function sanitizeLimit(rawValue: string | null) {
  const parsed = Number(rawValue || DEFAULT_LIMIT);
  if (!Number.isFinite(parsed)) return DEFAULT_LIMIT;
  return Math.min(Math.max(Math.floor(parsed), 1), MAX_LIMIT);
}

// Fix C-1: Add authentication check before using service client
async function getAuthUser(req: NextRequest) {
  const authHeader = req.headers.get("authorization");
  if (!authHeader) return null;
  const supabase = createAnonServerClient();
  const { data: { user }, error } = await supabase.auth.getUser(stripBearer(authHeader));
  if (error || !user) return null;
  return user;
}

export async function GET(req: NextRequest) {
  // Fix C-1: Require authentication to prevent unauthenticated DB enumeration
  const user = await getAuthUser(req);
  if (!user) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  // Fix N-13: Rate limit to prevent username enumeration
  const rate = consumeRateLimit({
    key: buildRateLimitKey("discover", req, { userId: user.id }),
    limit: DISCOVER_RATE_LIMIT,
    windowMs: DISCOVER_WINDOW_MS,
  });
  if (!rate.allowed) {
    return NextResponse.json({ ok: false, error: "Too many requests. Try again later." }, { status: 429 });
  }

  const query = req.nextUrl.searchParams.get("q")?.trim() || "";
  const limit = sanitizeLimit(req.nextUrl.searchParams.get("limit"));
  const supabase = createServiceSupabaseClient();

  let builder = supabase
    .from("user_profiles")
    .select("username, avatar_url, bio, created_at")
    .not("username", "is", null)
    .neq("username", "");

  if (query) {
    // Fix H-3: Escape SQL wildcard characters to prevent wildcard injection
    const escapedQuery = query.replace(/[%_\\]/g, '\\$&');
    builder = builder.ilike("username", `%${escapedQuery}%`);
  }

  const { data, error } = await builder
    .order("created_at", { ascending: false })
    .limit(limit);

  if (error) {
    return NextResponse.json(
      { ok: false, error: "Could not load public profiles." },
      { status: 500 },
    );
  }

  const profiles = Array.isArray(data)
    ? data.map((row) => ({
      username: String(row.username || ""),
      avatar_url: String(row.avatar_url || ""),
      bio: String(row.bio || ""),
      created_at: String(row.created_at || ""),
    })).filter((row) => row.username)
    : [];

  return NextResponse.json(
    {
      ok: true,
      profiles,
      query,
    },
    {
      headers: {
        "Cache-Control": "no-store, max-age=0",
      },
    },
  );
}
