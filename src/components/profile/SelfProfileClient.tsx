"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { getClientSupabase } from "@/lib/auth-client";
import PublicProfileHub from "@/components/profile/PublicProfileHub";
import styles from "@/app/profile/profile.module.css";

type Achievement = {
  achievement_id: string;
  unlocked_at: string;
  achievements: { name: string; icon: string; rarity: string } | null;
};

type SelfProfile = {
  user_id: string;
  email: string;
  username: string;
  avatar_url: string;
  bio: string;
  is_admin: boolean;
  created_at: string;
  last_seen_at: string | null;
  followers_count: number;
  following_count: number;
  recent_achievements: Achievement[];
  playtime: {
    tracking_started_on: string;
    total_seconds: number;
    fisher_seconds: number;
    farmer_seconds: number;
    last_played_at: string | null;
  };
};

function formatDuration(totalSeconds: number) {
  const safeSeconds = Math.max(0, Number(totalSeconds) || 0);
  const hours = Math.floor(safeSeconds / 3600);
  const minutes = Math.floor((safeSeconds % 3600) / 60);

  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }

  if (minutes > 0) {
    return `${minutes}m`;
  }

  return `${safeSeconds}s`;
}

export default function SelfProfileClient() {
  const [profile, setProfile] = useState<SelfProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [authenticated, setAuthenticated] = useState(false);
  const [error, setError] = useState("");
  const [usernameInput, setUsernameInput] = useState("");
  const [bioInput, setBioInput] = useState("");
  const [usernameMessage, setUsernameMessage] = useState("");
  const [bioMessage, setBioMessage] = useState("");
  const [passwordMessage, setPasswordMessage] = useState("");
  const [usernameBusy, setUsernameBusy] = useState(false);
  const [bioBusy, setBioBusy] = useState(false);
  const [passwordBusy, setPasswordBusy] = useState(false);
  const [showPasswordForm, setShowPasswordForm] = useState(false);
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");

  const syncProfileState = useCallback((nextProfile: SelfProfile | null) => {
    setProfile(nextProfile);
    setUsernameInput(nextProfile?.username || "");
    setBioInput(nextProfile?.bio || "");
  }, []);

  const getSessionToken = useCallback(async () => {
    const supabase = getClientSupabase();
    const { data: { session } } = await supabase.auth.getSession();
    return session?.access_token || null;
  }, []);

  const loadProfile = useCallback(async () => {
    setLoading(true);
    setError("");

    try {
      const token = await getSessionToken();
      if (!token) {
        setAuthenticated(false);
        syncProfileState(null);
        return;
      }

      setAuthenticated(true);
      const res = await fetch("/api/profile/me", {
        headers: { Authorization: `Bearer ${token}` },
      });
      const json = await res.json();

      if (!json.ok) {
        setError(json.error || "Failed to load your profile.");
        syncProfileState(null);
        return;
      }

      syncProfileState(json.profile as SelfProfile);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Failed to load your profile.");
      syncProfileState(null);
    } finally {
      setLoading(false);
    }
  }, [getSessionToken, syncProfileState]);

  useEffect(() => {
    void loadProfile();

    const supabase = getClientSupabase();
    const { data } = supabase.auth.onAuthStateChange(() => {
      void loadProfile();
    });

    return () => {
      data.subscription.unsubscribe();
    };
  }, [loadProfile]);

  const patchProfile = useCallback(async (payload: Record<string, unknown>) => {
    const token = await getSessionToken();
    if (!token) {
      throw new Error("Sign in to update your profile.");
    }

    const res = await fetch("/api/profile/me", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(payload),
    });
    const json = await res.json();

    if (!json.ok) {
      throw new Error(json.error || "Profile update failed.");
    }

    syncProfileState(json.profile as SelfProfile);
    return json.profile as SelfProfile;
  }, [getSessionToken, syncProfileState]);

  const handleUsernameSave = useCallback(async () => {
    const nextUsername = usernameInput.trim();
    if (!nextUsername) {
      setUsernameMessage("Choose a username to appear on both games.");
      return;
    }

    setUsernameBusy(true);
    setUsernameMessage("");

    try {
      await patchProfile({ username: nextUsername });
      setUsernameMessage("Global username saved.");
    } catch (saveError) {
      setUsernameMessage(saveError instanceof Error ? saveError.message : "Could not save username.");
    } finally {
      setUsernameBusy(false);
    }
  }, [patchProfile, usernameInput]);

  const handleBioSave = useCallback(async () => {
    setBioBusy(true);
    setBioMessage("");

    try {
      await patchProfile({ bio: bioInput });
      setBioMessage("Profile note saved.");
    } catch (saveError) {
      setBioMessage(saveError instanceof Error ? saveError.message : "Could not save profile note.");
    } finally {
      setBioBusy(false);
    }
  }, [bioInput, patchProfile]);

  const handlePasswordSave = useCallback(async () => {
    if (newPassword.length < 8) {
      setPasswordMessage("Password must be at least 8 characters.");
      return;
    }

    if (newPassword !== confirmPassword) {
      setPasswordMessage("Passwords do not match.");
      return;
    }

    const token = await getSessionToken();
    if (!token) {
      setPasswordMessage("Sign in to update your password.");
      return;
    }

    setPasswordBusy(true);
    setPasswordMessage("");

    try {
      const res = await fetch("/api/profile/password", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ newPassword }),
      });
      const json = await res.json();

      if (!json.ok) {
        throw new Error(json.error || "Could not update password.");
      }

      setPasswordMessage("Password updated.");
      setNewPassword("");
      setConfirmPassword("");
      setShowPasswordForm(false);
    } catch (saveError) {
      setPasswordMessage(saveError instanceof Error ? saveError.message : "Could not update password.");
    } finally {
      setPasswordBusy(false);
    }
  }, [confirmPassword, getSessionToken, newPassword]);

  if (loading) {
    return (
      <div className={styles.shell}>
        <p className={styles.loadingText}>Loading account profile...</p>
      </div>
    );
  }

  if (!authenticated) {
    return <PublicProfileHub />;
  }

  if (error || !profile) {
    return (
      <div className={styles.shell}>
        <div className={styles.errorCard}>
          <h2>Could not load profile</h2>
          <p>{error || "The account profile is unavailable right now."}</p>
          <button type="button" className={styles.btnPrimary} onClick={() => void loadProfile()}>
            Retry
          </button>
        </div>
      </div>
    );
  }

  const joinDate = new Date(profile.created_at).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  });
  const lastPlayed = profile.playtime.last_played_at
    ? new Date(profile.playtime.last_played_at).toLocaleString("en-US")
    : "No tracked sessions yet";

  return (
    <div className={styles.shell}>
      <section className={styles.header}>
        <div className={styles.avatar}>
          {profile.avatar_url ? (
            <img src={profile.avatar_url} alt={profile.username || profile.email} />
          ) : (
            <span>{(profile.username || profile.email || "?").charAt(0).toUpperCase()}</span>
          )}
        </div>
        <div className={styles.headerInfo}>
          <h1 className={styles.username}>
            {profile.username ? `@${profile.username}` : "Set your global username"}
            {profile.is_admin && <span className={styles.adminBadge}>ADMIN</span>}
          </h1>
          <p className={styles.bio}>
            {profile.email}
          </p>
          <p className={styles.meta}>Joined {joinDate}</p>
          <p className={styles.meta}>Playtime tracking started on {profile.playtime.tracking_started_on}</p>
        </div>
      </section>

      <section className={styles.statsRow}>
        <div className={styles.stat}><span className={styles.statNumber}>{profile.followers_count}</span><span className={styles.statLabel}>Followers</span></div>
        <div className={styles.stat}><span className={styles.statNumber}>{profile.following_count}</span><span className={styles.statLabel}>Following</span></div>
        <div className={styles.stat}><span className={styles.statNumber}>{profile.recent_achievements.length}</span><span className={styles.statLabel}>Recent Achievements</span></div>
      </section>

      <section className={styles.panelSection}>
        <div className={styles.sectionHeader}>
          <div>
            <h2 className={styles.sectionTitle}>Global Username</h2>
            <p className={styles.sectionHint}>
              One username powers both Virtual Fisher and Virtual Farmer leaderboards.
            </p>
          </div>
          <span className={styles.infoPill}>{profile.username ? "Active" : "Required for public leaderboard identity"}</span>
        </div>

        <div className={styles.inlineForm}>
          <label className={styles.field}>
            <span>Username</span>
            <input
              type="text"
              value={usernameInput}
              onChange={(event) => setUsernameInput(event.target.value)}
              minLength={3}
              maxLength={20}
              autoComplete="username"
              placeholder="3-20 chars, letters, numbers, underscores"
              disabled={usernameBusy}
            />
          </label>
          <button type="button" className={styles.btnPrimary} onClick={() => void handleUsernameSave()} disabled={usernameBusy}>
            {usernameBusy ? "Saving..." : profile.username ? "Update Username" : "Set Username"}
          </button>
        </div>
        {usernameMessage && <p className={styles.inlineMessage}>{usernameMessage}</p>}
      </section>

      <section className={styles.panelSection}>
        <div className={styles.sectionHeader}>
          <div>
            <h2 className={styles.sectionTitle}>Playtime</h2>
            <p className={styles.sectionHint}>
              Combined runtime across both games. More profile breakdowns are expanding soon.
            </p>
          </div>
        </div>

        <div className={styles.playtimeGrid}>
          <article className={styles.infoCard}>
            <p className={styles.cardLabel}>Total</p>
            <strong className={styles.cardValue}>{formatDuration(profile.playtime.total_seconds)}</strong>
          </article>
          <article className={styles.infoCard}>
            <p className={styles.cardLabel}>Virtual Fisher</p>
            <strong className={styles.cardValue}>{formatDuration(profile.playtime.fisher_seconds)}</strong>
          </article>
          <article className={styles.infoCard}>
            <p className={styles.cardLabel}>Virtual Farmer</p>
            <strong className={styles.cardValue}>{formatDuration(profile.playtime.farmer_seconds)}</strong>
          </article>
        </div>
        <p className={styles.meta}>Last tracked activity: {lastPlayed}</p>
      </section>

      <section className={styles.panelSection}>
        <div className={styles.sectionHeader}>
          <div>
            <h2 className={styles.sectionTitle}>Profile Note</h2>
            <p className={styles.sectionHint}>Public profile visitors can see this note.</p>
          </div>
        </div>

        <label className={styles.field}>
          <span>Bio</span>
          <textarea
            value={bioInput}
            onChange={(event) => setBioInput(event.target.value)}
            rows={4}
            maxLength={500}
            className={styles.bioTextarea}
            disabled={bioBusy}
          />
        </label>
        <div className={styles.inlineActions}>
          <button type="button" className={styles.btnSmall} onClick={() => void handleBioSave()} disabled={bioBusy}>
            {bioBusy ? "Saving..." : "Save Note"}
          </button>
        </div>
        {bioMessage && <p className={styles.inlineMessage}>{bioMessage}</p>}
      </section>

      <section className={styles.panelSection}>
        <div className={styles.sectionHeader}>
          <div>
            <h2 className={styles.sectionTitle}>Security</h2>
            <p className={styles.sectionHint}>Sign-out remains centralized in the account center.</p>
          </div>
        </div>

        <div className={styles.inlineActions}>
          <button type="button" className={styles.btnGhost} onClick={() => setShowPasswordForm((value) => !value)}>
            {showPasswordForm ? "Cancel Password Change" : "Change Password"}
          </button>
        </div>

        {showPasswordForm && (
          <div className={styles.passwordForm}>
            <label>
              <span>New Password</span>
              <input
                type="password"
                value={newPassword}
                onChange={(event) => setNewPassword(event.target.value)}
                minLength={8}
                autoComplete="new-password"
              />
            </label>
            <label>
              <span>Confirm Password</span>
              <input
                type="password"
                value={confirmPassword}
                onChange={(event) => setConfirmPassword(event.target.value)}
                minLength={8}
                autoComplete="new-password"
              />
            </label>
            <button type="button" className={styles.btnPrimary} onClick={() => void handlePasswordSave()} disabled={passwordBusy}>
              {passwordBusy ? "Updating..." : "Update Password"}
            </button>
          </div>
        )}
        {passwordMessage && <p className={styles.inlineMessage}>{passwordMessage}</p>}
      </section>

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
        <Link href="/account-center" className={styles.btnGhost}>Account Center</Link>
        <Link href="/leaderboard" className={styles.btnGhost}>Leaderboard</Link>
        <Link href="/friends" className={styles.btnGhost}>Friends</Link>
        {profile.username ? <Link href={`/profile/${profile.username}`} className={styles.btnGhost}>Public Profile</Link> : null}
      </section>
    </div>
  );
}
