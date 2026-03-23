"use client";

import { useCallback, useEffect, useState } from "react";
import { getClientSupabase } from "@/lib/auth-client";
import styles from "./onboarding.module.css";

const STEPS = [
  {
    id: "welcome",
    title: "Welcome to Virtual Harvest!",
    body: "One platform, two worlds. Your fishing and farming empires start here.",
    tip: "You can access both Virtual Fisher and Virtual Farmer from one account.",
  },
  {
    id: "games",
    title: "Choose Your Game",
    body: "Launch Virtual Fisher for skill-based fishing action, or Virtual Farmer for prestige-focused farming progression.",
    tip: "Both games sync your progress to the cloud automatically.",
  },
  {
    id: "profile",
    title: "Set Up Your Profile",
    body: "Add a bio, customize your avatar, and show off your achievements. Visit your profile page anytime.",
    tip: "Other players can find you through search and follow your progress.",
  },
  {
    id: "social",
    title: "Connect With Others",
    body: "Follow friends, climb leaderboards, and chat with the community in real-time.",
    tip: "Mutual follows become friends — unlock social achievements!",
  },
  {
    id: "shop",
    title: "Gear Up in the Shop",
    body: "Spend your earned coins on rods, bait, amulets, boosts, and cosmetics.",
    tip: "Rarer items give bigger bonuses. Save up for legendary gear!",
  },
];

export default function OnboardingFlow() {
  const [visible, setVisible] = useState(false);
  const [step, setStep] = useState(0);
  const [closing, setClosing] = useState(false);

  useEffect(() => {
    const check = async () => {
      try {
        const supabase = getClientSupabase();
        const { data: { session } } = await supabase.auth.getSession();
        if (!session?.user) return;
        const { data } = await supabase.from("onboarding_progress").select("completed_at, skipped").eq("user_id", session.user.id).maybeSingle();
        if (!data) {
          setVisible(true);
          await supabase.from("onboarding_progress").insert({ user_id: session.user.id });
        }
      } catch {
        // Silently skip onboarding check failures
      }
    };
    void check();
  }, []);

  const close = useCallback(async (skipped: boolean) => {
    setClosing(true);
    try {
      const supabase = getClientSupabase();
      const { data: { session } } = await supabase.auth.getSession();
      if (session?.user) {
        await supabase.from("onboarding_progress").update({
          completed_at: new Date().toISOString(),
          skipped,
          steps_completed: STEPS.slice(0, step + 1).map((s) => s.id),
        }).eq("user_id", session.user.id);
      }
    } finally {
      setTimeout(() => setVisible(false), 300);
    }
  }, [step]);

  if (!visible) return null;

  const current = STEPS[step];
  const isLast = step === STEPS.length - 1;

  return (
    <div className={`${styles.overlay} ${closing ? styles.overlayClosing : ""}`}>
      <div className={styles.card}>
        <button className={styles.skipBtn} onClick={() => void close(true)} aria-label="Skip tutorial">
          ✕
        </button>

        <div className={styles.stepIndicator}>
          {STEPS.map((_, i) => (
            <span key={i} className={`${styles.dot} ${i === step ? styles.dotActive : ""} ${i < step ? styles.dotDone : ""}`} />
          ))}
        </div>

        <h2 className={styles.stepTitle}>{current.title}</h2>
        <p className={styles.stepBody}>{current.body}</p>
        <p className={styles.stepTip}>{current.tip}</p>

        <div className={styles.actions}>
          {step > 0 && (
            <button className={styles.btnGhost} onClick={() => setStep(step - 1)}>Back</button>
          )}
          {isLast ? (
            <button className={styles.btnPrimary} onClick={() => void close(false)}>Get Started!</button>
          ) : (
            <button className={styles.btnPrimary} onClick={() => setStep(step + 1)}>Next</button>
          )}
          <button className={styles.skipText} onClick={() => void close(true)}>Skip Tutorial</button>
        </div>
      </div>
    </div>
  );
}
