/**
 * MYTHIC WATERS: ENHANCED EDITION ï¿½ Core Engine
 * Contains the Game class with all core mechanics:
 *   - Weather system
 *   - Fishing logic (cast, rarity roll, minigame)
 *   - Combo system
 *   - XP & Levels
 *   - Auto-fishing
 *
 * All data (RARITY, RODS, BAITS, LOCATIONS, WEATHER_DATA, FISH_DB)
 * and systems (UI, Shop, Inventory, SaveSystem) are loaded via prior script tags.
 *
 * Wrapped in IIFE to prevent global scope access (Vuln #1 hardening).
 */

(function () {
    const PURCHASED_WEATHER_DURATION_MS = 15 * 60 * 1000;
    const NATURAL_WEATHER_DURATION_MS = 20 * 60 * 1000;
    const MAX_INVENTORY_FISH = 5000;
    const AUTO_SELL_RARITIES = new Set(['common', 'uncommon', 'rare', 'epic', 'legendary']);
    const ROD_LOCKED_RARITIES = new Set(['absolute', 'singularity', 'paradox', 'null']);

    class Game {
        constructor() {
            this.state = {
                coins: 0,
                totalCoinsEarned: 0,
                xp: 0,
                level: 1,
                inventory: [],
                location: 'mistvale',
                rod: 'bamboo',
                rodsOwned: ['bamboo'],
                bait: 'worm',
                baitsOwned: ['worm'],
                baitBench: this._createDefaultBaitBenchState(),
                combo: 0,
                totalCatches: 0,
                // Persistent species registry: normalized name -> display name.
                caughtSpecies: {},
                // Pity timer: consecutive catches without rare+ fish
                pityCounter: 0,
                rodState: {
                    rodId: 'bamboo',
                    favor: 0,
                    windowCastsRemaining: 0
                },
                // Shop: Purchased weathers running simultaneously (max WEATHER_BUY_LIMIT)
                activeWeathers: [],
                // Purchased weather expiration times: { weatherKey: unixMs }
                purchasedWeatherExpirations: {},
                // Natural weather state persistence
                naturalWeatherKey: 'clear',
                naturalWeatherExpiresAt: 0,
                // Shop: Amulet stock per biome { biomeKey: count }
                amuletStock: {},
                // Currently worn amulet biome key (or null)
                activeAmulet: null,
                // Auto-fish persistence
                autoFishEnabled: false,
                lastSaveTimestamp: Date.now(),
                // Achievements
                achievements: [],
                achievementCounters: {},
                settings: {
                    floatingText: true,
                    themeMode: 'auto',
                    keyMap: {
                        cast: 'KeyC',
                        autoFish: 'KeyA',
                        inventory: 'KeyI',
                        shop: 'KeyO',
                        achievements: 'KeyH',
                        expeditions: 'KeyE',
                        settings: 'KeyP',
                        save: 'KeyS'
                    }
                }
            };

            this.weather = {
                current: 'clear',
                expiresAt: 0,
                timer: null,
                purchasedTimers: {}
            };

            this.minigame = {
                active: false,
                pos: 0,
                direction: 1,
                speed: 1,
                targetStart: 0,
                targetWidth: 20,
                fishOnLine: null
            };

            // Auto-fishing state
            this.autoFish = {
                enabled: false,
                phase: 'idle', // 'idle', 'casting', 'hooking', 'reeling'
                timer: null,
                // Background-tracking fields
                cooldownStart: 0,   // timestamp when cooldown began
                cooldownDuration: 0 // how long the cooldown lasts (ms)
            };

            this.activeFishingMode = 'idle';
            this.fishingResults = {
                auto: {
                    totalCatches: 0,
                    fishStored: 0,
                    xpBanked: 0,
                    comboBonus: 0
                },
                manual: {
                    totalCatches: 0,
                    fishStored: 0,
                    xpBanked: 0,
                    comboBonus: 0
                }
            };
            this._lastEscapeMessageByTier = {};
            this._lastGeneratedMessageByKey = {};
            this._lastCriticalStatus = { text: 'CRITICAL!', color: '#f43f5e' };

            this.loopId = null;
            this.autoCooldownRafId = null;

            // Web Worker for un-throttled background timers
            this._timerCallbacks = {};
            this._timerIdCounter = 0;
            this._initTimerWorker();

            // System Modules
            this.ui = new UI(this);
            this.inventory = new Inventory(this);
            this.shop = new Shop(this);
            this.saveSystem = new SaveSystem(this);
            this.achievementManager = new AchievementManager(this);
        }

        addCoins(amount, options = {}) {
            const numericAmount = Number(amount);
            if (!Number.isFinite(numericAmount)) return 0;

            const credit = Math.max(0, Math.floor(numericAmount));
            if (credit <= 0) return 0;

            this.state.coins += credit;

            if (options.trackEarnings !== false) {
                const currentLifetime = Number(this.state.totalCoinsEarned);
                const safeLifetime = Number.isFinite(currentLifetime) ? Math.max(0, Math.floor(currentLifetime)) : 0;
                this.state.totalCoinsEarned = safeLifetime + credit;
            }

            return credit;
        }

        spendCoins(amount) {
            const numericAmount = Number(amount);
            if (!Number.isFinite(numericAmount)) return 0;

            const debit = Math.max(0, Math.floor(numericAmount));
            if (debit <= 0) return 0;

            const spend = Math.min(this.state.coins, debit);
            this.state.coins -= spend;
            return spend;
        }

        init() {
            this.saveSystem.load();
            this._ensureRodState(RODS.find((rod) => rod.id === this.state.rod) || RODS[0]);
            this._ensureBaitBenchState();
            this._syncUnlockedBaitBenchRecipes({ logUnlocks: false });
            this._applySettingsDefaults();
            this._initThemeWatcher();
            this._initSettingsControls();
            this._applyThemeMode();

            if (typeof CloudSystem !== 'undefined' && CloudSystem && typeof CloudSystem.init === 'function') {
                CloudSystem.init(this);
            }

            this.achievementManager.init();
            this.processOfflineCatches();
            this.ui.renderAll();
            this._renderSettingsPanel();
            this.startWeatherCycle();
            this._startServerWeatherPolling();
            this._initVisibilityHandler();
            this._initKeyboardShortcuts();
            this._initJournalHotkeyPopover();

            // Auto-resume auto-fish if it was enabled before reload
            if (this.state.autoFishEnabled) {
                this.autoFish.enabled = true;
                const btn = document.getElementById('auto-fish-btn');
                const castBtn = document.getElementById('action-btn');
                btn.textContent = 'Disable Auto Fish';
                btn.classList.add('active');
                castBtn.disabled = true;
                castBtn.style.opacity = '0.5';
                this.setFishingMode('auto');
                this.log('Auto-fishing resumed from previous session.');
                this.startAutoFishCycle();
            } else {
                this.setFishingMode('idle');
            }
        }

        _createDefaultRodState(rodId = 'bamboo') {
            return {
                rodId,
                favor: 0,
                windowCastsRemaining: 0
            };
        }

        _getCurrentRod() {
            return RODS.find((rod) => rod.id === this.state.rod) || RODS[0];
        }

        _getSpecialRodPassive(rod = null) {
            const passive = (rod || this._getCurrentRod())?.passive;
            if (!passive || typeof passive !== 'object') return null;
            return passive.mode === 'volatile' || passive.mode === 'measured'
                ? passive
                : null;
        }

        _ensureRodState(rod = null) {
            const currentRod = rod || this._getCurrentRod();
            const existing = (this.state && typeof this.state.rodState === 'object' && this.state.rodState !== null && !Array.isArray(this.state.rodState))
                ? this.state.rodState
                : null;

            if (!existing || existing.rodId !== currentRod.id) {
                this.state.rodState = this._createDefaultRodState(currentRod.id);
            } else {
                this.state.rodState.rodId = currentRod.id;
                this.state.rodState.favor = Number.isFinite(existing.favor) && existing.favor > 0
                    ? Math.floor(existing.favor)
                    : 0;
                this.state.rodState.windowCastsRemaining = Number.isFinite(existing.windowCastsRemaining) && existing.windowCastsRemaining > 0
                    ? Math.floor(existing.windowCastsRemaining)
                    : 0;
            }

            return this.state.rodState;
        }

        onRodEquipped(rod, options = {}) {
            const currentRod = rod || this._getCurrentRod();
            this.state.rod = currentRod.id;
            this.state.rodState = this._createDefaultRodState(currentRod.id);

            if (options.silent !== true && this.ui && typeof this.ui.renderStats === 'function') {
                this.ui.renderStats();
            }

            return this.state.rodState;
        }

        _buildRodCastEffect(passive, source = 'volatile') {
            return {
                source,
                label: passive.effectLabel || 'Lucky Window',
                color: passive.effectColor || '#f59e0b',
                accessRarities: Array.isArray(passive.accessRarities) ? [...passive.accessRarities] : [],
                modifiers: {
                    rarityBias: passive.effectRarityBias && typeof passive.effectRarityBias === 'object'
                        ? { ...passive.effectRarityBias }
                        : {}
                },
                salvageChance: Number(passive.salvageChance),
                salvageRarities: Array.isArray(passive.salvageRarities) ? [...passive.salvageRarities] : [],
                salvageWeightMultiplier: Number(passive.salvageWeightMultiplier),
                salvageValueMultiplier: Number(passive.salvageValueMultiplier),
                failureSaveChance: Number(passive.failureSaveChance),
                failureDowngradeChance: Number(passive.failureDowngradeChance),
                failureDowngradeRarities: Array.isArray(passive.failureDowngradeRarities)
                    ? [...passive.failureDowngradeRarities]
                    : [],
                targetWidthMultiplier: Number(passive.targetWidthMultiplier)
            };
        }

        _announceRodCastEffect(context, effect) {
            if (!effect || context.mode === 'offline') return;
            this.log(`${context.rod.name}: ${effect.label} active.`);
            this.ui.floatTextStyled(effect.label.toUpperCase(), effect.color);
        }

        _prepareRodCastEffect(context, rng = Math.random) {
            const passive = this._getSpecialRodPassive(context.rod);
            if (!passive) return null;

            const rodState = this._ensureRodState(context.rod);
            if (passive.mode === 'measured') {
                if (rodState.windowCastsRemaining <= 0) return null;
                rodState.windowCastsRemaining = Math.max(0, rodState.windowCastsRemaining - 1);
                if (context.mode !== 'offline' && this.ui && typeof this.ui.renderStats === 'function') {
                    this.ui.renderStats();
                }
                return this._buildRodCastEffect(passive, 'measured');
            }

            const triggerChance = Number(passive.triggerChance);
            if (!Number.isFinite(triggerChance) || triggerChance <= 0) return null;
            if (rng() >= Math.min(0.95, triggerChance)) return null;

            const effect = this._buildRodCastEffect(passive, 'volatile');
            this._announceRodCastEffect(context, effect);
            return effect;
        }

        _getPreviousAvailableRarity(location, rarityKey) {
            const ordered = this._getLocationRarityOrder(location);
            const currentIndex = ordered.indexOf(rarityKey);
            if (currentIndex <= 0) return null;
            return ordered[currentIndex - 1] || null;
        }

        _clipFishForRodRescue(fish, rod, effect, valueMultiplier = 1) {
            const safeCap = Math.max(0.1, this._getEffectiveCapacity(rod, fish));
            const weightMultiplier = Number.isFinite(effect?.salvageWeightMultiplier) && effect.salvageWeightMultiplier > 0
                ? effect.salvageWeightMultiplier
                : 0.95;
            const rescued = {
                ...fish,
                weight: parseFloat(Math.min(fish.weight, Math.max(0.1, safeCap * weightMultiplier)).toFixed(2))
            };

            const safeValueMultiplier = Number.isFinite(valueMultiplier) && valueMultiplier > 0 ? valueMultiplier : 1;
            rescued.value = Math.max(1, Math.floor(fish.value * safeValueMultiplier));
            rescued._rodRescuedBy = effect?.label || 'Lucky Window';
            return rescued;
        }

        _maybeRescueOverweightFish(fish, rod) {
            const effect = fish?._rodCastEffect;
            if (!effect) return null;

            const salvageRarities = Array.isArray(effect.salvageRarities) && effect.salvageRarities.length > 0
                ? effect.salvageRarities
                : effect.accessRarities;
            if (!Array.isArray(salvageRarities) || !salvageRarities.includes(fish.rarity)) return null;

            const salvageChance = Number(effect.salvageChance);
            if (!Number.isFinite(salvageChance) || salvageChance <= 0) return null;
            if (Math.random() >= Math.min(0.95, salvageChance)) return null;

            const rescued = this._clipFishForRodRescue(fish, rod, effect, effect.salvageValueMultiplier);
            rescued._rodRescueMode = 'salvaged';
            return rescued;
        }

        _maybeRescueFailedCatch(fish, rod) {
            const effect = fish?._rodCastEffect;
            if (!effect) return null;

            const failureRarities = Array.isArray(effect.failureDowngradeRarities)
                ? effect.failureDowngradeRarities
                : [];
            if (!failureRarities.includes(fish.rarity)) return null;

            const saveChance = Math.max(0, Number(effect.failureSaveChance) || 0);
            const downgradeChance = Math.max(0, Number(effect.failureDowngradeChance) || 0);
            const roll = Math.random();

            if (roll < Math.min(0.95, saveChance)) {
                const rescued = this._clipFishForRodRescue(fish, rod, effect, effect.salvageValueMultiplier || 0.92);
                rescued._rodRescueMode = 'held';
                return rescued;
            }

            if (roll >= Math.min(0.99, saveChance + downgradeChance)) return null;

            const downgradedRarity = this._getPreviousAvailableRarity(this.state.location, fish.rarity);
            if (!downgradedRarity) return null;

            const rescued = this._clipFishForRodRescue(fish, rod, effect, 1);
            const currentMeta = this._getRarityMeta(fish.rarity);
            const downgradedMeta = this._getRarityMeta(downgradedRarity);
            const currentMult = Number.isFinite(currentMeta.mult) && currentMeta.mult > 0 ? currentMeta.mult : 1;
            const downgradedMult = Number.isFinite(downgradedMeta.mult) && downgradedMeta.mult > 0 ? downgradedMeta.mult : 1;
            const payoutScale = Number.isFinite(effect.salvageValueMultiplier) && effect.salvageValueMultiplier > 0
                ? effect.salvageValueMultiplier
                : 0.9;

            rescued.rarity = downgradedRarity;
            rescued.value = Math.max(1, Math.floor(fish.value * (downgradedMult / currentMult) * payoutScale));
            rescued._rodRescueMode = 'downgraded';
            rescued._rodRescueRarity = downgradedRarity;
            return rescued;
        }

        _recordMeasuredRodOutcome(outcome, fish = null, mode = 'manual') {
            const rod = this._getCurrentRod();
            const passive = this._getSpecialRodPassive(rod);
            if (!passive || passive.mode !== 'measured') return;
            const shouldPersistMeterState = mode !== 'offline'
                && outcome !== 'catch'
                && this.saveSystem
                && typeof this.saveSystem.save === 'function';

            const rodState = this._ensureRodState(rod);
            if (rodState.windowCastsRemaining > 0) {
                if (mode !== 'offline' && this.ui && typeof this.ui.renderStats === 'function') {
                    this.ui.renderStats();
                }
                if (shouldPersistMeterState) {
                    this.saveSystem.save();
                }
                return;
            }

            let gain = 0;
            if (outcome === 'empty') {
                gain = Number(passive.favorOnEmpty);
            } else if (outcome === 'escape') {
                gain = Number(passive.favorOnEscape);
            } else if (outcome === 'catch' && fish) {
                const rarityOrder = Object.keys(RARITY);
                const maxIndex = Math.max(0, rarityOrder.indexOf(passive.lowCatchMaxRarity || 'epic'));
                const fishIndex = rarityOrder.indexOf(fish.rarity);
                if (fishIndex >= 0 && fishIndex <= maxIndex) {
                    gain = Number(passive.favorOnLowCatch);
                }
            }

            if (!Number.isFinite(gain) || gain <= 0) {
                if (mode !== 'offline' && this.ui && typeof this.ui.renderStats === 'function') {
                    this.ui.renderStats();
                }
                if (shouldPersistMeterState) {
                    this.saveSystem.save();
                }
                return;
            }

            const favorGoal = Number.isFinite(passive.favorGoal) && passive.favorGoal > 0
                ? Math.floor(passive.favorGoal)
                : 10;
            rodState.favor = Math.min(favorGoal, rodState.favor + Math.floor(gain));

            if (rodState.favor >= favorGoal) {
                rodState.favor = 0;
                rodState.windowCastsRemaining = Number.isFinite(passive.windowCasts) && passive.windowCasts > 0
                    ? Math.floor(passive.windowCasts)
                    : 3;

                if (mode !== 'offline') {
                    this.log(`${rod.name}: ${passive.effectLabel || 'Lucky Window'} is live for ${rodState.windowCastsRemaining} casts.`);
                    this.ui.floatTextStyled((passive.effectLabel || 'Lucky Window').toUpperCase(), passive.effectColor || '#14b8a6');
                }
            }

            if (mode !== 'offline' && this.ui && typeof this.ui.renderStats === 'function') {
                this.ui.renderStats();
            }
            if (shouldPersistMeterState) {
                this.saveSystem.save();
            }
        }

        /* --- WEB WORKER TIMER (runs in background tabs) --- */
        _initTimerWorker() {
            try {
                // Inline the worker script as a Blob to avoid file:// SecurityError
                const workerCode = `
                const timers = {};
                self.onmessage = function (e) {
                    const { command, id, delay } = e.data;
                    if (command === 'start') {
                        if (timers[id]) clearTimeout(timers[id]);
                        timers[id] = setTimeout(() => {
                            delete timers[id];
                            self.postMessage({ id });
                        }, delay);
                    }
                    if (command === 'cancel') {
                        if (timers[id]) {
                            clearTimeout(timers[id]);
                            delete timers[id];
                        }
                    }
                };
            `;
                const blob = new Blob([workerCode], { type: 'application/javascript' });
                const url = URL.createObjectURL(blob);
                this._timerWorker = new Worker(url);
                URL.revokeObjectURL(url); // Clean up the URL after worker is created
                this._timerWorker.onmessage = (e) => {
                    const { id } = e.data;
                    const cb = this._timerCallbacks[id];
                    if (cb) {
                        delete this._timerCallbacks[id];
                        cb();
                    }
                };
            } catch (err) {
                // Fallback: if Workers aren't available, use regular setTimeout
                console.warn('Web Worker unavailable, falling back to setTimeout:', err);
                this._timerWorker = null;
            }
        }

        /** Schedule a callback after `delay` ms ï¿½ uses Worker if available */
        _workerTimeout(callback, delay) {
            if (this._timerWorker) {
                const id = 'timer_' + (++this._timerIdCounter);
                this._timerCallbacks[id] = callback;
                this._timerWorker.postMessage({ command: 'start', id, delay });
                return id;
            }
            // Fallback to regular setTimeout
            return setTimeout(callback, delay);
        }

        /** Cancel a pending worker timer */
        _cancelWorkerTimeout(id) {
            if (id == null) return;
            if (this._timerWorker && typeof id === 'string') {
                delete this._timerCallbacks[id];
                this._timerWorker.postMessage({ command: 'cancel', id });
            } else {
                clearTimeout(id);
            }
        }

        /* --- VISIBILITY CHANGE: sync UI when tab regains focus --- */
        _initVisibilityHandler() {
            document.addEventListener('visibilitychange', () => {
                if (document.visibilityState !== 'visible') return;

                this._removeExpiredPurchasedWeathers({ logExpired: true, persist: true });
                if (!WEATHER_DATA[this.weather.current] || Date.now() >= this.weather.expiresAt) {
                    this._rollNextNaturalWeather();
                } else {
                    this._scheduleNaturalWeatherTimer();
                }

                // Tab is back in focus - refresh all UI
                this.ui.renderStats();
                this.inventory.render();
                this.ui.updateWeather();

                // Sync cooldown progress bar if auto-fishing
                if (this.autoFish.enabled && this.autoFish.phase === 'casting') {
                    this._syncCooldownBar();
                }
            });
        }
        _defaultKeyMap() {
            return {
                cast: 'KeyC',
                autoFish: 'KeyA',
                inventory: 'KeyI',
                shop: 'KeyO',
                achievements: 'KeyH',
                expeditions: 'KeyE',
                settings: 'KeyP',
                save: 'KeyS'
            };
        }

        _defaultSettings() {
            return {
                floatingText: true,
                themeMode: 'auto',
                keyMap: this._defaultKeyMap()
            };
        }

        _normalizeShortcutCode(code) {
            if (typeof code !== 'string') return null;
            const normalized = code.trim();
            const validPattern = /^(Key[A-Z]|Digit[0-9]|Space|Tab|Enter|Backspace|Minus|Equal|BracketLeft|BracketRight|Backslash|Semicolon|Quote|Comma|Period|Slash|Backquote)$/;
            return validPattern.test(normalized) ? normalized : null;
        }

        _formatShortcutCode(code) {
            if (!code) return '';
            if (code.startsWith('Key')) return code.slice(3).toUpperCase();
            if (code.startsWith('Digit')) return code.slice(5);

            const named = {
                Space: 'Space',
                Tab: 'Tab',
                Enter: 'Enter',
                Backspace: 'Backspace',
                Minus: '-',
                Equal: '=',
                BracketLeft: '[',
                BracketRight: ']',
                Backslash: '\\',
                Semicolon: ';',
                Quote: "'",
                Comma: ',',
                Period: '.',
                Slash: '/',
                Backquote: '`'
            };
            return named[code] || code;
        }

        _applySettingsDefaults() {
            const defaults = this._defaultSettings();
            const existing = (this.state && this.state.settings && typeof this.state.settings === 'object')
                ? this.state.settings
                : {};
            const existingMap = (existing.keyMap && typeof existing.keyMap === 'object') ? existing.keyMap : {};

            const cleanKeyMap = {};
            const usedCodes = new Set();
            Object.entries(defaults.keyMap).forEach(([action, fallbackCode]) => {
                let candidate = this._normalizeShortcutCode(existingMap[action]) || fallbackCode;
                if (usedCodes.has(candidate)) {
                    const nextUnusedDefault = Object.values(defaults.keyMap).find(code => !usedCodes.has(code));
                    candidate = nextUnusedDefault || fallbackCode;
                }
                cleanKeyMap[action] = candidate;
                usedCodes.add(candidate);
            });

            this.state.settings = {
                floatingText: existing.floatingText !== false,
                themeMode: ['auto', 'light', 'dark'].includes(existing.themeMode) ? existing.themeMode : 'auto',
                keyMap: cleanKeyMap
            };
        }

        _initThemeWatcher() {
            if (this._themeWatcherInitialized) return;
            this._themeWatcherInitialized = true;
            if (typeof window.matchMedia !== 'function') return;

            this._themeMediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
            this._themeMediaListener = () => {
                if (this.state.settings?.themeMode === 'auto') {
                    this._applyThemeMode();
                }
            };

            if (typeof this._themeMediaQuery.addEventListener === 'function') {
                this._themeMediaQuery.addEventListener('change', this._themeMediaListener);
            } else if (typeof this._themeMediaQuery.addListener === 'function') {
                this._themeMediaQuery.addListener(this._themeMediaListener);
            }
        }

        _resolveEffectiveTheme(mode) {
            if (mode === 'dark' || mode === 'light') return mode;
            const prefersDark = typeof window.matchMedia === 'function'
                && window.matchMedia('(prefers-color-scheme: dark)').matches;
            return prefersDark ? 'dark' : 'light';
        }

        _applyThemeMode() {
            const mode = this.state.settings?.themeMode || 'auto';
            const effective = this._resolveEffectiveTheme(mode);
            document.body.classList.remove('theme-light', 'theme-dark');
            document.body.classList.add(`theme-${effective}`);
            document.body.setAttribute('data-theme-mode', mode);
            document.body.setAttribute('data-theme-effective', effective);
        }

        _setThemeMode(mode) {
            if (!['auto', 'light', 'dark'].includes(mode)) return;
            if (!this.state.settings) this._applySettingsDefaults();
            this.state.settings.themeMode = mode;
            this._applyThemeMode();
            this._renderSettingsPanel();
            this.saveSystem.save();
        }

        _setFloatingTextHidden(hidden) {
            if (!this.state.settings) this._applySettingsDefaults();
            this.state.settings.floatingText = hidden !== true;
            if (hidden === true && this.ui && typeof this.ui.clearFloatingText === 'function') {
                this.ui.clearFloatingText();
            }
            this.saveSystem.save();
        }

        setKeybind(action, code) {
            if (!this.state.settings?.keyMap || !(action in this.state.settings.keyMap)) return false;
            const normalizedCode = this._normalizeShortcutCode(code);
            if (!normalizedCode) return false;

            const keyMap = this.state.settings.keyMap;
            const previousCode = keyMap[action];
            if (previousCode === normalizedCode) return true;

            const conflictingAction = Object.keys(keyMap).find(k => k !== action && keyMap[k] === normalizedCode);
            if (conflictingAction) {
                keyMap[conflictingAction] = previousCode;
            }

            keyMap[action] = normalizedCode;
            this._renderSettingsPanel();
            this.saveSystem.save();
            return true;
        }

        resetKeybindsToDefault() {
            if (!this.state.settings) this._applySettingsDefaults();
            this.state.settings.keyMap = this._defaultKeyMap();
            this._renderSettingsPanel();
            this.saveSystem.save();
        }

        _renderHotkeyLegend() {
            const legendMap = {
                cast: 'hotkey-cast',
                autoFish: 'hotkey-autoFish',
                inventory: 'hotkey-inventory',
                shop: 'hotkey-shop',
                achievements: 'hotkey-achievements',
                expeditions: 'hotkey-expeditions',
                settings: 'hotkey-settings',
                save: 'hotkey-save'
            };

            Object.entries(legendMap).forEach(([action, elementId]) => {
                const el = document.getElementById(elementId);
                if (!el) return;
                el.textContent = this._formatShortcutCode(this.state.settings?.keyMap?.[action]);
            });
        }

        _renderSettingsPanel() {
            const floatingToggle = document.getElementById('settings-floating-text');
            if (floatingToggle) {
                floatingToggle.checked = this.state.settings?.floatingText === false;
            }

            const themeRadios = document.querySelectorAll('input[name="settings-theme-mode"]');
            themeRadios.forEach((radio) => {
                radio.checked = radio.value === (this.state.settings?.themeMode || 'auto');
            });

            const keyInputs = document.querySelectorAll('.settings-key-input[data-keybind]');
            keyInputs.forEach((input) => {
                const action = input.dataset.keybind;
                const keyCode = this.state.settings?.keyMap?.[action];
                input.value = this._formatShortcutCode(keyCode);
                input.classList.remove('is-listening');
            });

            this._renderHotkeyLegend();
        }

        _initSettingsControls() {
            if (this._settingsControlsInitialized) return;
            this._settingsControlsInitialized = true;

            const floatingToggle = document.getElementById('settings-floating-text');
            if (floatingToggle) {
                floatingToggle.addEventListener('change', (event) => {
                    this._setFloatingTextHidden(event.target.checked);
                });
            }

            const themeRadios = document.querySelectorAll('input[name="settings-theme-mode"]');
            themeRadios.forEach((radio) => {
                radio.addEventListener('change', (event) => {
                    if (event.target.checked) {
                        this._setThemeMode(event.target.value);
                    }
                });
            });

            const keyInputs = document.querySelectorAll('.settings-key-input[data-keybind]');
            keyInputs.forEach((input) => {
                input.addEventListener('focus', () => {
                    input.classList.add('is-listening');
                });

                input.addEventListener('blur', () => {
                    input.classList.remove('is-listening');
                });

                input.addEventListener('keydown', (event) => {
                    event.preventDefault();
                    event.stopPropagation();
                    if (event.repeat) return;

                    const action = input.dataset.keybind;
                    const normalizedCode = this._normalizeShortcutCode(event.code);
                    if (!action || !normalizedCode) return;

                    this.setKeybind(action, normalizedCode);
                    input.blur();
                });
            });

            const resetKeybindBtn = document.getElementById('settings-keybind-reset');
            if (resetKeybindBtn) {
                resetKeybindBtn.addEventListener('click', () => {
                    this.resetKeybindsToDefault();
                });
            }

            const settingsSaveBtn = document.getElementById('settings-save-btn');
            if (settingsSaveBtn) {
                settingsSaveBtn.addEventListener('click', () => {
                    this.saveSystem.manualSave();
                });
            }

            const settingsResetBtn = document.getElementById('settings-reset-btn');
            if (settingsResetBtn) {
                settingsResetBtn.addEventListener('click', () => {
                    this.saveSystem.resetData();
                });
            }

            this._renderSettingsPanel();
        }

        _isShopOpen() {
            return document.getElementById('shop-modal')?.classList.contains('active') || false;
        }

        _isAchievementsOpen() {
            return document.getElementById('achievements-modal')?.classList.contains('active') || false;
        }

        _isInventoryOpen() {
            return document.getElementById('inventory-modal')?.classList.contains('active') || false;
        }

        _isExpeditionsOpen() {
            return document.getElementById('expeditions-modal')?.classList.contains('active') || false;
        }

        _isSettingsOpen() {
            return document.getElementById('settings-modal')?.classList.contains('active') || false;
        }

        _toggleShop() {
            if (this._isShopOpen()) {
                this.shop.close();
                return;
            }
            this.closeAchievements();
            this.closeInventory();
            this.closeExpeditions();
            this.closeSettings();
            this.shop.open();
        }

        _toggleAchievements() {
            if (this._isAchievementsOpen()) {
                this.closeAchievements();
                return;
            }
            this.shop.close();
            this.closeInventory();
            this.closeExpeditions();
            this.closeSettings();
            this.openAchievements();
        }

        _toggleInventory() {
            if (this._isInventoryOpen()) {
                this.closeInventory();
                return;
            }
            this.shop.close();
            this.closeAchievements();
            this.closeExpeditions();
            this.closeSettings();
            this.openInventory();
        }

        _toggleExpeditions() {
            if (this._isExpeditionsOpen()) {
                this.closeExpeditions();
                return;
            }
            this.shop.close();
            this.closeAchievements();
            this.closeInventory();
            this.closeSettings();
            this.openExpeditions();
        }

        _toggleSettings() {
            if (this._isSettingsOpen()) {
                this.closeSettings();
                return;
            }
            this.shop.close();
            this.closeAchievements();
            this.closeInventory();
            this.closeExpeditions();
            this.openSettings();
        }

        _clickVisibleButtonByIndex(index) {
            const activeModals = Array.from(document.querySelectorAll('.shop-modal.active'));
            const root = activeModals.length > 0 ? activeModals[activeModals.length - 1] : document;
            const allButtons = Array.from(root.querySelectorAll('button'));

            const visibleButtons = allButtons.filter(btn => {
                if (btn.disabled) return false;

                const style = window.getComputedStyle(btn);
                if (style.display === 'none' || style.visibility === 'hidden') return false;

                const rect = btn.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0;
            });

            const target = visibleButtons[index];
            if (!target) return false;
            target.click();
            return true;
        }

        _initJournalHotkeyPopover() {
            const menu = document.querySelector('.journal-hotkey-menu');
            if (!menu) return;
            const list = menu.querySelector('.journal-hotkey-list');
            if (!list) return;

            this._journalHotkeyMenu = menu;
            this._journalHotkeyList = list;

            const syncPlacement = () => {
                this._syncJournalHotkeyPopoverPlacement();
            };

            this._journalHotkeySyncPlacement = syncPlacement;
            menu.addEventListener('toggle', () => {
                requestAnimationFrame(syncPlacement);
            });

            this._journalHotkeyResizeHandler = () => {
                if (!this._journalHotkeyMenu?.open) return;
                this._syncJournalHotkeyPopoverPlacement();
            };

            this._journalHotkeyScrollHandler = () => {
                if (!this._journalHotkeyMenu?.open) return;
                this._syncJournalHotkeyPopoverPlacement();
            };

            window.addEventListener('resize', this._journalHotkeyResizeHandler, { passive: true });
            window.addEventListener('scroll', this._journalHotkeyScrollHandler, { passive: true });

            this._syncJournalHotkeyPopoverPlacement();
        }

        _syncJournalHotkeyPopoverPlacement() {
            const menu = this._journalHotkeyMenu || document.querySelector('.journal-hotkey-menu');
            if (!menu) return;
            const list = this._journalHotkeyList || menu.querySelector('.journal-hotkey-list');
            if (!list) return;

            this._journalHotkeyMenu = menu;
            this._journalHotkeyList = list;

            list.classList.remove('journal-hotkey-list--left', 'journal-hotkey-list--clamped');
            list.style.removeProperty('--journal-hotkey-shift');
            list.style.removeProperty('--journal-hotkey-max-inline-size');

            if (!menu.open) return;

            const viewportWidth = Math.max(document.documentElement.clientWidth || 0, window.innerWidth || 0);
            const safePadding = 12;
            const maxInline = Math.max(180, viewportWidth - (safePadding * 2));
            list.style.setProperty('--journal-hotkey-max-inline-size', `${Math.round(maxInline)}px`);

            let rect = list.getBoundingClientRect();
            if (rect.right > viewportWidth - safePadding) {
                list.classList.add('journal-hotkey-list--left');
                rect = list.getBoundingClientRect();
            }

            const overflowsLeft = rect.left < safePadding;
            const overflowsRight = rect.right > viewportWidth - safePadding;
            if (overflowsLeft || overflowsRight) {
                list.classList.add('journal-hotkey-list--clamped');
                rect = list.getBoundingClientRect();

                let shift = 0;
                if (rect.left < safePadding) {
                    shift += safePadding - rect.left;
                }
                if (rect.right > viewportWidth - safePadding) {
                    shift -= rect.right - (viewportWidth - safePadding);
                }

                if (Math.abs(shift) > 0.5) {
                    list.style.setProperty('--journal-hotkey-shift', `${Math.round(shift)}px`);
                }
            }
        }

        _initKeyboardShortcuts() {
            document.addEventListener('keydown', (event) => {
                if (event.repeat) return;
                if (event.ctrlKey || event.metaKey) return;

                const active = document.activeElement;
                const isEditable = active
                    && (active.tagName === 'INPUT'
                        || active.tagName === 'TEXTAREA'
                        || active.isContentEditable);
                if (isEditable) return;

                const key = typeof event.key === 'string' ? event.key.toLowerCase() : '';
                const code = typeof event.code === 'string' ? event.code : '';
                if (!key && !code) return;
                const keyMap = this.state.settings?.keyMap || this._defaultKeyMap();
                const isBound = (action) => keyMap[action] === code;

                const anyModalOpen = this._isShopOpen()
                    || this._isAchievementsOpen()
                    || this._isInventoryOpen()
                    || this._isExpeditionsOpen()
                    || this._isSettingsOpen();

                if (key === 'escape') {
                    this.shop.close();
                    this.closeAchievements();
                    this.closeInventory();
                    this.closeExpeditions();
                    this.closeSettings();
                    return;
                }

                if (event.altKey && /^[1-9]$/.test(key)) {
                    event.preventDefault();
                    this._clickVisibleButtonByIndex(Number(key) - 1);
                    return;
                }

                if (this._isShopOpen() && ['1', '2', '3', '4'].includes(key)) {
                    event.preventDefault();
                    const tabs = ['weather', 'amulets', 'rods', 'baits'];
                    this.shop.switchTab(tabs[Number(key) - 1]);
                    return;
                }

                if (isBound('settings')) {
                    event.preventDefault();
                    this._toggleSettings();
                    return;
                }

                if (isBound('shop')) {
                    event.preventDefault();
                    this._toggleShop();
                    return;
                }

                if (isBound('achievements')) {
                    event.preventDefault();
                    this._toggleAchievements();
                    return;
                }

                if (isBound('inventory')) {
                    event.preventDefault();
                    this._toggleInventory();
                    return;
                }

                if (isBound('expeditions')) {
                    event.preventDefault();
                    this._toggleExpeditions();
                    return;
                }

                if (isBound('save')) {
                    event.preventDefault();
                    this.saveSystem.manualSave();
                    return;
                }

                if (isBound('autoFish')) {
                    if (anyModalOpen) return;
                    event.preventDefault();
                    this.toggleAutoFish();
                    return;
                }

                if (isBound('cast')) {
                    if (anyModalOpen) return;
                    event.preventDefault();
                    const actionBtn = document.getElementById('action-btn');
                    if (actionBtn && !actionBtn.disabled) actionBtn.click();
                    return;
                }

                if (key === 'l' && this._isInventoryOpen()) {
                    event.preventDefault();
                    const sellAllBtn = document.querySelector('#inventory-modal .inventory-header .btn-secondary');
                    if (sellAllBtn && !sellAllBtn.disabled) sellAllBtn.click();
                    return;
                }

                if (key === 'x' && event.shiftKey) {
                    event.preventDefault();
                    this.saveSystem.resetData();
                }
            });
        }


        /** Update the cooldown bar to reflect actual elapsed time (after background) */
        _syncCooldownBar() {
            const container = document.getElementById('auto-cooldown-container');
            const fill = document.getElementById('cooldown-bar-fill');
            if (!container || !fill) return;

            const elapsed = Date.now() - this.autoFish.cooldownStart;
            const duration = this.autoFish.cooldownDuration;
            const safeDuration = Math.max(1, Number(duration) || 0);
            const progress = Math.max(0, Math.min(elapsed / safeDuration, 1));
            fill.style.transform = `scaleX(${progress})`;
            if (progress >= 1) {
                container.classList.remove('active');
            } else {
                container.classList.add('active');
            }
        }

        _startGameplayLoop() {
            if (this.loopId !== null) return;
            this.loopId = requestAnimationFrame(() => this.gameLoop());
        }

        _stopGameplayLoop() {
            if (this.loopId === null) return;
            cancelAnimationFrame(this.loopId);
            this.loopId = null;
        }

        gameLoop() {
            if (!this.minigame.active) {
                this.loopId = null;
                return;
            }

            this.updateMinigame();
            this.loopId = requestAnimationFrame(() => this.gameLoop());
        }

        _startAutoCooldownLoop() {
            this._stopAutoCooldownLoop();

            const step = () => {
                if (!this.autoFish.enabled || this.autoFish.phase !== 'casting') {
                    this.autoCooldownRafId = null;
                    return;
                }

                this._syncCooldownBar();

                if ((Date.now() - this.autoFish.cooldownStart) < this.autoFish.cooldownDuration) {
                    this.autoCooldownRafId = requestAnimationFrame(step);
                } else {
                    this.autoCooldownRafId = null;
                }
            };

            this.autoCooldownRafId = requestAnimationFrame(step);
        }

        _stopAutoCooldownLoop() {
            if (this.autoCooldownRafId === null) return;
            cancelAnimationFrame(this.autoCooldownRafId);
            this.autoCooldownRafId = null;
        }

        /* --- MECHANICS: WEATHER --- */
        selectWeatherType() {
            // Dynamic weighted selection based on probability
            let totalWeight = 0;
            const weatherKeys = Object.keys(WEATHER_DATA);
            weatherKeys.forEach(key => {
                totalWeight += (WEATHER_DATA[key].probability || 0.1);
            });

            let random = Math.random() * totalWeight;
            for (const key of weatherKeys) {
                const weight = WEATHER_DATA[key].probability || 0.1;
                if (random < weight) {
                    return key;
                }
                random -= weight;
            }
            return 'clear'; // Fallback
        }

        _applyWeatherClasses() {
            Object.keys(WEATHER_DATA).forEach(k => document.body.classList.remove(`weather-${k}`));

            const baseKey = WEATHER_DATA[this.weather.current] ? this.weather.current : 'clear';
            document.body.classList.add(`weather-${baseKey}`);

            this.state.activeWeathers.forEach(k => {
                if (WEATHER_DATA[k]) document.body.classList.add(`weather-${k}`);
            });
        }

        _scheduleNaturalWeatherTimer() {
            this._cancelWorkerTimeout(this.weather.timer);
            this.weather.timer = null;

            if (!Number.isFinite(this.weather.expiresAt) || this.weather.expiresAt <= 0) return;
            const delay = Math.max(0, this.weather.expiresAt - Date.now());
            this.weather.timer = this._workerTimeout(() => {
                this.weather.timer = null;
                this._rollNextNaturalWeather();
            }, delay);
        }

        _rollNextNaturalWeather() {
            const nextWeather = this.selectWeatherType();
            const expiresAt = Date.now() + NATURAL_WEATHER_DURATION_MS;
            this.setWeather(nextWeather, { expiresAt, logChange: true });
            this.saveSystem.save();
        }

        _cancelPurchasedWeatherTimer(key) {
            const timerId = this.weather.purchasedTimers[key];
            if (timerId == null) return;
            this._cancelWorkerTimeout(timerId);
            delete this.weather.purchasedTimers[key];
        }

        _schedulePurchasedWeatherTimer(key) {
            this._cancelPurchasedWeatherTimer(key);

            const expiresAt = Number(this.state.purchasedWeatherExpirations?.[key]);
            if (!Number.isFinite(expiresAt) || expiresAt <= 0) return;

            const delay = expiresAt - Date.now();
            if (delay <= 0) {
                this.removePurchasedWeather(key, { expired: true, persist: true });
                return;
            }

            this.weather.purchasedTimers[key] = this._workerTimeout(() => {
                delete this.weather.purchasedTimers[key];
                this.removePurchasedWeather(key, { expired: true, persist: true });
            }, delay);
        }

        _syncPurchasedWeatherTimers() {
            let changed = false;
            if (typeof this.state.purchasedWeatherExpirations !== 'object'
                || this.state.purchasedWeatherExpirations === null
                || Array.isArray(this.state.purchasedWeatherExpirations)) {
                this.state.purchasedWeatherExpirations = {};
                changed = true;
            }

            const now = Date.now();
            const validActive = [...new Set(this.state.activeWeathers.filter(k => WEATHER_DATA[k]))]
                .slice(0, WEATHER_BUY_LIMIT);
            if (validActive.length !== this.state.activeWeathers.length) changed = true;
            this.state.activeWeathers = validActive;

            validActive.forEach(key => {
                const existingExpiry = Number(this.state.purchasedWeatherExpirations[key]);
                if (!Number.isFinite(existingExpiry) || existingExpiry <= 0) {
                    // Legacy migration: existing active weather without a timer gets a fresh 15m window.
                    this.state.purchasedWeatherExpirations[key] = now + PURCHASED_WEATHER_DURATION_MS;
                    changed = true;
                }
            });

            Object.keys(this.state.purchasedWeatherExpirations).forEach(key => {
                if (!validActive.includes(key)) {
                    delete this.state.purchasedWeatherExpirations[key];
                    this._cancelPurchasedWeatherTimer(key);
                    changed = true;
                }
            });

            if (this._removeExpiredPurchasedWeathers({ logExpired: false, persist: false })) {
                changed = true;
            }
            this.state.activeWeathers.forEach(key => this._schedulePurchasedWeatherTimer(key));
            return changed;
        }

        _removeExpiredPurchasedWeathers(options = {}) {
            const { logExpired = false, persist = false } = options;
            const now = Date.now();
            let removedAny = false;

            [...this.state.activeWeathers].forEach(key => {
                const expiresAt = Number(this.state.purchasedWeatherExpirations?.[key]);
                if (!Number.isFinite(expiresAt) || expiresAt > now) return;

                const removed = this.removePurchasedWeather(key, {
                    expired: true,
                    silent: !logExpired,
                    persist: false
                });
                removedAny = removedAny || removed;
            });

            if (removedAny && persist) {
                this.saveSystem.save();
            }

            return removedAny;
        }

        startWeatherCycle() {
            const weatherStateChanged = this._syncPurchasedWeatherTimers();

            const now = Date.now();
            const savedKey = WEATHER_DATA[this.state.naturalWeatherKey] ? this.state.naturalWeatherKey : null;
            const savedExpiry = Number(this.state.naturalWeatherExpiresAt);

            if (savedKey && Number.isFinite(savedExpiry) && savedExpiry > now) {
                this.setWeather(savedKey, { expiresAt: savedExpiry, logChange: false });
                if (weatherStateChanged) this.saveSystem.save();
            } else {
                this._rollNextNaturalWeather();
            }
        }

        setWeather(type, options = {}) {
            const safeType = WEATHER_DATA[type] ? type : 'clear';
            const now = Date.now();
            const providedExpiry = Number(options.expiresAt);
            const expiresAt = Number.isFinite(providedExpiry) && providedExpiry > now
                ? providedExpiry
                : now + NATURAL_WEATHER_DURATION_MS;
            const logChange = options.logChange !== false;

            this.weather.current = safeType;
            this.weather.expiresAt = expiresAt;
            this.state.naturalWeatherKey = safeType;
            this.state.naturalWeatherExpiresAt = expiresAt;

            this._applyWeatherClasses();
            this._scheduleNaturalWeatherTimer();
            this.ui.updateWeather();

            if (logChange) {
                this.log(`Weather: ${WEATHER_DATA[safeType].name} - ${WEATHER_DATA[safeType].desc}`);
            }
        }

        /* --- SERVER WEATHER INTEGRATION --- */
        _startServerWeatherPolling() {
            this._serverWeatherLastUpdated = null;
            this._fetchServerWeather();
            this._serverWeatherTimer = setInterval(() => this._fetchServerWeather(), 3 * 60 * 1000);
        }

        async _fetchServerWeather() {
            try {
                const res = await fetch('/api/weather?game=fisher');
                if (!res.ok) return;
                const json = await res.json();
                if (!json.ok) return;

                const { weather, updated_at } = json;
                if (!weather || !weather.condition) return;

                // Skip if we already applied this update
                if (updated_at && updated_at === this._serverWeatherLastUpdated) return;
                this._serverWeatherLastUpdated = updated_at;

                const condition = String(weather.condition).toLowerCase();
                if (condition === 'clear' || condition === 'auto') return;

                // Map admin conditions to WEATHER_DATA keys
                const key = WEATHER_DATA[condition] ? condition : null;
                if (!key) return;

                // Apply server weather as current natural weather
                const duration = NATURAL_WEATHER_DURATION_MS;
                this.setWeather(key, { expiresAt: Date.now() + duration, logChange: true });
                this.saveSystem.save();
            } catch (err) {
                // Silently ignore fetch errors (offline, etc.)
            }
        }

        /** Add a purchased weather (max WEATHER_BUY_LIMIT simultaneous) */
        addPurchasedWeather(key) {
            this._removeExpiredPurchasedWeathers({ logExpired: false, persist: false });

            if (this.state.activeWeathers.length >= WEATHER_BUY_LIMIT) return false;
            if (this.state.activeWeathers.includes(key)) return false;
            if (!WEATHER_DATA[key]) return false;

            this.state.activeWeathers.push(key);
            this.state.purchasedWeatherExpirations[key] = Date.now() + PURCHASED_WEATHER_DURATION_MS;
            this._schedulePurchasedWeatherTimer(key);

            document.body.classList.add(`weather-${key}`);
            this.ui.updateWeather();
            return true;
        }

        /** Remove a purchased weather */
        removePurchasedWeather(key, options = {}) {
            const { expired = false, silent = false, persist = false } = options;
            const idx = this.state.activeWeathers.indexOf(key);
            if (idx === -1) return false;

            this.state.activeWeathers.splice(idx, 1);
            delete this.state.purchasedWeatherExpirations[key];
            this._cancelPurchasedWeatherTimer(key);

            // Only remove CSS class if it's not also the natural weather.
            if (this.weather.current !== key) {
                document.body.classList.remove(`weather-${key}`);
            }

            if (expired && !silent && WEATHER_DATA[key]) {
                this.log(`${WEATHER_DATA[key].name} weather effect ended.`);
            }

            this.ui.updateWeather();
            if (this._isShopOpen()) this.shop.render();
            if (persist) this.saveSystem.save();
            return true;
        }

        /** Combined luck multiplier: base weather + all purchased weathers (additive bonuses) */
        getWeatherMultiplier() {
            this._removeExpiredPurchasedWeathers({ logExpired: false, persist: false });
            if (this.weather.expiresAt > 0 && Date.now() >= this.weather.expiresAt) {
                this._rollNextNaturalWeather();
            }

            const baseKey = WEATHER_DATA[this.weather.current] ? this.weather.current : 'clear';
            let bonus = WEATHER_DATA[baseKey].luck - 1;
            const seen = new Set([baseKey]);

            this.state.activeWeathers.forEach(key => {
                if (seen.has(key)) return;
                const data = WEATHER_DATA[key];
                if (!data) return;
                seen.add(key);
                bonus += (data.luck - 1);
            });

            // Keep multiplier positive for stability if future data introduces many low-luck weathers.
            return Math.max(0.1, 1 + bonus);
        }

        setFishingMode(mode) {
            const normalizedMode = mode === 'auto' || mode === 'manual' ? mode : 'idle';
            this.activeFishingMode = normalizedMode;
            this.ui.setFishingZoneMode(normalizedMode);
            this._syncFishingControls();
        }

        _isManualFishingActive() {
            return this.activeFishingMode === 'manual' || this.minigame.active;
        }

        _isAutoFishingActive() {
            return this.autoFish.enabled || this.autoFish.phase !== 'idle';
        }

        _syncFishingControls() {
            const autoBtn = document.getElementById('auto-fish-btn');
            const castBtn = document.getElementById('action-btn');
            const manualLocked = this._isAutoFishingActive();
            const autoLocked = this._isManualFishingActive() && !this._isAutoFishingActive();

            if (castBtn) {
                castBtn.disabled = manualLocked;
                castBtn.style.opacity = manualLocked ? '0.5' : '1';
            }

            if (autoBtn) {
                autoBtn.disabled = autoLocked;
                autoBtn.style.opacity = autoLocked ? '0.5' : '1';
            }
        }

        _normalizeSpeciesName(name) {
            if (typeof name !== 'string') return '';
            return name.replace(/\s+/g, ' ').trim();
        }

        _normalizeSpeciesKey(name) {
            const normalizedName = this._normalizeSpeciesName(name);
            return normalizedName ? normalizedName.toLowerCase() : '';
        }

        _ensureCaughtSpeciesMap() {
            if (!this.state || typeof this.state !== 'object') return {};
            if (typeof this.state.caughtSpecies !== 'object'
                || this.state.caughtSpecies === null
                || Array.isArray(this.state.caughtSpecies)) {
                this.state.caughtSpecies = {};
            }
            return this.state.caughtSpecies;
        }

        _createDefaultBaitBenchState() {
            const base = {
                resources: {},
                unlockedRecipes: {},
                charges: {},
                activeFamily: null
            };

            const resources = Array.isArray(BAIT_BENCH_RESOURCES) ? BAIT_BENCH_RESOURCES : [];
            resources.forEach((resource) => {
                if (!resource?.id) return;
                base.resources[resource.id] = 0;
            });

            const families = Array.isArray(BAIT_BENCH_FAMILIES) ? BAIT_BENCH_FAMILIES : [];
            families.forEach((family) => {
                if (!family?.id) return;
                base.unlockedRecipes[family.id] = false;
                base.charges[family.id] = 0;
            });

            return base;
        }

        _ensureBaitBenchState() {
            const defaults = this._createDefaultBaitBenchState();
            const incoming = (this.state?.baitBench && typeof this.state.baitBench === 'object' && !Array.isArray(this.state.baitBench))
                ? this.state.baitBench
                : {};

            const clean = {
                resources: {},
                unlockedRecipes: {},
                charges: {},
                activeFamily: null
            };

            const incomingResources = (incoming.resources && typeof incoming.resources === 'object' && !Array.isArray(incoming.resources))
                ? incoming.resources
                : {};
            Object.keys(defaults.resources).forEach((resourceId) => {
                const rawValue = Number(incomingResources[resourceId]);
                clean.resources[resourceId] = Number.isFinite(rawValue) && rawValue > 0
                    ? Math.floor(rawValue)
                    : 0;
            });

            const incomingUnlocks = (incoming.unlockedRecipes && typeof incoming.unlockedRecipes === 'object' && !Array.isArray(incoming.unlockedRecipes))
                ? incoming.unlockedRecipes
                : {};
            Object.keys(defaults.unlockedRecipes).forEach((familyId) => {
                clean.unlockedRecipes[familyId] = incomingUnlocks[familyId] === true;
            });

            const incomingCharges = (incoming.charges && typeof incoming.charges === 'object' && !Array.isArray(incoming.charges))
                ? incoming.charges
                : {};
            Object.keys(defaults.charges).forEach((familyId) => {
                const rawValue = Number(incomingCharges[familyId]);
                clean.charges[familyId] = Number.isFinite(rawValue) && rawValue > 0
                    ? Math.floor(rawValue)
                    : 0;
            });

            const requestedActive = typeof incoming.activeFamily === 'string' ? incoming.activeFamily : null;
            if (requestedActive && clean.charges[requestedActive] > 0 && clean.unlockedRecipes[requestedActive]) {
                clean.activeFamily = requestedActive;
            }

            this.state.baitBench = clean;
            return clean;
        }

        _getBaitBenchFamilyById(familyId) {
            if (!familyId || !Array.isArray(BAIT_BENCH_FAMILIES)) return null;
            return BAIT_BENCH_FAMILIES.find((family) => family.id === familyId) || null;
        }

        _getBaitBenchSpeciesLookup() {
            if (this._baitBenchSpeciesLookup) return this._baitBenchSpeciesLookup;

            const map = new Map();
            const families = Array.isArray(BAIT_BENCH_FAMILIES) ? BAIT_BENCH_FAMILIES : [];
            families.forEach((family) => {
                const familyId = family?.id;
                if (!familyId || !Array.isArray(family.fishNames)) return;

                family.fishNames.forEach((speciesName) => {
                    const key = this._normalizeSpeciesKey(speciesName);
                    if (!key || map.has(key)) return;
                    map.set(key, familyId);
                });
            });

            this._baitBenchSpeciesLookup = map;
            return map;
        }

        _syncUnlockedBaitBenchRecipes({ logUnlocks = false } = {}) {
            const speciesMap = this._ensureCaughtSpeciesMap();
            let unlockedCount = 0;

            Object.values(speciesMap).forEach((name) => {
                const result = this._unlockBaitBenchRecipeBySpecies(name, { logUnlock: false });
                if (result.unlocked) unlockedCount++;
            });

            if (logUnlocks && unlockedCount > 0) {
                this.log(`Bait Bench synced ${unlockedCount.toLocaleString('en-US')} recipe unlocks from your species journal.`);
            }

            return unlockedCount;
        }

        _unlockBaitBenchRecipeBySpecies(speciesName, { logUnlock = true } = {}) {
            const speciesKey = this._normalizeSpeciesKey(speciesName);
            if (!speciesKey) return { unlocked: false, family: null };

            const familyId = this._getBaitBenchSpeciesLookup().get(speciesKey);
            if (!familyId) return { unlocked: false, family: null };

            const bench = this._ensureBaitBenchState();
            if (bench.unlockedRecipes[familyId]) {
                return {
                    unlocked: false,
                    family: this._getBaitBenchFamilyById(familyId)
                };
            }

            bench.unlockedRecipes[familyId] = true;
            const family = this._getBaitBenchFamilyById(familyId);
            if (logUnlock && family) {
                this.log(`Bait Bench recipe unlocked: ${family.name}.`);
            }

            return { unlocked: true, family };
        }

        getBaitBenchState() {
            return this._ensureBaitBenchState();
        }

        getActiveBaitBenchFamily() {
            const bench = this._ensureBaitBenchState();
            if (!bench.activeFamily) return null;
            if ((bench.charges[bench.activeFamily] || 0) <= 0) {
                bench.activeFamily = null;
                return null;
            }
            return this._getBaitBenchFamilyById(bench.activeFamily);
        }

        breakDownDuplicateBaitFish() {
            const bench = this._ensureBaitBenchState();
            const speciesLookup = this._getBaitBenchSpeciesLookup();
            const groups = new Map();

            this.state.inventory.forEach((fish, index) => {
                if (!fish || typeof fish !== 'object') return;
                const speciesKey = this._normalizeSpeciesKey(fish.name);
                if (!speciesKey || !speciesLookup.has(speciesKey)) return;

                if (!groups.has(speciesKey)) groups.set(speciesKey, []);
                groups.get(speciesKey).push({ fish, index });
            });

            const indexesToRemove = new Set();
            const gained = {};
            Object.keys(bench.resources).forEach((resourceId) => {
                gained[resourceId] = 0;
            });

            let converted = 0;
            let skippedMythic = 0;

            groups.forEach((entries) => {
                if (!Array.isArray(entries) || entries.length <= 1) return;

                let keeper = entries[0];
                entries.forEach((entry) => {
                    if ((entry.fish?.value || 0) > (keeper.fish?.value || 0)) {
                        keeper = entry;
                    }
                });

                entries.forEach((entry) => {
                    if (entry.index === keeper.index) return;

                    const rarityKey = String(entry.fish?.rarity || '').toLowerCase();
                    if (rarityKey === 'mythic') {
                        skippedMythic++;
                        return;
                    }

                    const resourceId = BAIT_BENCH_BREAKDOWN_BY_RARITY[rarityKey];
                    if (!resourceId || !(resourceId in bench.resources)) return;

                    indexesToRemove.add(entry.index);
                    bench.resources[resourceId] += 1;
                    gained[resourceId] = (gained[resourceId] || 0) + 1;
                    converted++;
                });
            });

            if (indexesToRemove.size > 0) {
                this.state.inventory = this.state.inventory.filter((_, index) => !indexesToRemove.has(index));
            }

            return {
                converted,
                removed: indexesToRemove.size,
                skippedMythic,
                gained
            };
        }

        craftBaitBenchFamily(familyId) {
            const family = this._getBaitBenchFamilyById(familyId);
            if (!family) {
                return { ok: false, reason: 'invalid_family' };
            }

            const bench = this._ensureBaitBenchState();
            if (!bench.unlockedRecipes[familyId]) {
                return { ok: false, reason: 'locked', family };
            }

            const costs = family.craft?.costs || {};
            const resourceEntries = Object.entries(costs);
            const hasResources = resourceEntries.every(([resourceId, amount]) => {
                const needed = Math.max(0, Math.floor(Number(amount) || 0));
                return (bench.resources[resourceId] || 0) >= needed;
            });

            if (!hasResources) {
                return { ok: false, reason: 'insufficient_resources', family };
            }

            resourceEntries.forEach(([resourceId, amount]) => {
                const needed = Math.max(0, Math.floor(Number(amount) || 0));
                bench.resources[resourceId] = Math.max(0, (bench.resources[resourceId] || 0) - needed);
            });

            const addedCharges = Math.max(1, Math.floor(Number(family.craft?.makesCharges) || 1));
            bench.charges[familyId] = (bench.charges[familyId] || 0) + addedCharges;

            return {
                ok: true,
                family,
                addedCharges,
                totalCharges: bench.charges[familyId]
            };
        }

        setActiveBaitBenchFamily(familyId) {
            const bench = this._ensureBaitBenchState();

            if (!familyId) {
                bench.activeFamily = null;
                return { ok: true, family: null };
            }

            const family = this._getBaitBenchFamilyById(familyId);
            if (!family) {
                return { ok: false, reason: 'invalid_family' };
            }

            if (!bench.unlockedRecipes[familyId]) {
                return { ok: false, reason: 'locked', family };
            }

            if ((bench.charges[familyId] || 0) <= 0) {
                return { ok: false, reason: 'no_charges', family };
            }

            bench.activeFamily = familyId;
            return { ok: true, family };
        }

        _consumeActiveBaitBenchCharge(mode = 'manual') {
            const bench = this._ensureBaitBenchState();
            const activeFamily = this.getActiveBaitBenchFamily();
            if (!activeFamily) return null;

            const familyId = activeFamily.id;
            const currentCharges = Math.max(0, Math.floor(bench.charges[familyId] || 0));
            if (currentCharges <= 0) {
                bench.activeFamily = null;
                return null;
            }

            bench.charges[familyId] = currentCharges - 1;
            const remaining = bench.charges[familyId];
            if (remaining <= 0) {
                bench.activeFamily = null;
                if (mode !== 'offline') {
                    this.log(`${activeFamily.name} is depleted.`);
                }
            }

            return { family: activeFamily, remaining };
        }

        getDiscoveredSpeciesCount() {
            return Object.keys(this._ensureCaughtSpeciesMap()).length;
        }

        getDiscoveredSpeciesEntries() {
            const speciesMap = this._ensureCaughtSpeciesMap();
            return Object.entries(speciesMap)
                .map(([key, value]) => ({
                    key,
                    name: this._normalizeSpeciesName(value) || key
                }))
                .sort((a, b) => a.name.localeCompare(b.name));
        }

        _buildSpeciesCatalogEntries() {
            if (Array.isArray(this._speciesCatalogEntries)) {
                return this._speciesCatalogEntries;
            }

            const catalogMap = {};
            const allBiomes = (typeof FISH_DB === 'object' && FISH_DB) ? Object.values(FISH_DB) : [];

            allBiomes.forEach((biomeTable) => {
                if (!biomeTable || typeof biomeTable !== 'object') return;

                Object.values(biomeTable).forEach((rarityTable) => {
                    if (!Array.isArray(rarityTable)) return;

                    rarityTable.forEach((fishRow) => {
                        if (!Array.isArray(fishRow) || fishRow.length === 0) return;
                        const speciesName = this._normalizeSpeciesName(fishRow[0]);
                        const speciesKey = this._normalizeSpeciesKey(speciesName);
                        if (!speciesKey) return;
                        if (!catalogMap[speciesKey]) catalogMap[speciesKey] = speciesName;
                    });
                });
            });

            this._speciesCatalogEntries = Object.entries(catalogMap)
                .map(([key, name]) => ({ key, name }))
                .sort((a, b) => a.name.localeCompare(b.name));

            return this._speciesCatalogEntries;
        }

        getSpeciesCatalogEntries() {
            return this._buildSpeciesCatalogEntries();
        }

        getSpeciesCatalogCount() {
            return this._buildSpeciesCatalogEntries().length;
        }

        recordCaughtSpecies(fishOrName) {
            const incomingName = typeof fishOrName === 'string' ? fishOrName : fishOrName?.name;
            const normalizedName = this._normalizeSpeciesName(incomingName);
            if (!normalizedName) {
                return { isNew: false, name: '', key: '', total: this.getDiscoveredSpeciesCount() };
            }

            const speciesKey = this._normalizeSpeciesKey(normalizedName);
            if (!speciesKey) {
                return { isNew: false, name: normalizedName, key: '', total: this.getDiscoveredSpeciesCount() };
            }

            const speciesMap = this._ensureCaughtSpeciesMap();
            if (typeof speciesMap[speciesKey] === 'string' && speciesMap[speciesKey].trim().length > 0) {
                return {
                    isNew: false,
                    name: speciesMap[speciesKey],
                    key: speciesKey,
                    total: Object.keys(speciesMap).length
                };
            }

            speciesMap[speciesKey] = normalizedName;
            return {
                isNew: true,
                name: normalizedName,
                key: speciesKey,
                total: Object.keys(speciesMap).length
            };
        }

        resetFishingResults(mode) {
            const panel = this.fishingResults[mode];
            if (!panel) return;

            panel.totalCatches = 0;
            panel.fishStored = 0;
            panel.xpBanked = 0;
            panel.comboBonus = 0;
            this.ui.renderFishingResults();
        }

        _recordFishingResults(mode, { stored = false, xpGained = 0 } = {}) {
            const panel = this.fishingResults[mode];
            if (!panel) return;

            panel.totalCatches++;
            if (stored) panel.fishStored++;
            panel.xpBanked += Math.max(0, xpGained);
            panel.comboBonus = Math.max(0, this.state.combo * 10);
            this.ui.renderFishingResults();
        }

        _setFishingComboBonus(mode, comboBonus = 0) {
            const panel = this.fishingResults[mode];
            if (!panel) return;
            panel.comboBonus = Math.max(0, comboBonus);
            this.ui.renderFishingResults();
        }

        _autoSellInventoryIfFull() {
            if (this.state.inventory.length < MAX_INVENTORY_FISH) return false;

            let soldCount = 0;
            let soldValue = 0;
            const keptFish = [];

            for (const fish of this.state.inventory) {
                if (fish && AUTO_SELL_RARITIES.has(fish.rarity)) {
                    soldCount++;
                    soldValue += fish.value;
                } else {
                    keptFish.push(fish);
                }
            }

            if (soldCount === 0) return false;

            this.state.inventory = keptFish;
            this.addCoins(soldValue);
            this.achievementManager.onCoinsChange();
            this.log(`Inventory full (${MAX_INVENTORY_FISH}). Auto-sold ${soldCount.toLocaleString('en-US')} Common-Legendary fish for ${soldValue.toLocaleString('en-US')} coins.`);
            return true;
        }

        _storeCaughtFish(fish, sourceMode = 'manual') {
            this._autoSellInventoryIfFull();
            const cleanFish = { ...fish };
            delete cleanFish._rngLuckMultiplier;

            if (this.state.inventory.length < MAX_INVENTORY_FISH) {
                const uniqueId = typeof crypto !== 'undefined' && crypto.randomUUID
                    ? crypto.randomUUID()
                    : Date.now() + '_' + Math.random().toString(36).substr(2, 9);
                this.state.inventory.push({ ...cleanFish, id: uniqueId });
                return { stored: true, action: 'stored' };
            }

            if (AUTO_SELL_RARITIES.has(cleanFish.rarity)) {
                this.addCoins(cleanFish.value);
                this.achievementManager.onCoinsChange();
                this.log(`Inventory full (${MAX_INVENTORY_FISH}). Auto-sold ${sourceMode} catch ${cleanFish.name} for ${cleanFish.value.toLocaleString('en-US')} coins.`);
                return { stored: false, action: 'sold' };
            }

            this.log(`Inventory full (${MAX_INVENTORY_FISH}) with Mythic storage. ${sourceMode} catch ${cleanFish.name} could not be stored.`);
            return { stored: false, action: 'rejected' };
        }

        /* --- MECHANICS: FISHING LOGIC --- */
        _getRarityMeta(rarityKey) {
            const rarity = RARITY[rarityKey];
            if (rarity) return rarity;
            return {
                name: String(rarityKey || 'Unknown'),
                color: '#9ca3af',
                mult: 1,
                xp: 0,
                difficulty: 0.3,
                speed: 1.0,
                baseChance: 0,
                maxChance: 0
            };
        }

        _getLocationRarityOrder(loc) {
            const table = FISH_DB[loc];
            const globalOrder = Object.keys(RARITY);

            if (!table || typeof table !== 'object') return globalOrder;

            const available = Object.keys(table).filter((key) => {
                const rows = table[key];
                return Array.isArray(rows) && rows.length > 0;
            });
            if (available.length === 0) return globalOrder;

            const rank = new Map(globalOrder.map((key, index) => [key, index]));

            return available.sort((a, b) => {
                const aRank = rank.has(a) ? rank.get(a) : Number.MAX_SAFE_INTEGER;
                const bRank = rank.has(b) ? rank.get(b) : Number.MAX_SAFE_INTEGER;
                if (aRank !== bRank) return aRank - bRank;
                return a.localeCompare(b);
            });
        }

        _computeLuckMultiplier(totalLuck) {
            const safeTotalLuck = Number.isFinite(totalLuck) ? Math.max(0, totalLuck) : 0;
            // Luck scales absolute rarity rates directly. There is no pity or guarantee logic.
            return Math.max(1, 1 + (safeTotalLuck / 250));
        }

        _scaleTowardsOne(value, scale = 1) {
            const safeValue = Number(value);
            if (!Number.isFinite(safeValue) || safeValue <= 0) return 1;

            const safeScale = Number.isFinite(scale) ? Math.max(0, scale) : 1;
            return 1 + ((safeValue - 1) * safeScale);
        }

        _buildDefaultPassiveModifiers() {
            return {
                autoCycleMultiplier: 1,
                hookTimingMultiplier: 1,
                rarityBias: {},
                weightRanges: [],
                heavyThreshold: null,
                heavyPenalty: 0
            };
        }

        _mergePassiveModifiers(baseModifiers, incomingModifiers) {
            const base = baseModifiers || this._buildDefaultPassiveModifiers();
            const incoming = incomingModifiers || {};
            const merged = {
                autoCycleMultiplier: Number(base.autoCycleMultiplier) || 1,
                hookTimingMultiplier: Number(base.hookTimingMultiplier) || 1,
                rarityBias: { ...(base.rarityBias || {}) },
                weightRanges: Array.isArray(base.weightRanges) ? [...base.weightRanges] : [],
                heavyThreshold: Number.isFinite(base.heavyThreshold) ? base.heavyThreshold : null,
                heavyPenalty: Number.isFinite(base.heavyPenalty) ? base.heavyPenalty : 0
            };

            if (Number.isFinite(incoming.autoCycleMultiplier) && incoming.autoCycleMultiplier > 0) {
                merged.autoCycleMultiplier *= incoming.autoCycleMultiplier;
            }
            if (Number.isFinite(incoming.hookTimingMultiplier) && incoming.hookTimingMultiplier > 0) {
                merged.hookTimingMultiplier *= incoming.hookTimingMultiplier;
            }

            if (incoming.rarityBias && typeof incoming.rarityBias === 'object') {
                Object.entries(incoming.rarityBias).forEach(([rarityKey, mult]) => {
                    const scalar = Number(mult);
                    if (!Number.isFinite(scalar) || scalar <= 0) return;
                    const existing = Number(merged.rarityBias[rarityKey]);
                    merged.rarityBias[rarityKey] = (Number.isFinite(existing) && existing > 0 ? existing : 1) * scalar;
                });
            }

            if (Array.isArray(incoming.weightRanges)) {
                incoming.weightRanges.forEach((range) => {
                    if (!Array.isArray(range) || range.length < 2) return;
                    const min = Number(range[0]);
                    const max = Number(range[1]);
                    if (!Number.isFinite(min) || !Number.isFinite(max) || min <= 0 || max <= 0) return;
                    const lower = Math.min(min, max);
                    const upper = Math.max(min, max);
                    merged.weightRanges.push([lower, upper]);
                });
            }

            if (Number.isFinite(incoming.heavyPenalty) && incoming.heavyPenalty > 0) {
                const penalty = Math.min(0.9, Math.max(0, incoming.heavyPenalty));
                if (penalty >= merged.heavyPenalty) {
                    merged.heavyPenalty = penalty;
                    const threshold = Number(incoming.heavyThreshold);
                    merged.heavyThreshold = Number.isFinite(threshold) && threshold > 0 && threshold < 1
                        ? threshold
                        : merged.heavyThreshold;
                }
            }

            return merged;
        }

        _resolveRodPassiveModifiers(rod) {
            const passive = rod?.passive;
            if (!passive || typeof passive !== 'object') {
                return this._buildDefaultPassiveModifiers();
            }

            const modifiers = this._buildDefaultPassiveModifiers();
            const autoCycleMultiplier = Number(passive.autoCycleMultiplier);
            const hookTimingMultiplier = Number(passive.hookTimingMultiplier);
            if (Number.isFinite(autoCycleMultiplier) && autoCycleMultiplier > 0) {
                modifiers.autoCycleMultiplier = autoCycleMultiplier;
            }
            if (Number.isFinite(hookTimingMultiplier) && hookTimingMultiplier > 0) {
                modifiers.hookTimingMultiplier = hookTimingMultiplier;
            }

            if (passive.rarityBias && typeof passive.rarityBias === 'object') {
                modifiers.rarityBias = { ...passive.rarityBias };
            }

            const weightMin = Number(passive.weightMultiplierMin);
            const weightMax = Number(passive.weightMultiplierMax);
            if (Number.isFinite(weightMin) && Number.isFinite(weightMax) && weightMin > 0 && weightMax > 0) {
                modifiers.weightRanges.push([Math.min(weightMin, weightMax), Math.max(weightMin, weightMax)]);
            }

            const heavyThreshold = Number(passive.heavyThreshold);
            const heavyPenalty = Number(passive.heavyPenalty);
            if (Number.isFinite(heavyPenalty) && heavyPenalty > 0) {
                modifiers.heavyPenalty = Math.min(0.9, Math.max(0, heavyPenalty));
                if (Number.isFinite(heavyThreshold) && heavyThreshold > 0 && heavyThreshold < 1) {
                    modifiers.heavyThreshold = heavyThreshold;
                }
            }

            return modifiers;
        }

        _resolveBaitPassiveScale(baitPassive, rod) {
            if (!baitPassive || typeof baitPassive !== 'object') return 0;
            if (!baitPassive.midTierOnly) return 1;
            if (!rod || rod.tier !== 'mid') return 0;
            if (baitPassive.bestWithRod && rod.id === baitPassive.bestWithRod) return 1;
            const offSynergy = Number(baitPassive.offSynergyScale);
            if (Number.isFinite(offSynergy) && offSynergy > 0 && offSynergy <= 1) return offSynergy;
            return 0.7;
        }

        _resolveBaitPassiveModifiers(bait, rod) {
            const passive = bait?.passive;
            if (!passive || typeof passive !== 'object') {
                return this._buildDefaultPassiveModifiers();
            }

            const scale = this._resolveBaitPassiveScale(passive, rod);
            if (scale <= 0) {
                return this._buildDefaultPassiveModifiers();
            }

            const modifiers = this._buildDefaultPassiveModifiers();
            const autoCycleMultiplier = this._scaleTowardsOne(passive.autoCycleMultiplier, scale);
            const hookTimingMultiplier = this._scaleTowardsOne(passive.hookTimingMultiplier, scale);
            if (autoCycleMultiplier > 0) modifiers.autoCycleMultiplier = autoCycleMultiplier;
            if (hookTimingMultiplier > 0) modifiers.hookTimingMultiplier = hookTimingMultiplier;

            const weightMin = Number(passive.weightMultiplierMin);
            const weightMax = Number(passive.weightMultiplierMax);
            if (Number.isFinite(weightMin) && Number.isFinite(weightMax) && weightMin > 0 && weightMax > 0) {
                const scaledMin = this._scaleTowardsOne(weightMin, scale);
                const scaledMax = this._scaleTowardsOne(weightMax, scale);
                modifiers.weightRanges.push([Math.min(scaledMin, scaledMax), Math.max(scaledMin, scaledMax)]);
            }

            if (passive.rarityBias && typeof passive.rarityBias === 'object') {
                const scaledBias = {};
                Object.entries(passive.rarityBias).forEach(([rarityKey, scalar]) => {
                    const scaledScalar = this._scaleTowardsOne(scalar, scale);
                    if (scaledScalar > 0) scaledBias[rarityKey] = scaledScalar;
                });
                modifiers.rarityBias = scaledBias;
            }

            return modifiers;
        }

        _resolveCraftedFamilyModifiers(family) {
            if (!family?.effects || typeof family.effects !== 'object') {
                return this._buildDefaultPassiveModifiers();
            }

            const effects = family.effects;
            const modifiers = this._buildDefaultPassiveModifiers();

            const autoCycleMultiplier = Number(effects.autoCycleMultiplier);
            const hookTimingMultiplier = Number(effects.hookTimingMultiplier);
            if (Number.isFinite(autoCycleMultiplier) && autoCycleMultiplier > 0) {
                modifiers.autoCycleMultiplier = autoCycleMultiplier;
            }
            if (Number.isFinite(hookTimingMultiplier) && hookTimingMultiplier > 0) {
                modifiers.hookTimingMultiplier = hookTimingMultiplier;
            }

            const weightMin = Number(effects.weightMultiplierMin);
            const weightMax = Number(effects.weightMultiplierMax);
            if (Number.isFinite(weightMin) && Number.isFinite(weightMax) && weightMin > 0 && weightMax > 0) {
                modifiers.weightRanges.push([Math.min(weightMin, weightMax), Math.max(weightMin, weightMax)]);
            }

            if (effects.rarityBias && typeof effects.rarityBias === 'object') {
                modifiers.rarityBias = { ...effects.rarityBias };
            }

            return modifiers;
        }

        _buildCombinedPassiveModifiers({ rod, bait, includeCraftedFamily = false, craftedFamily = null } = {}) {
            const currentRod = rod || (RODS.find((r) => r.id === this.state.rod) || RODS[0]);
            const currentBait = bait || (BAITS.find((b) => b.id === this.state.bait) || BAITS[0]);

            let modifiers = this._buildDefaultPassiveModifiers();
            modifiers = this._mergePassiveModifiers(modifiers, this._resolveRodPassiveModifiers(currentRod));
            modifiers = this._mergePassiveModifiers(modifiers, this._resolveBaitPassiveModifiers(currentBait, currentRod));

            const activeFamily = craftedFamily || (includeCraftedFamily ? this.getActiveBaitBenchFamily() : null);
            if (activeFamily) {
                modifiers = this._mergePassiveModifiers(modifiers, this._resolveCraftedFamilyModifiers(activeFamily));
            }

            return { modifiers, activeFamily };
        }

        _applyWeightBiases(weight, maxWeight, modifiers, rng = Math.random) {
            const safeWeight = Number.isFinite(weight) ? Math.max(0.1, weight) : 0.1;
            const safeMaxWeight = Number.isFinite(maxWeight) ? Math.max(0.1, maxWeight) : 1;

            let adjustedWeight = safeWeight;
            const ranges = Array.isArray(modifiers?.weightRanges) ? modifiers.weightRanges : [];

            ranges.forEach((range) => {
                if (!Array.isArray(range) || range.length < 2) return;
                const min = Number(range[0]);
                const max = Number(range[1]);
                if (!Number.isFinite(min) || !Number.isFinite(max) || min <= 0 || max <= 0) return;

                const lower = Math.min(min, max);
                const upper = Math.max(min, max);
                const roll = lower + ((upper - lower) * rng());
                adjustedWeight *= roll;
            });

            const cappedWeight = Math.min(safeMaxWeight * 1.75, Math.max(0.1, adjustedWeight));
            return parseFloat(cappedWeight.toFixed(2));
        }

        _getEffectiveCapacity(rod, fish) {
            const baseCapacity = Number(rod?.capacity);
            if (!Number.isFinite(baseCapacity) || baseCapacity <= 0) return 0;

            const fishWeight = Number(fish?.weight);
            if (!Number.isFinite(fishWeight) || fishWeight <= 0) return baseCapacity;

            const passive = this._resolveRodPassiveModifiers(rod);
            const threshold = Number(passive.heavyThreshold);
            const penalty = Number(passive.heavyPenalty);

            if (Number.isFinite(penalty) && penalty > 0 && Number.isFinite(threshold) && threshold > 0 && threshold < 1) {
                if (fishWeight > (baseCapacity * threshold)) {
                    return Math.max(0.1, baseCapacity * (1 - Math.min(0.9, Math.max(0, penalty))));
                }
            }

            return baseCapacity;
        }

        _getAutoTimingMultipliers() {
            const rod = RODS.find((entry) => entry.id === this.state.rod) || RODS[0];
            const bait = BAITS.find((entry) => entry.id === this.state.bait) || BAITS[0];
            const combined = this._buildCombinedPassiveModifiers({
                rod,
                bait,
                includeCraftedFamily: true
            }).modifiers;

            return {
                autoCycleMultiplier: Number.isFinite(combined.autoCycleMultiplier) && combined.autoCycleMultiplier > 0
                    ? combined.autoCycleMultiplier
                    : 1,
                hookTimingMultiplier: Number.isFinite(combined.hookTimingMultiplier) && combined.hookTimingMultiplier > 0
                    ? combined.hookTimingMultiplier
                    : 1
            };
        }

        _buildRngContext(mode = 'manual') {
            const rod = RODS.find(r => r.id === this.state.rod) || RODS[0];
            const bait = BAITS.find(b => b.id === this.state.bait) || BAITS[0];

            let baseLuck = (rod?.luck || 0) + (bait?.luck || 0);
            if (this.state.activeAmulet === this.state.location && AMULETS[this.state.activeAmulet]) {
                baseLuck += AMULETS[this.state.activeAmulet].luckBonus;
            }

            const weatherMultiplier = this.getWeatherMultiplier();
            const totalLuck = baseLuck * weatherMultiplier;
            const luckMultiplier = this._computeLuckMultiplier(totalLuck);
            const weatherInfo = WEATHER_DATA[this.weather.current] || WEATHER_DATA.clear;
            const passiveModifiers = this._buildCombinedPassiveModifiers({ rod, bait }).modifiers;

            return {
                mode,
                location: this.state.location,
                rod,
                bait,
                baseLuck,
                totalLuck,
                weatherMultiplier,
                luckMultiplier,
                weatherInfo,
                passiveModifiers
            };
        }

        _rollChance(baseChance, maxChance, luckMultiplier) {
            const safeBase = Number.isFinite(baseChance) ? Math.max(0, baseChance) : 0;
            if (safeBase <= 0) return 0;

            const safeLuckMultiplier = Number.isFinite(luckMultiplier) ? Math.max(1, luckMultiplier) : 1;
            const cap = Number.isFinite(maxChance) ? Math.max(0, maxChance) : 0.95;
            return Math.min(cap, safeBase * safeLuckMultiplier);
        }

        _rollCatchCandidate(mode = 'manual', rng = Math.random) {
            const context = this._buildRngContext(mode);
            const craftedUse = this._consumeActiveBaitBenchCharge(mode);
            const craftedModifiers = this._resolveCraftedFamilyModifiers(craftedUse?.family);
            context.activeCraftedBaitFamily = craftedUse?.family || null;
            context.passiveModifiers = this._mergePassiveModifiers(context.passiveModifiers, craftedModifiers);
            context.rodCastEffect = this._prepareRodCastEffect(context, rng);
            if (context.rodCastEffect) {
                context.passiveModifiers = this._mergePassiveModifiers(
                    context.passiveModifiers,
                    context.rodCastEffect.modifiers
                );
            }

            const rarityKey = this.rollRarity(
                context.location,
                context.luckMultiplier,
                rng,
                context.passiveModifiers?.rarityBias || {},
                context.rodCastEffect?.accessRarities || []
            );
            const fishTemplate = this.pickFish(context.location, rarityKey, rng);

            if (!fishTemplate) {
                return { context, fish: null };
            }

            const mean = (fishTemplate.minWeight + fishTemplate.maxWeight) / 2;
            const baseWeight = this.generateWeight(mean, fishTemplate.maxWeight, rng);
            const weight = this._applyWeightBiases(baseWeight, fishTemplate.maxWeight, context.passiveModifiers, rng);
            const rarityMeta = this._getRarityMeta(rarityKey);
            const locationName = LOCATIONS[context.location]?.name || context.location;

            let finalValue = Math.floor(weight * rarityMeta.mult);
            let appliedBuff = null;

            const buffChance = Math.min(1, Math.max(0, Number(context.weatherInfo.buffChance) || 0));
            if (context.weatherInfo.buff && rng() < buffChance) {
                appliedBuff = context.weatherInfo.buff;
                finalValue = Math.floor(finalValue * (1 + (context.weatherInfo.valBonus || 0)));
            }

            return {
                context,
                fish: {
                    name: fishTemplate.name,
                    rarity: rarityKey,
                    weight,
                    value: finalValue,
                    location: locationName,
                    buff: appliedBuff,
                    _rngLuckMultiplier: context.luckMultiplier,
                    _rodCastEffect: context.rodCastEffect || null
                }
            };
        }

        startCast() {
            if (this.minigame.active) return false; // Prevent double cast
            if (this._isAutoFishingActive()) {
                this.ui.updateStatus('Disable auto fishing before casting manually.', 'warning');
                return false;
            }
            this.setFishingMode('manual');

            // Rate limiting to prevent rapid cast exploits
            const now = Date.now();
            if (this.lastCastTime && now - this.lastCastTime < 500) {
                this.ui.updateStatus('Slow down. Wait a moment before casting again.', 'warning');
                document.getElementById('action-btn').textContent = 'Cast Line';
                this.setFishingMode('idle');
                return false;
            }
            this.lastCastTime = now;
            document.getElementById('action-btn').textContent = 'Waiting...';

            const roll = this._rollCatchCandidate('manual');
            if (!roll.fish) {
                this.log('Nothing bit...');
                this._recordMeasuredRodOutcome('empty', null, 'manual');
                document.getElementById('action-btn').textContent = 'Cast Line';
                this.setFishingMode('idle');
                return false;
            }

            this.startMinigame(roll.fish);

            return true;
        }

        rollRarity(location, luckMultiplier = 1, rng = Math.random, rarityBias = {}, accessRarities = []) {
            const allowedLockedRarities = new Set(Array.isArray(accessRarities) ? accessRarities : []);
            const ordered = this._getLocationRarityOrder(location).filter((rarityKey) => {
                return !ROD_LOCKED_RARITIES.has(rarityKey) || allowedLockedRarities.has(rarityKey);
            });
            if (!Array.isArray(ordered) || ordered.length === 0) return 'common';

            const fallback = ordered.includes('common') ? 'common' : ordered[0];
            const rarestFirst = [...ordered].reverse();

            // Scarcity-first: each rarity has an absolute independent chance.
            // No pity, no rerolls, no guaranteed drops.
            for (const rarityKey of rarestFirst) {
                if (rarityKey === fallback) continue;
                const meta = this._getRarityMeta(rarityKey);
                const biasScalar = Number(rarityBias?.[rarityKey]);
                const safeBias = Number.isFinite(biasScalar) && biasScalar > 0 ? biasScalar : 1;
                const baseChance = this._rollChance(meta.baseChance, meta.maxChance, luckMultiplier);
                const safeCap = Number.isFinite(meta.maxChance) ? Math.max(0, meta.maxChance) : 0.95;
                const chance = Math.min(safeCap, baseChance * safeBias);
                if (chance > 0 && rng() < chance) {
                    return rarityKey;
                }
            }

            return fallback;
        }

        pickFish(loc, rarity, rng = Math.random) {
            const table = FISH_DB[loc]?.[rarity];
            if (!table) return null; // Fallback
            const f = table[Math.floor(rng() * table.length)];
            return { name: f[0], minWeight: f[1], maxWeight: f[2] };
        }

        generateWeight(mean, max, rng = Math.random) {
            // Simplified variance
            let w = mean + ((rng() - 0.5) * (mean * 0.5));
            return parseFloat(Math.min(max * 1.5, Math.max(0.1, w)).toFixed(2));
        }

        _applyCatchValueModifiers(
            fish,
            { comboBefore = 0, comboAfter = 0, luckMultiplier = 1, showFx = true, rng = Math.random } = {}
        ) {
            const safeComboBefore = Number.isFinite(comboBefore) ? Math.max(0, comboBefore) : 0;
            const comboBonus = 1 + (safeComboBefore * 0.1);
            fish.value = Math.floor(fish.value * comboBonus);

            this._rollVariant(fish, luckMultiplier, { showFx, rng });
            const isCrit = this._rollCritical(fish, comboAfter, { showFx, rng });

            return { comboBonus, isCrit };
        }

        /* --- MECHANICS: MINIGAME --- */
        startMinigame(fishData) {
            this.minigame.fishOnLine = fishData;
            this.minigame.active = true;
            this._startGameplayLoop();

            const rarityMeta = this._getRarityMeta(fishData.rarity);
            const diff = rarityMeta.difficulty;

            // Setup Logic
            this.minigame.pos = 0;
            this.minigame.direction = 1;
            const targetWidthMultiplier = Number(fishData?._rodCastEffect?.targetWidthMultiplier);
            const safeTargetWidthMultiplier = Number.isFinite(targetWidthMultiplier) && targetWidthMultiplier > 0
                ? targetWidthMultiplier
                : 1;
            this.minigame.targetWidth = Math.max(10, (30 * diff) * safeTargetWidthMultiplier);
            this.minigame.targetStart = Math.random() * (90 - this.minigame.targetWidth) + 5;

            // Base speed scales by rarity metadata.
            const baseSpeed = Number.isFinite(rarityMeta.speed) ? rarityMeta.speed : 1.0;

            // Apply weather difficulty modifier
            const weatherMod = (WEATHER_DATA[this.weather.current] || WEATHER_DATA.clear).difficulty_mod || 1.0;
            this.minigame.speed = (baseSpeed + (Math.random() * 0.5)) * weatherMod;

            // Update UI
            this.ui.showMinigame(true);
            this._setFishStatus(this._buildReelingStatus(fishData), fishData);
            document.getElementById('action-btn').textContent = "REEL NOW!";
            document.getElementById('action-btn').classList.add('reeling');

            // Set CSS for target zone
            const zone = document.getElementById('mg-target');
            zone.style.left = this.minigame.targetStart + '%';
            zone.style.width = this.minigame.targetWidth + '%';
        }

        updateMinigame() {
            // Move indicator
            this.minigame.pos += this.minigame.speed * this.minigame.direction;
            if (this.minigame.pos >= 100 || this.minigame.pos <= 0) {
                this.minigame.direction *= -1;
            }
            // Clamp to [0, 100] to prevent out-of-bounds hit detection on edge frames
            this.minigame.pos = Math.max(0, Math.min(100, this.minigame.pos));
            // Update DOM directly for smoothness
            document.getElementById('mg-indicator').style.left = this.minigame.pos + '%';
        }

        resolveMinigame() {
            if (!this.minigame.active) return;

            let fish = this.minigame.fishOnLine;
            const rod = RODS.find(r => r.id === this.state.rod);
            const effectiveCapacity = this._getEffectiveCapacity(rod, fish);
            const hit = this.minigame.pos >= this.minigame.targetStart &&
                this.minigame.pos <= (this.minigame.targetStart + this.minigame.targetWidth);

            this.minigame.active = false;
            this._stopGameplayLoop();
            this.ui.showMinigame(false);
            document.getElementById('action-btn').classList.remove('reeling');

            if (!hit) {
                this.catchFail(fish);
                return;
            }

            // Special rods occasionally keep an impossible fish live, but never on a guarantee.
            if (fish.weight > effectiveCapacity) {
                const rescuedFish = this._maybeRescueOverweightFish(fish, rod);
                if (rescuedFish) {
                    fish = rescuedFish;
                    this.minigame.fishOnLine = rescuedFish;
                    this.log(`${rod.name}: ${rescuedFish._rodRescuedBy} held ${rescuedFish.name} in line.`);
                    this.ui.floatTextStyled((rescuedFish._rodRescuedBy || 'Held').toUpperCase(), fish?._rodCastEffect?.color || '#f59e0b');
                } else {
                    const capacityText = effectiveCapacity < rod.capacity
                        ? `${effectiveCapacity.toFixed(1)}kg effective`
                        : `${rod.capacity}kg max`;
                    this.log(`Released: ${fish.name} (${fish.weight}kg) was too heavy for your ${rod.name} (${capacityText}).`);
                    this._setFishStatus(`${fish.name} broke free. Too heavy.`, fish, "danger");
                    this.ui.floatText("TOO HEAVY!");
                    this.achievementManager.onWeightFail(fish);
                    this._recordMeasuredRodOutcome('escape', fish, 'manual');
                    this.breakCombo();
                    this.setFishingMode('idle');
                    return;
                }
            }

            this._catchAuthorized = true; // Vuln #2: authorize catch before calling
            this.catchSuccess(fish);
        }

        /* --- MECHANICS: RESOLUTION --- */
        catchSuccess(fish) {
            // Vuln #2: Only accept catches from legitimate game flow
            if (!this._catchAuthorized) return;
            this._catchAuthorized = false;

            // Vuln #4: Rate limit ï¿½ prevent loop-based speedhacks
            const now = Date.now();
            if (this._lastCatchTime && now - this._lastCatchTime < 400) return;
            this._lastCatchTime = now;

            // 1. Apply combo-scaled value, then variant/critical rolls.
            const comboBefore = this.state.combo;
            this.incrementCombo();
            const comboAfter = this.state.combo;
            this.setFishingMode('manual');

            const luckMultiplier = Number(fish._rngLuckMultiplier) > 0
                ? fish._rngLuckMultiplier
                : this._buildRngContext('manual').luckMultiplier;

            const { isCrit } = this._applyCatchValueModifiers(fish, {
                comboBefore,
                comboAfter,
                luckMultiplier,
                showFx: true
            });

            // 2. Add to Inventory with unique ID
            const storeOutcome = this._storeCaughtFish(fish, 'manual');
            const speciesDiscovery = this.recordCaughtSpecies(fish);
            this._unlockBaitBenchRecipeBySpecies(speciesDiscovery.name, { logUnlock: speciesDiscovery.isNew });
            this.state.totalCatches++;
            this.inventory.render();
            this._consumeAmulet();

            // 3. XP
            const xpGained = this._getRarityMeta(fish.rarity).xp;
            this.gainXp(xpGained);
            this._recordFishingResults('manual', { stored: storeOutcome.stored, xpGained });

            // 4. Build log message
            let logMsg = `Caught ${fish.name} (${fish.weight}kg)`;
            if (fish.variant) logMsg = `${fish.variant.icon} ${fish.name} [${fish.variant.label}]`;
            if (isCrit) logMsg += ` ${this._lastCriticalStatus?.text || 'CRITICAL!'}`;
            logMsg += ` | +${fish.value} coins value`;
            this.log(logMsg);

            this._updateCatchStatus(fish, {
                mode: 'manual',
                isCrit,
                storeOutcome
            });
            this.ui.updateLastCatch(fish);
            this._recordMeasuredRodOutcome('catch', fish, 'manual');
            this.ui.renderStats();
            if (speciesDiscovery.isNew) {
                this.log(`New species discovered: ${speciesDiscovery.name}.`);
                this.ui.renderSpeciesTracker();
            }

            // 5. Check milestone rewards
            this._checkMilestone();

            // 6. Achievement check
            this.achievementManager.onCatch(fish);

            this.saveSystem.save();
            this.setFishingMode('idle');
        }

        catchFail(fish) {
            const rod = RODS.find((entry) => entry.id === this.state.rod) || RODS[0];
            const rescuedFish = this._maybeRescueFailedCatch(fish, rod);
            if (rescuedFish) {
                const rescueRarity = rescuedFish._rodRescueMode === 'downgraded'
                    ? this._getRarityMeta(rescuedFish.rarity).name
                    : this._getRarityMeta(fish.rarity).name;
                const rescueMsg = rescuedFish._rodRescueMode === 'downgraded'
                    ? `${rescuedFish._rodRescuedBy} softened the line. ${fish.name} slips in as ${rescueRarity}.`
                    : `${rescuedFish._rodRescuedBy} held the line. ${fish.name} stays with you.`;
                this.log(rescueMsg);
                this._setFishStatus(rescueMsg, fish, 'success');
                this.ui.floatTextStyled((rescuedFish._rodRescuedBy || 'Held').toUpperCase(), fish?._rodCastEffect?.color || '#f59e0b');
                this._catchAuthorized = true;
                this.catchSuccess(rescuedFish);
                return;
            }

            // Near-miss feedback with rotating dynamic messages.
            const rarityMeta = this._getRarityMeta(fish.rarity);
            const rarityName = rarityMeta.name;
            const tierIndex = Math.max(0, Object.keys(RARITY).indexOf(fish.rarity));
            const msg = this._buildEscapeMessage(fish, rarityName, tierIndex);

            let statusType = 'warning';
            if (tierIndex >= 4) {
                statusType = 'danger';
                this.ui.floatTextStyled(`${rarityName.toUpperCase()} ESCAPED!`, rarityMeta.color);
            } else if (tierIndex >= 3) {
                this.ui.floatTextStyled(`${rarityName} escaped!`, rarityMeta.color);
            }

            this.log(msg);
            this._setFishStatus(msg, fish, statusType);
            this._recordMeasuredRodOutcome('escape', fish, 'manual');
            this.breakCombo();
            this.setFishingMode('idle');
        }

        _pickEscapeMessage(tierKey, messages) {
            if (!Array.isArray(messages) || messages.length === 0) {
                return 'The fish got away.';
            }

            let index = Math.floor(Math.random() * messages.length);
            const lastIndex = this._lastEscapeMessageByTier[tierKey];

            if (messages.length > 1 && index === lastIndex) {
                index = (index + 1 + Math.floor(Math.random() * (messages.length - 1))) % messages.length;
            }

            this._lastEscapeMessageByTier[tierKey] = index;
            return messages[index];
        }

        _pickGeneratedMessage(key, messages, fallback = '') {
            if (!Array.isArray(messages) || messages.length === 0) {
                return fallback;
            }

            let index = Math.floor(Math.random() * messages.length);
            const lastIndex = this._lastGeneratedMessageByKey[key];

            if (messages.length > 1 && index === lastIndex) {
                index = (index + 1 + Math.floor(Math.random() * (messages.length - 1))) % messages.length;
            }

            this._lastGeneratedMessageByKey[key] = index;
            return messages[index];
        }

        _setFishStatus(message, fishOrName, type = 'normal') {
            const fishName = typeof fishOrName === 'string'
                ? fishOrName
                : String(fishOrName?.name || '');

            if (fishName && typeof this.ui.updateStatusWithFish === 'function') {
                this.ui.updateStatusWithFish(message, fishName, type);
                return;
            }

            this.ui.updateStatus(message, type);
        }

        _updateCatchStatus(fish, { mode = 'manual', isCrit = false, storeOutcome = null } = {}) {
            const prefix = mode === 'auto' ? 'Auto caught ' : 'Caught ';
            let fallback = `${prefix}${fish.name}.`;

            const parts = [{ text: prefix }];
            if (fish.variant) {
                const variantText = `${fish.variant.icon} ${fish.variant.label}`;
                parts.push({
                    text: variantText,
                    className: 'fish-variant-token fish-variant-status'
                });
                parts.push({ text: ' ' });
                fallback = `${prefix}${variantText} ${fish.name}.`;
            }

            parts.push({
                text: fish.name,
                className: 'fish-name-token fish-name-status'
            });
            parts.push({ text: '.' });

            if (isCrit) {
                const critText = this._lastCriticalStatus?.text || 'CRITICAL!';
                parts.push({ text: ` ${critText}` });
                fallback += ` ${critText}`;
            }

            if (storeOutcome?.action === 'sold') {
                const soldText = ' Inventory full: catch auto-sold.';
                parts.push({ text: soldText });
                fallback += soldText;
            } else if (storeOutcome?.action === 'rejected') {
                const rejectedText = ` Inventory full (${MAX_INVENTORY_FISH}).`;
                parts.push({ text: rejectedText });
                fallback += rejectedText;
            }

            if (typeof this.ui.updateStatusRich === 'function') {
                this.ui.updateStatusRich(parts, 'success');
                return;
            }

            this._setFishStatus(fallback, fish, 'success');
        }

        _buildReelingStatus(fish) {
            const rarityUpper = fish.rarity.toUpperCase();
            const messages = [
                `Hooked! Reeling in ${rarityUpper} ${fish.name}...`,
                `Line tension rising. Pulling ${rarityUpper} ${fish.name} to shore...`,
                `${rarityUpper} signal confirmed. Reeling ${fish.name} now...`,
                `Rod loaded. Dragging ${fish.name} (${rarityUpper}) through the current...`,
                `Contact locked. Bringing in ${rarityUpper} ${fish.name}...`,
                `Splash on the surface. Reeling ${fish.name} before it dives again...`,
                `Steady hands. ${rarityUpper} ${fish.name} is fighting back...`,
                `Hook set clean. Hauling ${fish.name} (${rarityUpper}) toward you...`,
                `Pressure spike detected. Reeling ${rarityUpper} ${fish.name} hard...`,
                `Keep the line tight. ${fish.name} is almost in range...`,
                `${rarityUpper} catch on the line. Recovering ${fish.name} now...`,
                `The reel is humming. Pulling ${fish.name} out of deep water...`,
                `Target acquired: ${rarityUpper} ${fish.name}. Final reel phase...`,
                `Fish turning left. Countering and reeling ${fish.name}...`,
                `Turbulence ahead. Holding angle on ${rarityUpper} ${fish.name}...`,
                `Good hook depth. Bringing ${fish.name} in with controlled drag...`,
                `${fish.name} is thrashing. Reeling sequence continues...`,
                `${rarityUpper} strike maintained. Keep pressure on ${fish.name}...`,
                `Almost there. Guiding ${fish.name} into landing position...`,
                `Final pull! Securing ${rarityUpper} ${fish.name}...`
            ];

            return this._pickGeneratedMessage('reeling_status', messages, `Hooked! Reeling in ${rarityUpper} ${fish.name}...`);
        }

        _pickCriticalStatus() {
            const statuses = [
                { text: 'CRITICAL!', color: '#f43f5e' },
                { text: 'DEAD CENTER!', color: '#fb7185' },
                { text: 'PERFECT STRIKE!', color: '#ef4444' },
                { text: 'PRECISION HIT!', color: '#f97316' },
                { text: 'SHARP REEL!', color: '#f59e0b' },
                { text: 'MAX IMPACT!', color: '#eab308' },
                { text: 'FLAWLESS HOOKSET!', color: '#84cc16' },
                { text: 'PURE MOMENTUM!', color: '#22c55e' },
                { text: 'SURGE BONUS!', color: '#10b981' },
                { text: 'RIPTIDE HIT!', color: '#14b8a6' },
                { text: 'LOCKED IN!', color: '#06b6d4' },
                { text: 'BULLSEYE REEL!', color: '#0ea5e9' },
                { text: 'HIGH-TENSION WIN!', color: '#3b82f6' },
                { text: 'CHAIN REACTION!', color: '#6366f1' },
                { text: 'VECTOR SPIKE!', color: '#8b5cf6' },
                { text: 'SPECTRUM BREAK!', color: '#a855f7' },
                { text: 'OVERDRIVE!', color: '#d946ef' },
                { text: 'QUANTUM SNAP!', color: '#ec4899' },
                { text: 'MYTHIC TIMING!', color: '#f43f5e' },
                { text: 'ULTRA REEL!', color: '#ff5a8a' }
            ];

            return this._pickGeneratedMessage(
                'critical_status',
                statuses,
                { text: 'CRITICAL!', color: '#f43f5e' }
            );
        }

        _buildEscapeMessage(fish, rarityName, tierIndex) {
            const legendaryMythicMessages = [
                `A ${rarityName.toUpperCase()} shadow thrashed once and snapped the line: ${fish.name} (${fish.weight}kg).`,
                `${fish.name} (${fish.weight}kg) breached, flashed, and vanished. ${rarityName.toUpperCase()} chance lost.`,
                `The reel screamed, then went silent. ${rarityName.toUpperCase()} ${fish.name} got free at the last second.`,
                `One heartbeat from victory, then nothing. ${rarityName.toUpperCase()} ${fish.name} escaped.`,
                `You had visual contact, then the line cut loose. ${rarityName.toUpperCase()} ${fish.name} is gone.`
            ];

            const epicMessages = [
                `Power surge on the line. ${rarityName} ${fish.name} (${fish.weight}kg) tore away.`,
                `The hook held, then slipped. ${rarityName} ${fish.name} disappeared below.`,
                `${fish.name} twisted free right before landing. ${rarityName} catch missed.`,
                `Surface ripple, empty line. ${rarityName} ${fish.name} escaped cleanly.`,
                `Bad timing on the reel-in. ${rarityName} ${fish.name} (${fish.weight}kg) got away.`
            ];

            const rareMessages = [
                `${rarityName} pull detected, but ${fish.name} dodged the hook set.`,
                `${fish.name} made one sharp turn and slipped free.`,
                `Line tension dropped for a split second. ${rarityName} ${fish.name} escaped.`,
                `${rarityName} ${fish.name} (${fish.weight}kg) shook loose and vanished below.`,
                `You nearly banked a ${rarityName} catch, but ${fish.name} got away.`
            ];

            const commonUncommonMessages = [
                `${fish.name} nibbled, then disappeared into the weeds.`,
                `${fish.name} escaped before the hook could lock.`,
                `Quick splash, empty line. ${fish.name} is gone.`,
                `${fish.name} slipped the hook and darted away.`,
                `No catch this cast. ${fish.name} escaped.`
            ];

            if (tierIndex >= 4) {
                return this._pickEscapeMessage('legendary_mythic', legendaryMythicMessages);
            }
            if (tierIndex >= 3) {
                return this._pickEscapeMessage('epic', epicMessages);
            }
            if (tierIndex >= 2) {
                return this._pickEscapeMessage('rare', rareMessages);
            }
            return this._pickEscapeMessage('common_uncommon', commonUncommonMessages);
        }

        _consumeAmulet() {
            const biome = this.state.location;
            if (this.state.activeAmulet !== biome) return;
            if (!this.state.amuletStock[biome] || this.state.amuletStock[biome] <= 0) {
                this.state.activeAmulet = null;
                return;
            }
            this.state.amuletStock[biome]--;
            this.achievementManager.onAmuletUsed();
            if (this.state.amuletStock[biome] <= 0) {
                this.state.activeAmulet = null;
                this.log(`Amulet for ${LOCATIONS[biome].name} has been used up!`);
            }
        }

        /* --- COMBO SYSTEM --- */
        incrementCombo() {
            // Manual mode capped at 20x combo
            if (this.state.combo < 20) {
                this.state.combo++;
                if (this.state.combo > 1) this.ui.floatText(`Combo x${this.state.combo}!`);
            }
            // Cap reached ï¿½ UI already shows "20x", no log spam needed
            this.achievementManager.onComboChange(this.state.combo, this.autoFish.enabled);
            if (this.activeFishingMode === 'auto' || this.activeFishingMode === 'manual') {
                this._setFishingComboBonus(this.activeFishingMode, this.state.combo * 10);
            }
            this.ui.renderStats();
        }

        breakCombo() {
            if (this.state.combo > 1) this.log(`Combo of ${this.state.combo} lost.`);
            this.state.combo = 0;
            if (this.activeFishingMode === 'auto' || this.activeFishingMode === 'manual') {
                this._setFishingComboBonus(this.activeFishingMode, 0);
            }
            this.ui.renderStats();
        }

        /* --- XP & LEVELS --- */
        gainXp(amount) {
            this.state.xp += amount;
            while (this.state.xp >= this.getXpNext()) {
                this.state.xp -= this.getXpNext();
                this.state.level++;
                this.log(`LEVEL UP! You are now level ${this.state.level}`);
                this.ui.floatText("LEVEL UP!");
            }
            this.ui.renderStats();
        }

        getXpNext() {
            return this.state.level * 1000 + Math.pow(this.state.level, 2) * 100;
        }

        /* --- AUTO-FISHING SYSTEM (Background-safe via Web Worker) --- */
        toggleAutoFish() {
            const enablingAutoFish = !this.autoFish.enabled;
            if (enablingAutoFish && this._isManualFishingActive()) {
                this.ui.updateStatus('Finish the manual catch before enabling auto fishing.', 'warning');
                return false;
            }

            this.autoFish.enabled = enablingAutoFish;
            this.state.autoFishEnabled = this.autoFish.enabled;
            const btn = document.getElementById('auto-fish-btn');
            const castBtn = document.getElementById('action-btn');

            if (this.autoFish.enabled) {
                btn.textContent = 'Disable Auto Fish';
                btn.classList.add('active');
                this.setFishingMode('auto');
                this.log('Auto-fishing ENABLED (runs in background).');
                this.startAutoFishCycle();
            } else {
                btn.textContent = 'Enable Auto Fish';
                btn.classList.remove('active');
                castBtn.textContent = 'Cast Line';
                this.autoFish.phase = 'idle';
                this._cancelWorkerTimeout(this.autoFish.timer);
                this.autoFish.timer = null;
                this._stopAutoCooldownLoop();
                this.ui.showMinigame(false);
                document.getElementById('auto-cooldown-container').classList.remove('active');
                const cooldownFill = document.getElementById('cooldown-bar-fill');
                if (cooldownFill) cooldownFill.style.transform = 'scaleX(0)';
                this.ui.updateStatus('Auto-fishing disabled. Ready to cast.');
                this.log('Auto-fishing DISABLED.');
                this.resetFishingResults('auto');
                this.setFishingMode('idle');
            }
            this.ui.renderStats();
            this.saveSystem.save();
            return true;
        }

        startAutoFishCycle() {
            if (!this.autoFish.enabled) return;
            this.setFishingMode('auto');

            this.autoFish.phase = 'casting';
            document.getElementById('action-btn').textContent = 'Auto Mode';

            // Randomized cooldown between 1-3 seconds for realistic auto-fishing
            const timing = this._getAutoTimingMultipliers();
            const cooldown = Math.max(350, (1000 + Math.random() * 2000) * timing.autoCycleMultiplier);

            // Track cooldown timing for background sync
            this.autoFish.cooldownStart = Date.now();
            this.autoFish.cooldownDuration = cooldown;

            // Show and animate cooldown progress bar
            const container = document.getElementById('auto-cooldown-container');
            const fill = document.getElementById('cooldown-bar-fill');
            container.classList.add('active');
            fill.style.transform = 'scaleX(0)';
            this._startAutoCooldownLoop();

            // Use Worker timer ï¿½ fires reliably even in background tabs
            this.autoFish.timer = this._workerTimeout(() => {
                if (!this.autoFish.enabled) return;
                container.classList.remove('active');
                this.autoCast();
            }, cooldown);
        }

        autoCast() {
            if (!this.autoFish.enabled) return;

            const roll = this._rollCatchCandidate('auto');
            const rod = roll.context.rod;
            const fish = roll.fish;

            if (!fish) {
                this.log('Nothing bit. Retrying auto-fish cycle.');
                this.ui.updateStatus('Nothing bit. Casting again.');
                this._recordMeasuredRodOutcome('empty', null, 'auto');
                this.startAutoFishCycle();
                return;
            }

            this.minigame.fishOnLine = fish;

            // Phase 2: Hook Time (based on rod speed, very fast)
            this.autoFish.phase = 'hooking';
            const hookMultiplier = Number(roll.context?.passiveModifiers?.hookTimingMultiplier);
            const safeHookMultiplier = Number.isFinite(hookMultiplier) && hookMultiplier > 0 ? hookMultiplier : 1;
            const baseHookDelay = Math.max(100, 500 - (rod.speed * 8));
            const hookDelay = Math.max(80, baseHookDelay * safeHookMultiplier);
            this.ui.updateStatus('Waiting for a bite...');

            this.autoFish.timer = this._workerTimeout(() => {
                if (!this.autoFish.enabled) return;
                this.autoReel();
            }, hookDelay);
        }

        autoReel() {
            if (!this.autoFish.enabled) return;

            const fish = this.minigame.fishOnLine;
            this.autoFish.phase = 'reeling';
            this._setFishStatus(this._buildReelingStatus(fish), fish);
            document.getElementById('action-btn').textContent = 'Reeling...';

            // Phase 3: Reel Time (0.5 seconds - faster than manual)
            this.autoFish.timer = this._workerTimeout(() => {
                if (!this.autoFish.enabled) return;
                this.autoResolve();
            }, 500);
        }

        autoResolve() {
            if (!this.autoFish.enabled) return;

            let fish = this.minigame.fishOnLine;
            const rod = RODS.find(r => r.id === this.state.rod) || RODS[0];
            const effectiveCapacity = this._getEffectiveCapacity(rod, fish);

            // Capacity check: special rods sometimes salvage an impossible load, but never on a certainty.
            if (fish.weight > effectiveCapacity) {
                const rescuedFish = this._maybeRescueOverweightFish(fish, rod);
                if (!rescuedFish) {
                    const capacityText = effectiveCapacity < rod.capacity
                        ? `${effectiveCapacity.toFixed(1)}kg effective`
                        : `${rod.capacity}kg max`;
                    this.log(`Released: ${fish.name} (${fish.weight}kg) was too heavy for ${rod.name} (${capacityText}).`);
                    this._setFishStatus(`${fish.name} broke free. Too heavy.`, fish, 'danger');
                    this.achievementManager.onWeightFail(fish);
                    this._recordMeasuredRodOutcome('escape', fish, 'auto');
                    this.breakCombo();
                    this.minigame.fishOnLine = null;
                    this.autoFish.phase = 'idle';
                    this.startAutoFishCycle();
                    return;
                }

                fish = rescuedFish;
                this.minigame.fishOnLine = rescuedFish;
                this.log(`${rod.name}: ${rescuedFish._rodRescuedBy} held ${rescuedFish.name} in line.`);
            }

            // Apply combo-scaled value, then variant/critical rolls.
            const comboBefore = this.state.combo;

            // Auto-fishing has a 10x combo limit for balance
            if (this.state.combo < 10) {
                this.incrementCombo();
            }
            const comboAfter = this.state.combo;

            const luckMultiplier = Number(fish._rngLuckMultiplier) > 0
                ? fish._rngLuckMultiplier
                : this._buildRngContext('auto').luckMultiplier;
            const { isCrit } = this._applyCatchValueModifiers(fish, {
                comboBefore,
                comboAfter,
                luckMultiplier,
                showFx: true
            });

            // Add to Inventory with unique ID
            const storeOutcome = this._storeCaughtFish(fish, 'auto');
            const speciesDiscovery = this.recordCaughtSpecies(fish);
            this._unlockBaitBenchRecipeBySpecies(speciesDiscovery.name, { logUnlock: speciesDiscovery.isNew });
            this.state.totalCatches++;
            this.inventory.render();
            this._consumeAmulet();
            const xpGained = this._getRarityMeta(fish.rarity).xp;
            this.gainXp(xpGained);
            this._recordFishingResults('auto', { stored: storeOutcome.stored, xpGained });

            let logMsg = `Auto caught ${fish.name} (${fish.weight}kg)`;
            if (fish.variant) logMsg = `Auto ${fish.variant.icon} ${fish.name} [${fish.variant.label}]`;
            if (isCrit) logMsg += ` ${this._lastCriticalStatus?.text || 'CRITICAL!'}`;
            logMsg += ` | +${fish.value} coins value`;
            this.log(logMsg);

            this._updateCatchStatus(fish, {
                mode: 'auto',
                isCrit,
                storeOutcome
            });
            this.ui.updateLastCatch(fish);
            this._recordMeasuredRodOutcome('catch', fish, 'auto');
            this.ui.renderStats();
            if (speciesDiscovery.isNew) {
                this.log(`New species discovered: ${speciesDiscovery.name}.`);
                this.ui.renderSpeciesTracker();
            }
            this._checkMilestone();
            this.achievementManager.onCatch(fish);
            this.saveSystem.save();

            this.minigame.fishOnLine = null;

            // Start next cycle
            this.autoFish.phase = 'idle';
            this.startAutoFishCycle();
        }

        /* --- OFFLINE PROGRESSION --- */
        processOfflineCatches() {
            // E2 fix: Prevent repeated calls from console
            if (this._offlineProcessed) return;
            this._offlineProcessed = true;

            if (!this.state.autoFishEnabled) return;
            if (!this.state.lastSaveTimestamp) return;

            const now = Date.now();
            const rawElapsed = now - this.state.lastSaveTimestamp;
            // E1 fix: Cap offline time to 8 hours to prevent time-travel exploits
            const MAX_OFFLINE_MS = 28800000; // 8 hours
            const elapsed = Math.min(Math.max(rawElapsed, 0), MAX_OFFLINE_MS);
            this.achievementManager.onOfflineReturn(rawElapsed);
            if (elapsed < 5000) return; // Less than 5 seconds away ï¿½ not worth simulating

            const rod = RODS.find(r => r.id === this.state.rod);
            const bait = BAITS.find(b => b.id === this.state.bait);
            if (!rod || !bait) return;

            // Average cycle time: ~2.5s cooldown + ~0.3s hook + 0.5s reel = ~3.3s
            const avgCycleMs = 3300;
            const maxCycles = Math.min(Math.floor(elapsed / avgCycleMs), 500); // Cap at 500 to prevent oversized saves
            if (maxCycles <= 0) return;

            let totalFishCaught = 0;
            let totalCoins = 0;
            let totalXpGained = 0;
            let totalNewSpecies = 0;
            let totalRecipeUnlocks = 0;
            let combo = Math.min(this.state.combo, 10);

            this.state.pityCounter = 0;

            for (let i = 0; i < maxCycles; i++) {
                const roll = this._rollCatchCandidate('offline');
                let fish = roll.fish;

                if (!fish) {
                    this._recordMeasuredRodOutcome('empty', null, 'offline');
                    combo = 0;
                    continue;
                }

                // Capacity check ï¿½ special rods can sometimes rescue an impossible catch.
                if (fish.weight > this._getEffectiveCapacity(rod, fish)) {
                    const rescuedFish = this._maybeRescueOverweightFish(fish, rod);
                    if (rescuedFish) {
                        fish = rescuedFish;
                    } else {
                        this._recordMeasuredRodOutcome('escape', fish, 'offline');
                        combo = 0;
                        continue;
                    }
                }

                // Successful catch
                const comboBefore = combo;
                if (combo < 10) combo++;
                this._applyCatchValueModifiers(fish, {
                    comboBefore,
                    comboAfter: combo,
                    luckMultiplier: roll.context.luckMultiplier,
                    showFx: false
                });
                this._recordMeasuredRodOutcome('catch', fish, 'offline');

                // Offline fish go directly to coins (not inventory) to prevent localStorage bloat
                // B2 note: Achievement hooks intentionally not fired for offline catches (limited simulation)
                const speciesDiscovery = this.recordCaughtSpecies(fish.name);
                if (speciesDiscovery.isNew) totalNewSpecies++;
                const recipeUnlock = this._unlockBaitBenchRecipeBySpecies(speciesDiscovery.name, { logUnlock: false });
                if (recipeUnlock.unlocked) totalRecipeUnlocks++;
                totalFishCaught++;
                totalCoins += fish.value;

                // Consume amulet stock
                if (this.state.activeAmulet === this.state.location && this.state.amuletStock[this.state.location] > 0) {
                    this.state.amuletStock[this.state.location]--;
                    if (this.state.amuletStock[this.state.location] <= 0) {
                        this.state.activeAmulet = null;
                    }
                }

                // XP (B3 fix: evaluate getXpNext() fresh each iteration)
                const xpGain = this._getRarityMeta(fish.rarity).xp;
                totalXpGained += xpGain;
                this.state.xp += xpGain;
                while (this.state.xp >= this.getXpNext()) {
                    this.state.xp -= this.getXpNext();
                    this.state.level++;
                }

                this.state.totalCatches++;

                // B1 fix: Check milestones during offline progression
                const c = this.state.totalCatches;
                if (c > 0 && c % 100 === 0) { totalCoins += 15000; }
                else if (c > 0 && c % 50 === 0) { totalCoins += 5000; }
                else if (c > 0 && c % 25 === 0) { totalCoins += 2000; }
                else if (c > 0 && c % 10 === 0) { totalCoins += 500; }
            }

            this.state.combo = combo;
            this.state.lastSaveTimestamp = now;

            if (totalFishCaught > 0) {
                // Add offline earnings directly to coins
                this.addCoins(totalCoins);
                this.achievementManager.onCoinsChange();
                this.showOfflinePopup(elapsed, totalFishCaught, totalCoins, totalXpGained);
                if (totalNewSpecies > 0) {
                    this.log(`Offline discovery: ${totalNewSpecies.toLocaleString('en-US')} new fish species cataloged.`);
                }
                if (totalRecipeUnlocks > 0) {
                    this.log(`Offline prep update: unlocked ${totalRecipeUnlocks.toLocaleString('en-US')} new Bait Bench recipes.`);
                }
            }

            this.saveSystem.save();
        }

        /* --- ACHIEVEMENTS MODAL --- */
        openAchievements() {
            this.closeSettings();
            this.achievementManager.renderModal();
            document.getElementById('achievements-overlay').classList.add('active');
            document.getElementById('achievements-modal').classList.add('active');
        }

        closeAchievements() {
            document.getElementById('achievements-overlay').classList.remove('active');
            document.getElementById('achievements-modal').classList.remove('active');
        }

        /* --- EXPEDITIONS MODAL --- */
        openExpeditions() {
            this.closeSettings();
            this.ui.renderLocations();
            document.getElementById('expeditions-overlay').classList.add('active');
            document.getElementById('expeditions-modal').classList.add('active');
        }

        closeExpeditions() {
            document.getElementById('expeditions-overlay').classList.remove('active');
            document.getElementById('expeditions-modal').classList.remove('active');
        }

        /* --- INVENTORY MODAL --- */
        openInventory() {
            this.closeSettings();
            this.inventory.render();
            document.getElementById('inventory-overlay').classList.add('active');
            document.getElementById('inventory-modal').classList.add('active');
        }

        closeInventory() {
            document.getElementById('inventory-overlay').classList.remove('active');
            document.getElementById('inventory-modal').classList.remove('active');
        }

        /* --- SETTINGS MODAL --- */
        openSettings() {
            this.shop.close();
            this.closeAchievements();
            this.closeInventory();
            this.closeExpeditions();
            this._renderSettingsPanel();
            document.getElementById('settings-overlay').classList.add('active');
            document.getElementById('settings-modal').classList.add('active');
        }

        closeSettings() {
            document.getElementById('settings-overlay').classList.remove('active');
            document.getElementById('settings-modal').classList.remove('active');
        }

        showOfflinePopup(elapsedMs, fishCount, coins, xp) {
            // Format time
            const totalSec = Math.floor(elapsedMs / 1000);
            let timeStr;
            if (totalSec < 60) {
                timeStr = `${totalSec}s`;
            } else if (totalSec < 3600) {
                const m = Math.floor(totalSec / 60);
                const s = totalSec % 60;
                timeStr = `${m}m ${s}s`;
            } else {
                const h = Math.floor(totalSec / 3600);
                const m = Math.floor((totalSec % 3600) / 60);
                timeStr = `${h}h ${m}m`;
            }

            // Create popup element
            const popup = document.createElement('div');
            popup.className = 'offline-popup';
            popup.innerHTML = `
            <div class="offline-popup-header">
                <span>Welcome Back</span>
                <button class="offline-popup-close" onclick="this.parentElement.parentElement.remove()">&times;</button>
            </div>
            <p class="offline-popup-copy">While you were away <strong>${timeStr}</strong>, you caught <strong>${fishCount}</strong> fish worth <strong>${coins.toLocaleString()}</strong> coins.</p>
            <p class="offline-popup-meta">+${xp} XP earned</p>
        `;
            document.body.appendChild(popup);

            // Auto-dismiss after 8 seconds
            setTimeout(() => {
                if (popup.parentNode) {
                    popup.classList.add('offline-popup-fade');
                    setTimeout(() => popup.remove(), 500);
                }
            }, 8000);
        }

        log(msg) {
            const ul = document.getElementById('game-log');
            if (!ul) {
                return;
            }
            const li = document.createElement('li');
            const timestamp = new Date().toLocaleTimeString('en-US', { hour12: false });
            li.textContent = `[${timestamp}] ${msg}`;
            ul.prepend(li);
            if (ul.children.length > 20) ul.lastChild.remove();
        }

        /* --- REWARD SYSTEMS --- */

        /** Roll a variant using absolute rarity rates scaled only by luck multiplier. */
        _rollVariant(fish, luckMultiplier = 1, options = {}) {
            const rng = typeof options.rng === 'function' ? options.rng : Math.random;
            const showFx = options.showFx !== false;

            const variants = [
                { label: 'Prismatic', icon: '??', mult: 10, color: '#e879f9', baseChance: 0.0005, maxChance: 0.02 },
                { label: 'Shadow', icon: '??', mult: 5, color: '#6366f1', baseChance: 0.002, maxChance: 0.05 },
                { label: 'Golden', icon: '??', mult: 3, color: '#facc15', baseChance: 0.01, maxChance: 0.2 }
            ];

            for (const variant of variants) {
                const chance = this._rollChance(variant.baseChance, variant.maxChance, luckMultiplier);
                if (chance > 0 && rng() < chance) {
                    fish.variant = { label: variant.label, icon: variant.icon, mult: variant.mult };
                    fish.value = Math.floor(fish.value * variant.mult);
                    if (showFx) this.ui.floatTextStyled(`${variant.icon} ${variant.label}!`, variant.color);
                    return fish.variant;
                }
            }

            return null;
        }

        /** Roll a critical catch. Returns true if critical hit. Mutates fish value. */
        _rollCritical(fish, combo, options = {}) {
            const rng = typeof options.rng === 'function' ? options.rng : Math.random;
            const showFx = options.showFx !== false;
            const critChance = Math.min(0.9, Math.max(0, 0.08 + (combo * 0.0085)));

            if (rng() < critChance) {
                fish.value = Math.floor(fish.value * 2);
                const critStatus = this._pickCriticalStatus();
                this._lastCriticalStatus = critStatus;
                if (showFx) this.ui.floatTextStyled(critStatus.text, critStatus.color);
                return true;
            }
            return false;
        }

        /** Scarcity model: pity is disabled and always remains zero. */
        _updatePity() {
            this.state.pityCounter = 0;
        }

        /** Scarcity model: no drought bonuses. */
        _getPityBonus() {
            return 0;
        }
        /** Check if totalCatches hit a milestone and award bonus coins. */
        _checkMilestone() {
            const c = this.state.totalCatches;
            let bonus = 0;
            let msg = '';

            if (c > 0 && c % 100 === 0) {
                bonus = 15000;
                msg = `Century catch #${c}. +${bonus.toLocaleString()} bonus coins.`;
            } else if (c > 0 && c % 50 === 0) {
                bonus = 5000;
                msg = `${c} catches milestone. +${bonus.toLocaleString()} bonus coins.`;
            } else if (c > 0 && c % 25 === 0) {
                bonus = 2000;
                msg = `${c} catches milestone. +${bonus.toLocaleString()} bonus coins.`;
            } else if (c > 0 && c % 10 === 0) {
                bonus = 500;
                msg = `${c}-catch streak. +${bonus.toLocaleString()} bonus coins.`;
            }

            if (bonus > 0) {
                this.addCoins(bonus);
                this.achievementManager.onCoinsChange();
                this.log(msg);
                this.ui.floatTextStyled(msg, '#facc15');
                this.ui.renderStats();
            }
        }
    }

    /* --- INIT --- */
    const game = new Game();

    // Event Listener for the Main Button
    document.getElementById('action-btn').addEventListener('click', () => {
        if (game.minigame.active) {
            game.resolveMinigame();
            document.getElementById('action-btn').textContent = 'Cast Line';
        } else {
            game.startCast();
        }
    });

    // Auto-Fish Button Event Listener
    document.getElementById('auto-fish-btn').addEventListener('click', () => {
        game.toggleAutoFish();
    });

    // Frozen public API ï¿½ only these methods are accessible from HTML onclick handlers
    // game itself is NOT global (trapped inside IIFE closure)
    window.GameAPI = Object.freeze({
        shopOpen: () => game.shop.open(),
        shopClose: () => game.shop.close(),
        shopSwitchTab: (t) => game.shop.switchTab(t),
        shopBuyWeather: (k) => game.shop.buyWeather(k),
        shopRemoveWeather: (k) => game.shop.removeWeather(k),
        shopBuyAmulet: (k) => game.shop.buyAmulet(k),
        shopWearAmulet: (k) => game.shop.wearAmulet(k),
        shopBuyRod: (id) => game.shop.buyRod(id),
        shopBuyBait: (id) => game.shop.buyBait(id),
        shopBreakDownBaitDuplicates: () => game.shop.breakDownBaitDuplicates(),
        shopCraftBaitBench: (familyId) => game.shop.craftBaitBenchFamily(familyId),
        shopActivateBaitBench: (familyId) => game.shop.activateBaitBenchFamily(familyId),
        inventorySellAll: () => game.inventory.sellAll(),
        openExpeditions: () => game.openExpeditions(),
        closeExpeditions: () => game.closeExpeditions(),
        openInventory: () => game.openInventory(),
        closeInventory: () => game.closeInventory(),
        openSettings: () => game.openSettings(),
        closeSettings: () => game.closeSettings(),
        manualSave: () => game.saveSystem.manualSave(),
        resetData: () => game.saveSystem.resetData(),
        openAchievements: () => game.openAchievements(),
        closeAchievements: () => game.closeAchievements(),
    });

    const finalizeBoot = () => {
        if (!document.body) return;
        if (!document.body.classList.contains('booting')) return;

        document.body.classList.remove('booting');
        document.body.classList.add('booted');
    };

    const scheduleBootFinalize = () => {
        requestAnimationFrame(() => {
            requestAnimationFrame(() => finalizeBoot());
        });
    };

    // Init Game
    game.init();
    scheduleBootFinalize();
    window.addEventListener('load', scheduleBootFinalize, { once: true });
    setTimeout(finalizeBoot, 3500);

})(); // End IIFE








