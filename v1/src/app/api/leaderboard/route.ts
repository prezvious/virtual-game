import { NextResponse } from "next/server";
import { fetchLeaderboardModel } from "@/lib/leaderboard";

export async function GET() {
  const model = await fetchLeaderboardModel(10);
  return NextResponse.json(
    {
      ok: !model.error,
      model,
      fetchedAt: new Date().toISOString(),
    },
    {
      headers: {
        "Cache-Control": "no-store, max-age=0",
      },
    },
  );
}

