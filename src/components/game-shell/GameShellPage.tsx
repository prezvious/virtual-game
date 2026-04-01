"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import styles from "./game-shell-page.module.css";

type GameShellPageProps = {
  title: string;
  iframeSrc: string;
  iframeTitle: string;
  alternateHref: string;
  alternateLabel: string;
  variant?: "default" | "fisher";
};

export default function GameShellPage({
  title,
  iframeSrc,
  iframeTitle,
  alternateHref,
  alternateLabel,
  variant = "default",
}: GameShellPageProps) {
  const [isFrameReady, setIsFrameReady] = useState(false);
  const [isSlowLoad, setIsSlowLoad] = useState(false);

  useEffect(() => {
    if (isFrameReady) {
      return;
    }

    const slowLoadTimeout = window.setTimeout(() => {
      setIsSlowLoad(true);
    }, 1200);

    return () => {
      window.clearTimeout(slowLoadTimeout);
    };
  }, [isFrameReady]);

  const isFisherVariant = variant === "fisher";
  const pageClassName = `${styles.page} ${isFisherVariant ? styles.pageFisher : ""}`;
  const topbarClassName = `${styles.topbar} ${isFisherVariant ? styles.topbarFisher : ""}`;
  const frameWrapClassName = `${styles.frameWrap} ${isFrameReady ? styles.frameWrapReady : ""} ${
    isFisherVariant ? styles.frameWrapFisher : ""
  }`;
  const alternateActionClassName = isFisherVariant ? styles.btnGhostMuted : styles.btnPrimary;
  const loadingEyebrow = isFisherVariant ? "Virtual Fisher" : "Virtual Harvest Runtime";
  const loadingTitle = isFisherVariant ? "Opening Virtual Fisher\u2026" : "Preparing runtime\u2026";
  const loadingMessage = isSlowLoad
    ? "Still loading the game. This can take a moment on slower connections."
    : "Syncing the shell and preparing your session.";

  return (
    <main id="main-content" tabIndex={-1} className={pageClassName}>
      <header className={topbarClassName}>
        <div className={styles.titleBlock}>
          <p className={styles.kicker}>{loadingEyebrow}</p>
          <p className={styles.title}>{title}</p>
        </div>
        <div className={styles.actions}>
          <Link href="/home" className={styles.btnGhost}>
            Home
          </Link>
          <Link href="/account-center" className={styles.btnGhost}>
            Account Center
          </Link>
          <Link href={alternateHref} className={alternateActionClassName}>
            {alternateLabel}
          </Link>
        </div>
      </header>

      <div className={frameWrapClassName}>
        {!isFrameReady ? (
          <div className={styles.loadingMask} role="status" aria-live="polite">
            <div className={styles.loadingPanel}>
              <p className={styles.loadingKicker}>{loadingEyebrow}</p>
              <p className={styles.loadingTitle}>{loadingTitle}</p>
              <p className={styles.loadingText}>{loadingMessage}</p>
            </div>
          </div>
        ) : null}
        <iframe
          key={iframeSrc}
          src={iframeSrc}
          title={iframeTitle}
          className={styles.frame}
          loading="eager"
          sandbox="allow-scripts allow-same-origin allow-forms allow-modals"
          allow="clipboard-read; clipboard-write"
          onLoad={() => setIsFrameReady(true)}
        />
      </div>
    </main>
  );
}
