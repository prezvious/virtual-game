"use client";

import FullDocumentLink from "@/components/ui/FullDocumentLink";
import InlineLegacyRuntime from "./InlineLegacyRuntime";
import styles from "./game-shell-page.module.css";

type GameShellPageProps = {
  documentPath: string;
  alternateHref: string;
  alternateLabel: string;
  runtimeKey: "fisher" | "farmer";
  title: string;
  variant?: "default" | "fisher";
};

export default function GameShellPage({
  documentPath,
  alternateHref,
  alternateLabel,
  runtimeKey,
  title,
  variant = "default",
}: GameShellPageProps) {
  const isFisherVariant = variant === "fisher";
  const pageClassName = `${styles.page} ${isFisherVariant ? styles.pageFisher : ""}`;
  const topbarClassName = `${styles.topbar} ${isFisherVariant ? styles.topbarFisher : ""}`;
  const frameWrapClassName = `${styles.frameWrap} ${isFisherVariant ? styles.frameWrapFisher : ""}`;
  const alternateActionClassName = isFisherVariant ? styles.btnGhostMuted : styles.btnPrimary;
  const loadingEyebrow = isFisherVariant ? "Virtual Fisher" : "Virtual Harvest Runtime";
  const loadingTitle = isFisherVariant ? "Opening Virtual Fisher\u2026" : "Preparing runtime\u2026";
  const loadingMessage = "Syncing the shell and preparing your session.";

  return (
    <main id="main-content" tabIndex={-1} className={pageClassName}>
      <header className={topbarClassName}>
        <div className={styles.titleBlock}>
          <p className={styles.kicker}>{loadingEyebrow}</p>
          <p className={styles.title}>{title}</p>
        </div>
        <div className={styles.actions}>
          <FullDocumentLink href="/home" className={styles.btnGhost}>
            Home
          </FullDocumentLink>
          <FullDocumentLink href="/account-center" className={styles.btnGhost}>
            Account Center
          </FullDocumentLink>
          <FullDocumentLink href={alternateHref} className={alternateActionClassName}>
            {alternateLabel}
          </FullDocumentLink>
        </div>
      </header>

      <div className={frameWrapClassName}>
        <InlineLegacyRuntime
          documentPath={documentPath}
          loadingEyebrow={loadingEyebrow}
          loadingTitle={loadingTitle}
          loadingMessage={loadingMessage}
          runtimeKey={runtimeKey}
        />
      </div>
    </main>
  );
}
