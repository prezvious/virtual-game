"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import styles from "./legacy-iframe-page.module.css";

type LegacyIframePageProps = {
  title: string;
  iframeSrc: string;
  iframeTitle: string;
  alternateHref: string;
  alternateLabel: string;
};

export default function LegacyIframePage({
  title,
  iframeSrc,
  iframeTitle,
  alternateHref,
  alternateLabel,
}: LegacyIframePageProps) {
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
        <p>{title}</p>
        <div className={styles.actions}>
          <Link href="/home" className={styles.btnGhost}>
            Platform Home
          </Link>
          <Link href={alternateHref} className={styles.btnGhost}>
            {alternateLabel}
          </Link>
        </div>
      </header>

      <div className={`${styles.frameWrap} ${isFrameReady ? styles.frameWrapReady : ""}`}>
        {!isFrameReady ? <div className={styles.loadingMask}>Loading runtime...</div> : null}
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
