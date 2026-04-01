/**
 * CLOUD EXTENSIONS
 * Adds public leaderboard rendering and shared username awareness on top of CloudSystem.
 */

(function () {
    if (typeof CloudSystem === 'undefined') return;

    const USERNAME_PATTERN = /^[A-Za-z][A-Za-z0-9_]{2,19}$/;
    const USERNAME_RESERVED = new Set([
        'admin', 'administrator', 'system', 'support', 'staff',
        'moderator', 'mod', 'owner', 'developer', 'team',
        'supabase', 'postgres', 'root', 'null', 'undefined',
        'fishit', 'virtualfisher'
    ]);
    const LEADERBOARD_REFRESH_MS = 20 * 60 * 1000;
    const LEADERBOARD_ENTRY_LIMIT = 10;
    const LEADERBOARD_FETCH_TIMEOUT_MS = 15000;
    const LEADERBOARD_AUTH_LOCK_RETRY_ATTEMPTS = 3;
    const LEADERBOARD_AUTH_LOCK_RETRY_DELAY_MS = 250;
    const LEADERBOARD_TRANSIENT_RETRY_DELAY_MS = 4000;
    const USERNAME_AUTH_LOCK_RETRY_ATTEMPTS = 2;
    const USERNAME_AUTH_LOCK_RETRY_DELAY_MS = 180;

    const extensionSupabaseClient = (typeof cloudSupabaseClient !== 'undefined' && cloudSupabaseClient)
        ? cloudSupabaseClient
        : null;

    CloudSystem.profile = null;
    CloudSystem.usernamePromptRequired = false;
    CloudSystem.usernamePromptSkippedThisSession = false;
    CloudSystem.usernameInputsBound = false;
    CloudSystem.usernameWatcherBound = false;
    CloudSystem.usernameDebounceTimers = {};
    CloudSystem.usernameRequestTokens = {};
    CloudSystem.leaderboardTimer = null;
    CloudSystem.lastLeaderboardRefreshedAt = 0;
    CloudSystem.leaderboardRefreshInFlight = false;
    CloudSystem.leaderboardRefreshCooldownUntil = 0;
    CloudSystem.leaderboardRefreshRpcUnavailable = false;
    CloudSystem.leaderboardCachedRows = [];
    CloudSystem.leaderboardRetryTimer = null;

    CloudSystem._escapeHtml = function (value) {
        const str = String(value == null ? '' : value);
        return str
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    };

    CloudSystem._normalizeUsername = function (value) {
        return String(value || '').trim().toLowerCase();
    };

    CloudSystem._validateUsernameLocally = function (value) {
        const normalized = this._normalizeUsername(value);

        if (!normalized) {
            return { ok: false, normalized, reason: 'Username is required.' };
        }
        if (normalized.length < 3 || normalized.length > 20) {
            return { ok: false, normalized, reason: 'Username must be 3-20 characters.' };
        }
        if (!USERNAME_PATTERN.test(normalized)) {
            return { ok: false, normalized, reason: 'Use letters, numbers, underscores, and start with a letter.' };
        }
        if (normalized.includes('__')) {
            return { ok: false, normalized, reason: 'Username cannot contain consecutive underscores.' };
        }
        if (USERNAME_RESERVED.has(normalized)) {
            return { ok: false, normalized, reason: 'That username is reserved.' };
        }

        return { ok: true, normalized, reason: 'Username format looks good.' };
    };

    CloudSystem._setInlineUsernameFeedback = function (elementId, message, tone = 'neutral') {
        const el = document.getElementById(elementId);
        if (!el) return;

        el.textContent = message || '';
        el.classList.remove('is-ok', 'is-error');

        if (!message) return;
        if (tone === 'ok') {
            el.classList.add('is-ok');
        } else if (tone === 'error') {
            el.classList.add('is-error');
        }
    };
    CloudSystem._wait = function (delayMs) {
        return new Promise((resolve) => {
            setTimeout(resolve, Math.max(0, Number(delayMs) || 0));
        });
    };
    CloudSystem._isAuthLockContentionError = function (error) {
        const message = String(typeof error === 'string' ? error : error?.message || '').toLowerCase();
        return message.includes('auth-token')
            && (message.includes('another request stole it') || message.includes('was released because another request stole it'));
    };
    CloudSystem._looksLikeRpcSignatureCacheError = function (error, fnName) {
        const message = String(error?.message || '');
        return /schema cache/i.test(message) && message.includes(fnName);
    };

    CloudSystem._formatUsernameRpcError = function (fnName, error) {
        const fallbackMessage = 'Could not verify username availability.';
        if (!error) return fallbackMessage;

        if (this._isAuthLockContentionError(error)) {
            return 'Session sync is still finishing. Try saving your username again in a moment.';
        }

        if (this._looksLikeRpcSignatureCacheError(error, fnName)) {
            return 'Username service is not installed on the database yet. Apply migration 20260309_usernames_and_leaderboards.sql.';
        }

        return error.message || fallbackMessage;
    };

    CloudSystem._isConsecutiveUnderscoreFalsePositive = function (reason, candidate = '') {
        const message = String(reason || '').toLowerCase();
        const normalized = this._normalizeUsername(candidate);
        return message.includes('consecutive underscore')
            && normalized.length > 0
            && !normalized.includes('__');
    };

    CloudSystem._saveUsernameWithoutRpc = async function (normalizedCandidate) {
        if (!extensionSupabaseClient) {
            return { ok: false, reason: 'Supabase is not available.' };
        }
        if (!this.user?.id) {
            return { ok: false, reason: 'You must be logged in first.' };
        }

        for (let attempt = 1; attempt <= USERNAME_AUTH_LOCK_RETRY_ATTEMPTS; attempt += 1) {
            try {
                const { data, error } = await extensionSupabaseClient
                    .from('user_profiles')
                    .upsert({
                        user_id: this.user.id,
                        username: normalizedCandidate,
                        username_normalized: normalizedCandidate,
                        username_set_at: new Date().toISOString()
                    }, { onConflict: 'user_id' })
                    .select('username, username_normalized, username_set_at')
                    .single();

                if (error) {
                    if (this._isAuthLockContentionError(error) && attempt < USERNAME_AUTH_LOCK_RETRY_ATTEMPTS) {
                        await this._wait(USERNAME_AUTH_LOCK_RETRY_DELAY_MS * attempt);
                        continue;
                    }
                    if (this._isAuthLockContentionError(error)) {
                        return { ok: false, reason: 'Session sync is still finishing. Try saving your username again in a moment.' };
                    }

                    const code = String(error.code || '').toUpperCase();
                    if (code === '23505') {
                        return { ok: false, reason: 'That username is already in use.' };
                    }
                    return { ok: false, reason: error.message || 'Could not save username.' };
                }

                return {
                    ok: true,
                    username: data?.username || normalizedCandidate,
                    normalized: data?.username_normalized || normalizedCandidate,
                    username_set_at: data?.username_set_at || new Date().toISOString()
                };
            } catch (err) {
                if (this._isAuthLockContentionError(err) && attempt < USERNAME_AUTH_LOCK_RETRY_ATTEMPTS) {
                    await this._wait(USERNAME_AUTH_LOCK_RETRY_DELAY_MS * attempt);
                    continue;
                }
                if (this._isAuthLockContentionError(err)) {
                    return { ok: false, reason: 'Session sync is still finishing. Try saving your username again in a moment.' };
                }
                return { ok: false, reason: err?.message || 'Could not save username.' };
            }
        }

        return { ok: false, reason: 'Could not save username.' };
    };

    CloudSystem._callUsernameRpc = async function (fnName, candidate) {
        const payloads = [
            { candidate },
            { p_candidate: candidate }
        ];

        for (let attempt = 1; attempt <= USERNAME_AUTH_LOCK_RETRY_ATTEMPTS; attempt += 1) {
            let firstError = null;
            let lockError = null;

            for (const payload of payloads) {
                try {
                    const { data, error } = await extensionSupabaseClient.rpc(fnName, payload);
                    if (!error) return { data, error: null };
                    if (!firstError) firstError = error;

                    if (this._isAuthLockContentionError(error)) {
                        lockError = error;
                        continue;
                    }

                    if (!this._looksLikeRpcSignatureCacheError(error, fnName)) {
                        return { data: null, error };
                    }
                } catch (err) {
                    if (!firstError) firstError = err;

                    if (this._isAuthLockContentionError(err)) {
                        lockError = err;
                        continue;
                    }

                    return { data: null, error: err };
                }
            }

            if (lockError && attempt < USERNAME_AUTH_LOCK_RETRY_ATTEMPTS) {
                await this._wait(USERNAME_AUTH_LOCK_RETRY_DELAY_MS * attempt);
                continue;
            }

            return { data: null, error: lockError || firstError };
        }

        return { data: null, error: new Error('Could not reach the username service.') };
    };

    CloudSystem._toBooleanLike = function (value) {
        if (typeof value === 'boolean') return value;
        if (typeof value === 'number') {
            if (value === 1) return true;
            if (value === 0) return false;
            return null;
        }
        if (typeof value === 'string') {
            const normalized = value.trim().toLowerCase();
            if (['true', 't', '1', 'yes', 'y'].includes(normalized)) return true;
            if (['false', 'f', '0', 'no', 'n'].includes(normalized)) return false;
        }
        return null;
    };

    CloudSystem._normalizeUsernameAvailabilityPayload = function (data, fallbackNormalized = '') {
        let payload = data;

        if (typeof payload === 'string') {
            try {
                payload = JSON.parse(payload);
            } catch (_err) {
                payload = { reason: payload };
            }
        }

        if (Array.isArray(payload)) {
            payload = payload.length > 0 ? payload[0] : {};
        }

        if (!payload || typeof payload !== 'object') {
            payload = {};
        }

        const rawAvailable = payload.available ?? payload.is_available ?? payload.isAvailable;
        let available = this._toBooleanLike(rawAvailable);

        const reasonText = String(payload.reason || '').trim();
        if (reasonText) {
            const reasonLower = reasonText.toLowerCase();
            const reasonSaysUnavailable = reasonLower.includes('already in use')
                || reasonLower.includes('already exists')
                || reasonLower.includes('unavailable')
                || reasonLower.includes('not available')
                || reasonLower.includes('reserved')
                || reasonLower.includes('taken');
            const reasonSaysAvailable = reasonLower.includes('is available')
                || reasonLower === 'available'
                || reasonLower.includes('username available');

            if (reasonSaysUnavailable) {
                available = false;
            } else if (available === null && reasonSaysAvailable) {
                available = true;
            }
        }

        if (available === null) {
            // Fail closed so uncertain payloads never show false positives.
            available = false;
        }

        return {
            available,
            normalized: String(payload.normalized || payload.username || fallbackNormalized || '').trim().toLowerCase(),
            reason: reasonText
        };
    };

    CloudSystem.checkUsernameAvailability = async function (value) {
        const local = this._validateUsernameLocally(value);
        if (!local.ok) {
            return { ok: false, available: false, normalized: local.normalized, reason: local.reason };
        }

        if (!extensionSupabaseClient) {
            return { ok: false, available: false, normalized: local.normalized, reason: 'Supabase is not available.' };
        }

        try {
            const { data, error } = await this._callUsernameRpc('check_username_availability', local.normalized);

            if (error) {
                return {
                    ok: false,
                    available: false,
                    normalized: local.normalized,
                    reason: this._formatUsernameRpcError('check_username_availability', error)
                };
            }

            const parsed = this._normalizeUsernameAvailabilityPayload(data, local.normalized);
            const available = parsed.available === true;
            return {
                ok: true,
                available,
                normalized: parsed.normalized || local.normalized,
                reason: parsed.reason || (available ? 'Username is available.' : 'That username is already in use.')
            };
        } catch (err) {
            return {
                ok: false,
                available: false,
                normalized: local.normalized,
                reason: `Could not verify username availability: ${err?.message || 'Network error.'}`
            };
        }
    };

    CloudSystem._scheduleUsernameAvailabilityCheck = function (inputId, feedbackId) {
        const input = document.getElementById(inputId);
        if (!input) return;

        const rawValue = input.value;
        const local = this._validateUsernameLocally(rawValue);

        if (!rawValue.trim()) {
            this._setInlineUsernameFeedback(feedbackId, '');
            return;
        }

        if (!local.ok) {
            this._setInlineUsernameFeedback(feedbackId, local.reason, 'error');
            return;
        }

        this._setInlineUsernameFeedback(feedbackId, 'Checking availability...', 'neutral');

        if (this.usernameDebounceTimers[inputId]) {
            clearTimeout(this.usernameDebounceTimers[inputId]);
        }

        const token = Date.now() + Math.random();
        this.usernameRequestTokens[inputId] = token;

        this.usernameDebounceTimers[inputId] = setTimeout(async () => {
            const activeInput = document.getElementById(inputId);
            if (!activeInput) return;
            const latest = activeInput.value;

            try {
                const check = await this.checkUsernameAvailability(latest);
                if (this.usernameRequestTokens[inputId] !== token) return;

                if (check.ok && check.available) {
                    this._setInlineUsernameFeedback(feedbackId, check.reason, 'ok');
                } else if (
                    inputId === 'username-required-input'
                    && this._isConsecutiveUnderscoreFalsePositive(check.reason, check.normalized || latest)
                ) {
                    this._setInlineUsernameFeedback(
                        feedbackId,
                        'Username service is outdated. Save anyway and it will be checked on submit.',
                        'neutral'
                    );
                } else {
                    this._setInlineUsernameFeedback(feedbackId, check.reason, 'error');
                }
            } catch (err) {
                if (this.usernameRequestTokens[inputId] !== token) return;
                this._setInlineUsernameFeedback(
                    feedbackId,
                    `Could not verify availability: ${err?.message || 'Network error.'}`,
                    'error'
                );
            }
        }, 240);
    };

    CloudSystem._bindUsernameInputs = function () {
        if (this.usernameInputsBound) return;
        this.usernameInputsBound = true;

        const signupInput = document.getElementById('auth-username');
        if (signupInput) {
            signupInput.addEventListener('input', () => {
                this._scheduleUsernameAvailabilityCheck('auth-username', 'auth-username-feedback');
            });
        }

        const requiredInput = document.getElementById('username-required-input');
        if (requiredInput) {
            requiredInput.addEventListener('input', () => {
                this._scheduleUsernameAvailabilityCheck('username-required-input', 'username-required-availability');
            });
        }
    };

    CloudSystem._setUsernameModalFeedback = function (message, tone = 'normal') {
        const el = document.getElementById('username-form-feedback');
        if (!el) return;

        el.textContent = message || '';
        if (tone === 'error') {
            el.style.color = 'var(--theme-danger-text)';
        } else if (tone === 'success') {
            el.style.color = 'var(--theme-success-text)';
        } else {
            el.style.color = 'var(--theme-info-text)';
        }
    };

    CloudSystem._hasUsername = function () {
        return !!(this.profile && typeof this.profile.username_normalized === 'string' && this.profile.username_normalized.length > 0);
    };

    CloudSystem._setLeaderboardMeta = function (message) {
        const el = document.getElementById('leaderboard-meta');
        if (!el) return;
        el.textContent = message;
    };

    CloudSystem._isMissingRelationError = function (error, relationName) {
        const code = String(error?.code || '').toUpperCase();
        const message = String(error?.message || '').toLowerCase();
        const relation = String(relationName || '').toLowerCase();
        return code === '42P01'
            || code === 'PGRST205'
            || (relation && message.includes(relation) && (message.includes('does not exist') || message.includes('could not find')));
    };

    CloudSystem._isPermissionDeniedError = function (error) {
        const code = String(error?.code || '').toUpperCase();
        const message = String(error?.message || '').toLowerCase();
        return code === '42501'
            || code === '401'
            || code === '403'
            || message.includes('permission denied')
            || message.includes('not authorized')
            || message.includes('forbidden');
    };

    CloudSystem._formatLeaderboardLoadError = function (error) {
        if (this._isAuthLockContentionError(error)) {
            return 'Leaderboard is waiting for session sync to finish. Retrying shortly.';
        }

        if (this._isLeaderboardTimeoutError(error)) {
            return 'Leaderboard is taking longer than usual. Retrying shortly.';
        }

        if (this._isRetriableCloudError(error)) {
            return 'Leaderboard is temporarily offline. Retrying on the next cycle.';
        }

        if (this._isMissingRelationError(error, 'leaderboard_snapshots')) {
            return 'Leaderboard table missing. Apply migration 20260309_usernames_and_leaderboards.sql.';
        }

        if (this._isPermissionDeniedError(error)) {
            return 'Leaderboard read access denied. Apply the latest leaderboard access migration.';
        }

        const message = String(error?.message || '').trim();
        return message
            ? `Leaderboard update failed: ${message}`
            : 'Leaderboard update failed. Retrying on the next cycle.';
    };
    CloudSystem._isLeaderboardTimeoutError = function (error) {
        const message = String(error?.message || '').toLowerCase();
        return message.includes('leaderboard request timed out');
    };

    CloudSystem._shouldPreserveLeaderboardRows = function (error) {
        return this._isAuthLockContentionError(error)
            || this._isLeaderboardTimeoutError(error)
            || this._isRetriableCloudError(error);
    };

    CloudSystem._clearLeaderboardRetry = function () {
        if (!this.leaderboardRetryTimer) return;
        clearTimeout(this.leaderboardRetryTimer);
        this.leaderboardRetryTimer = null;
    };

    CloudSystem._scheduleLeaderboardRetry = function (delayMs = LEADERBOARD_TRANSIENT_RETRY_DELAY_MS) {
        if (this.leaderboardRetryTimer) return;

        this.leaderboardRetryTimer = setTimeout(() => {
            this.leaderboardRetryTimer = null;
            this.refreshLeaderboards().catch((err) => {
                console.warn('Retry leaderboard refresh failed:', err?.message || err);
            });
        }, Math.max(500, Number(delayMs) || LEADERBOARD_TRANSIENT_RETRY_DELAY_MS));
    };

    CloudSystem._fetchLeaderboardRows = async function () {
        for (let attempt = 1; attempt <= LEADERBOARD_AUTH_LOCK_RETRY_ATTEMPTS; attempt += 1) {
            let timeoutId = null;

            try {
                const requestPromise = extensionSupabaseClient
                    .from('leaderboard_snapshots')
                    .select('metric, rank, username, score, refreshed_at')
                    .lte('rank', LEADERBOARD_ENTRY_LIMIT)
                    .order('metric', { ascending: true })
                    .order('rank', { ascending: true });

                const timeoutPromise = new Promise((resolve) => {
                    timeoutId = setTimeout(() => {
                        resolve({
                            data: null,
                            error: { message: 'Leaderboard request timed out.' }
                        });
                    }, LEADERBOARD_FETCH_TIMEOUT_MS);
                });

                const result = await Promise.race([requestPromise, timeoutPromise]);
                if (result?.error && this._isAuthLockContentionError(result.error) && attempt < LEADERBOARD_AUTH_LOCK_RETRY_ATTEMPTS) {
                    await this._wait(LEADERBOARD_AUTH_LOCK_RETRY_DELAY_MS * attempt);
                    continue;
                }

                return result;
            } catch (error) {
                if (this._isAuthLockContentionError(error) && attempt < LEADERBOARD_AUTH_LOCK_RETRY_ATTEMPTS) {
                    await this._wait(LEADERBOARD_AUTH_LOCK_RETRY_DELAY_MS * attempt);
                    continue;
                }

                return { data: null, error };
            } finally {
                if (timeoutId) clearTimeout(timeoutId);
            }
        }

        return { data: null, error: new Error('Leaderboard request failed.') };
    };

    CloudSystem._parseLeaderboardScore = function (value) {
        if (typeof value === 'bigint') {
            return value >= 0n ? value : null;
        }

        if (typeof value === 'number') {
            if (!Number.isFinite(value) || value < 0) return null;
            return BigInt(Math.floor(value));
        }

        const text = String(value == null ? '' : value).trim();
        if (!text) return null;

        if (/^\d+$/.test(text)) {
            try {
                return BigInt(text);
            } catch (_err) {
                return null;
            }
        }

        if (/^\d+\.\d+$/.test(text)) {
            const integerPart = text.split('.')[0];
            try {
                return BigInt(integerPart);
            } catch (_err) {
                return null;
            }
        }

        return null;
    };

    CloudSystem._formatLeaderboardScore = function (score) {
        if (typeof score === 'bigint') {
            return score.toLocaleString('en-US');
        }

        const numeric = Number(score);
        if (!Number.isFinite(numeric) || numeric < 0) {
            return '0';
        }

        return Math.floor(numeric).toLocaleString('en-US');
    };

    CloudSystem._extractLeaderboardRows = function (data) {
        if (!Array.isArray(data)) return [];

        return data
            .map((row) => ({
                metric: row?.metric,
                rank: Number(row?.rank),
                username: String(row?.username || ''),
                score: this._parseLeaderboardScore(row?.score),
                refreshed_at: row?.refreshed_at || null
            }))
            .filter((row) => (row.metric === 'money_earned' || row.metric === 'fish_caught')
                && Number.isFinite(row.rank)
                && row.rank >= 1
                && row.score !== null)
            .sort((a, b) => {
                if (a.metric === b.metric) return a.rank - b.rank;
                return a.metric.localeCompare(b.metric);
            });
    };

    CloudSystem._latestLeaderboardRefreshMs = function (rows) {
        let latest = 0;
        rows.forEach((row) => {
            const ms = Date.parse(row?.refreshed_at || '');
            if (Number.isFinite(ms)) latest = Math.max(latest, ms);
        });
        return latest;
    };

    CloudSystem._looksLikeMissingRpc = function (error, fnName) {
        if (this._looksLikeRpcSignatureCacheError(error, fnName)) return true;
        return this._isMissingRelationError(error, fnName)
            || String(error?.message || '').toLowerCase().includes(fnName.toLowerCase());
    };

    CloudSystem._requestLeaderboardRefresh = async function () {
        if (!this.user || !extensionSupabaseClient) {
            return { attempted: false, refreshed: false };
        }
        if (this.leaderboardRefreshRpcUnavailable) {
            return { attempted: false, refreshed: false };
        }

        const now = Date.now();
        if (this.leaderboardRefreshInFlight || now < this.leaderboardRefreshCooldownUntil) {
            return { attempted: false, refreshed: false };
        }

        this.leaderboardRefreshInFlight = true;

        try {
            for (let attempt = 1; attempt <= LEADERBOARD_AUTH_LOCK_RETRY_ATTEMPTS; attempt += 1) {
                try {
                    const { data, error } = await extensionSupabaseClient.rpc('request_leaderboard_refresh');
                    if (error) {
                        if (this._isAuthLockContentionError(error) && attempt < LEADERBOARD_AUTH_LOCK_RETRY_ATTEMPTS) {
                            await this._wait(LEADERBOARD_AUTH_LOCK_RETRY_DELAY_MS * attempt);
                            continue;
                        }

                        if (this._looksLikeMissingRpc(error, 'request_leaderboard_refresh')) {
                            this.leaderboardRefreshRpcUnavailable = true;
                        }

                        this.leaderboardRefreshCooldownUntil = Date.now()
                            + (this._shouldPreserveLeaderboardRows(error) ? LEADERBOARD_TRANSIENT_RETRY_DELAY_MS : 60000);
                        return { attempted: true, refreshed: false, error };
                    }

                    const refreshed = !!data?.refreshed;
                    this.leaderboardRefreshCooldownUntil = Date.now() + 60000;
                    return { attempted: true, refreshed, data };
                } catch (error) {
                    if (this._isAuthLockContentionError(error) && attempt < LEADERBOARD_AUTH_LOCK_RETRY_ATTEMPTS) {
                        await this._wait(LEADERBOARD_AUTH_LOCK_RETRY_DELAY_MS * attempt);
                        continue;
                    }

                    this.leaderboardRefreshCooldownUntil = Date.now()
                        + (this._shouldPreserveLeaderboardRows(error) ? LEADERBOARD_TRANSIENT_RETRY_DELAY_MS : 60000);
                    return { attempted: true, refreshed: false, error };
                }
            }

            this.leaderboardRefreshCooldownUntil = Date.now() + LEADERBOARD_TRANSIENT_RETRY_DELAY_MS;
            return { attempted: true, refreshed: false, error: new Error('Leaderboard refresh request failed.') };
        } finally {
            this.leaderboardRefreshInFlight = false;
        }
    };

    CloudSystem._updateLeaderboardUserNote = function () {
        const el = document.getElementById('leaderboard-user-note');
        if (!el) return;

        if (!this.user) {
            el.textContent = 'Sign in, then set a username on /profile to appear on the leaderboard.';
            return;
        }

        if (this._hasUsername()) {
            el.textContent = `Signed in as @${this.profile.username_normalized}. You are eligible for leaderboard snapshots.`;
            return;
        }

        el.textContent = 'Set a username on /profile to join global leaderboards in Virtual Fisher and Virtual Farmer.';
    };

    CloudSystem._renderLeaderboardRows = function (listId, rows) {
        const list = document.getElementById(listId);
        if (!list) return;

        if (!Array.isArray(rows) || rows.length === 0) {
            list.innerHTML = '<li class="leaderboard-empty">No entries yet.</li>';
            return;
        }

        list.innerHTML = rows.map((row) => {
            const rank = Number(row.rank) || 0;
            const score = this._formatLeaderboardScore(row.score);
            const safeUsername = this._escapeHtml(row.username || 'unknown');
            return `<li class="leaderboard-item"><span class="leaderboard-rank">#${rank}</span><span class="leaderboard-name">@${safeUsername}</span><span class="leaderboard-score">${score}</span></li>`;
        }).join('');
    };

    CloudSystem._renderLeaderboardGroups = function (rows) {
        const moneyRows = rows.filter((row) => row.metric === 'money_earned');
        const fishRows = rows.filter((row) => row.metric === 'fish_caught');
        this._renderLeaderboardRows('leaderboard-money-list', moneyRows);
        this._renderLeaderboardRows('leaderboard-fish-list', fishRows);
    };

    CloudSystem.refreshLeaderboards = async function () {
        try {
            if (!extensionSupabaseClient) {
                this._clearLeaderboardRetry();
                this._setLeaderboardMeta('Leaderboard unavailable: Supabase not detected.');
                this._renderLeaderboardRows('leaderboard-money-list', []);
                this._renderLeaderboardRows('leaderboard-fish-list', []);
                this._updateLeaderboardUserNote();
                return;
            }

            let data = null;
            let error = null;
            try {
                const initialFetch = await this._fetchLeaderboardRows();
                data = initialFetch?.data ?? null;
                error = initialFetch?.error ?? null;
            } catch (fetchError) {
                error = fetchError;
            }

            if (error) {
                this._setLeaderboardMeta(this._formatLeaderboardLoadError(error));
                if (this._shouldPreserveLeaderboardRows(error) && this.leaderboardCachedRows.length > 0) {
                    this._renderLeaderboardGroups(this.leaderboardCachedRows);
                    this._scheduleLeaderboardRetry();
                } else {
                    this._renderLeaderboardRows('leaderboard-money-list', []);
                    this._renderLeaderboardRows('leaderboard-fish-list', []);
                }
                this._updateLeaderboardUserNote();
                return;
            }

            let rows = this._extractLeaderboardRows(data);
            let latestRefreshedAtMs = this._latestLeaderboardRefreshMs(rows);
            const staleThresholdMs = LEADERBOARD_REFRESH_MS + (2 * 60 * 1000);
            const shouldRequestManualRefresh = rows.length === 0
                || (latestRefreshedAtMs > 0 && (Date.now() - latestRefreshedAtMs) > staleThresholdMs);
            let refreshError = null;

            if (shouldRequestManualRefresh) {
                const refreshAttempt = await this._requestLeaderboardRefresh();
                refreshError = refreshAttempt?.error || null;
                const shouldRetryFetch = refreshAttempt.refreshed
                    || (refreshAttempt.attempted && !refreshAttempt.error);

                if (shouldRetryFetch) {
                    try {
                        const retry = await this._fetchLeaderboardRows();
                        if (!retry.error) {
                            rows = this._extractLeaderboardRows(retry.data);
                            latestRefreshedAtMs = this._latestLeaderboardRefreshMs(rows);
                        }
                    } catch (_retryError) {
                        // Keep existing rows and meta message if retry fetch fails.
                    }
                }
            }

            this._renderLeaderboardGroups(rows);

            if (rows.length === 0) {
                if (refreshError && this._shouldPreserveLeaderboardRows(refreshError)) {
                    this._setLeaderboardMeta(this._formatLeaderboardLoadError(refreshError));
                    this._scheduleLeaderboardRetry();
                } else {
                    this._clearLeaderboardRetry();
                    this._setLeaderboardMeta('No leaderboard entries yet. Snapshots update every 20 minutes.');
                }
                this._updateLeaderboardUserNote();
                return;
            }

            this.leaderboardCachedRows = rows;
            const refreshedAt = latestRefreshedAtMs > 0 ? new Date(latestRefreshedAtMs) : new Date();
            this.lastLeaderboardRefreshedAt = refreshedAt.getTime();
            if (refreshError && this._shouldPreserveLeaderboardRows(refreshError)) {
                this._setLeaderboardMeta(`${this._formatLeaderboardLoadError(refreshError)} Showing the latest available snapshot from ${refreshedAt.toLocaleString('en-US')}.`);
                this._scheduleLeaderboardRetry();
            } else {
                this._clearLeaderboardRetry();
                this._setLeaderboardMeta(`Last updated: ${refreshedAt.toLocaleString('en-US')} (refreshes every 20 minutes)`);
            }
            this._updateLeaderboardUserNote();
        } catch (err) {
            this._setLeaderboardMeta(`Leaderboard update failed: ${err?.message || 'Unknown error'}`);
            if (this._shouldPreserveLeaderboardRows(err) && this.leaderboardCachedRows.length > 0) {
                this._renderLeaderboardGroups(this.leaderboardCachedRows);
                this._scheduleLeaderboardRetry();
            } else {
                this._renderLeaderboardRows('leaderboard-money-list', []);
                this._renderLeaderboardRows('leaderboard-fish-list', []);
            }
            this._updateLeaderboardUserNote();
        }
    };

    CloudSystem.initLeaderboards = function () {
        if (this.leaderboardTimer) {
            clearInterval(this.leaderboardTimer);
            this.leaderboardTimer = null;
        }
        this._clearLeaderboardRetry();

        this._setLeaderboardMeta('Loading leaderboard…');
        this.refreshLeaderboards().catch((err) => {
            this._setLeaderboardMeta(`Leaderboard update failed: ${err?.message || 'Unknown error'}`);
            if (this._shouldPreserveLeaderboardRows(err) && this.leaderboardCachedRows.length > 0) {
                this._renderLeaderboardGroups(this.leaderboardCachedRows);
                this._scheduleLeaderboardRetry();
            } else {
                this._renderLeaderboardRows('leaderboard-money-list', []);
                this._renderLeaderboardRows('leaderboard-fish-list', []);
            }
            this._updateLeaderboardUserNote();
            console.warn('Initial leaderboard refresh failed:', err?.message || err);
        });

        this.leaderboardTimer = setInterval(() => {
            this.refreshLeaderboards().catch((err) => {
                console.warn('Scheduled leaderboard refresh failed:', err?.message || err);
            });
        }, LEADERBOARD_REFRESH_MS);
    };

    CloudSystem.loadUserProfile = async function () {
        if (!this.user || !extensionSupabaseClient) {
            this.profile = null;
            this._updateLeaderboardUserNote();
            this.updateUI();
            return null;
        }

        const userId = this.user.id;
        const { data, error } = await extensionSupabaseClient
            .from('user_profiles')
            .select('username, username_normalized, username_set_at')
            .eq('user_id', userId)
            .single();

        if (error && error.code !== 'PGRST116') {
            console.warn('Profile load failed:', error.message || error);
            this.profile = null;
            this._updateLeaderboardUserNote();
            this.updateUI();
            return null;
        }

        if (error && error.code === 'PGRST116') {
            const { error: insertError } = await extensionSupabaseClient
                .from('user_profiles')
                .insert({ user_id: userId });
            if (insertError) {
                console.warn('Profile bootstrap failed:', insertError.message || insertError);
            }

            this.profile = {
                username: null,
                username_normalized: null,
                username_set_at: null
            };
            this._updateLeaderboardUserNote();
            this.updateUI();
            return this.profile;
        }

        this.profile = {
            username: data?.username || null,
            username_normalized: data?.username_normalized || null,
            username_set_at: data?.username_set_at || null
        };

        this._updateLeaderboardUserNote();
        this.updateUI();
        return this.profile;
    };

    CloudSystem.openUsernameModal = function (options = {}) {
        const required = options.required === true;
        const overlay = document.getElementById('username-overlay');
        const modal = document.getElementById('username-modal');
        const title = document.getElementById('username-modal-title');
        const subtitle = document.getElementById('username-modal-subtitle');
        const input = document.getElementById('username-required-input');
        const skipBtn = document.getElementById('username-skip-btn');

        if (title) {
            title.textContent = required
                ? 'Username Required For Leaderboards'
                : 'Set Username';
        }

        if (subtitle) {
            subtitle.textContent = required
                ? 'This account predates username support. Set a username to be included in leaderboard snapshots.'
                : 'Choose a unique username to appear on global leaderboards.';
        }

        if (skipBtn) {
            skipBtn.style.display = 'inline-flex';
        }

        if (input) {
            const current = this.profile?.username_normalized || '';
            if (current) input.value = current;
            input.focus();
            input.select();
        }

        this._setUsernameModalFeedback('');
        this._setInlineUsernameFeedback('username-required-availability', '');

        if (overlay) overlay.classList.add('active');
        if (modal) modal.classList.add('active');
    };

    CloudSystem.closeUsernameModal = function () {
        if (this.usernamePromptRequired && !this.usernamePromptSkippedThisSession && !this._hasUsername()) {
            this._setUsernameModalFeedback('Set a username or explicitly skip to continue without leaderboard access.', 'error');
            return false;
        }

        const overlay = document.getElementById('username-overlay');
        const modal = document.getElementById('username-modal');
        if (overlay) overlay.classList.remove('active');
        if (modal) modal.classList.remove('active');
        this._setUsernameModalFeedback('');
        return true;
    };

    CloudSystem._enforceUsernameRequirement = function () {
        if (!this.user) {
            this.usernamePromptRequired = false;
            return;
        }

        if (this._hasUsername()) {
            this.usernamePromptRequired = false;
            this.usernamePromptSkippedThisSession = false;
            return;
        }

        if (this.usernamePromptSkippedThisSession) return;

        this.usernamePromptRequired = true;
        this.openUsernameModal({ required: true });
    };

    const originalSyncAuthModalMode = CloudSystem._syncAuthModalMode.bind(CloudSystem);
    CloudSystem._syncAuthModalMode = function () {
        originalSyncAuthModalMode();
    };

    const originalSubmitAuth = CloudSystem.submitAuth.bind(CloudSystem);
    CloudSystem.submitAuth = async function (event) {
        return originalSubmitAuth(event);
    };

    const originalHandleLoginSuccess = CloudSystem.handleLoginSuccess.bind(CloudSystem);
    CloudSystem.handleLoginSuccess = async function (user) {
        // Prevent concurrent login processing for the same user (avoids lock contention
        // when onAuthStateChange and explicit auth paths both call handleLoginSuccess).
        if (this._loginProcessingUserId === user.id) return;
        this._loginProcessingUserId = user.id;

        originalHandleLoginSuccess(user);

        try {
            await this.loadUserProfile();
            await this.refreshLeaderboards();
        } catch (err) {
            console.warn('Post-login profile/leaderboard setup failed:', err?.message || err);
        } finally {
            this._loginProcessingUserId = null;
        }
    };

    const originalLogout = CloudSystem.logout.bind(CloudSystem);
    CloudSystem.logout = async function () {
        this.profile = null;
        this.usernamePromptRequired = false;
        this.usernamePromptSkippedThisSession = false;
        this.updateUI();
        this._updateLeaderboardUserNote();
        return originalLogout();
    };

    const originalUpdateUI = CloudSystem.updateUI.bind(CloudSystem);
    CloudSystem.updateUI = function () {
        originalUpdateUI();

        const statusTargets = [
            document.getElementById('user-status'),
            document.getElementById('account-cloud-status')
        ].filter(Boolean);

        if (this.user && statusTargets.length && this._isOnline() && this.sessionActive && !this.pendingCloudSync) {
            const statusText = this._hasUsername()
                ? `Cloud: ${this.user.email} (@${this.profile.username_normalized})`
                : `Cloud: ${this.user.email} (username required for leaderboard)`;
            statusTargets.forEach((el) => {
                el.innerText = statusText;
            });
        }

        if (typeof this.refreshAccountModal === 'function') {
            this.refreshAccountModal();
        }

        this._updateLeaderboardUserNote();
    };

    const originalInit = CloudSystem.init.bind(CloudSystem);
    CloudSystem.init = async function (gameInstance) {
        this.initLeaderboards();

        if (!this.usernameWatcherBound && extensionSupabaseClient) {
            this.usernameWatcherBound = true;
            extensionSupabaseClient.auth.onAuthStateChange((event) => {
                if (event === 'SIGNED_OUT') {
                    this.profile = null;
                    this.usernamePromptRequired = false;
                    this.usernamePromptSkippedThisSession = false;
                    this._updateLeaderboardUserNote();
                    this.refreshLeaderboards().catch(() => {});
                }
            });
        }

        await originalInit(gameInstance);

        if (this.user) {
            await this.loadUserProfile();
        }

        await this.refreshLeaderboards();
    };

})();
