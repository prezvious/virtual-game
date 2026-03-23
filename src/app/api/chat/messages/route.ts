import { NextRequest, NextResponse } from "next/server";
import { createServerSupabaseClient, createServiceSupabaseClient } from "@/lib/supabase";
import { consumeRateLimit, getRequestIp } from "@/lib/rate-limit";

export async function GET(req: NextRequest) {
  const roomId = req.nextUrl.searchParams.get("room_id") || "00000000-0000-0000-0000-000000000001";
  const limit = Math.min(50, Number(req.nextUrl.searchParams.get("limit")) || 50);

  const supabase = createServiceSupabaseClient();
  const { data, error } = await supabase
    .from("messages")
    .select("id, content, created_at, sender_id, user_profiles:sender_id(username, avatar_url)")
    .eq("room_id", roomId)
    .order("created_at", { ascending: false })
    .limit(limit);

  if (error) {
    return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true, messages: (data || []).reverse() });
}

export async function POST(req: NextRequest) {
  const ip = getRequestIp(req);
  const rate = consumeRateLimit({ key: `chat:${ip}`, limit: 20, windowMs: 30_000 });
  if (!rate.allowed) {
    return NextResponse.json({ ok: false, error: "Slow down! Too many messages." }, { status: 429 });
  }

  const authHeader = req.headers.get("authorization");
  if (!authHeader) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  const anonClient = createServerSupabaseClient();
  const { data: { user } } = await anonClient.auth.getUser(authHeader.replace("Bearer ", ""));
  if (!user) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  let body: { room_id?: string; content?: string };
  try {
    body = (await req.json()) as { room_id?: string; content?: string };
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid JSON." }, { status: 400 });
  }

  const roomId = body.room_id || "00000000-0000-0000-0000-000000000001";
  const content = (body.content || "").trim();

  if (!content || content.length > 2000) {
    return NextResponse.json({ ok: false, error: "Message must be 1-2000 characters." }, { status: 400 });
  }

  const supabase = createServiceSupabaseClient();
  const { data: msg, error } = await supabase
    .from("messages")
    .insert({ room_id: roomId, sender_id: user.id, content })
    .select("id, content, created_at, sender_id")
    .single();

  if (error) {
    return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true, message: msg });
}
