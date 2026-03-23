import Link from "next/link";

export default function NotFound() {
  return (
    <main style={{
      minHeight: "100dvh",
      display: "grid",
      placeItems: "center",
      padding: "2rem",
      background: "linear-gradient(135deg, #fef9f0, #edf6fb)",
      color: "#172034",
      textAlign: "center",
    }}>
      <div>
        <p style={{ fontSize: "5rem", fontWeight: 900, margin: 0, lineHeight: 1, opacity: 0.15 }}>404</p>
        <h1 style={{ margin: "0.5rem 0", fontSize: "1.8rem", letterSpacing: "-0.02em" }}>Page Not Found</h1>
        <p style={{ margin: "0.5rem 0 1.5rem", color: "#3f5072", maxWidth: "40ch" }}>
          The page you&apos;re looking for doesn&apos;t exist or has been moved. Let&apos;s get you back on track.
        </p>
        <div style={{ display: "flex", gap: "0.6rem", justifyContent: "center", flexWrap: "wrap" }}>
          <Link href="/" style={{
            display: "inline-flex", alignItems: "center", justifyContent: "center",
            padding: "0.6rem 1.1rem", borderRadius: "8px", fontWeight: 800, fontSize: "0.88rem",
            background: "linear-gradient(118deg, #f6c07c, #eba863)", border: "1px solid #d2924e", color: "#1b2c49",
          }}>
            Landing Page
          </Link>
          <Link href="/home" style={{
            display: "inline-flex", alignItems: "center", justifyContent: "center",
            padding: "0.6rem 1.1rem", borderRadius: "8px", fontWeight: 800, fontSize: "0.88rem",
            background: "transparent", border: "1px solid rgba(30,46,82,0.18)", color: "#223757",
          }}>
            Platform Home
          </Link>
          <Link href="/fish" style={{
            display: "inline-flex", alignItems: "center", justifyContent: "center",
            padding: "0.6rem 1.1rem", borderRadius: "8px", fontWeight: 800, fontSize: "0.88rem",
            background: "transparent", border: "1px solid rgba(30,46,82,0.18)", color: "#223757",
          }}>
            Play Fisher
          </Link>
        </div>
      </div>
    </main>
  );
}
