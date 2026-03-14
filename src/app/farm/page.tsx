import type { Metadata } from "next";
import LegacyIframePage from "@/components/game-shell/LegacyIframePage";

export const metadata: Metadata = {
  title: "Play | Virtual Farmer",
  description: "Launch Virtual Farmer from the unified platform.",
};

export default function FarmPage() {
  return (
    <LegacyIframePage
      title="Virtual Farmer"
      iframeSrc="/farmer-legacy/game.html"
      iframeTitle="Virtual Farmer"
      alternateHref="/fish"
      alternateLabel="Open Fisher"
    />
  );
}
