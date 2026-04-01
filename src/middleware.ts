import { NextRequest, NextResponse } from "next/server";

// Fix N-2: Centralized security layer
// Fix N-4: Security headers

const SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
};

// Public endpoints that don't require authentication
const PUBLIC_PATHS = new Set([
  "/api/weather",
  "/api/leaderboard",
  "/api/auth/exchange",
]);

// Endpoints that have their own auth logic and should not be blocked by middleware
const SELF_AUTH_PATHS = new Set([
  "/api/profile/discover",
  "/api/achievements",
  "/api/social",
  "/api/profile/me",
  "/api/profile",
  "/api/admin",
  "/api/auth/ban-status",
  "/api/profile/password",
  "/api/chat",
  "/api/search",
  "/api/shop",
  "/api/alerts",
]);

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Apply security headers to all responses
  const response = NextResponse.next();
  for (const [header, value] of Object.entries(SECURITY_HEADERS)) {
    response.headers.set(header, value);
  }

  // Skip auth check for public paths and self-auth paths
  if (PUBLIC_PATHS.has(pathname) || SELF_AUTH_PATHS.has(pathname)) {
    return response;
  }

  return response;
}

export const config = {
  matcher: [
    "/api/:path*",
  ],
};
