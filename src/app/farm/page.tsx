import type { Metadata } from "next";
import GameShellPage from "@/components/game-shell/GameShellPage";

export const metadata: Metadata = {
  title: "Virtual Farmer",
  description: "Launch Virtual Farmer inside the Virtual Harvest shell.",
};

export default function FarmPage() {
  return (
    <GameShellPage
      title="Virtual Farmer"
      iframeSrc="/farmer-legacy/game.html"
      iframeTitle="Virtual Farmer"
      alternateHref="/fish"
      alternateLabel="Open Virtual Fisher"
    />
  );
}
