import type { Metadata } from "next";
import AuthCallbackClient from "@/components/auth/AuthCallbackClient";

export const metadata: Metadata = {
  title: "Auth Callback | Fish It!",
  description: "Completes account verification and session setup for Fish It!.",
};

export default function AuthCallbackPage() {
  return <AuthCallbackClient />;
}

