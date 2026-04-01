"use client";

import GameShellPage from "@/components/game-shell/GameShellPage";

export default function LegacyGameClient() {
  return (
    <GameShellPage
      title="Virtual Fisher"
      iframeSrc="/legacy/index.html"
      iframeTitle="Virtual Fisher"
      alternateHref="/farm"
      alternateLabel="Open Virtual Farmer"
      variant="fisher"
    />
  );
}
