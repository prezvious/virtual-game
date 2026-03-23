"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import type { LeaderboardModel } from "@/lib/leaderboard";
import styles from "@/app/leaderboard/leaderboard.module.css";

type LeaderboardApiResponse = {
  ok: boolean;
  model: LeaderboardModel;
};

type Props = {
  initialModel: LeaderboardModel;
};

const REFRESH_INTERVAL_MS = 30_000;

function LeaderboardColumn({
  title,
  entries,
  emptyLabel,
  toneClass,
}: {
  title: string;
  entries: LeaderboardModel["money"];
  emptyLabel: string;
  toneClass: string;
}) {
  return (
    <article className={`${styles.boardColumn} ${toneClass}`}>
      <h2 className={styles.columnTitle}>{title}</h2>
      <ol className={styles.list}>
        {entries.length ? (
          entries.map((row) => (
            <li key={`${title}-${row.rank}-${row.username}`} className={styles.row}>
              <span className={styles.rankWrap}>
                <span className={styles.rank}>#{row.rank}</span>
                <b className={styles.name}>@{row.username}</b>
              </span>
              <span className={styles.score}>{row.score}</span>
            </li>
          ))
        ) : (
          <li className={`${styles.row} ${styles.empty}`}>
            <span>{emptyLabel}</span>
            <span>0</span>
          </li>
        )}
      </ol>
    </article>
  );
}

export default function LeaderboardLive({ initialModel }: Props) {
  const [model, setModel] = useState<LeaderboardModel>(initialModel);
  const [isRefreshing, setIsRefreshing] = useState(false);

  useEffect(() => {
    let stopped = false;

    const refresh = async () => {
      setIsRefreshing(true);
      try {
        const response = await fetch("/api/leaderboard", { cache: "no-store" });
        if (!response.ok) return;
        const data = (await response.json()) as LeaderboardApiResponse;
        if (stopped || !data?.model) return;
        setModel(data.model);
      } catch {
        // Keep currently rendered leaderboard values on refresh failures.
      } finally {
        if (!stopped) setIsRefreshing(false);
      }
    };

    const timer = window.setInterval(() => {
      void refresh();
    }, REFRESH_INTERVAL_MS);

    return () => {
      stopped = true;
      window.clearInterval(timer);
    };
  }, []);

  return (
    <div className={styles.shell}>
      <section className={styles.intro}>
        <h1 className={styles.title}>Leaderboard</h1>
        <p className={styles.subtitle}>
          {model.error
            ? `Leaderboard unavailable: ${model.error}`
            : model.refreshedAt
              ? `Last updated: ${model.refreshedAt}`
              : "No leaderboard entries yet."}
        </p>
        <p className={styles.liveNote}>
          <span className={`${styles.livePulse}${isRefreshing ? ` ${styles.isRefreshing}` : ""}`} />
          {isRefreshing ? "Refreshing leaderboard..." : "Auto-updates every 30 seconds."}
        </p>
      </section>

      <section className={styles.boardGrid}>
        <LeaderboardColumn
          title="Most Money Earned"
          entries={model.money}
          emptyLabel="No entries yet."
          toneClass={styles.moneyTone}
        />
        <LeaderboardColumn
          title="Most Fish Caught"
          entries={model.fish}
          emptyLabel="No entries yet."
          toneClass={styles.fishTone}
        />
      </section>

      <section className={styles.footer}>
        <div className={styles.actionRow}>
          <Link className={`${styles.btn} ${styles.btnSecondary}`} href="/home">
            Platform Home
          </Link>
          <Link className={`${styles.btn} ${styles.btnPrimary}`} href="/fish">
            Play Game
          </Link>
        </div>
      </section>
    </div>
  );
}
