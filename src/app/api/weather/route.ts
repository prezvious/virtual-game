import { NextRequest, NextResponse } from "next/server";
import { createAnonServerClient } from "@/lib/supabase";
import { buildRateLimitKey, consumeRateLimit } from "@/lib/rate-limit";
import { buildWeatherStateKey, isWeatherGame, toPublicWeatherState } from "@/lib/weather";

export async function GET(req: NextRequest) {
  const rate = consumeRateLimit({ key: buildRateLimitKey("weather", req), limit: 60, windowMs: 60_000 });
  if (!rate.allowed) {
    return NextResponse.json({ ok: false, error: "Rate limited." }, { status: 429 });
  }

  const game = req.nextUrl.searchParams.get("game") || "";

  if (!isWeatherGame(game)) {
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
    const weather = toPublicWeatherState(game, null);
    return NextResponse.json({
      ok: true,
      game,
      weather,
      updated_at: null,
      state_key: buildWeatherStateKey(weather, null),
    });
  }

  const weather = toPublicWeatherState(game, data.value);

  return NextResponse.json({
    ok: true,
    game,
    weather,
    updated_at: data.updated_at,
    state_key: buildWeatherStateKey(weather, data.updated_at),
  });
}
