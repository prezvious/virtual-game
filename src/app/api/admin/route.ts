import { NextRequest, NextResponse } from "next/server";
import { createAnonServerClient, createServiceSupabaseClient, stripBearer } from "@/lib/supabase";
import { consumeRateLimit, getRequestIp } from "@/lib/rate-limit";

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

      if (q) query = query.ilike("username", `%${q}%`);
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

    return NextResponse.json({ ok: true });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown server error";
    console.error("[admin GET]", message);
    return NextResponse.json({ ok: false, error: message }, { status: 500 });
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
        return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
      }

      const result = data as AdminInventoryRpcResult | null;
      if (!result?.ok || typeof result.quantity !== "number") {
        return NextResponse.json(
          { ok: false, error: result?.reason || "Failed to update inventory." },
          { status: 400 },
        );
      }

      await logAction({ item_id: itemId, delta: quantity, final_quantity: result.quantity });
      return NextResponse.json({ ok: true, message: `Spawned ${quantity}x ${itemId} for user.` });
    }

    if (action === "set_weather") {
      const condition = String(body.condition || "clear");
      const intensity = Math.min(Math.max(1, Number(body.intensity) || 1), 100);
      const game = String(body.game || "").toLowerCase();

      if (game !== "fisher" && game !== "farmer") {
        return NextResponse.json({ ok: false, error: "game must be 'fisher' or 'farmer'." }, { status: 400 });
      }

      const settingsKey = `${game}_weather`;
      const weatherValue = { condition, intensity };
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

      await logAction({ game, condition, intensity });
      return NextResponse.json({ ok: true, message: `${game} weather set to ${condition} (${intensity}).` });
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
        return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
      }

      const result = data as AdminBalanceRpcResult | null;
      if (!result?.ok || result.coins === undefined) {
        return NextResponse.json(
          { ok: false, error: result?.reason || "Failed to update balance." },
          { status: 400 },
        );
      }

      await logAction({ delta, final_balance: result.coins });
      return NextResponse.json({ ok: true, message: `Balance updated to ${String(result.coins)}.` });
    }

    if (action === "ban_user") {
      if (!targetId) {
        return NextResponse.json({ ok: false, error: "target_user_id required." }, { status: 400 });
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

      const { error: banError } = await supabase.auth.admin.updateUserById(targetId, { ban_duration: "876000h" });
      if (banError) {
        await logAction({ reason: String(body.reason || "Admin action"), error: banError.message });
        return NextResponse.json({ ok: false, error: banError.message }, { status: 500 });
      }

      await logAction({ reason: String(body.reason || "Admin action") });
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

      const { error: deleteError } = await supabase.auth.admin.deleteUser(targetId);
      if (deleteError) {
        await logAction({ reason: String(body.reason || "Admin action"), error: deleteError.message });
        return NextResponse.json({ ok: false, error: deleteError.message }, { status: 500 });
      }

      return NextResponse.json({ ok: true, message: "User account and data deleted." });
    }

    return NextResponse.json({ ok: false, error: "Unknown action." }, { status: 400 });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown server error";
    console.error("[admin POST]", message);
    return NextResponse.json({ ok: false, error: message }, { status: 500 });
  }
}
