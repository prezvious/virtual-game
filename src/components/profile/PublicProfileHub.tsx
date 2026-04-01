"use client";

import Link from "next/link";
import { useDeferredValue, useEffect, useState, useTransition } from "react";
import styles from "@/app/profile/profile.module.css";

type PublicProfileCard = {
  username: string;
  avatar_url: string;
  bio: string;
  created_at: string;
};

function formatJoinDate(value: string) {
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) {
    return "Recently joined";
  }

  return `Joined ${new Date(timestamp).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  })}`;
}

export default function PublicProfileHub() {
  const [query, setQuery] = useState("");
  const deferredQuery = useDeferredValue(query.trim());
  const [profiles, setProfiles] = useState<PublicProfileCard[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [isPending, startTransition] = useTransition();

  useEffect(() => {
    let cancelled = false;

    const loadProfiles = async () => {
      setLoading(true);
      setError("");

      const params = new URLSearchParams();
      if (deferredQuery) {
        params.set("q", deferredQuery);
        params.set("limit", "18");
      } else {
        params.set("limit", "12");
      }

      try {
        const response = await fetch(`/api/profile/discover?${params.toString()}`, {
          cache: "no-store",
        });
        const json = await response.json();

        if (!response.ok || !json.ok) {
          throw new Error(json.error || "Could not load public profiles.");
        }

        if (cancelled) return;
        startTransition(() => {
          setProfiles(Array.isArray(json.profiles) ? json.profiles as PublicProfileCard[] : []);
        });
      } catch (loadError) {
        if (cancelled) return;
        setError(loadError instanceof Error ? loadError.message : "Could not load public profiles.");
        startTransition(() => {
          setProfiles([]);
        });
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    };

    void loadProfiles();

    return () => {
      cancelled = true;
    };
  }, [deferredQuery]);

  const hasQuery = deferredQuery.length > 0;

  return (
    <div className={styles.shell}>
      <section className={styles.guestHero}>
        <p className={styles.guestKicker}>Public Profiles</p>
        <h1 className={styles.guestTitle}>Browse shared player identities without signing in.</h1>
        <p className={styles.guestLead}>
          Public usernames, profile notes, and achievement snapshots are open to everyone.
          Sign in only when you want to manage your own account or use social actions.
        </p>

        <div className={styles.guestActions}>
          <Link href="/account-center" className={styles.btnPrimary}>Open Account Center</Link>
          <Link href="/leaderboard" className={styles.btnGhost}>Leaderboard</Link>
        </div>
      </section>

      <section className={styles.discoveryPanel}>
        <div className={styles.discoveryHeader}>
          <div>
            <h2 className={styles.sectionTitle}>Find a Player</h2>
            <p className={styles.sectionHint}>
              Search by public username, or explore the latest visible profiles below.
            </p>
          </div>
          <span className={styles.infoPill}>{hasQuery ? "Search Mode" : "Recent Profiles"}</span>
        </div>

        <label className={styles.searchField}>
          <span>Username Search</span>
          <input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search public usernames"
            autoComplete="off"
            spellCheck={false}
          />
        </label>

        <p className={styles.discoveryMeta}>
          {loading || isPending
            ? "Refreshing public profiles..."
            : error
              ? error
              : hasQuery
                ? `${profiles.length} profile${profiles.length === 1 ? "" : "s"} found for "${deferredQuery}".`
                : "Showing recent profiles with public usernames."}
        </p>

        {error ? (
          <div className={styles.discoveryEmpty}>
            <h3>Profile discovery is unavailable</h3>
            <p>{error}</p>
          </div>
        ) : profiles.length === 0 && !loading ? (
          <div className={styles.discoveryEmpty}>
            <h3>{hasQuery ? "No matching profiles" : "No public profiles yet"}</h3>
            <p>
              {hasQuery
                ? "Try a different username search."
                : "Public profiles will appear here once players set a shared username."}
            </p>
          </div>
        ) : (
          <div className={styles.discoveryGrid}>
            {profiles.map((profile) => (
              <Link
                key={profile.username}
                href={`/profile/${profile.username}`}
                className={styles.discoveryCard}
              >
                <div className={styles.discoveryAvatar}>
                  {profile.avatar_url ? (
                    <img src={profile.avatar_url} alt={profile.username} />
                  ) : (
                    <span>{profile.username.charAt(0).toUpperCase()}</span>
                  )}
                </div>
                <div className={styles.discoveryBody}>
                  <strong className={styles.discoveryUsername}>@{profile.username}</strong>
                  <p className={styles.discoveryBio}>{profile.bio || "No profile note yet."}</p>
                  <span className={styles.discoveryDate}>{formatJoinDate(profile.created_at)}</span>
                </div>
              </Link>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
