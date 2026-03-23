import type { Metadata } from "next";
import LeaderboardLive from "@/components/leaderboard/LeaderboardLive";
import { fetchLeaderboardModel } from "@/lib/leaderboard";
import styles from "./leaderboard.module.css";

export const revalidate = 60;

export const metadata: Metadata = {
  title: "Leaderboard | Fish It!",
  description: "Public leaderboard for Fish It! Enhanced Edition.",
};

export default async function LeaderboardPage() {
  const model = await fetchLeaderboardModel(10);

  return (
    <main className={styles.page}>
      <LeaderboardLive initialModel={model} />
    </main>
  );
}
