"use client";

import { useEffect } from "react";

export default function ErrorPage({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error("[ErrorBoundary]", error);
  }, [error]);

  return (
    <main style={{
      minHeight: "100dvh",
      display: "grid",
      placeItems: "center",
      padding: "2rem",
      background: "linear-gradient(135deg, #fef9f0, #edf6fb)",
      color: "#172034",
      textAlign: "center",
    }}>
      <div>
        <p style={{ fontSize: "4rem", fontWeight: 900, margin: 0, lineHeight: 1, opacity: 0.15 }}>Error</p>
        <h1 style={{ margin: "0.5rem 0", fontSize: "1.6rem", letterSpacing: "-0.02em" }}>Something went wrong</h1>
        <p style={{ margin: "0.5rem 0 1.5rem", color: "#3f5072", maxWidth: "44ch" }}>
          An unexpected error occurred. You can try again or head back to the homepage.
        </p>
        <div style={{ display: "flex", gap: "0.6rem", justifyContent: "center", flexWrap: "wrap" }}>
          <button onClick={reset} style={{
            display: "inline-flex", alignItems: "center", justifyContent: "center",
            padding: "0.6rem 1.1rem", borderRadius: "8px", fontWeight: 800, fontSize: "0.88rem",
            background: "linear-gradient(118deg, #f6c07c, #eba863)", border: "1px solid #d2924e",
            color: "#1b2c49", cursor: "pointer",
          }}>
            Try Again
          </button>
          <a href="/home" style={{
            display: "inline-flex", alignItems: "center", justifyContent: "center",
            padding: "0.6rem 1.1rem", borderRadius: "8px", fontWeight: 800, fontSize: "0.88rem",
            background: "transparent", border: "1px solid rgba(30,46,82,0.18)", color: "#223757",
          }}>
            Platform Home
          </a>
        </div>
      </div>
    </main>
  );
}
