"use client";

import { useEffect } from "react";
import Link from "next/link";

export default function ErrorPage({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error("[ErrorBoundary]", error);
  }, [error]);

  return (
    <main className="feedbackPage">
      <div className="feedbackCard">
        <p className="feedbackEyebrow">Error</p>
        <h1 className="feedbackTitle">Something went wrong</h1>
        <p className="feedbackText">
          An unexpected error occurred. You can try again or head back to the homepage.
        </p>
        <div className="feedbackActions">
          <button onClick={reset} className="feedbackPrimary">
            Try Again
          </button>
          <Link href="/home" className="feedbackSecondary">
            Return Home
          </Link>
        </div>
      </div>
    </main>
  );
}
