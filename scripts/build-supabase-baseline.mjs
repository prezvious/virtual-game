import { readdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = fileURLToPath(new URL(".", import.meta.url));
const projectRoot = resolve(scriptDir, "..");
const migrationsDir = resolve(projectRoot, "supabase", "migrations");
const outputPath = resolve(projectRoot, "supabase", "virtual_harvest_fresh_setup.sql");

function normalizeSql(sql) {
  return sql
    .replace(/^\uFEFF/, "")
    .replace(/\r\n/g, "\n")
    .replace(/^create or replace view\s+([a-zA-Z0-9_."]+)\s+as$/gim, "drop view if exists $1;\ncreate view $1 as")
    .trimEnd();
}

async function main() {
  const migrationEntries = await readdir(migrationsDir, { withFileTypes: true });
  const migrationNames = migrationEntries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".sql"))
    .map((entry) => entry.name)
    .sort((left, right) => left.localeCompare(right));

  if (migrationNames.length === 0) {
    throw new Error("No SQL migrations were found in supabase/migrations.");
  }

  const sections = await Promise.all(
    migrationNames.map(async (name) => {
      const fullPath = resolve(migrationsDir, name);
      const sql = normalizeSql(await readFile(fullPath, "utf8"));
      return `-- ============================================================================\n-- SOURCE MIGRATION: ${name}\n-- ============================================================================\n\n${sql}\n`;
    }),
  );

  const generatedAt = new Date().toISOString();
  const header = [
    "-- Virtual Harvest fresh Supabase setup",
    "-- Generated from supabase/migrations in filename order.",
    "-- Use this file only for a brand-new Supabase database or a full reset.",
    "-- Do not paste this into an existing project that has already applied migrations.",
    `-- Generated at: ${generatedAt}`,
    "",
  ].join("\n");

  await writeFile(outputPath, `${header}${sections.join("\n")}\n`, "utf8");
  console.info(`[build-supabase-baseline] Wrote ${outputPath}`);
}

main().catch((error) => {
  console.error("[build-supabase-baseline] Failed:", error);
  process.exitCode = 1;
});
