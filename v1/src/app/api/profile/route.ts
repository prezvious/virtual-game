import { NextRequest, NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase";

export async function GET(req: NextRequest) {
  const username = req.nextUrl.searchParams.get("username");
  if (!username) {
    return NextResponse.json({ ok: false, error: "Username required." }, { status: 400 });
  }

  const supabase = createServerSupabaseClient();

  const { data: profile, error } = await supabase
    .from("user_profiles")
    .select("user_id, username, avatar_url, bio, is_admin, created_at, last_seen_at")
    .ilike("username", username)
    .single();

  if (error || !profile) {
    return NextResponse.json({ ok: false, error: "User not found." }, { status: 404 });
  }

  const { count: followersCount } = await supabase
    .from("follows")
    .select("*", { count: "exact", head: true })
    .eq("following_id", profile.user_id);

  const { count: followingCount } = await supabase
    .from("follows")
    .select("*", { count: "exact", head: true })
    .eq("follower_id", profile.user_id);

  const { data: achievements } = await supabase
    .from("user_achievements")
    .select("achievement_id, unlocked_at, achievements(name, icon, rarity)")
    .eq("user_id", profile.user_id)
    .order("unlocked_at", { ascending: false })
    .limit(6);

  return NextResponse.json({
    ok: true,
    profile: {
      ...profile,
      followers_count: followersCount || 0,
      following_count: followingCount || 0,
      recent_achievements: achievements || [],
    },
  });
}

export async function PATCH(req: NextRequest) {
  const supabase = createServerSupabaseClient();
  const authHeader = req.headers.get("authorization");

  if (!authHeader) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  const { data: { user }, error: authError } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  if (authError || !user) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid JSON." }, { status: 400 });
  }

  const updates: Record<string, unknown> = {};
  if (typeof body.bio === "string") updates.bio = body.bio.slice(0, 500);
  if (typeof body.avatar_url === "string") updates.avatar_url = body.avatar_url.slice(0, 500);

  if (Object.keys(updates).length === 0) {
    return NextResponse.json({ ok: false, error: "No valid fields to update." }, { status: 400 });
  }

  const { error } = await supabase
    .from("user_profiles")
    .update(updates)
    .eq("user_id", user.id);

  if (error) {
    return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
