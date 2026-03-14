(function initVirtualFarmerSupabase() {
    const STORAGE_CONFIG_KEY = "virtualFarmerSupabaseConfig";
    const SAVE_DEBOUNCE_MS = 1200;

    let client = null;
    let activeUser = null;
    let cachedProfile = null;
    let queuedSnapshot = null;
    let flushTimer = null;
    let saveInFlight = false;

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
        if (!user || typeof user !== "object") return "Farmer";
        if (typeof user.email === "string" && user.email.includes("@")) {
            const prefix = user.email.split("@")[0] || "";
            if (prefix) return prefix;
        }
        if (typeof user.id === "string" && user.id.length >= 8) {
            return `Farmer-${user.id.slice(0, 8)}`;
        }
        return "Farmer";
    }

    function sanitizeDisplayName(value, fallback = "Farmer") {
        const collapsed = String(value || "").trim().replace(/\s+/g, " ");
        const cleaned = collapsed.replace(/[^A-Za-z0-9 ._'-]/g, "").slice(0, 24).trim();
        const fallbackSafe = String(fallback || "Farmer")
            .replace(/[^A-Za-z0-9 ._'-]/g, "")
            .slice(0, 24)
            .trim();

        const candidate = cleaned || fallbackSafe || "Farmer";
        if (candidate.length >= 3) return candidate;
        return `Farmer-${Date.now().toString().slice(-6)}`;
    }

    async function upsertProfile(displayNameOverride) {
        if (!activeUser) return null;
        const supabaseClient = getClientOrThrow();
        const fallback = fallbackNameFromUser(activeUser);
        const displayName = sanitizeDisplayName(
            displayNameOverride || activeUser.user_metadata?.display_name,
            fallback
        );

        const row = {
            user_id: activeUser.id,
            display_name: displayName
        };

        const { error } = await supabaseClient
            .from("profiles")
            .upsert(row, { onConflict: "user_id" });

        if (error) throw error;
        cachedProfile = row;
        return row;
    }

    async function loadProfile() {
        if (!activeUser) {
            cachedProfile = null;
            return null;
        }

        const supabaseClient = getClientOrThrow();
        const { data, error } = await supabaseClient
            .from("profiles")
            .select("user_id, display_name")
            .eq("user_id", activeUser.id)
            .maybeSingle();

        if (error) throw error;

        if (data) {
            cachedProfile = data;
            return data;
        }

        return upsertProfile();
    }

    function setActiveUser(user) {
        activeUser = user || null;
        if (!activeUser) cachedProfile = null;
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

    async function signUp({ email, password, displayName }) {
        const fallback = String(email || "").includes("@") ? String(email).split("@")[0] : "Farmer";
        const safeName = sanitizeDisplayName(displayName, fallback || "Farmer");

        const accountBridge = window.PlatformAccountBridge;
        if (accountBridge && typeof accountBridge.signUp === "function") {
            const bridgeResult = await accountBridge.signUp({ email, password, displayName: safeName });
            if (!bridgeResult?.ok) {
                throw new Error(getBridgeErrorMessage(bridgeResult, "Sign-up failed."));
            }

            const bridgeState = bridgeResult.state || await readBridgeState(accountBridge);
            const farmerUser = bridgeState?.farmer?.user || null;
            setActiveUser(farmerUser);

            if (farmerUser) {
                try {
                    await loadProfile();
                } catch (profileError) {
                    console.error("Profile refresh failed after sign up:", profileError);
                }
            }

            return {
                user: farmerUser,
                session: bridgeState?.farmer?.session || null,
                requiresVerification: Boolean(bridgeResult.requiresVerification || !bridgeState?.farmer?.session)
            };
        }

        const supabaseClient = getClientOrThrow();
        const { data, error } = await supabaseClient.auth.signUp({
            email,
            password,
            options: {
                data: {
                    display_name: safeName
                }
            }
        });

        if (error) throw error;

        setActiveUser(data.session?.user || data.user || null);

        if (data.session?.user) {
            try {
                await upsertProfile(safeName);
            } catch (profileError) {
                console.error("Profile upsert failed after sign up:", profileError);
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

        const supabaseClient = getClientOrThrow();
        const payload = normalizeSnapshot(snapshot);

        const { error } = await supabaseClient
            .from("player_progress")
            .upsert(payload, { onConflict: "user_id" });

        if (error) throw error;

        if (!cachedProfile) {
            try {
                await upsertProfile();
            } catch (profileError) {
                console.error("Could not ensure profile while saving progress:", profileError);
            }
        }

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
            .select("user_id, display_name, total_plants, balance, xp, prestige_level, achievements_count, updated_at")
            .order(safeMetric, { ascending: false })
            .order("updated_at", { ascending: true })
            .limit(maxRows);

        if (error) throw error;
        return Array.isArray(data) ? data : [];
    }

    async function fetchLeaderboardBundle(limit = 10) {
        const [mostPlants, highestBalance, highestXP] = await Promise.all([
            fetchLeaderboard("total_plants", limit),
            fetchLeaderboard("balance", limit),
            fetchLeaderboard("xp", limit)
        ]);

        return {
            mostPlants,
            highestBalance,
            highestXP
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

    function getDisplayName() {
        if (cachedProfile && typeof cachedProfile.display_name === "string") {
            return cachedProfile.display_name;
        }
        if (activeUser?.user_metadata?.display_name) {
            return sanitizeDisplayName(activeUser.user_metadata.display_name, fallbackNameFromUser(activeUser));
        }
        return fallbackNameFromUser(activeUser);
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
        getDisplayName,
        redirectIfAuthenticated,
        signUp,
        signIn,
        signOut,
        saveProgress,
        loadProgress,
        queueSave,
        flushQueuedSave,
        fetchLeaderboard,
        fetchLeaderboardBundle,
        onAuthStateChange
    };
})();
