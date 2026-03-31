import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  turbopack: {
    root: process.cwd(),
  },
  async rewrites() {
    return [
      {
        source: "/api/profile/me",
        destination: "/api/profile?scope=self",
      },
    ];
  },
};

export default nextConfig;
