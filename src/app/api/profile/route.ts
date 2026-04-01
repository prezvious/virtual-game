import { NextRequest, NextResponse } from "next/server";
import { createAnonServerClient, createServiceSupabaseClient } from "@/lib/supabase";

const TRACKING_STARTED_ON = "2026-04-01";

type AchievementRow = {
  achievement_id: string;
  unlocked_at: string;
  achievements: { name: string; icon: string; rarity: string } | null;
};

type PlaytimeRow = {
  game_key: string | null;
  playtime_seconds: number | string | null;
  last_played_at: string | null;
};

type CanonicalGameKey = "fisher" | "farmer";

const GAME_KEY_ALIASES: Record<string, CanonicalGameKey> = {
  fisher: "fisher",
  "virtual-fisher": "fisher",
  virtual_fisher: "fisher",
  virtualfisher: "fisher",
  fishit: "fisher",
  farmer: "farmer",
  "virtual-farmer": "farmer",
  virtual_farmer: "farmer",
  virtualfarmer: "farmer",
};

function wantsSelfProfile(req: NextRequest) {
  const scope = req.nextUrl.searchParams.get("scope");
  const username = req.nextUrl.searchParams.get("username");
  return scope === "self" || (!username && req.headers.has("authorization"));
}

async function authenticateRequest(req: NextRequest) {
  const authHeader = req.headers.get("authorization");
  if (!authHeader) {
    return { user: null, response: NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 }) };
  }

  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return { user: null, response: NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 }) };
  }

  const anonClient = createAnonServerClient();
  const { data: { user }, error } = await anonClient.auth.getUser(token);
  if (error || !user) {
    return { user: null, response: NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 }) };
  }

  return { user, response: null };
}

function normalizeSeconds(value: number | string | null | undefined) {
  const numericValue = typeof value === "number" ? value : Number(value || 0);
  if (!Number.isFinite(numericValue) || numericValue <= 0) {
    return 0;
  }
  return Math.floor(numericValue);
}

function normalizeGameKey(value: string | null | undefined): CanonicalGameKey | null {
  const normalized = String(value || "").trim().toLowerCase();
  return GAME_KEY_ALIASES[normalized] || null;
}

function normalizeAchievementRows(rows: unknown[]) {
  return rows.map((row) => {
    const nextRow = row as {
      achievement_id: string;
      unlocked_at: string;
      achievements: { name: string; icon: string; rarity: string } | { name: string; icon: string; rarity: string }[] | null;
    };

    const relatedAchievement = Array.isArray(nextRow.achievements)
      ? nextRow.achievements[0] || null
      : (nextRow.achievements || null);

    return {
      achievement_id: nextRow.achievement_id,
      unlocked_at: nextRow.unlocked_at,
      achievements: relatedAchievement,
    } satisfies AchievementRow;
  });
}

async function ensureOwnProfileRow(serviceClient: ReturnType<typeof createServiceSupabaseClient>, userId: string) {
  const { data, error } = await serviceClient
    .from("user_profiles")
    .select("user_id, username, avatar_url, bio, is_admin, created_at, last_seen_at")
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (data) {
    return data;
  }

  const { error: insertError } = await serviceClient
    .from("user_profiles")
    .upsert({ user_id: userId }, { onConflict: "user_id" });

  if (insertError) {
    throw insertError;
  }

  return {
    user_id: userId,
    username: null,
    avatar_url: "",
    bio: "",
    is_admin: false,
    created_at: new Date().toISOString(),
    last_seen_at: null,
  };
}

async function loadSelfProfile(serviceClient: ReturnType<typeof createServiceSupabaseClient>, userId: string, email: string | undefined) {
  const profile = await ensureOwnProfileRow(serviceClient, userId);

  const [
    followersResult,
    followingResult,
    achievementsResult,
    playtimeResult,
  ] = await Promise.all([
    serviceClient
      .from("follows")
      .select("*", { count: "exact", head: true })
      .eq("following_id", userId),
    serviceClient
      .from("follows")
      .select("*", { count: "exact", head: true })
      .eq("follower_id", userId),
    serviceClient
      .from("user_achievements")
      .select("achievement_id, unlocked_at, achievements(name, icon, rarity)")
      .eq("user_id", userId)
      .order("unlocked_at", { ascending: false })
      .limit(6),
    serviceClient
      .from("user_game_stats")
      .select("game_key, playtime_seconds, last_played_at")
      .eq("user_id", userId),
  ]);

  const achievements = normalizeAchievementRows((achievementsResult.data || []) as unknown[]);
  const playtimeRows = (playtimeResult.data || []) as PlaytimeRow[];
  let fisherSeconds = 0;
  let farmerSeconds = 0;

  playtimeRows.forEach((row) => {
    const normalizedKey = normalizeGameKey(row.game_key);
    const seconds = normalizeSeconds(row.playtime_seconds);

    if (normalizedKey === "fisher") {
      fisherSeconds += seconds;
    } else if (normalizedKey === "farmer") {
      farmerSeconds += seconds;
    }
  });

  const lastPlayedAtMs = playtimeRows
    .map((row) => Date.parse(String(row.last_played_at || "")))
    .filter((value) => Number.isFinite(value))
    .reduce((latest, value) => Math.max(latest, value), 0);

  return {
    user_id: profile.user_id,
    email: email || "",
    username: profile.username || "",
    avatar_url: profile.avatar_url || "",
    bio: profile.bio || "",
    is_admin: Boolean(profile.is_admin),
    created_at: profile.created_at,
    last_seen_at: profile.last_seen_at,
    followers_count: followersResult.count || 0,
    following_count: followingResult.count || 0,
    recent_achievements: achievements,
    playtime: {
      tracking_started_on: TRACKING_STARTED_ON,
      total_seconds: fisherSeconds + farmerSeconds,
      fisher_seconds: fisherSeconds,
      farmer_seconds: farmerSeconds,
      last_played_at: lastPlayedAtMs > 0 ? new Date(lastPlayedAtMs).toISOString() : null,
    },
  };
}

export async function GET(req: NextRequest) {
  if (wantsSelfProfile(req)) {
    const auth = await authenticateRequest(req);
    if (!auth.user) {
      return auth.response!;
    }

    const serviceClient = createServiceSupabaseClient();

    try {
      const profile = await loadSelfProfile(serviceClient, auth.user.id, auth.user.email);
      return NextResponse.json({ ok: true, profile });
    } catch (error) {
      return NextResponse.json(
        { ok: false, error: error instanceof Error ? error.message : "Failed to load profile." },
        { status: 500 },
      );
    }
  }

  const username = req.nextUrl.searchParams.get("username");
  if (!username) {
    return NextResponse.json({ ok: false, error: "Username required." }, { status: 400 });
  }

  const serviceClient = createServiceSupabaseClient();

  const { data: profile, error } = await serviceClient
    .from("user_profiles")
    .select("user_id, username, avatar_url, bio, is_admin, created_at, last_seen_at")
    .ilike("username", username)
    .maybeSingle();

  if (error || !profile) {
    return NextResponse.json({ ok: false, error: "User not found." }, { status: 404 });
  }

  const { count: followersCount } = await serviceClient
    .from("follows")
    .select("*", { count: "exact", head: true })
    .eq("following_id", profile.user_id);

  const { count: followingCount } = await serviceClient
    .from("follows")
    .select("*", { count: "exact", head: true })
    .eq("follower_id", profile.user_id);

  const { data: achievements } = await serviceClient
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
  const auth = await authenticateRequest(req);
  if (!auth.user) {
    return auth.response!;
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
  const requestedUsername = typeof body.username === "string" ? body.username.trim() : null;

  if (requestedUsername !== null && !requestedUsername) {
    return NextResponse.json({ ok: false, error: "Username is required." }, { status: 400 });
  }

  if (Object.keys(updates).length === 0 && requestedUsername === null) {
    return NextResponse.json({ ok: false, error: "No valid fields to update." }, { status: 400 });
  }

  const serviceClient = createServiceSupabaseClient();

  try {
    await ensureOwnProfileRow(serviceClient, auth.user.id);

    if (Object.keys(updates).length > 0) {
      const { error } = await serviceClient
        .from("user_profiles")
        .update(updates)
        .eq("user_id", auth.user.id);

      if (error) {
        throw error;
      }
    }

    if (requestedUsername !== null) {
      const { data, error } = await serviceClient.rpc("_claim_username_for_user", {
        target_user_id: auth.user.id,
        candidate: requestedUsername,
      });

      if (error) {
        throw error;
      }

      if (!data?.ok) {
        return NextResponse.json(
          { ok: false, error: data?.reason || "Could not save username." },
          { status: 400 },
        );
      }
    }

    const profile = await loadSelfProfile(serviceClient, auth.user.id, auth.user.email);
    return NextResponse.json({ ok: true, profile });
  } catch (error) {
    return NextResponse.json(
      { ok: false, error: error instanceof Error ? error.message : "Failed to update profile." },
      { status: 500 },
    );
  }
}
