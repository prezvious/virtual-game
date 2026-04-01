import { NextRequest, NextResponse } from "next/server";
import { createAnonServerClient, createServiceSupabaseClient, stripBearer } from "@/lib/supabase";
import { consumeRateLimit, getRequestIp } from "@/lib/rate-limit";

function unauthorized() {
  return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
}

async function getAuthUser(req: NextRequest) {
  const authHeader = req.headers.get("authorization");
  if (!authHeader) return null;
  const supabase = createAnonServerClient();
  const { data: { user }, error } = await supabase.auth.getUser(stripBearer(authHeader));
  if (error || !user) return null;
  return user;
}

export async function GET(req: NextRequest) {
  const user = await getAuthUser(req);
  if (!user) return unauthorized();

  const supabase = createServiceSupabaseClient();
  const tab = req.nextUrl.searchParams.get("tab") || "followers";
  const targetId = req.nextUrl.searchParams.get("user_id") || user.id;

  if (tab === "followers") {
    const { data } = await supabase
      .from("follows")
      .select("follower_id, created_at, user_profiles!follows_follower_id_fkey(username, avatar_url)")
      .eq("following_id", targetId)
      .order("created_at", { ascending: false });
    return NextResponse.json({ ok: true, data: data || [] });
  }

  if (tab === "following") {
    const { data } = await supabase
      .from("follows")
      .select("following_id, created_at, user_profiles!follows_following_id_fkey(username, avatar_url)")
      .eq("follower_id", targetId)
      .order("created_at", { ascending: false });
    return NextResponse.json({ ok: true, data: data || [] });
  }

  if (tab === "friends") {
    const { data: following } = await supabase
      .from("follows")
      .select("following_id")
      .eq("follower_id", targetId);

    const followingIds = (following || []).map((f) => f.following_id);
    if (followingIds.length === 0) return NextResponse.json({ ok: true, data: [] });

    const { data: mutual } = await supabase
      .from("follows")
      .select("follower_id, user_profiles!follows_follower_id_fkey(username, avatar_url)")
      .eq("following_id", targetId)
      .in("follower_id", followingIds);

    return NextResponse.json({ ok: true, data: mutual || [] });
  }

  if (tab === "blocked") {
    const { data } = await supabase
      .from("blocks")
      .select("blocked_id, restriction_type, created_at, user_profiles!blocks_blocked_id_fkey(username, avatar_url)")
      .eq("blocker_id", user.id);
    return NextResponse.json({ ok: true, data: data || [] });
  }

  if (tab === "status") {
    const targetUserId = req.nextUrl.searchParams.get("target_id");
    if (!targetUserId) return NextResponse.json({ ok: true, data: { following: false, blocked: false } });

    const { data: followRow } = await supabase
      .from("follows")
      .select("follower_id")
      .eq("follower_id", user.id)
      .eq("following_id", targetUserId)
      .maybeSingle();

    const { data: reverseFollow } = await supabase
      .from("follows")
      .select("follower_id")
      .eq("follower_id", targetUserId)
      .eq("following_id", user.id)
      .maybeSingle();

    const { data: blockRow } = await supabase
      .from("blocks")
      .select("blocker_id, restriction_type")
      .eq("blocker_id", user.id)
      .eq("blocked_id", targetUserId)
      .maybeSingle();

    return NextResponse.json({
      ok: true,
      data: {
        following: !!followRow,
        follows_back: !!reverseFollow,
        is_friend: !!followRow && !!reverseFollow,
        block: blockRow ? blockRow.restriction_type : null,
      },
    });
  }

  return NextResponse.json({ ok: false, error: "Invalid tab." }, { status: 400 });
}

export async function POST(req: NextRequest) {
  const ip = getRequestIp(req);
  const rate = consumeRateLimit({ key: `social:${ip}`, limit: 30, windowMs: 60_000 });
  if (!rate.allowed) {
    return NextResponse.json({ ok: false, error: "Rate limited." }, { status: 429 });
  }

  const user = await getAuthUser(req);
  if (!user) return unauthorized();

  let body: Record<string, string>;
  try {
    body = (await req.json()) as Record<string, string>;
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid JSON." }, { status: 400 });
  }

  const action = body.action;
  const targetId = body.target_id;

  if (!targetId || targetId === user.id) {
    return NextResponse.json({ ok: false, error: "Invalid target." }, { status: 400 });
  }

  const supabase = createServiceSupabaseClient();

  if (action === "follow") {
    const { error } = await supabase.from("follows").upsert({ follower_id: user.id, following_id: targetId });
    if (error) return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
    return NextResponse.json({ ok: true, action: "followed" });
  }

  if (action === "unfollow") {
    const { error } = await supabase.from("follows").delete().eq("follower_id", user.id).eq("following_id", targetId);
    if (error) return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
    return NextResponse.json({ ok: true, action: "unfollowed" });
  }

  if (action === "block" || action === "restrict") {
    await supabase.from("follows").delete().eq("follower_id", user.id).eq("following_id", targetId);
    await supabase.from("follows").delete().eq("follower_id", targetId).eq("following_id", user.id);
    const { error } = await supabase.from("blocks").upsert({
      blocker_id: user.id,
      blocked_id: targetId,
      restriction_type: action,
    });
    if (error) return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
    return NextResponse.json({ ok: true, action: action === "block" ? "blocked" : "restricted" });
  }

  if (action === "unblock") {
    const { error } = await supabase.from("blocks").delete().eq("blocker_id", user.id).eq("blocked_id", targetId);
    if (error) return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
    return NextResponse.json({ ok: true, action: "unblocked" });
  }

  return NextResponse.json({ ok: false, error: "Unknown action." }, { status: 400 });
}
