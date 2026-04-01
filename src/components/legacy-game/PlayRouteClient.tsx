"use client";

export default function PlayRouteClient() {
  return (
    <div className="play-runtime" style={{ width: "100%" }}>
      <iframe
        src="/legacy/index.html"
        title="Virtual Fisher"
        className="play-root"
        loading="eager"
        sandbox="allow-scripts allow-same-origin allow-forms allow-modals"
        allow="clipboard-read; clipboard-write"
        style={{
          width: "100%",
          minHeight: "100dvh",
          border: 0,
          display: "block",
        }}
      />
    </div>
  );
}
