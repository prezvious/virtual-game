import type { Metadata } from "next";
import AdminClient from "@/components/admin/AdminClient";
import styles from "./admin.module.css";

export const metadata: Metadata = {
  title: "Admin Dashboard",
  description: "Platform administration and moderation tools.",
};

export default function AdminPage() {
  return (
    <main className={styles.page}>
      <AdminClient />
    </main>
  );
}
