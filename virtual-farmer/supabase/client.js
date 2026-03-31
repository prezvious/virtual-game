(function initVirtualFarmerSupabase() {
    const STORAGE_CONFIG_KEY = "virtualFarmerSupabaseConfig";
    const SAVE_DEBOUNCE_MS = 1200;
    const PLAYTIME_GAME_KEY = "farmer";
    const PLAYTIME_FLUSH_INTERVAL_MS = 15000;

    let client = null;
    let activeUser = null;
    let cachedProfile = null;
    let queuedSnapshot = null;
    let flushTimer = null;
    let saveInFlight = false;
    let playtimeStartedAt = 0;
    let playtimePendingMs = 0;
    let playtimeFlushInFlight = false;
    let playtimeIntervalId = null;
    let playtimeLifecycleBound = false;

    function trimTrailingSlash(value) {
        return value.replace(/\/+$/, "");
    }

    function isPlaceholder(value) {
        return /YOUR_PROJECT_REF|YOUR_SUPABASE_ANON_KEY/i.test(String(value || ""));
    }

    function readStoredConfig() {
        try {
            const raw = localStorage.getItem(STORAGE_CONFIG_KEY);
            if (!raw) return {};
            const parsed = JSON.parse(raw);
            return parsed && typeof parsed === "object" ? parsed : {};
        } catch {
            return {};
        }
    }

    function readConfig() {
        const fromWindow = window.__SUPABASE_CONFIG__ && typeof window.__SUPABASE_CONFIG__ === "object"
            ? window.__SUPABASE_CONFIG__
            : {};
        const fromStorage = readStoredConfig();

        const rawUrl = String(fromWindow.url || fromStorage.url || "").trim();
        const rawAnonKey = String(fromWindow.anonKey || fromStorage.anonKey || "").trim();
        const url = isPlaceholder(rawUrl) ? "" : rawUrl;
        const anonKey = isPlaceholder(rawAnonKey) ? "" : rawAnonKey;

        return {
            url: url ? trimTrailingSlash(url) : "",
            anonKey
        };
    }

    function persistConfig(config) {
        if (!config || typeof config !== "object") return;
        const url = String(config.url || "").trim();
        const anonKey = String(config.anonKey || "").trim();
        if (!url || !anonKey) return;
        const payload = { url: trimTrailingSlash(url), anonKey };
        localStorage.setItem(STORAGE_CONFIG_KEY, JSON.stringify(payload));
    }

    function ensureClient() {
        if (client) return client;

        // Reuse the bridge's farmer client when available to prevent lock contention
        // from multiple Supabase instances sharing the same storage key.
        const bridge = window.PlatformAccountBridge;
        if (bridge && typeof bridge.getClient === "function") {
            try {
                client = bridge.getClient("farmer");
                return client;
            } catch (e) {
                console.warn("Could not reuse bridge client:", e.message);
            }
        }

        if (!window.supabase || typeof window.supabase.createClient !== "function") return null;

        const config = readConfig();
        if (!config.url || !config.anonKey) return null;

        persistConfig(config);
        client = window.supabase.createClient(config.url, config.anonKey, {
            auth: {
                persistSession: true,
                autoRefreshToken: true,
                detectSessionInUrl: true
            }
        });

        return client;
    }

    function getClientOrThrow() {
        const instance = ensureClient();
        if (!instance) {
            throw new Error("Supabase is not configured. Set window.__SUPABASE_CONFIG__ in supabase/config.js.");
        }
        return instance;
    }

    function fallbackNameFromUser(user) {
        if (!user || typeof user !== "object") return "Player";
        if (typeof user.email === "string" && user.email.includes("@")) {
            const prefix = user.email.split("@")[0] || "";
            if (prefix) return prefix;
        }
        if (typeof user.id === "string" && user.id.length >= 8) {
            return `Player-${user.id.slice(0, 8)}`;
        }
        return "Player";
    }

    function getUsername() {
        return typeof cachedProfile?.username === "string" ? cachedProfile.username : "";
    }

    async function loadProfile() {
        if (!activeUser) {
            cachedProfile = null;
            return null;
        }

        const supabaseClient = getClientOrThrow();
        const { data, error } = await supabaseClient
            .from("user_profiles")
            .select("user_id, username")
            .eq("user_id", activeUser.id)
            .maybeSingle();

        if (error) throw error;

        if (data) {
            cachedProfile = data;
            return data;
        }

        cachedProfile = {
            user_id: activeUser.id,
            username: ""
        };
        return cachedProfile;
    }

    function canTrackPlaytime() {
        if (!activeUser) return false;
        if (typeof document !== "undefined" && document.visibilityState !== "visible") return false;
        if (typeof document !== "undefined" && typeof document.hasFocus === "function") {
            return document.hasFocus();
        }
        return true;
    }

    function syncPlaytimeActivity(forcePause = false) {
        const now = Date.now();
        const shouldTrack = !forcePause && canTrackPlaytime();

        if (shouldTrack) {
            if (!playtimeStartedAt) {
                playtimeStartedAt = now;
            }
            return;
        }

        if (playtimeStartedAt) {
            playtimePendingMs += Math.max(0, now - playtimeStartedAt);
            playtimeStartedAt = 0;
        }
    }

    async function flushPlaytime() {
        if (!activeUser) return null;
        if (typeof navigator !== "undefined" && navigator.onLine === false) return null;

        syncPlaytimeActivity();
        const wholeSeconds = Math.floor(playtimePendingMs / 1000);
        if (wholeSeconds <= 0 || playtimeFlushInFlight) return null;

        playtimeFlushInFlight = true;
        try {
            const supabaseClient = getClientOrThrow();
            const { data, error } = await supabaseClient.rpc("increment_user_game_playtime", {
                p_game_key: PLAYTIME_GAME_KEY,
                p_delta_seconds: wholeSeconds
            });
            if (error) throw error;
            playtimePendingMs = Math.max(0, playtimePendingMs - (wholeSeconds * 1000));
            return data || null;
        } catch (error) {
            console.error("Playtime sync failed:", error);
            return null;
        } finally {
            playtimeFlushInFlight = false;
            syncPlaytimeActivity();
        }
    }

    function bindPlaytimeLifecycle() {
        if (playtimeLifecycleBound) return;
        playtimeLifecycleBound = true;

        document.addEventListener("visibilitychange", () => {
            if (document.visibilityState === "visible") {
                syncPlaytimeActivity();
                return;
            }
            syncPlaytimeActivity(true);
            void flushPlaytime();
        });

        window.addEventListener("focus", () => {
            syncPlaytimeActivity();
        });

        window.addEventListener("blur", () => {
            syncPlaytimeActivity(true);
            void flushPlaytime();
        });

        window.addEventListener("pagehide", () => {
            syncPlaytimeActivity(true);
            void flushPlaytime();
        });

        playtimeIntervalId = window.setInterval(() => {
            if (!activeUser) return;
            syncPlaytimeActivity();
            void flushPlaytime();
        }, PLAYTIME_FLUSH_INTERVAL_MS);
    }

    function setActiveUser(user) {
        const nextUser = user || null;
        const didUserChange = activeUser?.id !== nextUser?.id;
        if (didUserChange) {
            syncPlaytimeActivity(true);
            playtimePendingMs = 0;
        }

        activeUser = nextUser;
        if (!activeUser) cachedProfile = null;
        syncPlaytimeActivity();
    }

    async function init({ requireAuth = false, redirectTo } = {}) {
        const config = readConfig();
        if (!config.url || !config.anonKey) {
            return { configured: false, user: null, profile: null };
        }

        const supabaseClient = ensureClient();
        if (!supabaseClient) {
            return {
                configured: true,
                user: null,
                profile: null,
                error: new Error("Supabase client library was not loaded.")
            };
        }

        bindPlaytimeLifecycle();

        let sessionData;
        try {
            sessionData = await supabaseClient.auth.getSession();
        } catch (sessionError) {
            return { configured: true, user: null, profile: null, error: sessionError };
        }

        const { data, error } = sessionData;
        if (error) {
            return { configured: true, user: null, profile: null, error };
        }

        setActiveUser(data.session?.user || null);

        if (activeUser) {
            try {
                await loadProfile();
            } catch (profileError) {
                console.error("Failed to load profile:", profileError);
            }
        }

        if (requireAuth && !activeUser) {
            const target = redirectTo || "login.html";
            window.location.href = target;
        }

        return {
            configured: true,
            user: activeUser,
            profile: cachedProfile
        };
    }

    async function redirectIfAuthenticated(target = "game.html") {
        const result = await init();
        if (result.configured && result.user) {
            window.location.href = target;
            return true;
        }
        return false;
    }

    async function readBridgeState(accountBridge) {
        if (!accountBridge || typeof accountBridge.getSessionState !== "function") {
            return null;
        }

        try {
            return await accountBridge.getSessionState();
        } catch (error) {
            console.warn("Could not read platform bridge state:", error);
            return null;
        }
    }

    function getBridgeErrorMessage(result, fallbackMessage) {
        const message = typeof result?.error === "string" ? result.error.trim() : "";
        return message || fallbackMessage;
    }

    async function signUp({ email, password }) {
        const accountBridge = window.PlatformAccountBridge;
        if (accountBridge && typeof accountBridge.signUp === "function") {
            const bridgeResult = await accountBridge.signUp({ email, password });
            if (!bridgeResult?.ok) {
                throw new Error(getBridgeErrorMessage(bridgeResult, "Sign-up failed."));
            }

            const bridgeState = bridgeResult.state || await readBridgeState(accountBridge);
            const farmerUser = bridgeState?.farmer?.user || null;
            const farmerSession = bridgeState?.farmer?.session || null;
            setActiveUser(farmerUser);

            // Avoid profile reads until the user has an authenticated session token.
            if (farmerUser && farmerSession) {
                try {
                    await loadProfile();
                } catch (profileError) {
                    console.error("Profile refresh failed after sign up:", profileError);
                }
            }

            return {
                user: farmerUser,
                session: farmerSession,
                requiresVerification: Boolean(bridgeResult.requiresVerification || !farmerSession)
            };
        }

        const supabaseClient = getClientOrThrow();
        const { data, error } = await supabaseClient.auth.signUp({
            email,
            password
        });

        if (error) throw error;

        setActiveUser(data.session?.user || data.user || null);

        if (data.session?.user) {
            try {
                await loadProfile();
            } catch (profileError) {
                console.error("Profile refresh failed after sign up:", profileError);
            }
        }

        return data;
    }

    async function signIn({ email, password }) {
        const accountBridge = window.PlatformAccountBridge;
        if (accountBridge && typeof accountBridge.signIn === "function") {
            const bridgeResult = await accountBridge.signIn({ email, password });
            if (!bridgeResult?.ok) {
                throw new Error(getBridgeErrorMessage(bridgeResult, "Login failed."));
            }

            let bridgeState = bridgeResult.state || await readBridgeState(accountBridge);
            let farmerUser = bridgeState?.farmer?.user
                || bridgeResult?.details?.farmer?.user
                || bridgeResult?.details?.recovery?.farmer?.user
                || null;
            let farmerSession = bridgeState?.farmer?.session
                || bridgeResult?.details?.farmer?.session
                || bridgeResult?.details?.recovery?.farmer?.session
                || null;

            if (!farmerUser) {
                await new Promise((resolve) => setTimeout(resolve, 150));
                const refreshed = await readBridgeState(accountBridge);
                if (refreshed) {
                    bridgeState = refreshed;
                    farmerUser = refreshed?.farmer?.user || farmerUser;
                    farmerSession = refreshed?.farmer?.session || farmerSession;
                }
            }

            if (!farmerUser) {
                const warning = Array.isArray(bridgeResult.warnings) && bridgeResult.warnings.length > 0
                    ? bridgeResult.warnings[0]
                    : "Virtual Farmer account is not ready. Verify account setup and try again.";
                throw new Error(warning);
            }

            setActiveUser(farmerUser);
            try {
                await loadProfile();
            } catch (profileError) {
                console.error("Failed to load profile after unified sign in:", profileError);
            }

            return {
                user: farmerUser,
                session: farmerSession || bridgeState?.farmer?.session || null
            };
        }

        const supabaseClient = getClientOrThrow();
        const { data, error } = await supabaseClient.auth.signInWithPassword({ email, password });
        if (error) throw error;

        setActiveUser(data.user || null);
        if (activeUser) {
            try {
                await loadProfile();
            } catch (profileError) {
                console.error("Failed to load profile after sign in:", profileError);
            }
        }

        return data;
    }

    async function signOut({ redirectTo = "login.html" } = {}) {
        try {
            await flushQueuedSave();
        } catch (saveError) {
            console.error("Final cloud save failed during sign out:", saveError);
        }
        await flushPlaytime();

        const accountBridge = window.PlatformAccountBridge;
        if (accountBridge && typeof accountBridge.signOut === "function") {
            await accountBridge.signOut();
        } else {
            const supabaseClient = ensureClient();
            if (supabaseClient) {
                await supabaseClient.auth.signOut();
            }
        }

        setActiveUser(null);
        if (redirectTo) {
            window.location.href = redirectTo;
        }
    }

    function computeTotalPlants(gameState) {
        if (!gameState || typeof gameState !== "object") return 0;
        const inventory = gameState.inventory && typeof gameState.inventory === "object"
            ? gameState.inventory
            : {};
        return Object.values(inventory).reduce((sum, value) => {
            const n = Number(value);
            return sum + (Number.isFinite(n) && n > 0 ? n : 0);
        }, 0);
    }

    function normalizeSnapshot(snapshot) {
        const gameState = snapshot?.game && typeof snapshot.game === "object" ? snapshot.game : {};
        const statsState = snapshot?.stats && typeof snapshot.stats === "object" ? snapshot.stats : {};
        const autoFarmState = snapshot?.autoFarmState && typeof snapshot.autoFarmState === "object"
            ? snapshot.autoFarmState
            : {};

        const totalPlants = Number.isFinite(Number(snapshot?.totalPlants))
            ? Number(snapshot.totalPlants)
            : computeTotalPlants(gameState);

        return {
            user_id: activeUser.id,
            balance: Math.max(0, Number(gameState.balance) || 0),
            xp: Math.max(0, Number(gameState.xp) || 0),
            total_plants: Math.max(0, totalPlants),
            prestige_level: Math.max(0, Math.floor(Number(gameState.prestigeLevel) || 0)),
            achievements_count: Array.isArray(gameState.achievements) ? gameState.achievements.length : 0,
            game_state: gameState,
            stats_state: statsState,
            auto_farm_state: autoFarmState,
            last_saved_at: new Date(snapshot?.timestamp || Date.now()).toISOString()
        };
    }

    async function saveProgress(snapshot) {
        if (!activeUser) return null;
        await flushPlaytime();

        const supabaseClient = getClientOrThrow();
        const payload = normalizeSnapshot(snapshot);

        const { error } = await supabaseClient
            .from("player_progress")
            .upsert(payload, { onConflict: "user_id" });

        if (error) throw error;

        return payload;
    }

    async function loadProgress() {
        if (!activeUser) return null;

        const supabaseClient = getClientOrThrow();
        const { data, error } = await supabaseClient
            .from("player_progress")
            .select("user_id, balance, xp, total_plants, prestige_level, achievements_count, game_state, stats_state, auto_farm_state, last_saved_at, updated_at")
            .eq("user_id", activeUser.id)
            .maybeSingle();

        if (error) throw error;
        return data || null;
    }

    async function fetchLeaderboard(metric = "total_plants", limit = 10) {
        const supabaseClient = getClientOrThrow();
        const safeMetric = ["total_plants", "balance", "xp"].includes(metric) ? metric : "total_plants";
        const maxRows = Math.min(Math.max(Number(limit) || 10, 1), 100);

        const { data, error } = await supabaseClient
            .from("leaderboard")
            .select("user_id, username, total_plants, balance, xp, prestige_level, achievements_count, updated_at")
            .order(safeMetric, { ascending: false })
            .order("updated_at", { ascending: true })
            .limit(maxRows);

        if (error) throw error;
        return Array.isArray(data) ? data : [];
    }

    function looksLikeMissingRpc(error, fnName) {
        const code = String(error?.code || "").toUpperCase();
        const message = String(error?.message || "").toLowerCase();
        const loweredFn = String(fnName || "").toLowerCase();
        return code === "PGRST202"
            || code === "42883"
            || (loweredFn
                && message.includes(loweredFn)
                && (message.includes("does not exist") || message.includes("could not find")));
    }

    async function requestLeaderboardRefresh() {
        const supabaseClient = getClientOrThrow();
        const { data, error } = await supabaseClient.rpc("request_farmer_leaderboard_refresh");
        if (error) {
            if (looksLikeMissingRpc(error, "request_farmer_leaderboard_refresh")) {
                return { ok: false, refreshed: false, unsupported: true, reason: error.message || "Refresh RPC missing." };
            }
            throw error;
        }
        return data && typeof data === "object" ? data : { ok: true, refreshed: false };
    }

    function getBundleRefreshedAt(rowsByMetric, rpcRefreshData) {
        const rpcRefreshedAt = String(rpcRefreshData?.refreshed_at || "").trim();
        if (rpcRefreshedAt) return rpcRefreshedAt;

        const allRows = Array.isArray(rowsByMetric) ? rowsByMetric.flat() : [];
        let latest = 0;
        allRows.forEach((row) => {
            const ts = Date.parse(String(row?.updated_at || ""));
            if (Number.isFinite(ts)) latest = Math.max(latest, ts);
        });

        return latest > 0 ? new Date(latest).toISOString() : "";
    }

    async function fetchLeaderboardBundle(limit = 10, options = {}) {
        const opts = options && typeof options === "object" ? options : {};
        const forceRefresh = opts.forceRefresh === true;
        let refreshResult = null;

        if (forceRefresh) {
            try {
                refreshResult = await requestLeaderboardRefresh();
            } catch (refreshError) {
                console.warn("Global leaderboard refresh request failed:", refreshError);
            }
        }

        const [mostPlants, highestBalance, highestXP] = await Promise.all([
            fetchLeaderboard("total_plants", limit),
            fetchLeaderboard("balance", limit),
            fetchLeaderboard("xp", limit)
        ]);

        return {
            mostPlants,
            highestBalance,
            highestXP,
            refreshedAt: getBundleRefreshedAt([mostPlants, highestBalance, highestXP], refreshResult)
        };
    }

    function queueSave(snapshot, { immediate = false } = {}) {
        if (!activeUser) return;
        queuedSnapshot = snapshot;

        if (immediate) {
            void flushQueuedSave();
            return;
        }

        if (flushTimer) {
            clearTimeout(flushTimer);
        }

        flushTimer = setTimeout(() => {
            flushTimer = null;
            void flushQueuedSave();
        }, SAVE_DEBOUNCE_MS);
    }

    async function flushQueuedSave() {
        if (!queuedSnapshot || !activeUser) return;
        if (saveInFlight) return;

        saveInFlight = true;
        const snapshot = queuedSnapshot;
        queuedSnapshot = null;

        try {
            await saveProgress(snapshot);
        } catch (error) {
            console.error("Cloud save failed:", error);
        } finally {
            saveInFlight = false;
            if (queuedSnapshot) {
                await flushQueuedSave();
            }
        }
    }

    function getPlayerLabel() {
        const username = getUsername();
        if (username) {
            return `@${username}`;
        }
        return activeUser?.email || fallbackNameFromUser(activeUser);
    }

    function onAuthStateChange(callback) {
        const supabaseClient = ensureClient();
        if (!supabaseClient || typeof callback !== "function") {
            return () => {};
        }

        const { data } = supabaseClient.auth.onAuthStateChange(async (_event, session) => {
            setActiveUser(session?.user || null);
            if (activeUser) {
                try {
                    await loadProfile();
                } catch (error) {
                    console.error("Profile refresh failed on auth state change:", error);
                }
            }
            callback({ user: activeUser, profile: cachedProfile });
        });

        return () => {
            if (data?.subscription) {
                data.subscription.unsubscribe();
            }
        };
    }

    function isConfigured() {
        const config = readConfig();
        return Boolean(config.url && config.anonKey);
    }

    function isAuthenticated() {
        return Boolean(activeUser);
    }

    function getCurrentUser() {
        return activeUser;
    }

    window.VirtualFarmerSupabase = {
        init,
        isConfigured,
        isAuthenticated,
        getCurrentUser,
        getUsername,
        getDisplayName: getPlayerLabel,
        redirectIfAuthenticated,
        signUp,
        signIn,
        signOut,
        saveProgress,
        loadProgress,
        queueSave,
        flushQueuedSave,
        flushPlaytime,
        fetchLeaderboard,
        fetchLeaderboardBundle,
        onAuthStateChange
    };
})();
