import { NextRequest, NextResponse } from "next/server";
import { fetchLeaderboardModel } from "@/lib/leaderboard";

export async function GET(req: NextRequest) {
  try {
    const url = new URL(req.url);
    const limitParam = url.searchParams.get("limit");
    const offsetParam = url.searchParams.get("offset");

    const limit = limitParam ? Math.min(Math.max(1, parseInt(limitParam, 10)), 100) : 10;
    const offset = offsetParam ? Math.max(0, parseInt(offsetParam, 10)) : 0;

    const model = await fetchLeaderboardModel(limit, offset);
    return NextResponse.json(
      {
        ok: !model.error,
        model,
        pagination: { limit, offset },
        fetchedAt: new Date().toISOString(),
      },
      {
        headers: {
          "Cache-Control": "no-store, max-age=0",
        },
      },
    );
  } catch (error) {
    console.error("[leaderboard GET]", error);
    return NextResponse.json(
      { ok: false, error: "Failed to load leaderboard." },
      { status: 500 },
    );
  }
}
