import type { Metadata } from "next";
import FriendsClient from "@/components/social/FriendsClient";
import styles from "./friends.module.css";

export const metadata: Metadata = {
  title: "Friends",
  description: "Manage your friends and social connections.",
};

export default function FriendsPage() {
  return (
    <main className={styles.page}>
      <FriendsClient />
    </main>
  );
}
