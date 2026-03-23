import type { Metadata } from "next";
import { Fraunces, IBM_Plex_Mono } from "next/font/google";
import AdminClient from "@/components/admin/AdminClient";
import styles from "./admin.module.css";

const fraunces = Fraunces({ subsets: ["latin"], weight: ["500", "700", "900"], variable: "--font-display", preload: false });
const plexMono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["500", "700"], variable: "--font-mono", preload: false });

export const metadata: Metadata = {
  title: "Admin Dashboard | Virtual Harvest",
  description: "Platform administration and moderation tools.",
};

export default function AdminPage() {
  return (
    <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
      <AdminClient />
    </main>
  );
}
