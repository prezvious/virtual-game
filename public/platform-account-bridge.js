(function initPlatformAccountBridge() {
    const FISHER_CONFIG = {
        name: 'fisher',
        label: 'Virtual Fisher',
        url: 'https://wlyrmqfaiixoohdyizam.supabase.co',
        anonKey: 'sb_publishable_h3m3EuajBFphREc0LpVN3g_PWcWv9gM'
    };

    const FARMER_CONFIG = {
        name: 'farmer',
        label: 'Virtual Farmer',
        url: 'https://nunhsqvospdmtyrceljr.supabase.co',
        anonKey: 'sb_publishable_8xg5zRZch29kT_wVLQJgEA_GoL7WQZl'
    };

    const PROJECTS = {
        fisher: FISHER_CONFIG,
        farmer: FARMER_CONFIG
    };

    const clients = {
        fisher: null,
        farmer: null
    };

    function sanitizeText(value) {
        return String(value || '').trim();
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

    function buildDisplayName(value, email) {
        const candidate = sanitizeText(value)
            .replace(/\s+/g, ' ')
            .replace(/[^A-Za-z0-9 ._'-]/g, '')
            .slice(0, 24)
            .trim();

        if (candidate.length >= 3) {
            return candidate;
        }

        const prefix = sanitizeText(email.split('@')[0])
            .replace(/[^A-Za-z0-9 ._'-]/g, '')
            .slice(0, 24)
            .trim();

        if (prefix.length >= 3) {
            return prefix;
        }

        return 'Player';
    }

    function getSupabaseFactory() {
        if (!window.supabase || typeof window.supabase.createClient !== 'function') {
            throw new Error('Supabase client library is not available.');
        }
        return window.supabase.createClient;
    }

    function getProjectConfig(name) {
        return PROJECTS[name] || null;
    }

    function getClient(name) {
        const key = name === 'farmer' ? 'farmer' : 'fisher';
        if (clients[key]) {
            return clients[key];
        }

        const config = getProjectConfig(key);
        if (!config) {
            throw new Error(`Unknown account project: ${name}`);
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
        const client = getClient(name);

        try {
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
        const [fisher, farmer] = await Promise.all([
            readProjectSession('fisher'),
            readProjectSession('farmer')
        ]);

        const primaryUser = fisher.user || farmer.user || null;
        return {
            fisher,
            farmer,
            primaryUser,
            isSignedIn: Boolean(primaryUser),
            isFullyLinked: Boolean(fisher.user && farmer.user)
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
        const displayName = buildDisplayName(input && input.displayName, email);
        return { email, password, displayName };
    }

    function fisherSignUpOptions(displayName) {
        return {
            emailRedirectTo: `${window.location.origin}/auth/callback`,
            data: {
                display_name: displayName
            }
        };
    }

    function farmerSignUpOptions(displayName) {
        return {
            data: {
                display_name: displayName
            }
        };
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
            ? fisherSignUpOptions(payload.displayName)
            : farmerSignUpOptions(payload.displayName);

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
        const payload = getAuthPayload(input || {});

        const [fisherLogin, farmerLogin] = await Promise.all([
            attemptSignIn('fisher', payload),
            attemptSignIn('farmer', payload)
        ]);

        const warnings = [];
        const recovery = {};

        const anyLoginSuccess = fisherLogin.ok || farmerLogin.ok;

        if (anyLoginSuccess && !fisherLogin.ok) {
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

        if (anyLoginSuccess && !farmerLogin.ok) {
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
        const payload = getAuthPayload(input || {});

        const fisherClient = getClient('fisher');
        const farmerClient = getClient('farmer');

        const [fisherResult, farmerResult] = await Promise.all([
            fisherClient.auth.signUp({
                email: payload.email,
                password: payload.password,
                options: fisherSignUpOptions(payload.displayName)
            }),
            farmerClient.auth.signUp({
                email: payload.email,
                password: payload.password,
                options: farmerSignUpOptions(payload.displayName)
            })
        ]);

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
        if (farmerResult.error && !isAlreadyRegisteredError(farmerError)) {
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
        const farmerNeedsVerification = Boolean(farmerResult.data?.user && !farmerResult.data?.session);

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
        const fisherClient = getClient('fisher');
        const farmerClient = getClient('farmer');

        await Promise.allSettled([
            fisherClient.auth.signOut(),
            farmerClient.auth.signOut()
        ]);

        return getSessionState();
    }

    window.PlatformAccountBridge = {
        version: '2026-03-14b',
        getSessionState,
        signIn,
        signUp,
        signOut
    };
})();
