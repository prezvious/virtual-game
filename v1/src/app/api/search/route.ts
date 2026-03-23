import { NextRequest, NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase";
import { consumeRateLimit, getRequestIp } from "@/lib/rate-limit";

export async function GET(req: NextRequest) {
  const ip = getRequestIp(req);
  const rate = consumeRateLimit({ key: `search:${ip}`, limit: 30, windowMs: 60_000 });
  if (!rate.allowed) {
    return NextResponse.json({ ok: false, error: "Rate limited." }, { status: 429 });
  }

  const q = (req.nextUrl.searchParams.get("q") || "").trim();
  const tab = req.nextUrl.searchParams.get("tab") || "players";

  if (!q || q.length < 2) {
    return NextResponse.json({ ok: true, results: [] });
  }

  const supabase = createServerSupabaseClient();

  if (tab === "players") {
    const { data } = await supabase
      .from("user_profiles")
      .select("user_id, username, avatar_url, bio, created_at")
      .ilike("username", `%${q}%`)
      .order("username", { ascending: true })
      .limit(20);
    return NextResponse.json({ ok: true, results: data || [] });
  }

  if (tab === "leaderboard") {
    const { data } = await supabase
      .from("leaderboard_snapshots")
      .select("metric, rank, username, score, refreshed_at")
      .ilike("username", `%${q}%`)
      .order("rank", { ascending: true })
      .limit(20);
    return NextResponse.json({ ok: true, results: data || [] });
  }

  if (tab === "games") {
    const games = [
      { id: "fisher", name: "Virtual Fisher", description: "Skill-based fishing loop with cloud saves.", href: "/fish", tags: ["fishing", "fish", "rod", "bait", "biome"] },
      { id: "farmer", name: "Virtual Farmer", description: "Prestige-focused farming progression.", href: "/farm", tags: ["farming", "farm", "crop", "harvest", "prestige"] },
    ];
    const lower = q.toLowerCase();
    const results = games.filter((g) => g.name.toLowerCase().includes(lower) || g.tags.some((t) => t.includes(lower)));
    return NextResponse.json({ ok: true, results });
  }

  return NextResponse.json({ ok: true, results: [] });
}
