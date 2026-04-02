"use client";

import GameShellPage from "@/components/game-shell/GameShellPage";

export default function LegacyGameClient() {
  return (
    <GameShellPage
      title="Virtual Fisher"
      documentPath="/legacy/index.html"
      alternateHref="/farm"
      alternateLabel="Open Virtual Farmer"
      runtimeKey="fisher"
      variant="fisher"
    />
  );
}
