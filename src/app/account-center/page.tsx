import type { Metadata } from "next";
import AccountCenterClient from "@/components/account-center/AccountCenterClient";
import OnboardingFlow from "@/components/onboarding/OnboardingFlow";
import styles from "./account-center.module.css";

export const metadata: Metadata = {
  title: "Account Center",
  description: "Manage account access and game linking for Virtual Harvest.",
};

export default function AccountCenterPage() {
  return (
    <main className={styles.page}>
      <AccountCenterClient />
      <OnboardingFlow />
    </main>
  );
}
