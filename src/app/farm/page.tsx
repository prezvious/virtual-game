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
      documentPath="/farmer-legacy/game.html"
      alternateHref="/fish"
      alternateLabel="Open Virtual Fisher"
      runtimeKey="farmer"
    />
  );
}
