import type { Metadata } from "next";
import HomePage from "@/components/home/HomePage";

export const metadata: Metadata = {
  title: "Home",
  description: "The main home page for Virtual Harvest.",
};

export default function HomeRoutePage() {
  return <HomePage />;
}
