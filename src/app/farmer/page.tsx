import type { Metadata } from "next";
import { redirect } from "next/navigation";

export const metadata: Metadata = {
  title: "Redirecting",
  description: "Redirects to /farm.",
};

export default function FarmerPage() {
  redirect("/farm");
}
