"use client";

import { useCallback, useEffect, useRef, useState } from "react";
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

const ONBOARDING_DISMISSED_KEY = (userId: string) => `onboarding_dismissed:${userId}`;

export default function OnboardingFlow() {
  const [visible, setVisible] = useState(false);
  const [step, setStep] = useState(0);
  const [closing, setClosing] = useState(false);
  const userIdRef = useRef<string | null>(null);

  useEffect(() => {
    let mounted = true;

    const check = async () => {
      try {
        const supabase = getClientSupabase();
        const { data: { session }, error: sessionError } = await supabase.auth.getSession();
        if (sessionError) {
          console.warn("Onboarding session check failed:", sessionError.message);
          return;
        }
        if (!session?.user) return;
        const userId = session.user.id;
        userIdRef.current = userId;

        const dismissedKey = ONBOARDING_DISMISSED_KEY(userId);
        try {
          if (localStorage.getItem(dismissedKey) === "true") return;
        } catch {
          // localStorage unavailable - proceed with onboarding
        }

        const { data, error } = await supabase
          .from("onboarding_progress")
          .select("completed_at, skipped, steps_completed")
          .eq("user_id", userId)
          .maybeSingle();

        if (!mounted) return;

        if (error) {
          console.warn("Onboarding progress check failed:", error.message);
          return;
        }

        if (data?.completed_at || data?.skipped) {
          try {
            localStorage.setItem(dismissedKey, "true");
          } catch {
            // localStorage unavailable
          }

          if (data?.skipped && !data?.completed_at) {
            const { error: backfillError } = await supabase.from("onboarding_progress").upsert({
              user_id: userId,
              completed_at: new Date().toISOString(),
              skipped: true,
              steps_completed: Array.isArray(data.steps_completed) ? data.steps_completed : [],
            }, { onConflict: "user_id" });

            if (backfillError) {
              console.warn("Onboarding skipped-state backfill failed:", backfillError.message);
            }
          }

          return;
        }

        setStep(0);
        setClosing(false);
        setVisible(true);
      } catch (error) {
        console.warn("Onboarding visibility check failed:", error);
      }
    };

    void check();

    return () => {
      mounted = false;
    };
  }, []);

  const close = useCallback(async (skipped: boolean) => {
    if (closing) return;

    setClosing(true);
    setVisible(false);

    const userId = userIdRef.current;
    if (!userId) return;

    try {
      localStorage.setItem(ONBOARDING_DISMISSED_KEY(userId), "true");
    } catch {
      // localStorage unavailable
    }

    try {
      const supabase = getClientSupabase();
      const { error } = await supabase.from("onboarding_progress").upsert({
        user_id: userId,
        completed_at: new Date().toISOString(),
        skipped,
        steps_completed: STEPS.slice(0, step + 1).map((s) => s.id),
      }, { onConflict: "user_id" });

      if (error) {
        console.warn("Onboarding dismissal persistence failed:", error.message);
      }
    } catch (error) {
      console.warn("Onboarding dismissal failed:", error);
    }
  }, [closing, step]);

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
