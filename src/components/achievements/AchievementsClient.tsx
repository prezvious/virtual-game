"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getClientSupabase } from "@/lib/auth-client";
import styles from "@/app/achievements/achievements.module.css";

type Achievement = {
  id: string;
  name: string;
  description: string;
  icon: string;
  category: string;
  requirement_type: string;
  requirement_value: number;
  rarity: string;
  xp_reward: number;
  sort_order: number;
  unlocked: boolean;
  unlocked_at: string | null;
};

const RARITY_THEME: Record<string, { color: string; background: string }> = {
  common: { color: "var(--text-muted)", background: "rgba(194, 210, 186, 0.16)" },
  uncommon: { color: "var(--sage-300)", background: "rgba(194, 210, 186, 0.22)" },
  rare: { color: "var(--olive-500)", background: "rgba(142, 169, 103, 0.18)" },
  epic: { color: "var(--olive-700)", background: "rgba(119, 136, 54, 0.18)" },
  legendary: { color: "var(--apricot-500)", background: "rgba(240, 223, 203, 0.82)" },
};

const CATEGORIES = ["all", "fishing", "exploration", "dedication", "social", "economy", "collection", "meta"];

export default function AchievementsClient() {
  const [achievements, setAchievements] = useState<Achievement[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState("all");

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const supabase = getClientSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      const userId = session?.user?.id || "";
      if (!userId) {
        setError("Sign in to view achievements.");
        setLoading(false);
        return;
      }
      const res = await fetch(`/api/achievements?user_id=${userId}`);
      if (!res.ok) {
        setError(`Failed to load achievements (${res.status}).`);
        return;
      }
      const json = await res.json();
      if (json.ok) {
        setAchievements(json.achievements);
      } else {
        setError(json.error || "Failed to load achievements.");
      }
    } catch {
      setError("Network error. Check your connection.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void load(); }, []);

  const filtered = filter === "all" ? achievements : achievements.filter((achievement) => achievement.category === filter);
  const unlockedCount = achievements.filter((achievement) => achievement.unlocked).length;
  const totalXp = achievements
    .filter((achievement) => achievement.unlocked)
    .reduce((sum, achievement) => sum + achievement.xp_reward, 0);

  return (
    <div className={styles.shell}>
      <section className={styles.header}>
        <h1 className={styles.title}>Achievements</h1>
        <p className={styles.subtitle}>
          {unlockedCount} / {achievements.length} unlocked - {totalXp.toLocaleString()} XP earned
        </p>
      </section>

      <div className={styles.progressBar}>
        <div
          className={styles.progressFill}
          style={{ width: achievements.length > 0 ? `${(unlockedCount / achievements.length) * 100}%` : "0%" }}
        />
      </div>

      <nav className={styles.filters}>
        {CATEGORIES.map((category) => (
          <button
            key={category}
            className={`${styles.filterBtn} ${filter === category ? styles.filterActive : ""}`}
            onClick={() => setFilter(category)}
          >
            {category.charAt(0).toUpperCase() + category.slice(1)}
          </button>
        ))}
      </nav>

      <section className={styles.grid}>
        {loading ? (
          <p className={styles.emptyMsg}>Loading achievements...</p>
        ) : error ? (
          <div className={styles.emptyMsg}>
            <p>{error}</p>
            <button onClick={() => void load()} className={styles.filterBtn} style={{ marginTop: "0.5rem" }}>
              Retry
            </button>
          </div>
        ) : filtered.length === 0 ? (
          <p className={styles.emptyMsg}>No achievements in this category.</p>
        ) : (
          filtered.map((achievement) => {
            const rarityTheme = RARITY_THEME[achievement.rarity] || RARITY_THEME.common;

            return (
              <article
                key={achievement.id}
                className={`${styles.card} ${achievement.unlocked ? styles.cardUnlocked : styles.cardLocked}`}
                style={{
                  borderColor: rarityTheme.color,
                  background: achievement.unlocked ? rarityTheme.background : "var(--bg-surface)",
                }}
              >
                <div className={styles.cardHeader}>
                  <span className={styles.cardIcon} style={{ color: rarityTheme.color }}>
                    {achievement.unlocked ? "★" : "☆"}
                  </span>
                  <div>
                    <h3 className={styles.cardName}>{achievement.name}</h3>
                    <span className={styles.cardRarity} style={{ color: rarityTheme.color }}>
                      {achievement.rarity.toUpperCase()}
                    </span>
                  </div>
                </div>
                <p className={styles.cardDesc}>{achievement.description}</p>
                <div className={styles.cardFooter}>
                  <span className={styles.cardXp}>+{achievement.xp_reward} XP</span>
                  {achievement.unlocked && achievement.unlocked_at && (
                    <span className={styles.cardDate}>
                      {new Date(achievement.unlocked_at).toLocaleDateString("en-US")}
                    </span>
                  )}
                </div>
              </article>
            );
          })
        )}
      </section>

      <section className={styles.navSection}>
        <Link href="/home" className={styles.btnGhost}>Home</Link>
        <Link href="/profile" className={styles.btnGhost}>Profiles</Link>
      </section>
    </div>
  );
}
