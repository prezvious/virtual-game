import { NextRequest, NextResponse } from "next/server";
import { extractBannedUntil } from "@/lib/ban";
import { createAnonServerClient, createServiceSupabaseClient, stripBearer } from "@/lib/supabase";
import { consumeRateLimit, getRequestIp } from "@/lib/rate-limit";
import { createAdminWeatherValue, isWeatherGame } from "@/lib/weather";

type AdminInventoryRpcResult = {
  ok?: boolean;
  reason?: string;
  quantity?: number;
};

type AdminBalanceRpcResult = {
  ok?: boolean;
  reason?: string;
  coins?: number | string;
};

const PERMANENT_BAN_DURATION = "876000h";

function forbidden() {
  return NextResponse.json({ ok: false, error: "Forbidden." }, { status: 403 });
}

async function verifyAdmin(req: NextRequest) {
  const authHeader = req.headers.get("authorization");
  if (!authHeader) return null;

  const anonClient = createAnonServerClient();
  const { data: { user }, error: userError } = await anonClient.auth.getUser(stripBearer(authHeader));
  if (userError || !user) return null;

  const supabase = createServiceSupabaseClient();
  const { data: profile, error: profileError } = await supabase
    .from("user_profiles")
    .select("is_admin")
    .eq("user_id", user.id)
    .single();

  if (profileError || !profile?.is_admin) return null;
  return { user, supabase };
}

export async function GET(req: NextRequest) {
  try {
    // Fix H-2: Add rate limiting to GET endpoints
    const ip = getRequestIp(req);
    const rate = consumeRateLimit({ key: `admin-get:${ip}`, limit: 30, windowMs: 60_000 });
    if (!rate.allowed) {
      return NextResponse.json({ ok: false, error: "Rate limited." }, { status: 429 });
    }

    const admin = await verifyAdmin(req);
    if (!admin) return forbidden();

    const tab = req.nextUrl.searchParams.get("tab") || "users";
    const { supabase } = admin;

    if (tab === "users") {
      const q = req.nextUrl.searchParams.get("q") || "";
      let query = supabase
        .from("user_profiles")
        .select("user_id, username, avatar_url, bio, is_admin, created_at, last_seen_at")
        .order("created_at", { ascending: false })
        .limit(50);

      if (q) {
        // Fix H-3: Escape SQL wildcard characters
        const escapedQ = q.replace(/[%_\\]/g, '\\$&');
        query = query.ilike("username", `%${escapedQ}%`);
      }
      const { data, error } = await query;
      if (error) {
        return NextResponse.json({ ok: false, error: "Failed to fetch users." }, { status: 500 });
      }
      return NextResponse.json({ ok: true, users: data || [] });
    }

    if (tab === "logs") {
      const { data: logs, error: logsError } = await supabase
        .from("admin_logs")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(100);

      if (logsError) {
        return NextResponse.json({ ok: false, error: "Failed to fetch logs." }, { status: 500 });
      }

      const adminIds = [...new Set((logs || []).map((l: Record<string, unknown>) => l.admin_id).filter(Boolean))] as string[];
      let usernameMap: Record<string, string> = {};
      if (adminIds.length > 0) {
        const { data: profiles } = await supabase
          .from("user_profiles")
          .select("user_id, username")
          .in("user_id", adminIds);
        if (profiles) {
          usernameMap = Object.fromEntries(profiles.map((p: { user_id: string; username: string }) => [p.user_id, p.username]));
        }
      }

      const enrichedLogs = (logs || []).map((l: Record<string, unknown>) => ({
        ...l,
        admin_username: l.admin_id ? usernameMap[l.admin_id as string] || null : null,
      }));

      return NextResponse.json({ ok: true, logs: enrichedLogs });
    }

    if (tab === "settings") {
      const { data, error } = await supabase.from("platform_settings").select("*");
      if (error) {
        return NextResponse.json({ ok: false, error: "Failed to fetch settings." }, { status: 500 });
      }
      return NextResponse.json({ ok: true, settings: data || [] });
    }

    return NextResponse.json({ ok: false, error: `Unknown tab: ${tab}.` }, { status: 400 });
  } catch (err: unknown) {
    // Fix M-1: Don't leak internal error details to client
    console.error("[admin GET]", err);
    return NextResponse.json({ ok: false, error: "An internal error occurred." }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  try {
    const ip = getRequestIp(req);
    const rate = consumeRateLimit({ key: `admin:${ip}`, limit: 30, windowMs: 60_000 });
    if (!rate.allowed) {
      return NextResponse.json({ ok: false, error: "Rate limited." }, { status: 429 });
    }

    const admin = await verifyAdmin(req);
    if (!admin) return forbidden();

    const { user: adminUser, supabase } = admin;

    let body: Record<string, unknown>;
    try {
      body = (await req.json()) as Record<string, unknown>;
    } catch {
      return NextResponse.json({ ok: false, error: "Invalid JSON." }, { status: 400 });
    }

    const action = String(body.action || "");
    const targetId = String(body.target_user_id || "");

    async function logAction(details: Record<string, unknown>) {
      await supabase.from("admin_logs").insert({
        admin_id: adminUser.id,
        action,
        target_user_id: targetId || null,
        details,
      });
    }

    if (action === "spawn_item") {
      const itemId = String(body.item_id || "");
      const quantity = Math.min(Math.max(1, Number(body.quantity) || 1), 9999);

      if (!targetId || !itemId) {
        return NextResponse.json({ ok: false, error: "target_user_id and item_id required." }, { status: 400 });
      }

      const { data, error } = await supabase.rpc("admin_increment_inventory", {
        p_target_user_id: targetId,
        p_item_id: itemId,
        p_delta: quantity,
      });

      if (error) {
        // Fix M-4: Log failed admin actions
        await logAction({ item_id: itemId, delta: quantity, error: error.message });
        return NextResponse.json({ ok: false, error: "Failed to update inventory." }, { status: 500 });
      }

      const result = data as AdminInventoryRpcResult | null;
      if (!result?.ok || typeof result.quantity !== "number") {
        // Fix M-4: Log failed admin actions
        await logAction({ item_id: itemId, delta: quantity, error: result?.reason || "RPC returned invalid result" });
        return NextResponse.json(
          { ok: false, error: result?.reason || "Failed to update inventory." },
          { status: 400 },
        );
      }

      await logAction({ item_id: itemId, delta: quantity, final_quantity: result.quantity });
      return NextResponse.json({ ok: true, message: `Spawned ${quantity}x ${itemId} for user.` });
    }

    if (action === "set_weather") {
      // Fix M-8: Validate condition against allowed values
      const ALLOWED_CONDITIONS = new Set(["clear", "rain", "storm", "fog", "snow", "wind"]);
      const condition = String(body.condition || "clear");
      if (!ALLOWED_CONDITIONS.has(condition)) {
        return NextResponse.json({ ok: false, error: "Invalid weather condition." }, { status: 400 });
      }
      const intensity = Math.min(Math.max(1, Number(body.intensity) || 1), 5);
      const game = String(body.game || "").toLowerCase();

      if (!isWeatherGame(game)) {
        return NextResponse.json({ ok: false, error: "game must be 'fisher' or 'farmer'." }, { status: 400 });
      }

      const settingsKey = `${game}_weather`;
      const weatherValue = createAdminWeatherValue(condition, intensity);
      const now = new Date().toISOString();

      const { error: writeError } = await supabase
        .from("platform_settings")
        .upsert(
          { key: settingsKey, value: weatherValue, updated_by: adminUser.id, updated_at: now },
          { onConflict: "key" }
        );

      if (writeError) {
        return NextResponse.json({ ok: false, error: writeError.message }, { status: 500 });
      }

      await logAction({
        game,
        condition: weatherValue.condition,
        intensity: weatherValue.intensity,
        started_at: weatherValue.started_at,
        expires_at: weatherValue.expires_at,
        duration_minutes: weatherValue.duration_minutes,
        announcement_id: weatherValue.announcement_id,
        source: weatherValue.source,
      });
      return NextResponse.json({
        ok: true,
        message: `${game} weather set to ${weatherValue.condition} (${weatherValue.intensity}) for ${weatherValue.duration_minutes} minutes.`,
        duration_minutes: weatherValue.duration_minutes,
        announcement_id: weatherValue.announcement_id,
      });
    }

    if (action === "add_money" || action === "remove_money") {
      const amount = Math.abs(Number(body.amount) || 0);
      if (!targetId || !amount) {
        return NextResponse.json({ ok: false, error: "target_user_id and amount required." }, { status: 400 });
      }

      const delta = action === "add_money" ? amount : -amount;
      const { data, error } = await supabase.rpc("admin_adjust_user_balance", {
        p_target_user_id: targetId,
        p_delta: delta,
      });

      if (error) {
        // Fix M-4: Log failed admin actions
        await logAction({ delta, error: error.message });
        return NextResponse.json({ ok: false, error: "Failed to update balance." }, { status: 500 });
      }

      const result = data as AdminBalanceRpcResult | null;
      if (!result?.ok || result.coins === undefined) {
        // Fix M-4: Log failed admin actions
        await logAction({ delta, error: result?.reason || "RPC returned invalid result" });
        return NextResponse.json(
          { ok: false, error: result?.reason || "Failed to update balance." },
          { status: 400 },
        );
      }

      await logAction({ delta, final_balance: result.coins });
      return NextResponse.json({ ok: true, message: `Balance updated to ${String(result.coins)}.` });
    }

    if (action === "ban_user") {
      const reason = String(body.reason || "").trim();
      if (!targetId) {
        return NextResponse.json({ ok: false, error: "target_user_id required." }, { status: 400 });
      }

      if (!reason) {
        return NextResponse.json({ ok: false, error: "Reason required to ban a user." }, { status: 400 });
      }

      if (targetId === adminUser.id) {
        return NextResponse.json({ ok: false, error: "Cannot ban yourself." }, { status: 400 });
      }

      const { data: targetProfile, error: targetProfileError } = await supabase
        .from("user_profiles")
        .select("is_admin")
        .eq("user_id", targetId)
        .maybeSingle();

      if (targetProfileError) {
        return NextResponse.json({ ok: false, error: targetProfileError.message }, { status: 500 });
      }

      if (targetProfile?.is_admin) {
        return NextResponse.json({ ok: false, error: "Cannot ban another admin." }, { status: 403 });
      }

      const { data: banResult, error: banError } = await supabase.auth.admin.updateUserById(targetId, {
        ban_duration: PERMANENT_BAN_DURATION,
      });
      if (banError) {
        await logAction({ reason, error: banError.message });
        return NextResponse.json({ ok: false, error: banError.message }, { status: 500 });
      }

      const bannedUntil = extractBannedUntil(banResult?.user)
        || extractBannedUntil((await supabase.auth.admin.getUserById(targetId)).data.user);

      await logAction({
        reason,
        banned_until: bannedUntil,
        ban_duration: PERMANENT_BAN_DURATION,
        source: "admin_console",
      });
      return NextResponse.json({ ok: true, message: "User banned." });
    }

    if (action === "delete_user_data") {
      if (!targetId) {
        return NextResponse.json({ ok: false, error: "target_user_id required." }, { status: 400 });
      }

      if (targetId === adminUser.id) {
        return NextResponse.json({ ok: false, error: "Cannot delete yourself." }, { status: 400 });
      }

      const { data: targetProfile, error: targetProfileError } = await supabase
        .from("user_profiles")
        .select("is_admin")
        .eq("user_id", targetId)
        .maybeSingle();

      if (targetProfileError) {
        return NextResponse.json({ ok: false, error: targetProfileError.message }, { status: 500 });
      }

      if (targetProfile?.is_admin) {
        return NextResponse.json({ ok: false, error: "Cannot delete another admin." }, { status: 403 });
      }

      // Fix H-5: Delete related records before deleting the auth user
      // Delete in order to respect foreign key constraints
      await supabase.from("user_achievements").delete().eq("user_id", targetId);
      await supabase.from("user_game_stats").delete().eq("user_id", targetId);
      await supabase.from("follows").delete().eq("follower_id", targetId);
      await supabase.from("follows").delete().eq("following_id", targetId);
      await supabase.from("blocks").delete().eq("blocker_id", targetId);
      await supabase.from("blocks").delete().eq("blocked_id", targetId);
      await supabase.from("user_profiles").delete().eq("user_id", targetId);

      const { error: deleteError } = await supabase.auth.admin.deleteUser(targetId);
      if (deleteError) {
        await logAction({ reason: String(body.reason || "Admin action"), error: deleteError.message });
        return NextResponse.json({ ok: false, error: deleteError.message }, { status: 500 });
      }

      await logAction({
        reason: String(body.reason || "Admin action"),
        source: "admin_console",
      });

      return NextResponse.json({ ok: true, message: "User account and data deleted." });
    }

    return NextResponse.json({ ok: false, error: "Unknown action." }, { status: 400 });
  } catch (err: unknown) {
    // Fix M-1: Don't leak internal error details
    console.error("[admin POST]", err);
    return NextResponse.json({ ok: false, error: "An internal error occurred." }, { status: 500 });
  }
}
