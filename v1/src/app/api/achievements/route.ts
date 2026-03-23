import { NextRequest, NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase";

export async function GET(req: NextRequest) {
  const supabase = createServerSupabaseClient();
  const userId = req.nextUrl.searchParams.get("user_id");

  const { data: allAchievements, error } = await supabase
    .from("achievements")
    .select("*")
    .order("sort_order", { ascending: true });

  if (error) {
    return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
  }

  let userAchievements: { achievement_id: string; unlocked_at: string }[] = [];
  if (userId) {
    const { data } = await supabase
      .from("user_achievements")
      .select("achievement_id, unlocked_at")
      .eq("user_id", userId);
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
