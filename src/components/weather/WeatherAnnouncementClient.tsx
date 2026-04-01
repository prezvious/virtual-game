"use client";

import { startTransition, useCallback, useEffect, useRef, useState } from "react";
import { usePathname } from "next/navigation";
import { getClientSupabase } from "@/lib/auth-client";
import {
  formatWeatherRemainingLabel,
  getWeatherAnnouncementStorageKey,
  getWeatherConditionLabel,
  toPublicWeatherState,
  WEATHER_GAME_LABELS,
  WEATHER_GAMES,
  WEATHER_NOTIFICATION_DURATION_MS,
  type NormalizedWeatherState,
  type PublicWeatherState,
  type WeatherGame,
} from "@/lib/weather";
import styles from "./weather-announcement.module.css";

type WeatherAnnouncement = {
  id: string;
  game: WeatherGame;
  title: string;
  subtitle: string;
  detail: string;
};

type WeatherApiResponse = {
  ok?: boolean;
  weather?: PublicWeatherState;
};

function buildAnnouncement(game: WeatherGame, weather: NormalizedWeatherState): WeatherAnnouncement | null {
  if (!weather.active || !weather.announcement_id) {
    return null;
  }

  const conditionLabel = getWeatherConditionLabel(weather.condition);
  const durationLabel = weather.duration_minutes
    ? `${weather.duration_minutes} minute${weather.duration_minutes === 1 ? "" : "s"}`
    : "limited time";
  const remainingLabel = formatWeatherRemainingLabel(weather.remaining_ms);

  return {
    id: weather.announcement_id,
    game,
    title: `${WEATHER_GAME_LABELS[game]} Weather Active`,
    subtitle: conditionLabel,
    detail: `${conditionLabel} weather is active for ${durationLabel}.${remainingLabel ? ` ${remainingLabel}` : ""}`,
  };
}

export default function WeatherAnnouncementClient() {
  const pathname = usePathname();
  const [announcements, setAnnouncements] = useState<WeatherAnnouncement[]>([]);
  const dismissalTimersRef = useRef<Map<string, number>>(new Map());
  const seenAnnouncementsRef = useRef<Set<string>>(new Set());
  const suppressOnPage = pathname === "/fish" || pathname === "/farm";

  const dismissAnnouncement = useCallback((announcementId: string) => {
    const pendingTimer = dismissalTimersRef.current.get(announcementId);
    if (pendingTimer) {
      window.clearTimeout(pendingTimer);
      dismissalTimersRef.current.delete(announcementId);
    }

    startTransition(() => {
      setAnnouncements((currentAnnouncements) => (
        currentAnnouncements.filter((announcement) => announcement.id !== announcementId)
      ));
    });
  }, []);

  const enqueueAnnouncement = useCallback((game: WeatherGame, weather: NormalizedWeatherState) => {
    const announcement = buildAnnouncement(game, weather);
    if (!announcement) {
      return;
    }

    // Fix H-6/N-24: Wrap localStorage in try/catch for Safari private browsing
    let alreadySeen = false;
    try {
      const storageKey = getWeatherAnnouncementStorageKey(announcement.id);
      alreadySeen = seenAnnouncementsRef.current.has(announcement.id) || window.localStorage.getItem(storageKey) === "seen";
    } catch {
      // localStorage unavailable - proceed without persistence check
    }

    if (alreadySeen) {
      return;
    }

    seenAnnouncementsRef.current.add(announcement.id);
    try {
      const storageKey = getWeatherAnnouncementStorageKey(announcement.id);
      window.localStorage.setItem(storageKey, "seen");
    } catch {
      // localStorage unavailable - continue without persistence
    }

    startTransition(() => {
      setAnnouncements((currentAnnouncements) => {
        if (currentAnnouncements.some((currentAnnouncement) => currentAnnouncement.id === announcement.id)) {
          return currentAnnouncements;
        }

        return [...currentAnnouncements, announcement];
      });
    });

    const dismissalTimer = window.setTimeout(() => {
      dismissAnnouncement(announcement.id);
    }, WEATHER_NOTIFICATION_DURATION_MS);
    dismissalTimersRef.current.set(announcement.id, dismissalTimer);
  }, [dismissAnnouncement]);

  useEffect(() => {
    if (suppressOnPage) {
      return;
    }

    let ignore = false;

    void Promise.all(
      WEATHER_GAMES.map(async (game) => {
        const response = await fetch(`/api/weather?game=${game}`, { cache: "no-store" });
        if (!response.ok) {
          return null;
        }

        const payload = await response.json() as WeatherApiResponse;
        return payload.ok && payload.weather ? { game, weather: payload.weather } : null;
      }),
    ).then((results) => {
      if (ignore) {
        return;
      }

      results.forEach((result) => {
        if (!result) {
          return;
        }

        enqueueAnnouncement(result.game, result.weather);
      });
    }).catch(() => {
      // Notification fetch failures should not interrupt page rendering.
    });

    return () => {
      ignore = true;
    };
  }, [enqueueAnnouncement, suppressOnPage]);

  useEffect(() => {
    if (suppressOnPage) {
      return;
    }

    let supabase;

    try {
      supabase = getClientSupabase();
    } catch {
      return;
    }

    const channel = supabase
      .channel("weather-announcements")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "platform_settings", filter: "key=eq.fisher_weather" },
        (payload) => {
          const nextRow = payload.new && typeof payload.new === "object"
            ? payload.new as Record<string, unknown>
            : null;
          const nextWeather = toPublicWeatherState("fisher", nextRow?.value);
          enqueueAnnouncement("fisher", nextWeather);
        },
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "platform_settings", filter: "key=eq.farmer_weather" },
        (payload) => {
          const nextRow = payload.new && typeof payload.new === "object"
            ? payload.new as Record<string, unknown>
            : null;
          const nextWeather = toPublicWeatherState("farmer", nextRow?.value);
          enqueueAnnouncement("farmer", nextWeather);
        },
      )
      .subscribe();

    // Fix N-18: Always cleanup subscription on unmount, not just when suppressOnPage changes
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [enqueueAnnouncement, suppressOnPage]);

  useEffect(() => {
    const dismissalTimers = dismissalTimersRef.current;

    return () => {
      dismissalTimers.forEach((timerId) => {
        window.clearTimeout(timerId);
      });
      dismissalTimers.clear();
    };
  }, []);

  if (suppressOnPage || announcements.length === 0) {
    return null;
  }

  return (
    <div className={styles.viewport} aria-live="polite" aria-atomic="false">
      {announcements.map((announcement) => (
        <section key={announcement.id} className={styles.toast}>
          <p className={styles.kicker}>{announcement.title}</p>
          <p className={styles.subtitle}>{announcement.subtitle}</p>
          <p className={styles.detail}>{announcement.detail}</p>
        </section>
      ))}
    </div>
  );
}
