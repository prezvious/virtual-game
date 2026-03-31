import { NextRequest, NextResponse } from "next/server";
import { createServiceSupabaseClient } from "@/lib/supabase";

const DEFAULT_LIMIT = 12;
const MAX_LIMIT = 24;

function sanitizeLimit(rawValue: string | null) {
  const parsed = Number(rawValue || DEFAULT_LIMIT);
  if (!Number.isFinite(parsed)) return DEFAULT_LIMIT;
  return Math.min(Math.max(Math.floor(parsed), 1), MAX_LIMIT);
}

export async function GET(req: NextRequest) {
  const query = req.nextUrl.searchParams.get("q")?.trim() || "";
  const limit = sanitizeLimit(req.nextUrl.searchParams.get("limit"));
  const supabase = createServiceSupabaseClient();

  let builder = supabase
    .from("user_profiles")
    .select("username, avatar_url, bio, created_at")
    .not("username", "is", null)
    .neq("username", "");

  if (query) {
    builder = builder.ilike("username", `%${query}%`);
  }

  const { data, error } = await builder
    .order("created_at", { ascending: false })
    .limit(limit);

  if (error) {
    return NextResponse.json(
      { ok: false, error: error.message || "Could not load public profiles." },
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
