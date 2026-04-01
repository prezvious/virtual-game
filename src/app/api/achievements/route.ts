import { NextRequest, NextResponse } from "next/server";
import { createAnonServerClient, stripBearer } from "@/lib/supabase";
import { consumeRateLimit, getRequestIp } from "@/lib/rate-limit";

const ACHIEVEMENTS_RATE_LIMIT = 30;
const ACHIEVEMENTS_WINDOW_MS = 60_000;

async function getAuthUser(req: NextRequest) {
  const authHeader = req.headers.get("authorization");
  if (!authHeader) return null;
  const supabase = createAnonServerClient();
  const { data: { user }, error } = await supabase.auth.getUser(stripBearer(authHeader));
  if (error || !user) return null;
  return user;
}

export async function GET(req: NextRequest) {
  const ip = getRequestIp(req);
  const rate = consumeRateLimit({ key: `achievements:${ip}`, limit: ACHIEVEMENTS_RATE_LIMIT, windowMs: ACHIEVEMENTS_WINDOW_MS });
  if (!rate.allowed) {
    return NextResponse.json({ ok: false, error: "Too many requests. Try again later." }, { status: 429 });
  }

  // Fix C-2: Require authentication for user-specific achievement data
  const user = await getAuthUser(req);
  if (!user) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  const supabase = createAnonServerClient();
  // Only allow users to query their own achievements, or no user_id for public achievement list
  const requestedUserId = req.nextUrl.searchParams.get("user_id");
  const userId = requestedUserId && requestedUserId === user.id ? requestedUserId : user.id;

  // Fix C-2: Use explicit column selection instead of select("*")
  const { data: allAchievements, error } = await supabase
    .from("achievements")
    .select("id, name, icon, rarity, sort_order, description")
    .order("sort_order", { ascending: true });

  if (error) {
    return NextResponse.json({ ok: false, error: "Failed to load achievements." }, { status: 500 });
  }

  let userAchievements: { achievement_id: string; unlocked_at: string }[] = [];
  if (userId) {
    const { data, error: userAchieveError } = await supabase
      .from("user_achievements")
      .select("achievement_id, unlocked_at")
      .eq("user_id", userId);
    if (userAchieveError) {
      return NextResponse.json({ ok: false, error: "Failed to load user achievements." }, { status: 500 });
    }
    userAchievements = data || [];
  }

  const unlockedMap = new Map(userAchievements.map((ua) => [ua.achievement_id, ua.unlocked_at]));

  const merged = (allAchievements || []).map((a) => ({
    ...a,
    unlocked: unlockedMap.has(a.id),
    unlocked_at: unlockedMap.get(a.id) || null,
  }));

  return NextResponse.json({ ok: true, achievements: merged });
}
