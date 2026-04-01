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
    body: "Set your shared username, add a profile note, and review your cross-game playtime from one account page.",
    tip: "Your username is the single public handle for both Virtual Fisher and Virtual Farmer.",
  },
  {
    id: "social",
    title: "Connect With Others",
    body: "Follow friends, climb leaderboards, and keep one public profile across the platform.",
    tip: "Mutual follows become friends - unlock social achievements.",
  },
];

export default function OnboardingFlow() {
  const [visible, setVisible] = useState(false);
  const [step, setStep] = useState(0);
  const [closing, setClosing] = useState(false);

  useEffect(() => {
    let userId = "";
    const check = async () => {
      try {
        const supabase = getClientSupabase();
        const { data: { session } } = await supabase.auth.getSession();
        if (!session?.user) return;
        userId = session.user.id;
        const DISMISSED_KEY = `onboarding_dismissed:${userId}`;
        if (localStorage.getItem(DISMISSED_KEY) === "true") return;
        const { data } = await supabase
          .from("onboarding_progress")
          .select("completed_at, skipped")
          .eq("user_id", session.user.id)
          .maybeSingle();
        if (data?.completed_at || data?.skipped) {
          localStorage.setItem(DISMISSED_KEY, "true");
          return;
        }
        setVisible(true);
        if (!data) {
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
        localStorage.setItem(`onboarding_dismissed:${session.user.id}`, "true");
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
          x
        </button>

        <div className={styles.stepIndicator}>
          {STEPS.map((_, index) => (
            <span
              key={index}
              className={`${styles.dot} ${index === step ? styles.dotActive : ""} ${index < step ? styles.dotDone : ""}`}
            />
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
