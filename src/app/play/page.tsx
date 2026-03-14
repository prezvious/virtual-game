import type { Metadata } from "next";
import { redirect } from "next/navigation";

export const metadata: Metadata = {
  title: "Redirecting | Virtual Fisher",
  description: "Legacy route redirect to /fish.",
};

export default function PlayPage() {
  redirect("/fish");
}
