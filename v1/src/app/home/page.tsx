import type { Metadata } from "next";
import { Fraunces, IBM_Plex_Mono } from "next/font/google";
import PlatformHubClient from "@/components/platform/PlatformHubClient";
import OnboardingFlow from "@/components/onboarding/OnboardingFlow";
import styles from "./home.module.css";

const fraunces = Fraunces({
  subsets: ["latin"],
  weight: ["500", "700", "900"],
  variable: "--font-display",
  preload: false,
});

const plexMono = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["500", "700"],
  variable: "--font-mono",
  preload: false,
});

export const metadata: Metadata = {
  title: "Platform Home | Virtual Harvest",
  description: "Centralized homepage for Virtual Fisher and Virtual Farmer.",
};

export default function PlatformHomePage() {
  return (
    <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
      <PlatformHubClient />
      <OnboardingFlow />
    </main>
  );
}
