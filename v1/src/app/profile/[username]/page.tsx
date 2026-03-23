import type { Metadata } from "next";
import { Fraunces, IBM_Plex_Mono } from "next/font/google";
import ProfileClient from "@/components/profile/ProfileClient";
import styles from "../profile.module.css";

const fraunces = Fraunces({ subsets: ["latin"], weight: ["500", "700", "900"], variable: "--font-display", preload: false });
const plexMono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["500", "700"], variable: "--font-mono", preload: false });

type Props = { params: Promise<{ username: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { username } = await params;
  return { title: `@${username} | Virtual Harvest`, description: `Profile page for ${username}.` };
}

export default async function UserProfilePage({ params }: Props) {
  const { username } = await params;
  return (
    <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
      <ProfileClient username={username} />
    </main>
  );
}
