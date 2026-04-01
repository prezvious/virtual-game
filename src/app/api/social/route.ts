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
  // Fix N-5: Restrict sensitive tabs to own user only
  const targetId = req.nextUrl.searchParams.get("user_id") || user.id;

  if (tab === "followers") {
    const { data, error } = await supabase
      .from("follows")
      .select("follower_id, created_at, user_profiles!follows_follower_id_fkey(username, avatar_url)")
      .eq("following_id", targetId)
      .order("created_at", { ascending: false });
    // Fix H-4: Check for errors
    if (error) {
      return NextResponse.json({ ok: false, error: "Failed to load followers." }, { status: 500 });
    }
    return NextResponse.json({ ok: true, data: data || [] });
  }

  if (tab === "following") {
    const { data, error } = await supabase
      .from("follows")
      .select("following_id, created_at, user_profiles!follows_following_id_fkey(username, avatar_url)")
      .eq("follower_id", targetId)
      .order("created_at", { ascending: false });
    if (error) {
      return NextResponse.json({ ok: false, error: "Failed to load following." }, { status: 500 });
    }
    return NextResponse.json({ ok: true, data: data || [] });
  }

  if (tab === "friends") {
    const { data: following, error: followingError } = await supabase
      .from("follows")
      .select("following_id")
      .eq("follower_id", targetId);
    if (followingError) {
      return NextResponse.json({ ok: false, error: "Failed to load friends." }, { status: 500 });
    }

    const followingIds = (following || []).map((f) => f.following_id);
    if (followingIds.length === 0) return NextResponse.json({ ok: true, data: [] });

    const { data: mutual, error: mutualError } = await supabase
      .from("follows")
      .select("follower_id, user_profiles!follows_follower_id_fkey(username, avatar_url)")
      .eq("following_id", targetId)
      .in("follower_id", followingIds);
    if (mutualError) {
      return NextResponse.json({ ok: false, error: "Failed to load friends." }, { status: 500 });
    }

    return NextResponse.json({ ok: true, data: mutual || [] });
  }

  if (tab === "blocked") {
    // Fix N-5: Only allow viewing own blocked list
    const { data, error } = await supabase
      .from("blocks")
      .select("blocked_id, restriction_type, created_at, user_profiles!blocks_blocked_id_fkey(username, avatar_url)")
      .eq("blocker_id", user.id);
    if (error) {
      return NextResponse.json({ ok: false, error: "Failed to load blocked users." }, { status: 500 });
    }
    return NextResponse.json({ ok: true, data: data || [] });
  }

  if (tab === "status") {
    const targetUserId = req.nextUrl.searchParams.get("target_id");
    if (!targetUserId) return NextResponse.json({ ok: true, data: { following: false, blocked: false } });

    const { data: followRow, error: followError } = await supabase
      .from("follows")
      .select("follower_id")
      .eq("follower_id", user.id)
      .eq("following_id", targetUserId)
      .maybeSingle();

    const { data: reverseFollow, error: reverseError } = await supabase
      .from("follows")
      .select("follower_id")
      .eq("follower_id", targetUserId)
      .eq("following_id", user.id)
      .maybeSingle();

    const { data: blockRow, error: blockError } = await supabase
      .from("blocks")
      .select("blocker_id, restriction_type")
      .eq("blocker_id", user.id)
      .eq("blocked_id", targetUserId)
      .maybeSingle();

    if (followError || reverseError || blockError) {
      return NextResponse.json({ ok: false, error: "Failed to load status." }, { status: 500 });
    }

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
    // Fix M-9: Add onConflict to prevent duplicate rows
    const { error } = await supabase
      .from("follows")
      .upsert(
        { follower_id: user.id, following_id: targetId },
        { onConflict: "follower_id,following_id" }
      );
    if (error) return NextResponse.json({ ok: false, error: "Failed to follow user." }, { status: 500 });
    return NextResponse.json({ ok: true, action: "followed" });
  }

  if (action === "unfollow") {
    const { error } = await supabase.from("follows").delete().eq("follower_id", user.id).eq("following_id", targetId);
    if (error) return NextResponse.json({ ok: false, error: "Failed to unfollow user." }, { status: 500 });
    return NextResponse.json({ ok: true, action: "unfollowed" });
  }

  if (action === "block" || action === "restrict") {
    await supabase.from("follows").delete().eq("follower_id", user.id).eq("following_id", targetId);
    await supabase.from("follows").delete().eq("follower_id", targetId).eq("following_id", user.id);
    const { error } = await supabase.from("blocks").upsert({
      blocker_id: user.id,
      blocked_id: targetId,
      restriction_type: action,
    }, { onConflict: "blocker_id,blocked_id" });
    if (error) return NextResponse.json({ ok: false, error: "Failed to block user." }, { status: 500 });
    return NextResponse.json({ ok: true, action: action === "block" ? "blocked" : "restricted" });
  }

  if (action === "unblock") {
    const { error } = await supabase.from("blocks").delete().eq("blocker_id", user.id).eq("blocked_id", targetId);
    if (error) return NextResponse.json({ ok: false, error: "Failed to unblock user." }, { status: 500 });
    return NextResponse.json({ ok: true, action: "unblocked" });
  }

  return NextResponse.json({ ok: false, error: "Unknown action." }, { status: 400 });
}
