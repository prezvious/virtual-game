import { NextRequest, NextResponse } from "next/server";
import { createAnonServerClient, createServiceSupabaseClient, stripBearer } from "@/lib/supabase";
import { consumeRateLimit, getRequestIp } from "@/lib/rate-limit";

export async function POST(req: NextRequest) {
  const ip = getRequestIp(req);
  const rate = consumeRateLimit({ key: `pwd:${ip}`, limit: 5, windowMs: 300_000 });

  if (!rate.allowed) {
    return NextResponse.json({ ok: false, error: "Too many attempts. Try again later." }, { status: 429 });
  }

  const authHeader = req.headers.get("authorization");
  if (!authHeader) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  let body: { newPassword?: string };
  try {
    body = (await req.json()) as { newPassword?: string };
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid JSON." }, { status: 400 });
  }

  const newPassword = typeof body.newPassword === "string" ? body.newPassword.trim() : "";
  if (newPassword.length < 8) {
    return NextResponse.json({ ok: false, error: "Password must be at least 8 characters." }, { status: 400 });
  }

  const anonClient = createAnonServerClient();
  const supabase = createServiceSupabaseClient();

  const { data: { user }, error: authError } = await anonClient.auth.getUser(stripBearer(authHeader));
  if (authError || !user) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  const { error } = await supabase.auth.admin.updateUserById(user.id, { password: newPassword });
  if (error) {
    return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true, message: "Password updated successfully." });
}
