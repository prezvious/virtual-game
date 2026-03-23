import type { Metadata } from "next";
import LegacyIframePage from "@/components/game-shell/LegacyIframePage";

export const metadata: Metadata = {
  title: "Play | Fish It!",
  description: "Play Fish It! Enhanced Edition in the Next.js client route.",
};

export default function FishPage() {
  return (
    <LegacyIframePage
      title="Virtual Fisher"
      iframeSrc="/legacy/index.html"
      iframeTitle="Virtual Fisher"
      alternateHref="/farm"
      alternateLabel="Open Farmer"
    />
  );
}
