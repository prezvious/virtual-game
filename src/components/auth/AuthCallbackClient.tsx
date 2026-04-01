"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { getClientSupabase } from "@/lib/auth-client";

type ExchangeResponse = {
  ok: boolean;
  error?: string;
  session?: {
    access_token: string;
    refresh_token: string;
  };
};

async function exchangeViaServer(body: Record<string, string>): Promise<ExchangeResponse> {
  const response = await fetch("/api/auth/exchange", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    cache: "no-store",
  });

  const data = (await response.json()) as ExchangeResponse;
  if (!response.ok) {
    return { ok: false, error: data?.error || "Auth exchange failed." };
  }
  return data;
}

export default function AuthCallbackClient() {
  const router = useRouter();
  const [status, setStatus] = useState("Checking verification token...");
  const [ready, setReady] = useState(false);
  const [success, setSuccess] = useState(false);
  const supabase = useMemo(() => getClientSupabase(), []);

  useEffect(() => {
    let mounted = true;

    const run = async () => {
      try {
        const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""));
        const query = new URLSearchParams(window.location.search);

        let applied = false;
        const accessToken = hash.get("access_token");
        const refreshToken = hash.get("refresh_token");

        if (accessToken && refreshToken) {
          setStatus("Applying secure session...");
          const { error } = await supabase.auth.setSession({
            access_token: accessToken,
            refresh_token: refreshToken,
          });
          applied = !error;
        }

        if (!applied) {
          const code = query.get("code");
          if (code) {
            setStatus("Exchanging authorization code...");
            const result = await exchangeViaServer({ code });
            if (result.ok && result.session?.access_token && result.session?.refresh_token) {
              const { error } = await supabase.auth.setSession({
                access_token: result.session.access_token,
                refresh_token: result.session.refresh_token,
              });
              applied = !error;
            }
          }
        }

        if (!applied) {
          const tokenHash = query.get("token_hash");
          const type = query.get("type");
          if (tokenHash && type) {
            setStatus("Verifying secure email token...");
            const result = await exchangeViaServer({ token_hash: tokenHash, type });
            if (result.ok && result.session?.access_token && result.session?.refresh_token) {
              const { error } = await supabase.auth.setSession({
                access_token: result.session.access_token,
                refresh_token: result.session.refresh_token,
              });
              applied = !error;
            }
          }
        }

        setStatus("Finalizing cloud session...");
        await supabase.auth.getSession();

        if (!mounted) return;
        setSuccess(applied);
        setReady(true);
        setStatus(
          applied
            ? "Session verified. Redirecting to the account center..."
            : "Token processed. Continue to the account center and log in if required.",
        );

        if (applied) {
          window.setTimeout(() => {
            router.replace("/account-center");
          }, 1200);
        }
      } catch (error) {
        if (!mounted) return;
        const message = error instanceof Error ? error.message : "Unexpected callback failure.";
        setReady(true);
        setSuccess(false);
        setStatus(`Verification issue: ${message}`);
      }
    };

    void run();
    return () => {
      mounted = false;
    };
  }, [router, supabase]);

  return (
    <main className="callback-wrap">
      <section className={`app-section callback-card${success ? " is-success" : ""}`}>
        <h1 className="app-title">{success ? "Registration complete." : "Verifying secure access..."}</h1>
        <p className="app-subtitle">
          {success
            ? "Your account link is active and cloud sync is ready."
            : "Please wait while your callback token is processed."}
        </p>
        <p className="callback-status">{status}</p>
        {ready ? (
          <div className="app-nav">
            <Link className="app-btn" href="/account-center">
              Open Account Center
            </Link>
            <Link className="app-btn secondary" href="/fish">
              Launch Virtual Fisher
            </Link>
          </div>
        ) : null}
      </section>
    </main>
  );
}
