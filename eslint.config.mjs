import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "**/.next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
    // Legacy/static sources kept for migration fallback:
    "auth/**",
    "js/**",
    "public/vendor/**",
    "public/legacy/**",
    "public/farmer-legacy/**",
    "nextjs-scaffold/**",
    // Archived sibling projects outside active root app:
    "v1/**",
    "virtual-fisher/**",
    "virtual-farmer/**",
  ]),
]);

export default eslintConfig;
