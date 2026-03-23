"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import styles from "@/app/search/search.module.css";

type Tab = "players" | "leaderboard" | "games";

type PlayerResult = { user_id: string; username: string; avatar_url: string; bio: string; created_at: string };
type LeaderboardResult = { metric: string; rank: number; username: string; score: string };
type GameResult = { id: string; name: string; description: string; href: string };

export default function SearchClient() {
  const [query, setQuery] = useState("");
  const [tab, setTab] = useState<Tab>("players");
  const [results, setResults] = useState<unknown[]>([]);
  const [loading, setLoading] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const search = useCallback(async (q: string, t: Tab) => {
    if (q.length < 2) { setResults([]); return; }
    setLoading(true);
    try {
      const res = await fetch(`/api/search?q=${encodeURIComponent(q)}&tab=${t}`);
      const json = await res.json();
      if (json.ok) setResults(json.results);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => { void search(query, tab); }, 300);
    return () => { if (debounceRef.current) clearTimeout(debounceRef.current); };
  }, [query, tab, search]);

  const tabs: { key: Tab; label: string }[] = [
    { key: "players", label: "Players" },
    { key: "leaderboard", label: "Leaderboard" },
    { key: "games", label: "Games" },
  ];

  return (
    <div className={styles.shell}>
      <section className={styles.header}>
        <h1 className={styles.title}>Search</h1>
        <div className={styles.searchBox}>
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search players, games, leaderboards..."
            className={styles.searchInput}
            autoFocus
          />
        </div>
      </section>

      <nav className={styles.tabs}>
        {tabs.map((t) => (
          <button key={t.key} className={`${styles.tab} ${tab === t.key ? styles.tabActive : ""}`} onClick={() => setTab(t.key)}>
            {t.label}
          </button>
        ))}
      </nav>

      <section className={styles.results}>
        {loading && <p className={styles.emptyMsg}>Searching...</p>}
        {!loading && query.length >= 2 && results.length === 0 && <p className={styles.emptyMsg}>No results found.</p>}
        {!loading && query.length < 2 && <p className={styles.emptyMsg}>Type at least 2 characters to search.</p>}

        {!loading && tab === "players" && (results as PlayerResult[]).map((p) => (
          <Link key={p.user_id} href={`/profile/${p.username}`} className={styles.resultRow}>
            <span className={styles.resultAvatar}>{p.username.charAt(0).toUpperCase()}</span>
            <div className={styles.resultInfo}>
              <span className={styles.resultName}>@{p.username}</span>
              <span className={styles.resultMeta}>{p.bio || "No bio"}</span>
            </div>
          </Link>
        ))}

        {!loading && tab === "leaderboard" && (results as LeaderboardResult[]).map((r, i) => (
          <div key={`${r.metric}-${r.rank}-${i}`} className={styles.resultRow}>
            <span className={styles.resultRank}>#{r.rank}</span>
            <div className={styles.resultInfo}>
              <Link href={`/profile/${r.username}`} className={styles.resultName}>@{r.username}</Link>
              <span className={styles.resultMeta}>{r.metric.replace(/_/g, " ")} — {r.score}</span>
            </div>
          </div>
        ))}

        {!loading && tab === "games" && (results as GameResult[]).map((g) => (
          <Link key={g.id} href={g.href} className={styles.resultRow}>
            <div className={styles.resultInfo}>
              <span className={styles.resultName}>{g.name}</span>
              <span className={styles.resultMeta}>{g.description}</span>
            </div>
          </Link>
        ))}
      </section>

      <section className={styles.navSection}>
        <Link href="/home" className={styles.btnGhost}>Platform Home</Link>
        <Link href="/friends" className={styles.btnGhost}>My Friends</Link>
      </section>
    </div>
  );
}
