import type { Metadata } from "next";
import { Fraunces, IBM_Plex_Mono } from "next/font/google";
import ChatClient from "@/components/chat/ChatClient";
import styles from "./chat.module.css";

const fraunces = Fraunces({ subsets: ["latin"], weight: ["500", "700", "900"], variable: "--font-display", preload: false });
const plexMono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["500", "700"], variable: "--font-mono", preload: false });

export const metadata: Metadata = {
  title: "Chat | Virtual Harvest",
  description: "Real-time chat with the Virtual Harvest community.",
};

export default function ChatPage() {
  return (
    <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
      <ChatClient />
    </main>
  );
}
