import type { Metadata } from "next";
import { Fraunces, IBM_Plex_Mono } from "next/font/google";
import SearchClient from "@/components/search/SearchClient";
import styles from "./search.module.css";

const fraunces = Fraunces({ subsets: ["latin"], weight: ["500", "700", "900"], variable: "--font-display", preload: false });
const plexMono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["500", "700"], variable: "--font-mono", preload: false });

export const metadata: Metadata = {
  title: "Search | Virtual Harvest",
  description: "Search for players, games, and leaderboard entries.",
};

export default function SearchPage() {
  return (
    <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
      <SearchClient />
    </main>
  );
}
