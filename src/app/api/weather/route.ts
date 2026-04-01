import { NextRequest, NextResponse } from "next/server";
import { createAnonServerClient } from "@/lib/supabase";
import { consumeRateLimit, getRequestIp } from "@/lib/rate-limit";

export async function GET(req: NextRequest) {
  const ip = getRequestIp(req);
  const rate = consumeRateLimit({ key: `weather:${ip}`, limit: 60, windowMs: 60_000 });
  if (!rate.allowed) {
    return NextResponse.json({ ok: false, error: "Rate limited." }, { status: 429 });
  }

  const game = req.nextUrl.searchParams.get("game") || "";

  if (game !== "fisher" && game !== "farmer") {
    return NextResponse.json({ ok: false, error: "game must be 'fisher' or 'farmer'." }, { status: 400 });
  }

  const supabase = createAnonServerClient();
  const { data, error } = await supabase
    .from("platform_settings")
    .select("value, updated_at")
    .eq("key", `${game}_weather`)
    .maybeSingle();

  if (error) {
    return NextResponse.json({ ok: false, error: "Failed to fetch weather." }, { status: 500 });
  }

  if (!data) {
    return NextResponse.json({
      ok: true,
      weather: { condition: "clear", intensity: 1 },
      updated_at: null,
    });
  }

  return NextResponse.json({
    ok: true,
    weather: data.value,
    updated_at: data.updated_at,
  });
}
