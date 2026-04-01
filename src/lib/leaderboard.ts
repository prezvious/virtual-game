import { createServiceSupabaseClient } from "@/lib/supabase";

export type LeaderboardEntry = {
  rank: number;
  username: string;
  score: string;
};

export type LeaderboardModel = {
  money: LeaderboardEntry[];
  fish: LeaderboardEntry[];
  refreshedAt: string;
  error: string;
};

function formatScore(value: unknown): string {
  if (typeof value === "bigint") return value.toLocaleString("en-US");
  if (typeof value === "number") return Math.max(0, Math.floor(value)).toLocaleString("en-US");

  const text = String(value ?? "").trim();
  if (!text) return "0";

  if (/^\d+$/.test(text)) {
    try {
      return BigInt(text).toLocaleString("en-US");
    } catch {
      return "0";
    }
  }

  const asNumber = Number(text);
  if (Number.isFinite(asNumber)) return Math.max(0, Math.floor(asNumber)).toLocaleString("en-US");
  return "0";
}

export async function fetchLeaderboardModel(limit = 10): Promise<LeaderboardModel> {
  const supabase = createServiceSupabaseClient();
  const { data, error } = await supabase
    .from("leaderboard_snapshots")
    .select("metric, rank, username, score, refreshed_at")
    .lte("rank", limit)
    .order("metric", { ascending: true })
    .order("rank", { ascending: true });

  if (error) {
    return {
      money: [],
      fish: [],
      refreshedAt: "",
      error: error.message || "Could not load leaderboard.",
    };
  }

  const rows = Array.isArray(data) ? data : [];
  const money = rows
    .filter((row) => row.metric === "money_earned")
    .map((row) => ({
      rank: Number(row.rank) || 0,
      username: String(row.username || "unknown"),
      score: formatScore(row.score),
    }));

  const fish = rows
    .filter((row) => row.metric === "fish_caught")
    .map((row) => ({
      rank: Number(row.rank) || 0,
      username: String(row.username || "unknown"),
      score: formatScore(row.score),
    }));

  const refreshedMs = rows.reduce((acc, row) => {
    const ts = Date.parse(String(row.refreshed_at || ""));
    return Number.isFinite(ts) ? Math.max(acc, ts) : acc;
  }, 0);

  return {
    money,
    fish,
    refreshedAt: refreshedMs > 0 ? new Date(refreshedMs).toLocaleString("en-US") : "",
    error: "",
  };
}

