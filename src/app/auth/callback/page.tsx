import type { Metadata } from "next";
import AuthCallbackClient from "@/components/auth/AuthCallbackClient";

export const metadata: Metadata = {
  title: "Account Verification",
  description: "Completes account verification and session setup for Virtual Harvest.",
};

export default function AuthCallbackPage() {
  return <AuthCallbackClient />;
}
