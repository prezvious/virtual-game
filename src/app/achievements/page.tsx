import type { Metadata } from "next";
import AchievementsClient from "@/components/achievements/AchievementsClient";
import styles from "./achievements.module.css";

export const metadata: Metadata = {
  title: "Achievements",
  description: "Track your achievements across all Virtual Harvest games.",
};

export default function AchievementsPage() {
  return (
    <main className={styles.page}>
      <AchievementsClient />
    </main>
  );
}
