"use client";

import SelfProfileClient from "@/components/profile/SelfProfileClient";
import styles from "./profile.module.css";

export default function MyProfilePage() {
  return (
    <main className={styles.page}>
      <SelfProfileClient />
    </main>
  );
}
