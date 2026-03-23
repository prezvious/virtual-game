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
  last_seen_at: string;
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

const RARITY_COLORS: Record<string, string> = {
  common: "#6b7280",
  uncommon: "#22c55e",
  rare: "#3b82f6",
  epic: "#a855f7",
  legendary: "#f59e0b",
};

export default function ProfileClient({ username }: Props) {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [socialStatus, setSocialStatus] = useState<SocialStatus | null>(null);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [isOwn, setIsOwn] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [showPasswordForm, setShowPasswordForm] = useState(false);
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordMsg, setPasswordMsg] = useState("");
  const [editingBio, setEditingBio] = useState(false);
  const [bioInput, setBioInput] = useState("");
  const [actionBusy, setActionBusy] = useState(false);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        const supabase = getClientSupabase();
        const { data: { session } } = await supabase.auth.getSession();
        const token = session?.access_token;
        if (session?.user) setCurrentUserId(session.user.id);

        const res = await fetch(`/api/profile?username=${encodeURIComponent(username)}`);
        const json = await res.json();
        if (!json.ok) { setError(json.error || "Profile not found."); return; }

        setProfile(json.profile);
        setBioInput(json.profile.bio || "");

        if (session?.user && json.profile.user_id === session.user.id) {
          setIsOwn(true);
        } else if (session?.user && token) {
          const socialRes = await fetch(`/api/social?tab=status&target_id=${json.profile.user_id}`, {
            headers: { Authorization: `Bearer ${token}` },
          });
          const socialJson = await socialRes.json();
          if (socialJson.ok) setSocialStatus(socialJson.data);
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load profile.");
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
      await fetch("/api/social", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify({ action, target_id: profile.user_id }),
      });
      const socialRes = await fetch(`/api/social?tab=status&target_id=${profile.user_id}`, {
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
      const socialJson = await socialRes.json();
      if (socialJson.ok) setSocialStatus(socialJson.data);
    } finally {
      setActionBusy(false);
    }
  }, [profile, actionBusy]);

  const handlePasswordChange = useCallback(async () => {
    if (newPassword.length < 8) { setPasswordMsg("Password must be at least 8 characters."); return; }
    if (newPassword !== confirmPassword) { setPasswordMsg("Passwords do not match."); return; }
    setActionBusy(true);
    try {
      const supabase = getClientSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;
      const res = await fetch("/api/profile/password", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify({ newPassword }),
      });
      const json = await res.json();
      setPasswordMsg(json.ok ? "Password updated!" : json.error || "Failed.");
      if (json.ok) { setNewPassword(""); setConfirmPassword(""); setShowPasswordForm(false); }
    } finally {
      setActionBusy(false);
    }
  }, [newPassword, confirmPassword]);

  const handleBioSave = useCallback(async () => {
    setActionBusy(true);
    try {
      const supabase = getClientSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;
      const res = await fetch("/api/profile", {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify({ bio: bioInput }),
      });
      const json = await res.json();
      if (json.ok && profile) { setProfile({ ...profile, bio: bioInput }); setEditingBio(false); }
    } finally {
      setActionBusy(false);
    }
  }, [bioInput, profile]);

  if (loading) return <div className={styles.shell}><p className={styles.loadingText}>Loading profile...</p></div>;

  if (error || !profile) {
    return (
      <div className={styles.shell}>
        <div className={styles.errorCard}>
          <h2>Profile not found</h2>
          <p>{error || "This user does not exist."}</p>
          <Link href="/home" className={styles.btnPrimary}>Back to Home</Link>
        </div>
      </div>
    );
  }

  const joinDate = new Date(profile.created_at).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" });

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
          {editingBio ? (
            <div className={styles.bioEdit}>
              <textarea value={bioInput} onChange={(e) => setBioInput(e.target.value)} maxLength={500} rows={3} className={styles.bioTextarea} />
              <div className={styles.bioActions}>
                <button onClick={() => void handleBioSave()} disabled={actionBusy} className={styles.btnSmall}>Save</button>
                <button onClick={() => { setEditingBio(false); setBioInput(profile.bio); }} className={styles.btnSmallGhost}>Cancel</button>
              </div>
            </div>
          ) : (
            <p className={styles.bio}>
              {profile.bio || (isOwn ? "No bio yet. Click edit to add one." : "No bio.")}
              {isOwn && <button onClick={() => setEditingBio(true)} className={styles.editLink}>Edit</button>}
            </p>
          )}
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
            <button onClick={() => void doSocialAction("unblock")} disabled={actionBusy} className={styles.btnDanger}>Unblock User</button>
          ) : (
            <>
              {socialStatus.following ? (
                <button onClick={() => void doSocialAction("unfollow")} disabled={actionBusy} className={styles.btnGhost}>
                  {socialStatus.is_friend ? "Friends — Unfollow" : "Following — Unfollow"}
                </button>
              ) : (
                <button onClick={() => void doSocialAction("follow")} disabled={actionBusy} className={styles.btnPrimary}>
                  {socialStatus.follows_back ? "Follow Back" : "Follow"}
                </button>
              )}
              <button onClick={() => void doSocialAction("block")} disabled={actionBusy} className={styles.btnDanger}>Block</button>
              <button onClick={() => void doSocialAction("restrict")} disabled={actionBusy} className={styles.btnGhostDanger}>Restrict</button>
            </>
          )}
        </section>
      )}

      {profile.recent_achievements.length > 0 && (
        <section className={styles.achievementsSection}>
          <h2 className={styles.sectionTitle}>Recent Achievements</h2>
          <div className={styles.achievementGrid}>
            {profile.recent_achievements.map((a) => (
              <div key={a.achievement_id} className={styles.achievementCard} style={{ borderColor: RARITY_COLORS[a.achievements?.rarity || "common"] }}>
                <span className={styles.achievementName}>{a.achievements?.name || a.achievement_id}</span>
                <span className={styles.achievementDate}>{new Date(a.unlocked_at).toLocaleDateString("en-US")}</span>
              </div>
            ))}
          </div>
          <Link href="/achievements" className={styles.viewAll}>View All Achievements</Link>
        </section>
      )}

      {isOwn && (
        <section className={styles.settingsSection}>
          <h2 className={styles.sectionTitle}>Account Settings</h2>
          <div className={styles.settingsGrid}>
            <button onClick={() => setShowPasswordForm(!showPasswordForm)} className={styles.btnGhost}>
              {showPasswordForm ? "Cancel" : "Change Password"}
            </button>
            <Link href="/friends" className={styles.btnGhost}>Manage Friends</Link>
            <Link href="/achievements" className={styles.btnGhost}>All Achievements</Link>
          </div>
          {showPasswordForm && (
            <div className={styles.passwordForm}>
              <label><span>New Password</span><input type="password" value={newPassword} onChange={(e) => setNewPassword(e.target.value)} minLength={8} autoComplete="new-password" /></label>
              <label><span>Confirm Password</span><input type="password" value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} minLength={8} autoComplete="new-password" /></label>
              <button onClick={() => void handlePasswordChange()} disabled={actionBusy} className={styles.btnPrimary}>
                {actionBusy ? "Updating..." : "Update Password"}
              </button>
              {passwordMsg && <p className={styles.passwordMsg}>{passwordMsg}</p>}
            </div>
          )}
        </section>
      )}

      <section className={styles.navSection}>
        <Link href="/home" className={styles.btnGhost}>Platform Home</Link>
        <Link href="/leaderboard" className={styles.btnGhost}>Leaderboard</Link>
        <Link href="/shop" className={styles.btnGhost}>Shop</Link>
      </section>
    </div>
  );
}
