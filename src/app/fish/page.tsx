import type { Metadata } from "next";
import GameShellPage from "@/components/game-shell/GameShellPage";

export const metadata: Metadata = {
  title: "Virtual Fisher",
  description: "Launch Virtual Fisher inside the Virtual Harvest shell.",
};

export default function FishPage() {
  return (
    <GameShellPage
      title="Virtual Fisher"
      iframeSrc="/legacy/index.html"
      iframeTitle="Virtual Fisher"
      alternateHref="/farm"
      alternateLabel="Open Virtual Farmer"
    />
  );
}
