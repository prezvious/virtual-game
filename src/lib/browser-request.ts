import { NextRequest, NextResponse } from "next/server";

const SAFE_FETCH_SITES = new Set(["same-origin", "same-site", "none"]);

function crossSiteForbidden() {
  return NextResponse.json(
    { ok: false, error: "Cross-site browser requests are not allowed." },
    { status: 403 },
  );
}

export function requireSameOriginBrowserRequest(req: NextRequest) {
  const fetchSite = req.headers.get("sec-fetch-site")?.trim().toLowerCase() || "";
  if (fetchSite === "cross-site") {
    return crossSiteForbidden();
  }

  const origin = req.headers.get("origin")?.trim();
  if (!origin) {
    return null;
  }

  let parsedOrigin: URL;
  try {
    parsedOrigin = new URL(origin);
  } catch {
    return crossSiteForbidden();
  }

  if (parsedOrigin.origin !== req.nextUrl.origin) {
    return crossSiteForbidden();
  }

  if (fetchSite && !SAFE_FETCH_SITES.has(fetchSite)) {
    return crossSiteForbidden();
  }

  return null;
}
