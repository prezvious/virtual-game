"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { getClientSupabase } from "@/lib/auth-client";
import styles from "@/app/friends/friends.module.css";

type SocialUser = {
  follower_id?: string;
  following_id?: string;
  blocked_id?: string;
  restriction_type?: string;
  created_at?: string;
  user_profiles?: { username: string; avatar_url: string } | null;
};

type Tab = "friends" | "followers" | "following" | "blocked";

export default function FriendsClient() {
  const [tab, setTab] = useState<Tab>("friends");
  const [data, setData] = useState<SocialUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionBusy, setActionBusy] = useState(false);

  const fetchData = useCallback(async (activeTab: Tab) => {
    setLoading(true);
    try {
      const supabase = getClientSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;
      const res = await fetch(`/api/social?tab=${activeTab}`, {
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
      const json = await res.json();
      if (json.ok) setData(json.data || []);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void fetchData(tab); }, [tab, fetchData]);

  const doAction = useCallback(async (action: string, targetId: string) => {
    setActionBusy(true);
    try {
      const supabase = getClientSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;
      await fetch("/api/social", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify({ action, target_id: targetId }),
      });
      await fetchData(tab);
    } finally {
      setActionBusy(false);
    }
  }, [tab, fetchData]);

  const getUserId = (item: SocialUser) => item.follower_id || item.following_id || item.blocked_id || "";
  const getUsername = (item: SocialUser) => item.user_profiles?.username || "Unknown";

  const tabs: { key: Tab; label: string }[] = [
    { key: "friends", label: "Friends" },
    { key: "followers", label: "Followers" },
    { key: "following", label: "Following" },
    { key: "blocked", label: "Blocked" },
  ];

  return (
    <div className={styles.shell}>
      <section className={styles.header}>
        <h1 className={styles.title}>Social</h1>
        <p className={styles.subtitle}>Manage your connections.</p>
      </section>

      <nav className={styles.tabs}>
        {tabs.map((t) => (
          <button key={t.key} className={`${styles.tab} ${tab === t.key ? styles.tabActive : ""}`} onClick={() => setTab(t.key)}>
            {t.label}
          </button>
        ))}
      </nav>

      <section className={styles.list}>
        {loading ? (
          <p className={styles.emptyMsg}>Loading...</p>
        ) : data.length === 0 ? (
          <p className={styles.emptyMsg}>
            {tab === "friends" && "No friends yet. Follow users and wait for them to follow back!"}
            {tab === "followers" && "No followers yet."}
            {tab === "following" && "Not following anyone yet."}
            {tab === "blocked" && "No blocked users."}
          </p>
        ) : (
          data.map((item) => {
            const userId = getUserId(item);
            const uname = getUsername(item);
            return (
              <div key={userId} className={styles.row}>
                <Link href={`/profile/${uname}`} className={styles.userLink}>
                  <span className={styles.userAvatar}>{uname.charAt(0).toUpperCase()}</span>
                  <span className={styles.userName}>@{uname}</span>
                </Link>
                <div className={styles.rowActions}>
                  {tab === "followers" && (
                    <button onClick={() => void doAction("follow", userId)} disabled={actionBusy} className={styles.btnSmall}>Follow Back</button>
                  )}
                  {tab === "following" && (
                    <button onClick={() => void doAction("unfollow", userId)} disabled={actionBusy} className={styles.btnSmallDanger}>Unfollow</button>
                  )}
                  {tab === "friends" && (
                    <button onClick={() => void doAction("unfollow", userId)} disabled={actionBusy} className={styles.btnSmallDanger}>Unfriend</button>
                  )}
                  {tab === "blocked" && (
                    <>
                      <span className={styles.restrictType}>{item.restriction_type}</span>
                      <button onClick={() => void doAction("unblock", userId)} disabled={actionBusy} className={styles.btnSmall}>Unblock</button>
                    </>
                  )}
                </div>
              </div>
            );
          })
        )}
      </section>

      <section className={styles.navSection}>
        <Link href="/home" className={styles.btnGhost}>Platform Home</Link>
        <Link href="/search" className={styles.btnGhost}>Find Players</Link>
      </section>
    </div>
  );
}
