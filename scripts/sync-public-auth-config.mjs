import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const projectRoot = process.cwd();
const mode = process.env.NODE_ENV === "production" ? "production" : "development";
const outputPath = resolve(projectRoot, "public", "runtime-supabase-config.js");

function parseEnvFile(filePath) {
  const values = {};
  const contents = readFileSync(filePath, "utf8");

  for (const rawLine of contents.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;

    const separatorIndex = line.indexOf("=");
    if (separatorIndex <= 0) continue;

    const key = line.slice(0, separatorIndex).trim();
    let value = line.slice(separatorIndex + 1).trim();

    if (
      (value.startsWith('"') && value.endsWith('"'))
      || (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    values[key] = value;
  }

  return values;
}

function loadLocalEnvValues() {
  const envFiles = [
    ".env",
    `.env.${mode}`,
    ".env.local",
    `.env.${mode}.local`,
  ];

  const combined = {};
  for (const relativePath of envFiles) {
    const absolutePath = resolve(projectRoot, relativePath);
    if (!existsSync(absolutePath)) continue;
    Object.assign(combined, parseEnvFile(absolutePath));
  }

  return combined;
}

const localEnv = loadLocalEnvValues();

function readEnv(name) {
  const processValue = process.env[name]?.trim();
  if (processValue) return processValue;

  const localValue = localEnv[name]?.trim();
  if (localValue) return localValue;

  return "";
}

function resolveProjectConfig(projectName) {
  const upperName = projectName.toUpperCase();
  const sharedUrl = readEnv("NEXT_PUBLIC_SUPABASE_URL");
  const sharedAnonKey = readEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");

  return {
    url: readEnv(`NEXT_PUBLIC_${upperName}_SUPABASE_URL`) || sharedUrl,
    anonKey: readEnv(`NEXT_PUBLIC_${upperName}_SUPABASE_ANON_KEY`) || sharedAnonKey,
  };
}

const sharedConfig = {
  url: readEnv("NEXT_PUBLIC_SUPABASE_URL"),
  anonKey: readEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
};

const runtimeConfig = {
  shared: sharedConfig,
  fisher: resolveProjectConfig("fisher"),
  farmer: resolveProjectConfig("farmer"),
};

const output = `window.__PLATFORM_SUPABASE_CONFIG__ = Object.freeze(${JSON.stringify(runtimeConfig, null, 2)});\n`;

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, output, "utf8");

const hasAnyConfig = Object.values(runtimeConfig).some((entry) =>
  entry && typeof entry === "object" && (entry.url || entry.anonKey),
);

if (!hasAnyConfig) {
  console.warn("[sync-public-auth-config] No public Supabase config was found. Generated blank runtime config.");
} else {
  console.info("[sync-public-auth-config] Wrote public/runtime-supabase-config.js");
}
