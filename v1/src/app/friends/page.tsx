import type { Metadata } from "next";
import { Fraunces, IBM_Plex_Mono } from "next/font/google";
import FriendsClient from "@/components/social/FriendsClient";
import styles from "./friends.module.css";

const fraunces = Fraunces({ subsets: ["latin"], weight: ["500", "700", "900"], variable: "--font-display", preload: false });
const plexMono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["500", "700"], variable: "--font-mono", preload: false });

export const metadata: Metadata = {
  title: "Friends | Virtual Harvest",
  description: "Manage your friends and social connections.",
};

export default function FriendsPage() {
  return (
    <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
      <FriendsClient />
    </main>
  );
}
