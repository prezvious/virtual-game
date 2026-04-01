export const WEATHER_DURATION_MIN_MINUTES = 30;
export const WEATHER_DURATION_MAX_MINUTES = 60;
export const WEATHER_NOTIFICATION_DURATION_MS = 20_000;
export const WEATHER_ANNOUNCEMENT_STORAGE_PREFIX = "vh-weather-announcement:";

export const WEATHER_GAMES = ["fisher", "farmer"] as const;

export type WeatherGame = (typeof WEATHER_GAMES)[number];

export type WeatherSource = "admin_console" | "default";

export type StoredWeatherValue = {
  condition?: unknown;
  intensity?: unknown;
  started_at?: unknown;
  expires_at?: unknown;
  duration_minutes?: unknown;
  announcement_id?: unknown;
  source?: unknown;
};

export type NormalizedWeatherState = {
  condition: string;
  intensity: number;
  started_at: string | null;
  expires_at: string | null;
  duration_minutes: number | null;
  announcement_id: string | null;
  source: string;
  active: boolean;
  remaining_ms: number | null;
};

export type PublicWeatherState = NormalizedWeatherState & {
  game: WeatherGame;
  game_label: string;
};

const DEFAULT_CONDITION = "clear";
const DEFAULT_INTENSITY = 1;

export const WEATHER_GAME_LABELS: Record<WeatherGame, string> = {
  fisher: "Virtual Fisher",
  farmer: "Virtual Farmer",
};

const WEATHER_CONDITION_LABELS: Record<string, string> = {
  clear: "Clear",
  rain: "Rain",
  storm: "Storm",
  fog: "Fog",
  snow: "Snow",
  wind: "Wind",
};

function asRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }

  return value as Record<string, unknown>;
}

function clampIntensity(value: unknown) {
  const numericValue = Number(value);
  if (!Number.isFinite(numericValue)) {
    return DEFAULT_INTENSITY;
  }

  return Math.max(1, Math.min(5, Math.floor(numericValue)));
}

function normalizeIsoString(value: unknown) {
  if (typeof value !== "string" || !value.trim()) {
    return null;
  }

  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) {
    return null;
  }

  return new Date(timestamp).toISOString();
}

function normalizeDurationMinutes(value: unknown) {
  const numericValue = Number(value);
  if (!Number.isFinite(numericValue)) {
    return null;
  }

  const wholeMinutes = Math.floor(numericValue);
  if (wholeMinutes < WEATHER_DURATION_MIN_MINUTES || wholeMinutes > WEATHER_DURATION_MAX_MINUTES) {
    return null;
  }

  return wholeMinutes;
}

function deriveDurationMinutes(startedAt: string | null, expiresAt: string | null) {
  if (!startedAt || !expiresAt) {
    return null;
  }

  const startedAtMs = Date.parse(startedAt);
  const expiresAtMs = Date.parse(expiresAt);
  if (!Number.isFinite(startedAtMs) || !Number.isFinite(expiresAtMs) || expiresAtMs <= startedAtMs) {
    return null;
  }

  const derivedMinutes = Math.round((expiresAtMs - startedAtMs) / 60_000);
  return normalizeDurationMinutes(derivedMinutes);
}

export function createDefaultWeatherState(): NormalizedWeatherState {
  return {
    condition: DEFAULT_CONDITION,
    intensity: DEFAULT_INTENSITY,
    started_at: null,
    expires_at: null,
    duration_minutes: null,
    announcement_id: null,
    source: "default",
    active: false,
    remaining_ms: null,
  };
}

export function isWeatherGame(value: string): value is WeatherGame {
  return WEATHER_GAMES.includes(value as WeatherGame);
}

export function randomWeatherDurationMinutes() {
  const span = WEATHER_DURATION_MAX_MINUTES - WEATHER_DURATION_MIN_MINUTES + 1;
  return WEATHER_DURATION_MIN_MINUTES + Math.floor(Math.random() * span);
}

export function createAdminWeatherValue(condition: string, intensity: number, now = new Date()) {
  const durationMinutes = randomWeatherDurationMinutes();
  const startedAt = new Date(now.getTime());
  const expiresAt = new Date(now.getTime() + durationMinutes * 60_000);

  return {
    condition: (condition || DEFAULT_CONDITION).trim().toLowerCase() || DEFAULT_CONDITION,
    intensity: clampIntensity(intensity),
    started_at: startedAt.toISOString(),
    expires_at: expiresAt.toISOString(),
    duration_minutes: durationMinutes,
    announcement_id: crypto.randomUUID(),
    source: "admin_console" as const,
  };
}

export function normalizeWeatherValue(value: unknown, now = Date.now()): NormalizedWeatherState {
  const storedValue = asRecord(value) as StoredWeatherValue;
  const normalizedCondition = typeof storedValue.condition === "string" && storedValue.condition.trim()
    ? storedValue.condition.trim().toLowerCase()
    : DEFAULT_CONDITION;
  const startedAt = normalizeIsoString(storedValue.started_at);
  const expiresAt = normalizeIsoString(storedValue.expires_at);
  const durationMinutes = normalizeDurationMinutes(storedValue.duration_minutes)
    ?? deriveDurationMinutes(startedAt, expiresAt);
  const announcementId = typeof storedValue.announcement_id === "string" && storedValue.announcement_id.trim()
    ? storedValue.announcement_id.trim()
    : null;
  const source = typeof storedValue.source === "string" && storedValue.source.trim()
    ? storedValue.source.trim()
    : "default";
  const expiresAtMs = expiresAt ? Date.parse(expiresAt) : Number.NaN;
  const isActive = Number.isFinite(expiresAtMs) && expiresAtMs > now;

  if (!isActive) {
    return createDefaultWeatherState();
  }

  return {
    condition: normalizedCondition,
    intensity: clampIntensity(storedValue.intensity),
    started_at: startedAt,
    expires_at: expiresAt,
    duration_minutes: durationMinutes,
    announcement_id: announcementId,
    source,
    active: true,
    remaining_ms: Math.max(0, expiresAtMs - now),
  };
}

export function toPublicWeatherState(game: WeatherGame, value: unknown, now = Date.now()): PublicWeatherState {
  return {
    ...normalizeWeatherValue(value, now),
    game,
    game_label: WEATHER_GAME_LABELS[game],
  };
}

export function getWeatherConditionLabel(condition: string) {
  const normalizedCondition = String(condition || DEFAULT_CONDITION).trim().toLowerCase();
  if (WEATHER_CONDITION_LABELS[normalizedCondition]) {
    return WEATHER_CONDITION_LABELS[normalizedCondition];
  }

  return normalizedCondition
    .split(/[\s_-]+/)
    .filter(Boolean)
    .map((token) => token[0]?.toUpperCase() + token.slice(1))
    .join(" ") || WEATHER_CONDITION_LABELS.clear;
}

export function formatWeatherRemainingLabel(remainingMs: number | null) {
  if (!Number.isFinite(remainingMs) || (remainingMs ?? 0) <= 0) {
    return "";
  }

  const remainingMinutes = Math.max(1, Math.ceil((remainingMs as number) / 60_000));
  return `Ends in about ${remainingMinutes} minute${remainingMinutes === 1 ? "" : "s"}.`;
}

export function buildWeatherStateKey(weather: NormalizedWeatherState, updatedAt: string | null) {
  return [
    updatedAt || "none",
    weather.active ? "active" : "inactive",
    weather.condition,
    String(weather.intensity),
    weather.announcement_id || "none",
    weather.expires_at || "none",
  ].join("|");
}

export function getWeatherAnnouncementStorageKey(announcementId: string) {
  return `${WEATHER_ANNOUNCEMENT_STORAGE_PREFIX}${announcementId}`;
}
