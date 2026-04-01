"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import styles from "./BanGuard.module.css";
import { BAN_NOTICE_STORAGE_KEY, type BanNotice, type BanStatusResponse } from "@/lib/ban";
import { getClientSupabase } from "@/lib/auth-client";

function readStoredNotice(): BanNotice | null {
  try {
    const raw = window.localStorage.getItem(BAN_NOTICE_STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<BanNotice>;
    if (typeof parsed !== "object" || parsed === null) return null;
    if (typeof parsed.isPermanent !== "boolean") return null;
    const bannedUntil = typeof parsed.bannedUntil === "string" && parsed.bannedUntil.trim()
      ? parsed.bannedUntil
      : null;
    const reason = typeof parsed.reason === "string" && parsed.reason.trim()
      ? parsed.reason.trim()
      : undefined;
    return { bannedUntil, isPermanent: parsed.isPermanent, ...(reason ? { reason } : {}) };
  } catch {
    return null;
  }
}

function formatBanTitle(notice: BanNotice): string {
  if (notice.isPermanent || !notice.bannedUntil) {
    return "Your account has been banned permanently.";
  }

  const date = new Date(notice.bannedUntil);
  if (Number.isNaN(date.getTime())) {
    return `Your account has been banned until ${notice.bannedUntil}.`;
  }

  return `Your account has been banned until ${new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date)}.`;
}

export default function BanGuard() {
  const supabase = useMemo(() => getClientSupabase(), []);
  const [notice, setNotice] = useState<BanNotice | null>(null);
  const handlingBanRef = useRef(false);

  const syncStoredNotice = useCallback(() => {
    setNotice(readStoredNotice());
  }, []);

  const dismissNotice = useCallback(() => {
    window.localStorage.removeItem(BAN_NOTICE_STORAGE_KEY);
    setNotice(null);
  }, []);

  const handleBanned = useCallback(async (status: Extract<BanStatusResponse, { banned: true }>) => {
    if (handlingBanRef.current) return;
    handlingBanRef.current = true;

    const nextNotice: BanNotice = {
      bannedUntil: status.bannedUntil,
      isPermanent: status.isPermanent,
      ...(status.reason ? { reason: status.reason } : {}),
    };

    window.localStorage.setItem(BAN_NOTICE_STORAGE_KEY, JSON.stringify(nextNotice));
    setNotice(nextNotice);

    const signOutTasks: Promise<unknown>[] = [supabase.auth.signOut()];
    const bridge = (window as unknown as Record<string, unknown>).PlatformAccountBridge;
    if (
      bridge
      && typeof bridge === "object"
      && "signOut" in bridge
      && typeof bridge.signOut === "function"
    ) {
      signOutTasks.push(bridge.signOut());
    }

    await Promise.allSettled(signOutTasks);
    window.location.replace("/home");
  }, [supabase]);

  const checkBanStatus = useCallback(async () => {
    if (typeof document !== "undefined" && document.visibilityState === "hidden") {
      return;
    }

    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.access_token) {
      if (!window.localStorage.getItem(BAN_NOTICE_STORAGE_KEY)) {
        handlingBanRef.current = false;
      }
      return;
    }

    try {
      const response = await fetch("/api/auth/ban-status", {
        headers: { Authorization: `Bearer ${session.access_token}` },
        cache: "no-store",
      });
      const json = await response.json() as BanStatusResponse | { ok: false; error?: string };
      if (!response.ok || !json.ok || !json.banned) return;
      await handleBanned(json);
    } catch {
      // Ignore transient check failures to avoid forcing sign-outs on network issues.
    }
  }, [handleBanned, supabase]);

  useEffect(() => {
    const syncTimerId = window.setTimeout(syncStoredNotice, 0);
    const checkTimerId = window.setTimeout(() => {
      void checkBanStatus();
    }, 0);

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!session) {
        if (!window.localStorage.getItem(BAN_NOTICE_STORAGE_KEY)) {
          handlingBanRef.current = false;
        }
        return;
      }
      void checkBanStatus();
    });

    const handleFocus = () => {
      void checkBanStatus();
    };
    const handleVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        void checkBanStatus();
      }
    };
    const handleStorage = (event: StorageEvent) => {
      if (event.key === BAN_NOTICE_STORAGE_KEY) {
        syncStoredNotice();
      }
    };

    window.addEventListener("focus", handleFocus);
    document.addEventListener("visibilitychange", handleVisibilityChange);
    window.addEventListener("storage", handleStorage);

    const intervalId = window.setInterval(() => {
      if (document.visibilityState === "visible") {
        void checkBanStatus();
      }
    }, 30_000);

    return () => {
      window.clearTimeout(syncTimerId);
      window.clearTimeout(checkTimerId);
      subscription.unsubscribe();
      window.removeEventListener("focus", handleFocus);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      window.removeEventListener("storage", handleStorage);
      window.clearInterval(intervalId);
    };
  }, [checkBanStatus, supabase, syncStoredNotice]);

  if (!notice) return null;

  return (
    <div className={styles.overlay}>
      <section
        className={styles.dialog}
        role="dialog"
        aria-modal="true"
        aria-labelledby="ban-notice-title"
      >
        <button
          type="button"
          className={styles.closeIcon}
          onClick={dismissNotice}
          aria-label="Close ban notice"
        >
          X
        </button>
        <p className={styles.eyebrow}>Access disabled</p>
        <h2 id="ban-notice-title" className={styles.title}>{formatBanTitle(notice)}</h2>
        <p className={styles.body}>
          Your website session has been signed out automatically. If you think this is a mistake, contact an administrator.
        </p>
        {notice.reason ? (
          <p className={styles.reason}>
            <strong>Reason:</strong> {notice.reason}
          </p>
        ) : null}
        <div className={styles.footer}>
          <button type="button" className={styles.closeBtn} onClick={dismissNotice}>
            Close
          </button>
        </div>
      </section>
    </div>
  );
}
