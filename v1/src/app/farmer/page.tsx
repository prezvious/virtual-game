import type { Metadata } from "next";
import { redirect } from "next/navigation";

export const metadata: Metadata = {
  title: "Redirecting | Virtual Farmer",
  description: "Legacy route redirect to /farm.",
};

export default function FarmerPage() {
  redirect("/farm");
}
