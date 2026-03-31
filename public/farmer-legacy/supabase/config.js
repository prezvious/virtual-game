(function initVirtualFarmerRuntimeConfig() {
    const runtimeConfig = window.__PLATFORM_SUPABASE_CONFIG__ && typeof window.__PLATFORM_SUPABASE_CONFIG__ === "object"
        ? window.__PLATFORM_SUPABASE_CONFIG__
        : {};
    const sharedConfig = runtimeConfig.shared && typeof runtimeConfig.shared === "object"
        ? runtimeConfig.shared
        : {};
    const farmerConfig = runtimeConfig.farmer && typeof runtimeConfig.farmer === "object"
        ? runtimeConfig.farmer
        : {};

    window.__SUPABASE_CONFIG__ = {
        url: String(farmerConfig.url || sharedConfig.url || "").trim(),
        anonKey: String(farmerConfig.anonKey || sharedConfig.anonKey || "").trim()
    };
})();
