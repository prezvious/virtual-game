"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { getClientSupabase } from "@/lib/auth-client";
import styles from "@/app/profile/profile.module.css";

type Achievement = {
  achievement_id: string;
  unlocked_at: string;
  achievements: { name: string; icon: string; rarity: string } | null;
};

type Profile = {
  user_id: string;
  username: string;
  avatar_url: string;
  bio: string;
  is_admin: boolean;
  created_at: string;
  last_seen_at: string | null;
  followers_count: number;
  following_count: number;
  recent_achievements: Achievement[];
};

type SocialStatus = {
  following: boolean;
  follows_back: boolean;
  is_friend: boolean;
  block: string | null;
};

type Props = { username: string };

export default function ProfileClient({ username }: Props) {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [socialStatus, setSocialStatus] = useState<SocialStatus | null>(null);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [actionBusy, setActionBusy] = useState(false);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      setError("");

      try {
        const supabase = getClientSupabase();
        const { data: { session } } = await supabase.auth.getSession();
        const token = session?.access_token;
        if (session?.user) {
          setCurrentUserId(session.user.id);
        } else {
          setCurrentUserId(null);
        }

        const res = await fetch(`/api/profile?username=${encodeURIComponent(username)}`);
        const json = await res.json();
        if (!json.ok) {
          setError(json.error || "Profile not found.");
          setProfile(null);
          return;
        }

        const nextProfile = json.profile as Profile;
        setProfile(nextProfile);

        if (session?.user && token && nextProfile.user_id !== session.user.id) {
          const socialRes = await fetch(`/api/social?tab=status&target_id=${nextProfile.user_id}`, {
            headers: { Authorization: `Bearer ${token}` },
          });
          const socialJson = await socialRes.json();
          if (socialJson.ok) {
            setSocialStatus(socialJson.data as SocialStatus);
          }
        } else {
          setSocialStatus(null);
        }
      } catch (loadError) {
        setError(loadError instanceof Error ? loadError.message : "Failed to load profile.");
        setProfile(null);
      } finally {
        setLoading(false);
      }
    };

    void load();
  }, [username]);

  const doSocialAction = useCallback(async (action: string) => {
    if (!profile || actionBusy) return;

    setActionBusy(true);
    try {
      const supabase = getClientSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;

      const res = await fetch("/api/social", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({ action, target_id: profile.user_id }),
      });
      const json = await res.json();
      if (!json.ok) return;

      const socialRes = await fetch(`/api/social?tab=status&target_id=${profile.user_id}`, {
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
      const socialJson = await socialRes.json();
      if (socialJson.ok) {
        setSocialStatus(socialJson.data as SocialStatus);
      }
    } finally {
      setActionBusy(false);
    }
  }, [actionBusy, profile]);

  if (loading) {
    return (
      <div className={styles.shell}>
        <p className={styles.loadingText}>Loading profile...</p>
      </div>
    );
  }

  if (error || !profile) {
    return (
      <div className={styles.shell}>
        <div className={styles.errorCard}>
          <h2>Profile not found</h2>
          <p>{error || "This user does not exist."}</p>
          <Link href="/home" className={styles.btnPrimary}>Return Home</Link>
        </div>
      </div>
    );
  }

  const isOwn = currentUserId === profile.user_id;
  const joinDate = new Date(profile.created_at).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  });

  return (
    <div className={styles.shell}>
      <section className={styles.header}>
        <div className={styles.avatar}>
          {profile.avatar_url ? (
            <img src={profile.avatar_url} alt={profile.username} />
          ) : (
            <span>{profile.username.charAt(0).toUpperCase()}</span>
          )}
        </div>
        <div className={styles.headerInfo}>
          <h1 className={styles.username}>
            @{profile.username}
            {profile.is_admin && <span className={styles.adminBadge}>ADMIN</span>}
          </h1>
          <p className={styles.bio}>{profile.bio || "No profile note yet."}</p>
          <p className={styles.meta}>Joined {joinDate}</p>
        </div>
      </section>

      <section className={styles.statsRow}>
        <div className={styles.stat}><span className={styles.statNumber}>{profile.followers_count}</span><span className={styles.statLabel}>Followers</span></div>
        <div className={styles.stat}><span className={styles.statNumber}>{profile.following_count}</span><span className={styles.statLabel}>Following</span></div>
        <div className={styles.stat}><span className={styles.statNumber}>{profile.recent_achievements.length}</span><span className={styles.statLabel}>Achievements</span></div>
      </section>

      {!isOwn && currentUserId && socialStatus && (
        <section className={styles.socialActions}>
          {socialStatus.block ? (
            <button type="button" onClick={() => void doSocialAction("unblock")} disabled={actionBusy} className={styles.btnDanger}>
              Unblock User
            </button>
          ) : (
            <>
              {socialStatus.following ? (
                <button type="button" onClick={() => void doSocialAction("unfollow")} disabled={actionBusy} className={styles.btnGhost}>
                  {socialStatus.is_friend ? "Friends - Unfollow" : "Following - Unfollow"}
                </button>
              ) : (
                <button type="button" onClick={() => void doSocialAction("follow")} disabled={actionBusy} className={styles.btnPrimary}>
                  {socialStatus.follows_back ? "Follow Back" : "Follow"}
                </button>
              )}
              <button type="button" onClick={() => void doSocialAction("block")} disabled={actionBusy} className={styles.btnDanger}>
                Block
              </button>
              <button type="button" onClick={() => void doSocialAction("restrict")} disabled={actionBusy} className={styles.btnGhostDanger}>
                Restrict
              </button>
            </>
          )}
        </section>
      )}

      {profile.recent_achievements.length > 0 && (
        <section className={styles.achievementsSection}>
          <h2 className={styles.sectionTitle}>Recent Achievements</h2>
          <div className={styles.achievementGrid}>
            {profile.recent_achievements.map((achievement) => (
              <div key={achievement.achievement_id} className={styles.achievementCard}>
                <span className={styles.achievementName}>{achievement.achievements?.name || achievement.achievement_id}</span>
                <span className={styles.achievementDate}>{new Date(achievement.unlocked_at).toLocaleDateString("en-US")}</span>
              </div>
            ))}
          </div>
        </section>
      )}

      <section className={styles.navSection}>
        <Link href="/home" className={styles.btnGhost}>Home</Link>
        <Link href="/leaderboard" className={styles.btnGhost}>Leaderboard</Link>
        <Link href="/friends" className={styles.btnGhost}>Friends</Link>
        {isOwn ? <Link href="/profile" className={styles.btnGhost}>Account Profile</Link> : null}
      </section>
    </div>
  );
}
