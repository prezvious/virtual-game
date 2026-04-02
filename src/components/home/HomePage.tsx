import Link from "next/link";
import FullDocumentLink from "@/components/ui/FullDocumentLink";
import styles from "./home-page.module.css";

const worldCards = [
  {
    label: "Virtual Fisher",
    title: "High-focus water runs, cloud progress, and live competition.",
    description:
      "Track precision routes, preserve your inventory, and keep your fishing session inside the same Virtual Harvest account system.",
    href: "/fish",
    cta: "Open Fisher",
  },
  {
    label: "Virtual Farmer",
    title: "Long-form farming loops with prestige depth and persistent saves.",
    description:
      "Manage crops, upgrades, and longer progression chains without dropping out of the shared platform shell.",
    href: "/farm",
    cta: "Open Farmer",
  },
];

const platformCards = [
  {
    label: "Shared Identity",
    title: "One account center for sign-in, linking, and profile setup.",
    description: "Open your account tools, connect both games, and keep one public identity across the platform.",
    href: "/account-center",
    cta: "Open Account Center",
  },
  {
    label: "Community",
    title: "Profiles, friends, achievements, and public discovery live together.",
    description: "Browse players, follow friends, and keep platform activity visible through one consistent navigation system.",
    href: "/profile",
    cta: "Browse Profiles",
  },
  {
    label: "Competition",
    title: "Leaderboards stay public, readable, and close to the core flow.",
    description: "Check rankings without hunting through account screens or switching to a separate site structure.",
    href: "/leaderboard",
    cta: "View Leaderboard",
  },
];

const highlights = [
  { value: "1", label: "platform brand" },
  { value: "2", label: "active game worlds" },
  { value: "1", label: "shared identity layer" },
];

function isGameRoute(href: string) {
  return href === "/fish" || href === "/farm";
}

export default function HomePage() {
  return (
    <main id="main-content" tabIndex={-1} className={styles.page}>
      <div className={styles.shell}>
        <header className={styles.topbar}>
          <div className={styles.brandBlock}>
            <p className={styles.brandKicker}>Virtual Harvest</p>
            <p className={styles.brandText}>Unified home for Virtual Fisher and Virtual Farmer.</p>
          </div>

          <nav className={styles.nav}>
            <Link href="/leaderboard" className={styles.navLink}>
              Leaderboard
            </Link>
            <Link href="/profile" className={styles.navLink}>
              Profiles
            </Link>
            <Link href="/account-center" className={styles.navPrimary}>
              Account Center
            </Link>
          </nav>
        </header>

        <section className={styles.hero}>
          <div className={styles.heroCopy}>
            <p className={styles.kicker}>One platform. Two living worlds.</p>
            <h1>Run both game worlds from one calm, consistent home base.</h1>
            <p className={styles.lede}>
              Virtual Harvest now treats fishing, farming, profiles, and competition as one cohesive
              platform. The routes stay familiar, but the experience no longer feels split between
              separate systems.
            </p>

            <div className={styles.heroActions}>
              <Link href="/account-center" className={styles.primaryAction}>
                Open Account Center
              </Link>
              <FullDocumentLink href="/fish" className={styles.secondaryAction}>
                Launch Virtual Fisher
              </FullDocumentLink>
              <FullDocumentLink href="/farm" className={styles.secondaryAction}>
                Launch Virtual Farmer
              </FullDocumentLink>
            </div>
          </div>

          <aside className={styles.heroPanel}>
            <p className={styles.panelLabel}>Platform Snapshot</p>
            <div className={styles.highlightGrid}>
              {highlights.map((item) => (
                <article key={item.label} className={styles.highlightCard}>
                  <strong>{item.value}</strong>
                  <span>{item.label}</span>
                </article>
              ))}
            </div>
            <p className={styles.panelNote}>
              `/fish` and `/farm` still launch directly. `/play` and `/farmer` remain intact as redirect
              paths so older links do not break.
            </p>
          </aside>
        </section>

        <section className={styles.section}>
          <div className={styles.sectionHeader}>
            <p className={styles.sectionTag}>Game Worlds</p>
            <h2>Each game keeps its identity, but the platform stops feeling fragmented.</h2>
          </div>

          <div className={styles.worldGrid}>
            {worldCards.map((card) => (
              <article key={card.label} className={styles.worldCard}>
                <p className={styles.cardTag}>{card.label}</p>
                <h3>{card.title}</h3>
                <p>{card.description}</p>
                {isGameRoute(card.href) ? (
                  <FullDocumentLink href={card.href} className={styles.cardAction}>
                    {card.cta}
                  </FullDocumentLink>
                ) : (
                  <Link href={card.href} className={styles.cardAction}>
                    {card.cta}
                  </Link>
                )}
              </article>
            ))}
          </div>
        </section>

        <section className={styles.section}>
          <div className={styles.sectionHeader}>
            <p className={styles.sectionTag}>Platform Layer</p>
            <h2>Shared tools now feel like part of the same product instead of extras bolted on later.</h2>
          </div>

          <div className={styles.platformGrid}>
            {platformCards.map((card) => (
              <article key={card.label} className={styles.platformCard}>
                <p className={styles.cardTag}>{card.label}</p>
                <h3>{card.title}</h3>
                <p>{card.description}</p>
                <Link href={card.href} className={styles.cardAction}>
                  {card.cta}
                </Link>
              </article>
            ))}
          </div>
        </section>

        <section className={styles.footerPanel}>
          <div>
            <p className={styles.sectionTag}>Start Here</p>
            <h2>Use `/home` as the real front door, then jump anywhere from one navigation rhythm.</h2>
          </div>
          <div className={styles.footerActions}>
            <Link href="/account-center" className={styles.primaryAction}>
              Go To Account Center
            </Link>
            <Link href="/friends" className={styles.secondaryAction}>
              Open Friends
            </Link>
            <Link href="/achievements" className={styles.secondaryAction}>
              View Achievements
            </Link>
          </div>
        </section>
      </div>
    </main>
  );
}
