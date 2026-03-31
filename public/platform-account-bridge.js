(function initPlatformAccountBridge() {
    const PROJECTS = {
        fisher: {
            name: 'fisher',
            label: 'Virtual Fisher'
        },
        farmer: {
            name: 'farmer',
            label: 'Virtual Farmer'
        }
    };

    const clients = {
        fisher: null,
        farmer: null
    };
    let sharedSessionStatePromise = null;

    function sanitizeText(value) {
        return String(value || '').trim();
    }

    function getRuntimePlatformConfig() {
        const config = window.__PLATFORM_SUPABASE_CONFIG__;
        return config && typeof config === 'object' ? config : {};
    }

    function resolveProjectConfig(project) {
        const runtimeConfig = getRuntimePlatformConfig();
        const shared = runtimeConfig.shared && typeof runtimeConfig.shared === 'object'
            ? runtimeConfig.shared
            : {};
        const projectRuntime = runtimeConfig[project.name] && typeof runtimeConfig[project.name] === 'object'
            ? runtimeConfig[project.name]
            : {};

        return {
            name: project.name,
            label: project.label,
            url: sanitizeText(projectRuntime.url || shared.url),
            anonKey: sanitizeText(projectRuntime.anonKey || shared.anonKey)
        };
    }

    function hasProjectConfig(config) {
        const url = sanitizeText(config && config.url);
        const anonKey = sanitizeText(config && config.anonKey);
        if (!url || !anonKey) return false;
        return !/YOUR_PROJECT_REF|YOUR_SUPABASE_ANON_KEY/i.test(`${url} ${anonKey}`);
    }

    function getConfigurationError() {
        const fisherConfig = getProjectConfig('fisher');
        const farmerConfig = getProjectConfig('farmer');
        const missing = [];
        if (!hasProjectConfig(fisherConfig)) missing.push(fisherConfig.label);
        if (!hasProjectConfig(farmerConfig)) missing.push(farmerConfig.label);
        if (!missing.length) return '';
        return `${missing.join(' and ')} account sync is not configured for this local copy.`;
    }

    function usesSharedAuthBackend() {
        const fisherConfig = getProjectConfig('fisher');
        const farmerConfig = getProjectConfig('farmer');
        if (!hasProjectConfig(fisherConfig) || !hasProjectConfig(farmerConfig)) {
            return false;
        }
        return fisherConfig.url === farmerConfig.url
            && fisherConfig.anonKey === farmerConfig.anonKey;
    }

    function ensureEmail(value) {
        const email = sanitizeText(value).toLowerCase();
        if (!email || !email.includes('@')) {
            throw new Error('A valid email address is required.');
        }
        return email;
    }

    function ensurePassword(value) {
        const password = String(value || '');
        if (!password) {
            throw new Error('Password is required.');
        }
        return password;
    }

    function getSupabaseFactory() {
        if (!window.supabase || typeof window.supabase.createClient !== 'function') {
            throw new Error('Supabase client library is not available.');
        }
        return window.supabase.createClient;
    }

    function getProjectConfig(name) {
        const project = PROJECTS[name] || null;
        return project ? resolveProjectConfig(project) : null;
    }

    function getClient(name) {
        const key = name === 'farmer' ? 'farmer' : 'fisher';

        // When both games share the same Supabase project, reuse a single
        // client instance to prevent navigator.locks contention.
        if (key === 'farmer' && usesSharedAuthBackend()) {
            if (!clients.fisher) {
                getClient('fisher');
            }
            return clients.fisher;
        }

        if (clients[key]) {
            return clients[key];
        }

        const config = getProjectConfig(key);
        if (!config) {
            throw new Error(`Unknown account project: ${name}`);
        }
        if (!hasProjectConfig(config)) {
            throw new Error(`${config.label} account sync is not configured for this local copy.`);
        }

        const createClient = getSupabaseFactory();
        clients[key] = createClient(config.url, config.anonKey, {
            auth: {
                persistSession: true,
                autoRefreshToken: true,
                detectSessionInUrl: false
            }
        });

        return clients[key];
    }

    function normalizeError(error) {
        if (!error) return '';
        if (typeof error === 'string') return error;
        if (typeof error.message === 'string' && error.message.trim()) return error.message.trim();
        return 'Unknown authentication error.';
    }

    function isAlreadyRegisteredError(errorMessage) {
        const text = sanitizeText(errorMessage).toLowerCase();
        return text.includes('already registered')
            || text.includes('already been registered')
            || text.includes('already exists')
            || text.includes('duplicate key');
    }

    async function readProjectSession(name) {
        const config = getProjectConfig(name);
        if (!config) {
            return {
                project: name,
                label: name,
                ok: false,
                user: null,
                session: null,
                error: 'Unknown account project.'
            };
        }
        if (!hasProjectConfig(config)) {
            return {
                project: name,
                label: config.label,
                ok: false,
                user: null,
                session: null,
                error: `${config.label} account sync is not configured for this local copy.`
            };
        }

        try {
            const client = getClient(name);
            const { data, error } = await client.auth.getSession();
            if (error) {
                return {
                    project: name,
                    label: config.label,
                    ok: false,
                    user: null,
                    session: null,
                    error: normalizeError(error)
                };
            }

            return {
                project: name,
                label: config.label,
                ok: true,
                user: data && data.session ? data.session.user : null,
                session: data ? data.session : null,
                error: ''
            };
        } catch (error) {
            return {
                project: name,
                label: config.label,
                ok: false,
                user: null,
                session: null,
                error: normalizeError(error)
            };
        }
    }

    async function getSessionState() {
        if (usesSharedAuthBackend()) {
            if (!sharedSessionStatePromise) {
                sharedSessionStatePromise = readProjectSession('fisher')
                    .then((sharedState) => {
                        const fisherConfig = getProjectConfig('fisher');
                        const farmerConfig = getProjectConfig('farmer');
                        const sharedUser = sharedState.user || null;
                        const sharedSession = sharedState.session || null;
                        const sharedOk = sharedUser ? true : sharedState.ok;
                        const sharedError = sharedUser ? '' : sharedState.error;

                        const fisher = {
                            ...sharedState,
                            project: 'fisher',
                            label: fisherConfig.label,
                            ok: sharedOk,
                            user: sharedUser,
                            session: sharedSession,
                            error: sharedError
                        };

                        const farmer = {
                            ...fisher,
                            project: 'farmer',
                            label: farmerConfig.label
                        };

                        const primaryUser = sharedUser;
                        return {
                            fisher,
                            farmer,
                            primaryUser,
                            isSignedIn: Boolean(primaryUser),
                            isFullyLinked: Boolean(primaryUser)
                        };
                    })
                    .finally(() => {
                        sharedSessionStatePromise = null;
                    });
            }

            return sharedSessionStatePromise;
        }

        let [fisher, farmer] = await Promise.all([
            readProjectSession('fisher'),
            readProjectSession('farmer')
        ]);

        if (usesSharedAuthBackend()) {
            const sharedUser = fisher.user || farmer.user || null;
            const sharedSession = fisher.session || farmer.session || null;

            if (sharedUser) {
                fisher = {
                    ...fisher,
                    ok: true,
                    user: sharedUser,
                    session: sharedSession,
                    error: ''
                };
                farmer = {
                    ...farmer,
                    ok: true,
                    user: sharedUser,
                    session: sharedSession,
                    error: ''
                };
            }
        }

        const primaryUser = fisher.user || farmer.user || null;
        return {
            fisher,
            farmer,
            primaryUser,
            isSignedIn: Boolean(primaryUser),
            isFullyLinked: usesSharedAuthBackend()
                ? Boolean(primaryUser)
                : Boolean(fisher.user && farmer.user)
        };
    }

    function mergeProjectState(baseProjectState, candidates) {
        const next = {
            ...baseProjectState
        };

        for (const candidate of candidates) {
            if (!candidate) continue;
            if (!next.user && candidate.user) next.user = candidate.user;
            if (!next.session && candidate.session) next.session = candidate.session;
            if (!next.error && candidate.error) next.error = candidate.error;
            next.ok = Boolean(next.ok || candidate.ok || next.user || next.session);
        }

        if (next.ok) {
            next.error = '';
        }

        return next;
    }

    function mergeSessionState(baseState, overlays = {}) {
        const fisher = mergeProjectState(baseState.fisher, [
            overlays.fisherLogin,
            overlays.fisherProvision
        ]);

        const farmer = mergeProjectState(baseState.farmer, [
            overlays.farmerLogin,
            overlays.farmerProvision
        ]);

        const primaryUser = fisher.user || farmer.user || null;
        return {
            ...baseState,
            fisher,
            farmer,
            primaryUser,
            isSignedIn: Boolean(primaryUser),
            isFullyLinked: Boolean(fisher.user && farmer.user)
        };
    }

    function getAuthPayload(input) {
        const email = ensureEmail(input && input.email);
        const password = ensurePassword(input && input.password);
        return { email, password };
    }

    function fisherSignUpOptions() {
        return {
            emailRedirectTo: `${window.location.origin}/auth/callback`
        };
    }

    function farmerSignUpOptions() {
        return {};
    }

    async function attemptSignIn(name, payload) {
        const client = getClient(name);
        try {
            const { data, error } = await client.auth.signInWithPassword({
                email: payload.email,
                password: payload.password
            });

            return {
                project: name,
                ok: !error,
                user: data ? data.user || data.session?.user || null : null,
                session: data ? data.session || null : null,
                error: normalizeError(error)
            };
        } catch (error) {
            return {
                project: name,
                ok: false,
                user: null,
                session: null,
                error: normalizeError(error)
            };
        }
    }

    async function attemptProvision(name, payload) {
        const client = getClient(name);
        const options = name === 'fisher'
            ? fisherSignUpOptions()
            : farmerSignUpOptions();

        try {
            const { data, error } = await client.auth.signUp({
                email: payload.email,
                password: payload.password,
                options
            });

            if (error) {
                return {
                    project: name,
                    ok: false,
                    provisioned: false,
                    needsVerification: false,
                    error: normalizeError(error)
                };
            }

            const session = data ? data.session || null : null;
            return {
                project: name,
                ok: Boolean(session),
                provisioned: true,
                needsVerification: !session,
                user: data ? data.user || session?.user || null : null,
                session,
                error: ''
            };
        } catch (error) {
            return {
                project: name,
                ok: false,
                provisioned: false,
                needsVerification: false,
                user: null,
                session: null,
                error: normalizeError(error)
            };
        }
    }

    async function signIn(input) {
        const configurationError = getConfigurationError();
        if (configurationError) {
            return {
                ok: false,
                state: await getSessionState(),
                error: configurationError,
                warnings: []
            };
        }

        const payload = getAuthPayload(input || {});
        const sharedBackend = usesSharedAuthBackend();

        let fisherLogin;
        let farmerLogin;

        if (sharedBackend) {
            fisherLogin = await attemptSignIn('fisher', payload);
            farmerLogin = { ...fisherLogin, project: 'farmer' };
        } else {
            [fisherLogin, farmerLogin] = await Promise.all([
                attemptSignIn('fisher', payload),
                attemptSignIn('farmer', payload)
            ]);
        }

        const warnings = [];
        const recovery = {};

        const anyLoginSuccess = fisherLogin.ok || farmerLogin.ok;

        if (!sharedBackend && anyLoginSuccess && !fisherLogin.ok) {
            const provision = await attemptProvision('fisher', payload);
            recovery.fisher = provision;
            if (!provision.ok) {
                if (provision.needsVerification) {
                    warnings.push('Virtual Fisher account needs email verification to finish linking.');
                } else if (!isAlreadyRegisteredError(provision.error)) {
                    warnings.push(`Virtual Fisher link issue: ${provision.error}`);
                }
            }
        }

        if (!sharedBackend && anyLoginSuccess && !farmerLogin.ok) {
            const provision = await attemptProvision('farmer', payload);
            recovery.farmer = provision;
            if (!provision.ok) {
                if (provision.needsVerification) {
                    warnings.push('Virtual Farmer account needs email verification to finish linking.');
                } else if (!isAlreadyRegisteredError(provision.error)) {
                    warnings.push(`Virtual Farmer link issue: ${provision.error}`);
                }
            }
        }

        const rawState = await getSessionState();
        const state = mergeSessionState(rawState, {
            fisherLogin,
            farmerLogin,
            fisherProvision: recovery.fisher,
            farmerProvision: recovery.farmer
        });

        if (!state.isSignedIn) {
            const firstError = fisherLogin.error || farmerLogin.error || 'Login failed. Check your credentials.';
            return {
                ok: false,
                state,
                error: firstError,
                warnings,
                details: {
                    fisher: fisherLogin,
                    farmer: farmerLogin,
                    recovery
                }
            };
        }

        if (!state.isFullyLinked) {
            warnings.push('Account is signed in, but one game still needs linking. Use Create Account to complete linking.');
        }

        return {
            ok: true,
            state,
            warnings,
            details: {
                fisher: fisherLogin,
                farmer: farmerLogin,
                recovery
            }
        };
    }

    async function signUp(input) {
        const configurationError = getConfigurationError();
        if (configurationError) {
            return {
                ok: false,
                state: await getSessionState(),
                error: configurationError,
                warnings: []
            };
        }

        const payload = getAuthPayload(input || {});
        const sharedBackend = usesSharedAuthBackend();

        let fisherResult;
        let farmerResult;

        if (sharedBackend) {
            const fisherClient = getClient('fisher');
            fisherResult = await fisherClient.auth.signUp({
                email: payload.email,
                password: payload.password,
                options: fisherSignUpOptions()
            });
            farmerResult = {
                data: fisherResult.data,
                error: fisherResult.error
            };
        } else {
            const fisherClient = getClient('fisher');
            const farmerClient = getClient('farmer');

            [fisherResult, farmerResult] = await Promise.all([
                fisherClient.auth.signUp({
                    email: payload.email,
                    password: payload.password,
                    options: fisherSignUpOptions()
                }),
                farmerClient.auth.signUp({
                    email: payload.email,
                    password: payload.password,
                    options: farmerSignUpOptions()
                })
            ]);
        }

        const fisherError = normalizeError(fisherResult.error);
        const farmerError = normalizeError(farmerResult.error);

        if (fisherResult.error && farmerResult.error) {
            const bothAlreadyRegistered = isAlreadyRegisteredError(fisherError) && isAlreadyRegisteredError(farmerError);
            if (bothAlreadyRegistered) {
                return signIn(payload);
            }

            return {
                ok: false,
                state: await getSessionState(),
                error: fisherError || farmerError || 'Account creation failed.',
                warnings: []
            };
        }

        const warnings = [];
        if (fisherResult.error && !isAlreadyRegisteredError(fisherError)) {
            warnings.push(`Virtual Fisher signup issue: ${fisherError}`);
        }
        if (!sharedBackend && farmerResult.error && !isAlreadyRegisteredError(farmerError)) {
            warnings.push(`Virtual Farmer signup issue: ${farmerError}`);
        }

        const rawState = await getSessionState();
        const state = mergeSessionState(rawState, {
            fisherLogin: {
                ok: !fisherResult.error,
                user: fisherResult.data?.user || fisherResult.data?.session?.user || null,
                session: fisherResult.data?.session || null,
                error: fisherError
            },
            farmerLogin: {
                ok: !farmerResult.error,
                user: farmerResult.data?.user || farmerResult.data?.session?.user || null,
                session: farmerResult.data?.session || null,
                error: farmerError
            }
        });
        const fisherNeedsVerification = Boolean(fisherResult.data?.user && !fisherResult.data?.session);
        const farmerNeedsVerification = sharedBackend
            ? fisherNeedsVerification
            : Boolean(farmerResult.data?.user && !farmerResult.data?.session);

        if (fisherNeedsVerification || farmerNeedsVerification) {
            warnings.push('Check your email to verify account access before full sync is available.');
        }

        return {
            ok: true,
            state,
            warnings,
            requiresVerification: fisherNeedsVerification || farmerNeedsVerification
        };
    }

    async function signOut() {
        if (getConfigurationError()) {
            return getSessionState();
        }

        if (usesSharedAuthBackend()) {
            const fisherClient = getClient('fisher');
            await fisherClient.auth.signOut();
        } else {
            const fisherClient = getClient('fisher');
            const farmerClient = getClient('farmer');

            await Promise.allSettled([
                fisherClient.auth.signOut(),
                farmerClient.auth.signOut()
            ]);
        }

        return getSessionState();
    }

    window.PlatformAccountBridge = {
        version: '2026-04-01b',
        getSessionState,
        signIn,
        signUp,
        signOut,
        getClient
    };
})();
