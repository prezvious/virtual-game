import { NextRequest, NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase";
import { consumeRateLimit, getRequestIp } from "@/lib/rate-limit";

export async function POST(req: NextRequest) {
  const ip = getRequestIp(req);
  const rate = consumeRateLimit({ key: `shop:${ip}`, limit: 20, windowMs: 60_000 });
  if (!rate.allowed) {
    return NextResponse.json({ ok: false, error: "Rate limited." }, { status: 429 });
  }

  const authHeader = req.headers.get("authorization");
  if (!authHeader) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  const supabase = createServerSupabaseClient();
  const { data: { user }, error: authError } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  if (authError || !user) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  let body: { item_id?: string; quantity?: number };
  try {
    body = (await req.json()) as { item_id?: string; quantity?: number };
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid JSON." }, { status: 400 });
  }

  const itemId = body.item_id;
  const quantity = Math.max(1, body.quantity || 1);

  if (!itemId) {
    return NextResponse.json({ ok: false, error: "Item ID required." }, { status: 400 });
  }

  const { data: item } = await supabase.from("shop_items").select("*").eq("id", itemId).eq("is_available", true).single();
  if (!item) {
    return NextResponse.json({ ok: false, error: "Item not found or unavailable." }, { status: 404 });
  }

  const totalCost = item.price * quantity;

  const { data: balance } = await supabase.from("user_balances").select("coins, gems").eq("user_id", user.id).single();

  if (!balance) {
    await supabase.from("user_balances").insert({ user_id: user.id, coins: 500, gems: 0 });
    return NextResponse.json({ ok: false, error: "Insufficient funds." }, { status: 400 });
  }

  const currencyField = item.currency === "gems" ? "gems" : "coins";
  const currentBalance = (balance as Record<string, number>)[currencyField] || 0;

  if (currentBalance < totalCost) {
    return NextResponse.json({
      ok: false,
      error: `Not enough ${item.currency}. Need ${totalCost}, have ${currentBalance}.`,
    }, { status: 400 });
  }

  const { error: deductError } = await supabase
    .from("user_balances")
    .update({ [currencyField]: currentBalance - totalCost })
    .eq("user_id", user.id);

  if (deductError) {
    return NextResponse.json({ ok: false, error: "Payment failed." }, { status: 500 });
  }

  const { data: existing } = await supabase
    .from("user_inventory")
    .select("quantity")
    .eq("user_id", user.id)
    .eq("item_id", itemId)
    .maybeSingle();

  if (existing) {
    await supabase
      .from("user_inventory")
      .update({ quantity: existing.quantity + quantity })
      .eq("user_id", user.id)
      .eq("item_id", itemId);
  } else {
    await supabase.from("user_inventory").insert({ user_id: user.id, item_id: itemId, quantity });
  }

  return NextResponse.json({
    ok: true,
    message: `Purchased ${quantity}x ${item.name}`,
    new_balance: currentBalance - totalCost,
  });
}
