"use client";

import { useEffect, useState } from "react";
import { Fraunces, IBM_Plex_Mono } from "next/font/google";
import { getClientSupabase } from "@/lib/auth-client";
import ProfileClient from "@/components/profile/ProfileClient";
import styles from "./profile.module.css";

const fraunces = Fraunces({ subsets: ["latin"], weight: ["500", "700", "900"], variable: "--font-display", preload: false });
const plexMono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["500", "700"], variable: "--font-mono", preload: false });

export default function MyProfilePage() {
  const [username, setUsername] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      try {
        const supabase = getClientSupabase();
        const { data: { session } } = await supabase.auth.getSession();
        if (session?.user) {
          const { data } = await supabase.from("user_profiles").select("username").eq("user_id", session.user.id).single();
          if (data?.username) setUsername(data.username);
        }
      } finally {
        setLoading(false);
      }
    };
    void load();
  }, []);

  if (loading) {
    return (
      <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
        <div className={styles.shell}><p className={styles.loadingText}>Loading...</p></div>
      </main>
    );
  }

  if (!username) {
    return (
      <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
        <div className={styles.shell}>
          <div className={styles.errorCard}>
            <h2>Not signed in</h2>
            <p>Sign in to view your profile.</p>
            <a href="/home" className={styles.btnPrimary}>Go to Sign In</a>
          </div>
        </div>
      </main>
    );
  }

  return (
    <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
      <ProfileClient username={username} />
    </main>
  );
}
