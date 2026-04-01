import type { Metadata } from "next";
import ProfileClient from "@/components/profile/ProfileClient";
import styles from "../profile.module.css";

type Props = { params: Promise<{ username: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { username } = await params;
  return { title: `@${username}`, description: `Profile page for ${username}.` };
}

export default async function UserProfilePage({ params }: Props) {
  const { username } = await params;
  return (
    <main className={styles.page}>
      <ProfileClient username={username} />
    </main>
  );
}
