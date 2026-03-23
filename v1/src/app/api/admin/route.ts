import { NextRequest, NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase";
import { consumeRateLimit, getRequestIp } from "@/lib/rate-limit";

function forbidden() {
  return NextResponse.json({ ok: false, error: "Forbidden." }, { status: 403 });
}

async function verifyAdmin(req: NextRequest) {
  const authHeader = req.headers.get("authorization");
  if (!authHeader) return null;

  const supabase = createServerSupabaseClient();
  const { data: { user } } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  if (!user) return null;

  const { data: profile } = await supabase
    .from("user_profiles")
    .select("is_admin")
    .eq("user_id", user.id)
    .single();

  if (!profile?.is_admin) return null;
  return { user, supabase };
}

export async function GET(req: NextRequest) {
  const admin = await verifyAdmin(req);
  if (!admin) return forbidden();

  const tab = req.nextUrl.searchParams.get("tab") || "users";
  const { supabase } = admin;

  if (tab === "users") {
    const q = req.nextUrl.searchParams.get("q") || "";
    let query = supabase
      .from("user_profiles")
      .select("user_id, username, avatar_url, bio, is_admin, created_at, last_seen_at, onboarding_completed")
      .order("created_at", { ascending: false })
      .limit(50);

    if (q) query = query.ilike("username", `%${q}%`);
    const { data } = await query;
    return NextResponse.json({ ok: true, users: data || [] });
  }

  if (tab === "logs") {
    const { data } = await supabase
      .from("admin_logs")
      .select("*, user_profiles!admin_logs_admin_id_fkey(username)")
      .order("created_at", { ascending: false })
      .limit(100);
    return NextResponse.json({ ok: true, logs: data || [] });
  }

  if (tab === "settings") {
    const { data } = await supabase.from("platform_settings").select("*");
    return NextResponse.json({ ok: true, settings: data || [] });
  }

  return NextResponse.json({ ok: true });
}

export async function POST(req: NextRequest) {
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
    const quantity = Math.max(1, Number(body.quantity) || 1);

    if (!targetId || !itemId) {
      return NextResponse.json({ ok: false, error: "target_user_id and item_id required." }, { status: 400 });
    }

    const { data: existing } = await supabase
      .from("user_inventory")
      .select("quantity")
      .eq("user_id", targetId)
      .eq("item_id", itemId)
      .maybeSingle();

    if (existing) {
      await supabase.from("user_inventory").update({ quantity: existing.quantity + quantity }).eq("user_id", targetId).eq("item_id", itemId);
    } else {
      await supabase.from("user_inventory").insert({ user_id: targetId, item_id: itemId, quantity });
    }

    await logAction({ item_id: itemId, quantity });
    return NextResponse.json({ ok: true, message: `Spawned ${quantity}x ${itemId} for user.` });
  }

  if (action === "set_weather") {
    const condition = String(body.condition || "clear");
    const intensity = Number(body.intensity) || 1;

    await supabase
      .from("platform_settings")
      .update({ value: { condition, intensity }, updated_by: adminUser.id, updated_at: new Date().toISOString() })
      .eq("key", "global_weather");

    await logAction({ condition, intensity });
    return NextResponse.json({ ok: true, message: `Weather set to ${condition} (${intensity}).` });
  }

  if (action === "add_money" || action === "remove_money") {
    const amount = Math.abs(Number(body.amount) || 0);
    if (!targetId || !amount) {
      return NextResponse.json({ ok: false, error: "target_user_id and amount required." }, { status: 400 });
    }

    const { data: balance } = await supabase.from("user_balances").select("coins").eq("user_id", targetId).single();
    const current = balance?.coins || 0;
    const newAmount = action === "add_money" ? current + amount : Math.max(0, current - amount);

    const { data: existing } = await supabase.from("user_balances").select("user_id").eq("user_id", targetId).maybeSingle();
    if (existing) {
      await supabase.from("user_balances").update({ coins: newAmount }).eq("user_id", targetId);
    } else {
      await supabase.from("user_balances").insert({ user_id: targetId, coins: newAmount });
    }

    await logAction({ previous: current, new_amount: newAmount, change: action === "add_money" ? amount : -amount });
    return NextResponse.json({ ok: true, message: `Balance updated: ${current} -> ${newAmount}` });
  }

  if (action === "ban_user") {
    if (!targetId) {
      return NextResponse.json({ ok: false, error: "target_user_id required." }, { status: 400 });
    }

    await supabase.auth.admin.updateUserById(targetId, { ban_duration: "876000h" });
    await logAction({ reason: String(body.reason || "Admin action") });
    return NextResponse.json({ ok: true, message: "User banned." });
  }

  if (action === "delete_user_data") {
    if (!targetId) {
      return NextResponse.json({ ok: false, error: "target_user_id required." }, { status: 400 });
    }

    await supabase.from("game_saves").delete().eq("user_id", targetId);
    await supabase.from("user_inventory").delete().eq("user_id", targetId);
    await supabase.from("user_balances").delete().eq("user_id", targetId);
    await supabase.from("user_achievements").delete().eq("user_id", targetId);
    await supabase.from("messages").delete().eq("sender_id", targetId);
    await supabase.from("follows").delete().or(`follower_id.eq.${targetId},following_id.eq.${targetId}`);

    await logAction({ reason: String(body.reason || "Admin action") });
    return NextResponse.json({ ok: true, message: "User data deleted." });
  }

  return NextResponse.json({ ok: false, error: "Unknown action." }, { status: 400 });
}
