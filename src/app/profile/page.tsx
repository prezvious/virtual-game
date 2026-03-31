"use client";

import { Fraunces, IBM_Plex_Mono } from "next/font/google";
import SelfProfileClient from "@/components/profile/SelfProfileClient";
import styles from "./profile.module.css";

const fraunces = Fraunces({ subsets: ["latin"], weight: ["500", "700", "900"], variable: "--font-display", preload: false });
const plexMono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["500", "700"], variable: "--font-mono", preload: false });

export default function MyProfilePage() {
  return (
    <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
      <SelfProfileClient />
    </main>
  );
}
