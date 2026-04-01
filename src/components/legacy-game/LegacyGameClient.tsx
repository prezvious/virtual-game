"use client";

import { useEffect, useRef, useState } from "react";
import { createClient } from "@supabase/supabase-js";

type LegacyScript = {
  src: string | null;
  code: string;
};

declare global {
  interface Window {
    supabase?: {
      createClient: typeof createClient;
    };
    __legacyLoaderDone?: boolean;
  }
}

function rewriteLegacyAssetPath(rawValue: string | null): string {
  if (!rawValue) return "";
  const value = rawValue.trim();
  if (!value) return "";
  if (/^https?:\/\//i.test(value)) return value;
  if (value.startsWith("data:")) return value;
  if (value.startsWith("/legacy/")) return value;
  if (value.startsWith("/")) return value;
  return `/legacy/${value}`;
}

function extractLegacyPayload(html: string) {
  const parser = new DOMParser();
  const doc = parser.parseFromString(html, "text/html");
  const body = doc.body;

  const scripts: LegacyScript[] = [];
  body.querySelectorAll("script").forEach((scriptEl) => {
    scripts.push({
      src: scriptEl.getAttribute("src"),
      code: scriptEl.textContent || "",
    });
    scriptEl.remove();
  });

  body.querySelectorAll<HTMLElement>("[src]").forEach((node) => {
    const src = node.getAttribute("src");
    node.setAttribute("src", rewriteLegacyAssetPath(src));
  });

  return {
    shellHtml: body.innerHTML,
    scripts,
  };
}

// Fix M-5: Add timeout to script loading
function loadScriptWithTimeout(src: string, timeoutMs = 15000): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const scriptTag = document.createElement("script");
    scriptTag.src = src;
    scriptTag.async = false;
    scriptTag.defer = false;

    const timer = setTimeout(() => {
      scriptTag.remove();
      reject(new Error(`Timeout loading legacy script: ${src}`));
    }, timeoutMs);

    scriptTag.onload = () => {
      clearTimeout(timer);
      resolve();
    };
    scriptTag.onerror = () => {
      clearTimeout(timer);
      reject(new Error(`Failed to load legacy script: ${src}`));
    };
    document.body.appendChild(scriptTag);
    return scriptTag;
  });
}

async function loadLegacyScriptsInOrder(scripts: LegacyScript[]) {
  const injectedScripts: HTMLScriptElement[] = [];

  for (const item of scripts) {
    const src = item.src?.trim() || "";

    if (src) {
      if (src.includes("@supabase/supabase-js")) {
        continue;
      }

      const scriptUrl = rewriteLegacyAssetPath(src);
      // Fix M-5: Use timeout-based loading
      await new Promise<void>((resolve, reject) => {
        loadScriptWithTimeout(scriptUrl).then(resolve).catch(reject);
      });
      continue;
    }

    const inlineCode = item.code.trim();
    if (!inlineCode) continue;

    const inlineScript = document.createElement("script");
    inlineScript.text = inlineCode;
    document.body.appendChild(inlineScript);
    injectedScripts.push(inlineScript);
  }

  return () => {
    injectedScripts.forEach((s) => s.remove());
  };
}

export default function LegacyGameClient() {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const [status, setStatus] = useState("Loading game client...");

  useEffect(() => {
    let cancelled = false;
    let cleanupScripts: (() => void) | null = null;

    const bootstrap = async () => {
      try {
        setStatus("Preparing Supabase client...");
        if (!window.supabase) {
          window.supabase = { createClient };
        }

        setStatus("Loading legacy game shell...");
        const response = await fetch("/legacy/index.html", { cache: "no-store" });
        if (!response.ok) {
          throw new Error(`Unable to load legacy shell (${response.status}).`);
        }
        const html = await response.text();
        if (cancelled) return;

        const { shellHtml, scripts } = extractLegacyPayload(html);
        const host = hostRef.current;
        if (!host) {
          throw new Error("Legacy host container is not available.");
        }
        host.innerHTML = shellHtml;

        setStatus("Booting game runtime...");
        cleanupScripts = await loadLegacyScriptsInOrder(scripts);
        if (cancelled) return;

        window.__legacyLoaderDone = true;
        setStatus("");
      } catch (error) {
        if (cancelled) return;
        const message = error instanceof Error ? error.message : "Unknown loader error.";
        setStatus(`Game bootstrap failed: ${message}`);
      }
    };

    void bootstrap();
    return () => {
      cancelled = true;
      window.__legacyLoaderDone = false;
      // Fix M-6: Clean up window.supabase on unmount
      delete window.supabase;
      cleanupScripts?.();
    };
  }, []);

  return (
    <div className="play-runtime">
      <div ref={hostRef} className="play-root" />
      {status ? (
        <div className="play-loading">
          <div>{status}</div>
        </div>
      ) : null}
    </div>
  );
}
