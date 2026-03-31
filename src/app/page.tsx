import Link from "next/link";
import { Fraunces, IBM_Plex_Mono } from "next/font/google";
import styles from "./landing.module.css";

const fraunces = Fraunces({
  subsets: ["latin"],
  weight: ["500", "700", "900"],
  variable: "--font-display",
  preload: false,
});

const plexMono = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["500", "700"],
  variable: "--font-mono",
  preload: false,
});

export default function LandingPage() {
  return (
    <main className={`${styles.page} ${fraunces.variable} ${plexMono.variable}`}>
      <div className={styles.grain} aria-hidden="true" />
      <div className={styles.shell}>
        <header className={styles.topbar}>
          <p className={styles.brand}>Virtual Harvest Platform</p>
          <Link className={styles.topCta} href="/home">
            Account Home
          </Link>
        </header>

        <section className={styles.hero}>
          <p className={styles.kicker}>One Account. Two Worlds.</p>
          <h1>Run your fishing and farming empires from one platform.</h1>
          <p className={styles.lede}>
            One login now links Virtual Fisher and Virtual Farmer, keeps each save system intact, and
            gives you one launch hub for both games.
          </p>
          <div className={styles.heroActions}>
            <Link className={styles.primary} href="/home">
              Open Account Center
            </Link>
            <Link className={styles.secondary} href="/fish">
              Launch Fisher
            </Link>
            <Link className={styles.secondary} href="/farm">
              Launch Farmer
            </Link>
          </div>
        </section>

        <section className={styles.columns}>
          <article className={styles.column}>
            <p className={styles.columnTag}>Virtual Fisher</p>
            <h2>High-tempo biome fishing with cloud sync.</h2>
            <p>
              Keep your rods, baits, combo routes, and leaderboard climb in the same account context as
              your farming progress.
            </p>
          </article>

          <article className={styles.column}>
            <p className={styles.columnTag}>Virtual Farmer</p>
            <h2>Progression farming loops with prestige depth.</h2>
            <p>
              Preserve your inventory, upgrades, auto-farm cycles, and cloud snapshots while operating from
              the unified platform account.
            </p>
          </article>
        </section>

        <section className={styles.columns}>
          <article className={styles.column}>
            <p className={styles.columnTag}>Community</p>
            <h2>Connect, compete, and track both games.</h2>
            <p>
              Follow friends, climb leaderboards, earn achievements, and manage one public username
              across Virtual Fisher and Virtual Farmer.
            </p>
          </article>

          <article className={styles.column}>
            <p className={styles.columnTag}>Profile Hub</p>
            <h2>One profile for both worlds.</h2>
            <p>
              Open your account profile to manage your username, review your email-linked account, and
              track cross-game playtime from one page.
            </p>
          </article>
        </section>

        <section className={styles.footerCta}>
          <h2>Start from the platform homepage.</h2>
          <p>
            Sign in once, check both game statuses, and launch whichever world you want without switching
            websites.
          </p>
          <div className={styles.heroActions}>
            <Link className={styles.primary} href="/home">
              Go To Platform Home
            </Link>
            <Link className={styles.secondary} href="/profile">
              Browse Profiles
            </Link>
          </div>
        </section>
      </div>
    </main>
  );
}
