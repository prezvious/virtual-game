"use client";

import { useEffect, useMemo, useState } from "react";
import styles from "./game-shell-page.module.css";

type LegacyRuntimeKind = "fisher" | "farmer";

type HeadResource = {
  as?: string | null;
  crossOrigin?: string | null;
  href: string;
  rel: string;
};

type ScriptResource = {
  noModule: boolean;
  src: string | null;
  text: string | null;
  type: string | null;
};

type ParsedLegacyDocument = {
  bodyAttributes: Array<[string, string]>;
  bodyClassNames: string[];
  bodyHtml: string;
  resources: HeadResource[];
  scripts: ScriptResource[];
};

type BodySnapshot = {
  attributes: Map<string, string>;
  className: string;
  styleText: string;
};

type RuntimeManager = {
  activeKey: LegacyRuntimeKind | null;
  bodySnapshot: BodySnapshot | null;
  cleanupBound: boolean;
  loadPromise: Promise<void> | null;
  mountElement: HTMLElement | null;
  ready: boolean;
  runtimeBodyNodes: Set<Node>;
  runtimeContext:
    | {
        key: LegacyRuntimeKind;
        routePath: string;
        staticBasePath: string;
      }
    | null;
};

declare global {
  interface Window {
    __VH_INLINE_RUNTIME_CONTEXT__?:
      | {
          key: LegacyRuntimeKind;
          routePath: string;
          staticBasePath: string;
        }
      | undefined;
    __VH_INLINE_RUNTIME_MANAGER__?: RuntimeManager | undefined;
  }
}

const RUNTIME_STATIC_BASE: Record<LegacyRuntimeKind, string> = {
  fisher: "/legacy/",
  farmer: "/farmer-legacy/",
};

function getRuntimeManager(): RuntimeManager {
  if (!window.__VH_INLINE_RUNTIME_MANAGER__) {
    window.__VH_INLINE_RUNTIME_MANAGER__ = {
      activeKey: null,
      bodySnapshot: null,
      cleanupBound: false,
      loadPromise: null,
      mountElement: null,
      ready: false,
      runtimeBodyNodes: new Set(),
      runtimeContext: null,
    };
  }

  return window.__VH_INLINE_RUNTIME_MANAGER__;
}

function snapshotBody(element: HTMLElement): BodySnapshot {
  const attributes = new Map<string, string>();
  for (const attribute of Array.from(element.attributes)) {
    attributes.set(attribute.name, attribute.value);
  }

  return {
    attributes,
    className: element.className,
    styleText: element.style.cssText,
  };
}

function restoreBody(manager: RuntimeManager) {
  const snapshot = manager.bodySnapshot;
  if (!snapshot) {
    return;
  }

  const body = document.body;
  for (const attribute of Array.from(body.attributes)) {
    if (!snapshot.attributes.has(attribute.name)) {
      body.removeAttribute(attribute.name);
    }
  }

  for (const [name, value] of snapshot.attributes.entries()) {
    body.setAttribute(name, value);
  }

  body.className = snapshot.className;
  body.style.cssText = snapshot.styleText;

  for (const node of Array.from(manager.runtimeBodyNodes)) {
    if (node.parentNode === body) {
      node.parentNode.removeChild(node);
    }
  }
  manager.runtimeBodyNodes.clear();
}

function normalizeUrlAttribute(rawValue: string, baseUrl: string): string {
  const value = rawValue.trim();
  if (
    value === "" ||
    value.startsWith("/") ||
    value.startsWith("#") ||
    value.startsWith("data:") ||
    value.startsWith("mailto:") ||
    value.startsWith("tel:") ||
    value.startsWith("javascript:") ||
    /^[a-zA-Z][a-zA-Z\d+\-.]*:/.test(value)
  ) {
    return value;
  }

  const resolved = new URL(value, baseUrl);
  return `${resolved.pathname}${resolved.search}${resolved.hash}`;
}

function parseFetchedLegacyDocument(htmlText: string, documentPath: string): ParsedLegacyDocument {
  const parser = new DOMParser();
  const parsed = parser.parseFromString(htmlText, "text/html");
  const documentUrl = new URL(documentPath, window.location.origin).toString();

  const bodyClone = parsed.body.cloneNode(true) as HTMLBodyElement;
  const scriptElements = Array.from(bodyClone.querySelectorAll("script"));
  const scripts = scriptElements.map<ScriptResource>((script) => ({
    noModule: script.noModule,
    src: script.src ? normalizeUrlAttribute(script.getAttribute("src") || "", documentUrl) : null,
    text: script.src ? null : script.textContent,
    type: script.type || null,
  }));
  for (const script of scriptElements) {
    script.remove();
  }

  const urlAttributes = ["action", "href", "poster", "src"] as const;
  for (const attribute of urlAttributes) {
    for (const element of Array.from(bodyClone.querySelectorAll<HTMLElement>(`[${attribute}]`))) {
      const rawValue = element.getAttribute(attribute);
      if (!rawValue) {
        continue;
      }
      element.setAttribute(attribute, normalizeUrlAttribute(rawValue, documentUrl));
    }
  }

  const resources = Array.from(parsed.head.querySelectorAll<HTMLLinkElement>("link[rel='preconnect'], link[rel='stylesheet']"))
    .map<HeadResource>((link) => ({
      as: link.getAttribute("as"),
      crossOrigin: link.getAttribute("crossorigin"),
      href: normalizeUrlAttribute(link.getAttribute("href") || "", documentUrl),
      rel: link.rel,
    }))
    .filter((resource) => resource.href !== "");

  return {
    bodyAttributes: Array.from(parsed.body.attributes)
      .filter((attribute) => attribute.name !== "class")
      .map((attribute) => [attribute.name, attribute.value] as [string, string]),
    bodyClassNames: Array.from(parsed.body.classList),
    bodyHtml: bodyClone.innerHTML,
    resources,
    scripts,
  };
}

function resourceKey(resource: HeadResource) {
  return `${resource.rel}:${resource.href}`;
}

async function ensureHeadResources(resources: HeadResource[]) {
  const pendingLoads: Promise<void>[] = [];

  for (const resource of resources) {
    const key = resourceKey(resource);
    const existing = document.head.querySelector<HTMLLinkElement>(`link[data-vh-runtime-resource="${CSS.escape(key)}"]`);
    if (existing) {
      continue;
    }

    const link = document.createElement("link");
    link.rel = resource.rel;
    link.href = resource.href;
    link.dataset.vhRuntimeResource = key;

    if (resource.as) {
      link.as = resource.as;
    }
    if (resource.crossOrigin) {
      link.crossOrigin = resource.crossOrigin;
    }

    if (resource.rel === "stylesheet") {
      pendingLoads.push(
        new Promise((resolve) => {
          link.addEventListener("load", () => resolve(), { once: true });
          link.addEventListener("error", () => resolve(), { once: true });
        }),
      );
    }

    document.head.appendChild(link);
  }

  if (pendingLoads.length > 0) {
    await Promise.all(pendingLoads);
  }
}

function ensureUnloadCleanup(manager: RuntimeManager) {
  if (manager.cleanupBound) {
    return;
  }

  manager.cleanupBound = true;
  window.addEventListener(
    "beforeunload",
    () => {
      restoreBody(manager);
      manager.activeKey = null;
      manager.bodySnapshot = null;
      manager.loadPromise = null;
      manager.mountElement = null;
      manager.ready = false;
      manager.runtimeContext = null;
      delete window.__VH_INLINE_RUNTIME_CONTEXT__;
    },
    { once: true },
  );
}

async function loadExternalScript(src: string) {
  return new Promise<void>((resolve, reject) => {
    const script = document.createElement("script");
    script.src = src;
    script.async = false;
    script.dataset.vhRuntimeScript = src;
    script.addEventListener("load", () => resolve(), { once: true });
    script.addEventListener("error", () => reject(new Error(`Failed to load ${src}`)), { once: true });
    document.body.appendChild(script);
  });
}

async function runInlineScript(scriptResource: ScriptResource, runtimeKey: LegacyRuntimeKind) {
  const script = document.createElement("script");
  script.async = false;
  if (scriptResource.type) {
    script.type = scriptResource.type;
  }
  if (scriptResource.noModule) {
    script.noModule = true;
  }
  script.dataset.vhRuntimeInline = runtimeKey;
  script.text = scriptResource.text || "";
  document.body.appendChild(script);
}

async function loadScriptsSequentially(scripts: ScriptResource[], runtimeKey: LegacyRuntimeKind) {
  for (const script of scripts) {
    if (script.src) {
      await loadExternalScript(script.src);
      continue;
    }

    await runInlineScript(script, runtimeKey);
  }
}

function applyRuntimeBody(parsed: ParsedLegacyDocument, runtimeKey: LegacyRuntimeKind) {
  const body = document.body;
  for (const className of parsed.bodyClassNames) {
    body.classList.add(className);
  }
  for (const [name, value] of parsed.bodyAttributes) {
    body.setAttribute(name, value);
  }
  body.dataset.vhLegacyActive = runtimeKey;
}

function bindBodyNodeTracker(manager: RuntimeManager) {
  const observer = new MutationObserver((records) => {
    for (const record of records) {
      for (const node of Array.from(record.addedNodes)) {
        if (
          record.target === document.body &&
          node.parentNode === document.body &&
          node instanceof HTMLElement &&
          !node.hasAttribute("data-vh-runtime-script") &&
          !node.hasAttribute("data-vh-runtime-inline")
        ) {
          manager.runtimeBodyNodes.add(node);
        }
      }
    }
  });

  observer.observe(document.body, { childList: true });
}

async function mountInlineRuntime(
  runtimeKey: LegacyRuntimeKind,
  documentPath: string,
  mountElement: HTMLElement,
) {
  const manager = getRuntimeManager();

  if (manager.activeKey && manager.activeKey !== runtimeKey) {
    window.location.reload();
    return;
  }

  if (manager.ready && manager.activeKey === runtimeKey) {
    if (manager.mountElement && manager.mountElement !== mountElement) {
      window.location.reload();
    }
    return;
  }

  if (manager.loadPromise) {
    await manager.loadPromise;
    return;
  }

  manager.activeKey = runtimeKey;
  manager.mountElement = mountElement;
  manager.bodySnapshot = snapshotBody(document.body);
  manager.runtimeContext = {
    key: runtimeKey,
    routePath: window.location.pathname,
    staticBasePath: RUNTIME_STATIC_BASE[runtimeKey],
  };
  window.__VH_INLINE_RUNTIME_CONTEXT__ = manager.runtimeContext;
  ensureUnloadCleanup(manager);
  bindBodyNodeTracker(manager);

  manager.loadPromise = (async () => {
    const response = await fetch(documentPath, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Failed to load runtime document: ${documentPath}`);
    }

    const htmlText = await response.text();
    const parsed = parseFetchedLegacyDocument(htmlText, documentPath);

    await ensureHeadResources(parsed.resources);
    applyRuntimeBody(parsed, runtimeKey);
    mountElement.innerHTML = parsed.bodyHtml;
    await loadScriptsSequentially(parsed.scripts, runtimeKey);
    manager.ready = true;
  })();

  await manager.loadPromise;
}

type InlineLegacyRuntimeProps = {
  documentPath: string;
  loadingEyebrow: string;
  loadingTitle: string;
  loadingMessage: string;
  runtimeKey: LegacyRuntimeKind;
};

export default function InlineLegacyRuntime({
  documentPath,
  loadingEyebrow,
  loadingTitle,
  loadingMessage,
  runtimeKey,
}: InlineLegacyRuntimeProps) {
  const [error, setError] = useState("");
  const [isReady, setIsReady] = useState(false);
  const mountId = useMemo(() => `vh-runtime-${runtimeKey}`, [runtimeKey]);
  const retryHref = typeof window === "undefined" ? documentPath : window.location.pathname;

  useEffect(() => {
    let cancelled = false;
    const mountElement = document.getElementById(mountId);

    if (!(mountElement instanceof HTMLElement)) {
      window.setTimeout(() => {
        if (!cancelled) {
          setError("Runtime mount point is missing.");
        }
      }, 0);
      return;
    }

    void mountInlineRuntime(runtimeKey, documentPath, mountElement)
      .then(() => {
        if (!cancelled) {
          setIsReady(true);
        }
      })
      .catch((runtimeError) => {
        if (!cancelled) {
          setError(runtimeError instanceof Error ? runtimeError.message : "Runtime failed to load.");
        }
      });

    return () => {
      cancelled = true;
    };
  }, [documentPath, mountId, runtimeKey]);

  return (
    <>
      {!isReady && !error ? (
        <div className={styles.loadingMask} role="status" aria-live="polite">
          <div className={styles.loadingPanel}>
            <p className={styles.loadingKicker}>{loadingEyebrow}</p>
            <p className={styles.loadingTitle}>{loadingTitle}</p>
            <p className={styles.loadingText}>{loadingMessage}</p>
          </div>
        </div>
      ) : null}

      {error ? (
        <div className={styles.loadingMask} role="alert">
          <div className={styles.loadingPanel}>
            <p className={styles.loadingKicker}>{loadingEyebrow}</p>
            <p className={styles.loadingTitle}>Runtime Unavailable</p>
            <p className={styles.loadingText}>{error}</p>
            <a href={retryHref} className={styles.retryLink}>
              Reload Page
            </a>
          </div>
        </div>
      ) : null}

      <div id={mountId} className={styles.runtimeMount} aria-hidden={!isReady} />
    </>
  );
}
