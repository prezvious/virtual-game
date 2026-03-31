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

const RARITY_COLORS: Record<string, string> = {
  common: "#6b7280", uncommon: "#22c55e", rare: "#3b82f6", epic: "#a855f7", legendary: "#f59e0b",
};
const RARITY_BG: Record<string, string> = {
  common: "rgba(107,114,128,0.08)", uncommon: "rgba(34,197,94,0.08)", rare: "rgba(59,130,246,0.08)", epic: "rgba(168,85,247,0.08)", legendary: "rgba(245,158,11,0.08)",
};
const CATEGORIES = ["all", "fishing", "exploration", "dedication", "social", "economy", "collection", "meta"];

export default function AchievementsClient() {
  const [achievements, setAchievements] = useState<Achievement[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState("all");

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        const supabase = getClientSupabase();
        const { data: { session } } = await supabase.auth.getSession();
        const userId = session?.user?.id || "";
        const res = await fetch(`/api/achievements?user_id=${userId}`);
        const json = await res.json();
        if (json.ok) setAchievements(json.achievements);
      } finally {
        setLoading(false);
      }
    };
    void load();
  }, []);

  const filtered = filter === "all" ? achievements : achievements.filter((a) => a.category === filter);
  const unlockedCount = achievements.filter((a) => a.unlocked).length;
  const totalXp = achievements.filter((a) => a.unlocked).reduce((sum, a) => sum + a.xp_reward, 0);

  return (
    <div className={styles.shell}>
      <section className={styles.header}>
        <h1 className={styles.title}>Achievements</h1>
        <p className={styles.subtitle}>{unlockedCount} / {achievements.length} unlocked — {totalXp.toLocaleString()} XP earned</p>
      </section>

      <div className={styles.progressBar}>
        <div className={styles.progressFill} style={{ width: achievements.length > 0 ? `${(unlockedCount / achievements.length) * 100}%` : "0%" }} />
      </div>

      <nav className={styles.filters}>
        {CATEGORIES.map((cat) => (
          <button key={cat} className={`${styles.filterBtn} ${filter === cat ? styles.filterActive : ""}`} onClick={() => setFilter(cat)}>
            {cat.charAt(0).toUpperCase() + cat.slice(1)}
          </button>
        ))}
      </nav>

      <section className={styles.grid}>
        {loading ? (
          <p className={styles.emptyMsg}>Loading achievements...</p>
        ) : filtered.length === 0 ? (
          <p className={styles.emptyMsg}>No achievements in this category.</p>
        ) : (
          filtered.map((a) => (
            <article key={a.id} className={`${styles.card} ${a.unlocked ? styles.cardUnlocked : styles.cardLocked}`}
              style={{ borderColor: RARITY_COLORS[a.rarity], background: a.unlocked ? RARITY_BG[a.rarity] : "rgba(0,0,0,0.02)" }}>
              <div className={styles.cardHeader}>
                <span className={styles.cardIcon} style={{ color: RARITY_COLORS[a.rarity] }}>{a.unlocked ? "★" : "☆"}</span>
                <div>
                  <h3 className={styles.cardName}>{a.name}</h3>
                  <span className={styles.cardRarity} style={{ color: RARITY_COLORS[a.rarity] }}>{a.rarity.toUpperCase()}</span>
                </div>
              </div>
              <p className={styles.cardDesc}>{a.description}</p>
              <div className={styles.cardFooter}>
                <span className={styles.cardXp}>+{a.xp_reward} XP</span>
                {a.unlocked && a.unlocked_at && <span className={styles.cardDate}>{new Date(a.unlocked_at).toLocaleDateString("en-US")}</span>}
              </div>
            </article>
          ))
        )}
      </section>

      <section className={styles.navSection}>
        <Link href="/home" className={styles.btnGhost}>Platform Home</Link>
        <Link href="/profile" className={styles.btnGhost}>Profiles</Link>
      </section>
    </div>
  );
}
