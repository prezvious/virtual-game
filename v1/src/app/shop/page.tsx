import type { Metadata } from "next";
import { Fraunces, IBM_Plex_Mono } from "next/font/google";
import ShopClient from "@/components/shop/ShopClient";
import styles from "./shop.module.css";

const fraunces = Fraunces({ subsets: ["latin"], weight: ["500", "700", "900"], variable: "--font-display", preload: false });
const plexMono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["500", "700"], variable: "--font-mono", preload: false });

export const metadata: Metadata = {
  title: "Shop | Virtual Harvest",
  description: "Buy rods, bait, amulets, boosts, and cosmetics.",
};

export default function ShopPage() {
  return (
    <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
      <ShopClient />
    </main>
  );
}
