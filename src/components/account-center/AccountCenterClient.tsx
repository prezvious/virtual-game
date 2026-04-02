"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import FullDocumentLink from "@/components/ui/FullDocumentLink";
import styles from "./account-center.module.css";

type BridgeProjectState = {
  project: "fisher" | "farmer";
  label: string;
  ok: boolean;
  user: {
    id: string;
    email?: string;
  } | null;
  session: unknown | null;
  error: string;
};

type BridgeSessionState = {
  fisher: BridgeProjectState;
  farmer: BridgeProjectState;
  primaryUser: {
    id: string;
    email?: string;
  } | null;
  isSignedIn: boolean;
  isFullyLinked: boolean;
};

type BridgeAuthResult = {
  ok: boolean;
  state: BridgeSessionState;
  error?: string;
  warnings?: string[];
  requiresVerification?: boolean;
};

type AccountBridgeApi = {
  getSessionState: () => Promise<BridgeSessionState>;
  signIn: (payload: { email: string; password: string }) => Promise<BridgeAuthResult>;
  signUp: (payload: { email: string; password: string }) => Promise<BridgeAuthResult>;
  signOut: () => Promise<BridgeSessionState>;
};

declare global {
  interface Window {
    PlatformAccountBridge?: AccountBridgeApi;
  }
}

const BRIDGE_SRC = "/platform-account-bridge.js";
const RUNTIME_CONFIG_SRC = "/runtime-supabase-config.js";
const SUPABASE_VENDOR_SRC = "/vendor/supabase/supabase.js";

type StatusTone = "neutral" | "success" | "error";

type SupabaseGlobal = {
  createClient?: unknown;
};

function hasSupabaseFactory() {
  const globalSupabase = (window as Window & { supabase?: SupabaseGlobal }).supabase;
  return typeof globalSupabase?.createClient === "function";
}

function ensureSupabaseScript(): Promise<void> {
  if (hasSupabaseFactory()) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    const currentScript = document.querySelector(`script[src="${SUPABASE_VENDOR_SRC}"]`) as
      | HTMLScriptElement
      | null;

    if (currentScript) {
      if (hasSupabaseFactory()) {
        resolve();
        return;
      }

      if (currentScript.dataset.loadFailed === "true") {
        currentScript.remove();
        loadSupabaseScript(resolve, reject);
        return;
      }

      currentScript.addEventListener("load", () => {
        if (hasSupabaseFactory()) {
          resolve();
          return;
        }
        reject(new Error("Supabase client library is not available."));
      });
      currentScript.addEventListener("error", () => {
        currentScript.dataset.loadFailed = "true";
        reject(new Error("Supabase client script failed to load."));
      });
      // Fix M-7: Check if script already loaded before adding listeners
      if ((currentScript as HTMLScriptElement & { readyState?: string }).readyState === "complete") {
        if (hasSupabaseFactory()) {
          resolve();
        } else {
          reject(new Error("Supabase client library is not available."));
        }
      }
      return;
    }

    loadSupabaseScript(resolve, reject);
  });
}

function loadSupabaseScript(resolve: () => void, reject: (reason: Error) => void) {
  const script = document.createElement("script");
  script.src = SUPABASE_VENDOR_SRC;
  script.async = true;
  script.onload = () => {
    if (hasSupabaseFactory()) {
      resolve();
      return;
    }
    reject(new Error("Supabase client library is not available."));
  };
  script.onerror = () => {
    script.dataset.loadFailed = "true";
    reject(new Error("Supabase client script failed to load."));
  };
  document.head.appendChild(script);
}

function hasRuntimeConfig() {
  return typeof (window as Window & { __PLATFORM_SUPABASE_CONFIG__?: unknown }).__PLATFORM_SUPABASE_CONFIG__ === "object";
}

function ensureRuntimeConfigScript(): Promise<void> {
  if (hasRuntimeConfig()) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    const currentScript = document.querySelector(`script[src="${RUNTIME_CONFIG_SRC}"]`) as
      | HTMLScriptElement
      | null;

    if (currentScript) {
      if (currentScript.dataset.loadFailed === "true") {
        currentScript.remove();
        loadRuntimeConfigScript(resolve, reject);
        return;
      }

      currentScript.addEventListener("load", () => {
        if (hasRuntimeConfig()) {
          resolve();
          return;
        }
        reject(new Error("Runtime auth config loaded without platform settings."));
      });
      currentScript.addEventListener("error", () => {
        currentScript.dataset.loadFailed = "true";
        reject(new Error("Runtime auth config failed to load."));
      });
      // Fix M-7: Check if script already loaded
      if ((currentScript as HTMLScriptElement & { readyState?: string }).readyState === "complete") {
        if (hasRuntimeConfig()) {
          resolve();
        } else {
          reject(new Error("Runtime auth config loaded without platform settings."));
        }
      }
      return;
    }

    loadRuntimeConfigScript(resolve, reject);
  });
}

function loadRuntimeConfigScript(resolve: () => void, reject: (reason: Error) => void) {
  const script = document.createElement("script");
  script.src = RUNTIME_CONFIG_SRC;
  script.async = true;
  script.onload = () => {
    if (hasRuntimeConfig()) {
      resolve();
      return;
    }
    reject(new Error("Runtime auth config loaded without platform settings."));
  };
  script.onerror = () => {
    script.dataset.loadFailed = "true";
    reject(new Error("Runtime auth config failed to load."));
  };
  document.head.appendChild(script);
}

async function ensureBridgeScript(): Promise<AccountBridgeApi> {
  await ensureRuntimeConfigScript();
  await ensureSupabaseScript();

  const existing = window.PlatformAccountBridge;
  if (existing) {
    return Promise.resolve(existing);
  }

  return new Promise((resolve, reject) => {
    const currentScript = document.querySelector(`script[src="${BRIDGE_SRC}"]`);
    if (currentScript) {
      if ((currentScript as HTMLScriptElement).dataset.loadFailed === "true") {
        currentScript.remove();
        loadBridgeScript(resolve, reject);
        return;
      }

      currentScript.addEventListener("load", () => {
        if (window.PlatformAccountBridge) {
          resolve(window.PlatformAccountBridge);
          return;
        }
        reject(new Error("Bridge loaded without API."));
      });
      currentScript.addEventListener("error", () => {
        (currentScript as HTMLScriptElement).dataset.loadFailed = "true";
        reject(new Error("Bridge script failed to load."));
      });
      // Fix M-7: Check if script already loaded
      if ((currentScript as HTMLScriptElement & { readyState?: string }).readyState === "complete") {
        if (window.PlatformAccountBridge) {
          resolve(window.PlatformAccountBridge);
        } else {
          reject(new Error("Bridge loaded without API."));
        }
      }
      return;
    }

    loadBridgeScript(resolve, reject);
  });
}

function loadBridgeScript(resolve: (api: AccountBridgeApi) => void, reject: (reason: Error) => void) {
  const script = document.createElement("script");
  script.src = BRIDGE_SRC;
  script.async = true;
  script.onload = () => {
    if (window.PlatformAccountBridge) {
      resolve(window.PlatformAccountBridge);
      return;
    }
    reject(new Error("Bridge loaded without API."));
  };
  script.onerror = () => {
    script.dataset.loadFailed = "true";
    reject(new Error("Bridge script failed to load."));
  };
  document.head.appendChild(script);
}

function statusText(state: BridgeSessionState | null) {
  if (!state || !state.isSignedIn) {
    return "Signed out. Use the account center to connect your platform identity.";
  }

  if (state.isFullyLinked) {
    return "Account linked across Virtual Fisher and Virtual Farmer.";
  }

  return "Signed in with a partial link. Finish setup to connect both game accounts.";
}

export default function AccountCenterClient() {
  const [bridge, setBridge] = useState<AccountBridgeApi | null>(null);
  const [sessionState, setSessionState] = useState<BridgeSessionState | null>(null);
  const [isBusy, setIsBusy] = useState(false);
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [statusMessage, setStatusMessage] = useState("Loading shared account status...");
  const [statusTone, setStatusTone] = useState<StatusTone>("neutral");

  const refreshState = useCallback(
    async (targetBridge?: AccountBridgeApi) => {
      const activeBridge = targetBridge || bridge;
      if (!activeBridge) return;

      const nextState = await activeBridge.getSessionState();
      setSessionState(nextState);
      setStatusMessage(statusText(nextState));
      setStatusTone(nextState.isSignedIn ? "success" : "neutral");
    },
    [bridge],
  );

  useEffect(() => {
    let mounted = true;

    const boot = async () => {
      try {
        const loadedBridge = await ensureBridgeScript();
        if (!mounted) return;

        setBridge(loadedBridge);
        await refreshState(loadedBridge);
      } catch (error) {
        if (!mounted) return;
        setStatusTone("error");
        setStatusMessage(error instanceof Error ? error.message : "Bridge initialization failed.");
      }
    };

    void boot();
    return () => {
      mounted = false;
    };
  }, [refreshState]);

  const accountLabel = useMemo(() => {
    if (!sessionState?.primaryUser?.email) return "No active account";
    return sessionState.primaryUser.email;
  }, [sessionState]);

  const onSubmit = useCallback(
    async (event: FormEvent<HTMLFormElement>) => {
      event.preventDefault();
      if (!bridge) return;

      setIsBusy(true);
      setStatusTone("neutral");
      setStatusMessage(mode === "signup" ? "Creating account..." : "Signing in...");

      try {
        const payload = { email, password };
        const result = mode === "signup" ? await bridge.signUp(payload) : await bridge.signIn(payload);

        if (!result.ok) {
          setStatusTone("error");
          setStatusMessage(result.error || "Account action failed.");
          return;
        }

        setSessionState(result.state);
        if (result.warnings && result.warnings.length > 0) {
          setStatusTone("neutral");
          setStatusMessage(result.warnings.join(" "));
        } else if (result.requiresVerification) {
          setStatusTone("neutral");
          setStatusMessage("Account created. Verify your email to complete full linking.");
        } else {
          setStatusTone("success");
          setStatusMessage(statusText(result.state));
        }

        if (mode === "signup") {
          setPassword("");
        }
      } catch (error) {
        setStatusTone("error");
        setStatusMessage(error instanceof Error ? error.message : "Account action failed.");
      } finally {
        setIsBusy(false);
      }
    },
    [bridge, email, mode, password],
  );

  const onSignOut = useCallback(async () => {
    if (!bridge) return;
    setIsBusy(true);
    setStatusTone("neutral");
    setStatusMessage("Signing out from all linked games...");

    try {
      const nextState = await bridge.signOut();
      setSessionState(nextState);
      setStatusTone("success");
      setStatusMessage("Signed out from Virtual Fisher and Virtual Farmer.");
    } catch (error) {
      setStatusTone("error");
      setStatusMessage(error instanceof Error ? error.message : "Sign out failed.");
    } finally {
      setIsBusy(false);
    }
  }, [bridge]);

  return (
    <div className={styles.shell}>
      <section className={styles.hero}>
        <div>
          <p className={styles.kicker}>Account Center</p>
          <h1>Manage the shared account layer behind both game worlds.</h1>
          <p>
            Sign in once, check linking status, and move into Virtual Fisher or Virtual Farmer without
            leaving the same platform shell.
          </p>
        </div>
        <div className={styles.heroActions}>
          <Link href="/home" className={styles.btnGhost}>
            Return Home
          </Link>
          <button
            type="button"
            className={styles.btnGhost}
            onClick={() => void refreshState()}
            disabled={!bridge || isBusy}
          >
            Refresh Status
          </button>
        </div>
      </section>

      <div className={styles.grid}>
        <section className={styles.accountSection}>
          <div className={styles.accountHead}>
            <p className={styles.sectionLabel}>Account Status</p>
            <p className={styles.accountEmail}>{accountLabel}</p>
          </div>

          <div className={styles.modeSwitch}>
            <button
              type="button"
              className={`${styles.modeBtn} ${mode === "login" ? styles.modeBtnActive : ""}`}
              onClick={() => setMode("login")}
              disabled={isBusy}
            >
              Log In
            </button>
            <button
              type="button"
              className={`${styles.modeBtn} ${mode === "signup" ? styles.modeBtnActive : ""}`}
              onClick={() => setMode("signup")}
              disabled={isBusy}
            >
              Create Account
            </button>
          </div>

          <form className={styles.form} onSubmit={onSubmit}>
            <label>
              <span>Email</span>
              <input
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                autoComplete="email"
                required
                disabled={isBusy}
              />
            </label>

            <label>
              <span>Password</span>
              <input
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                minLength={8}
                autoComplete={mode === "signup" ? "new-password" : "current-password"}
                required
                disabled={isBusy}
              />
            </label>

            <button type="submit" className={styles.btnPrimary} disabled={!bridge || isBusy}>
              {isBusy ? "Working..." : mode === "signup" ? "Create Account" : "Log In"}
            </button>
          </form>

          <div className={styles.statusRow} data-tone={statusTone}>
            <p>{statusMessage}</p>
            {sessionState?.isSignedIn ? (
              <button type="button" onClick={() => void onSignOut()} className={styles.btnDanger} disabled={isBusy}>
                Sign Out All
              </button>
            ) : null}
          </div>

          <div className={styles.linkStateGrid}>
            <div className={styles.linkState}>
              <h3>Virtual Fisher</h3>
              <p>{sessionState?.fisher?.user ? "Linked" : "Not linked"}</p>
            </div>
            <div className={styles.linkState}>
              <h3>Virtual Farmer</h3>
              <p>{sessionState?.farmer?.user ? "Linked" : "Not linked"}</p>
            </div>
          </div>
        </section>

        <section className={styles.gameColumns}>
          <article className={styles.gameSection}>
            <p className={styles.sectionLabel}>Game Launch</p>
            <h2>Virtual Fisher</h2>
            <p>Jump straight into the fishing runtime after your account state is ready.</p>
            <div className={styles.sectionActions}>
              <FullDocumentLink href="/fish" className={styles.btnPrimary}>
                Launch Fisher
              </FullDocumentLink>
            </div>
          </article>

          <article className={styles.gameSection}>
            <p className={styles.sectionLabel}>Game Launch</p>
            <h2>Virtual Farmer</h2>
            <p>Keep farming progression connected to the same platform identity and profile layer.</p>
            <div className={styles.sectionActions}>
              <FullDocumentLink href="/farm" className={styles.btnPrimary}>
                Launch Farmer
              </FullDocumentLink>
            </div>
          </article>
        </section>

        <section className={styles.accountSection}>
          <div className={styles.accountHead}>
            <p className={styles.sectionLabel}>Account Tools</p>
          </div>
          <div className={styles.sectionActions}>
            <Link href="/profile" className={styles.btnGhost}>Profiles</Link>
            <Link href="/friends" className={styles.btnGhost}>Friends</Link>
            <Link href="/achievements" className={styles.btnGhost}>Achievements</Link>
          </div>
        </section>
      </div>
    </div>
  );
}
