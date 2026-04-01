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
};

export default function GameShellPage({
  title,
  iframeSrc,
  iframeTitle,
  alternateHref,
  alternateLabel,
}: GameShellPageProps) {
  const [isFrameReady, setIsFrameReady] = useState(false);

  useEffect(() => {
    const revealTimeout = window.setTimeout(() => {
      setIsFrameReady(true);
    }, 4500);

    return () => {
      window.clearTimeout(revealTimeout);
    };
  }, []);

  return (
    <main className={styles.page}>
      <header className={styles.topbar}>
        <div className={styles.titleBlock}>
          <p className={styles.kicker}>Virtual Harvest Runtime</p>
          <p className={styles.title}>{title}</p>
        </div>
        <div className={styles.actions}>
          <Link href="/home" className={styles.btnGhost}>
            Home
          </Link>
          <Link href="/account-center" className={styles.btnGhost}>
            Account Center
          </Link>
          <Link href={alternateHref} className={styles.btnPrimary}>
            {alternateLabel}
          </Link>
        </div>
      </header>

      <div className={`${styles.frameWrap} ${isFrameReady ? styles.frameWrapReady : ""}`}>
        {!isFrameReady ? <div className={styles.loadingMask}>Preparing runtime...</div> : null}
        <iframe
          key={iframeSrc}
          src={iframeSrc}
          title={iframeTitle}
          className={styles.frame}
          loading="eager"
          allow="clipboard-read; clipboard-write"
          onLoad={() => setIsFrameReady(true)}
        />
      </div>
    </main>
  );
}
