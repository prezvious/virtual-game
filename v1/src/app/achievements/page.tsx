import type { Metadata } from "next";
import { Fraunces, IBM_Plex_Mono } from "next/font/google";
import AchievementsClient from "@/components/achievements/AchievementsClient";
import styles from "./achievements.module.css";

const fraunces = Fraunces({ subsets: ["latin"], weight: ["500", "700", "900"], variable: "--font-display", preload: false });
const plexMono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["500", "700"], variable: "--font-mono", preload: false });

export const metadata: Metadata = {
  title: "Achievements | Virtual Harvest",
  description: "Track your achievements across all Virtual Harvest games.",
};

export default function AchievementsPage() {
  return (
    <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
      <AchievementsClient />
    </main>
  );
}
