import type { Metadata } from "next";
import { Analytics } from "@vercel/analytics/next";
import Script from "next/script";
import "./globals.css";

export const metadata: Metadata = {
  title: "Virtual Harvest Platform",
  description: "Unified platform for Virtual Fisher and Virtual Farmer with one account.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <Script src="/runtime-supabase-config.js" strategy="beforeInteractive" />
        {children}
        <Analytics />
      </body>
    </html>
  );
}
