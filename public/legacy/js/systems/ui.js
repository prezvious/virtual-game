/**
 * UI HANDLER
 * Handles rendering of stats, locations, weather, status text, and floating feedback.
 */

class UI {
    constructor(game) {
        this.game = game;
    }

    renderAll() {
        this.renderStats();
        this.renderSpeciesTracker();
        this.renderFishingResults();
        this.setFishingZoneMode(this.game.activeFishingMode || 'idle');
        this.renderLocations();
        this.game.shop.render();
        this.game.inventory.render();
    }

    renderStats() {
        const s = this.game.state;
        const rod = RODS.find(r => r.id === s.rod) || RODS[0];

        const coinsEl = document.getElementById('coins-display');
        const levelEl = document.getElementById('level-display');
        const xpCurrentEl = document.getElementById('xp-current');
        const xpNextEl = document.getElementById('xp-next');
        const capacityEl = document.getElementById('capacity-display');
        const comboEl = document.getElementById('combo-display');
        const xpBarEl = document.getElementById('xp-bar');

        if (!coinsEl || !levelEl || !xpCurrentEl || !xpNextEl || !capacityEl || !comboEl || !xpBarEl) return;

        coinsEl.textContent = s.coins.toLocaleString('en-US');
        levelEl.textContent = s.level;
        xpCurrentEl.textContent = Math.floor(s.xp).toLocaleString('en-US');
        xpNextEl.textContent = this.game.getXpNext().toLocaleString('en-US');
        capacityEl.textContent = `${rod.capacity} kg`;
        comboEl.textContent = `${s.combo}x`;

        const pct = Math.max(0, Math.min((s.xp / this.game.getXpNext()) * 100, 100));
        xpBarEl.style.width = `${pct}%`;

        const autoStatePill = document.getElementById('auto-status-pill');
        if (autoStatePill) {
            const isAutoActive = this.game.autoFish.enabled || this.game.state.autoFishEnabled;
            autoStatePill.textContent = isAutoActive ? 'Automatic Fishing' : 'Inactive';
            autoStatePill.classList.toggle('active', isAutoActive);
        }

        this.renderSpeciesTracker();
    }

    renderSpeciesTracker() {
        const countEl = document.getElementById('species-indicator-count');
        const totalEl = document.getElementById('species-indicator-total');
        const barEl = document.getElementById('species-indicator-bar');
        if (!countEl && !totalEl && !barEl) return;

        const discoveredCount = typeof this.game.getDiscoveredSpeciesCount === 'function'
            ? this.game.getDiscoveredSpeciesCount()
            : 0;
        const catalogCount = typeof this.game.getSpeciesCatalogCount === 'function'
            ? this.game.getSpeciesCatalogCount()
            : 0;
        const denominator = Math.max(discoveredCount, catalogCount, 1);
        const percent = Math.max(0, Math.min((discoveredCount / denominator) * 100, 100));

        if (countEl) countEl.textContent = discoveredCount.toLocaleString('en-US');
        if (totalEl) totalEl.textContent = Math.max(discoveredCount, catalogCount).toLocaleString('en-US');
        if (barEl) barEl.style.width = `${percent}%`;
    }

    renderFishingResults() {
        const autoResults = this.game.fishingResults?.auto;
        const manualResults = this.game.fishingResults?.manual;

        if (autoResults) {
            const autoCatchesEl = document.getElementById('auto-result-catches');
            const autoStoredEl = document.getElementById('auto-result-stored');
            const autoXpEl = document.getElementById('auto-result-xp');
            const autoComboEl = document.getElementById('auto-result-combo');

            if (autoCatchesEl) autoCatchesEl.textContent = autoResults.totalCatches.toLocaleString('en-US');
            if (autoStoredEl) autoStoredEl.textContent = autoResults.fishStored.toLocaleString('en-US');
            if (autoXpEl) autoXpEl.textContent = Math.floor(autoResults.xpBanked).toLocaleString('en-US');
            if (autoComboEl) autoComboEl.textContent = `${Math.max(0, autoResults.comboBonus)}%`;
        }

        if (manualResults) {
            const manualCatchesEl = document.getElementById('manual-result-catches');
            const manualStoredEl = document.getElementById('manual-result-stored');
            const manualXpEl = document.getElementById('manual-result-xp');
            const manualComboEl = document.getElementById('manual-result-combo');

            if (manualCatchesEl) manualCatchesEl.textContent = manualResults.totalCatches.toLocaleString('en-US');
            if (manualStoredEl) manualStoredEl.textContent = manualResults.fishStored.toLocaleString('en-US');
            if (manualXpEl) manualXpEl.textContent = Math.floor(manualResults.xpBanked).toLocaleString('en-US');
            if (manualComboEl) manualComboEl.textContent = `${Math.max(0, manualResults.comboBonus)}%`;
        }
    }

    setFishingZoneMode(mode = 'idle') {
        const zone = document.querySelector('.fishing-zone');
        if (!zone) return;

        const isAutoMode = mode === 'auto';
        const isManualMode = mode === 'manual';
        const hasActiveMode = isAutoMode || isManualMode;

        zone.classList.remove('fishing-zone--idle', 'fishing-zone--manual', 'fishing-zone--auto');

        if (isAutoMode) {
            zone.classList.add('fishing-zone--auto');
        } else if (isManualMode) {
            zone.classList.add('fishing-zone--manual');
        } else {
            zone.classList.add('fishing-zone--idle');
        }

        const resultsStack = zone.querySelector('.results-panel-stack');
        if (resultsStack) resultsStack.hidden = !hasActiveMode;

        const autoResultsPanel = document.getElementById('auto-results-panel');
        const manualResultsPanel = document.getElementById('manual-results-panel');

        if (autoResultsPanel) autoResultsPanel.hidden = !isAutoMode;
        if (manualResultsPanel) manualResultsPanel.hidden = !isManualMode;
    }

    renderLocations() {
        const grid = document.getElementById('location-grid');
        if (!grid) return;

        grid.innerHTML = '';

        Object.entries(LOCATIONS).forEach(([key, data]) => {
            const div = document.createElement('div');
            div.className = `location-card ${this.game.state.location === key ? 'active' : ''}`;
            div.style.setProperty('--loc-a', data.colors?.[0] || '#cbd5e1');
            div.style.setProperty('--loc-b', data.colors?.[1] || '#94a3b8');
            div.innerHTML = `<div class="loc-name">${data.name}</div><div class="loc-desc">${data.desc}</div>`;

            div.onclick = () => {
                this.game.state.location = key;
                this.game.breakCombo();

                if (this.game.state.activeAmulet && this.game.state.activeAmulet !== key) {
                    this.game.log(`Your ${AMULETS[this.game.state.activeAmulet].name} faded after leaving its biome.`);
                    this.game.state.activeAmulet = null;
                }

                this.game.log(`Traveled to ${data.name}.`);
                this.renderLocations();
                this.updateTheme();
                this.game.saveSystem.save();
                if (typeof this.game.closeExpeditions === 'function') {
                    this.game.closeExpeditions();
                }
            };

            grid.appendChild(div);
        });

        this.renderBiomeAtlas();
        this.updateTheme();
    }

    renderBiomeAtlas() {
        const container = document.getElementById('biome-atlas-sections');
        if (!container) return;

        const atlasGroups = (typeof NEW_BIOME_ATLAS !== 'undefined' && Array.isArray(NEW_BIOME_ATLAS))
            ? NEW_BIOME_ATLAS
            : [];

        const playableKeys = new Set(Object.keys(LOCATIONS));
        const visibleGroups = atlasGroups
            .map((group) => ({
                ...group,
                biomes: (group.biomes || []).filter((biome) => !playableKeys.has(biome.id))
            }))
            .filter((group) => (group.biomes || []).length > 0);

        container.innerHTML = '';
        if (visibleGroups.length === 0) {
            container.innerHTML = '<p class="panel-note">All atlas biomes are now playable.</p>';
            return;
        }

        visibleGroups.forEach((group) => {
            const section = document.createElement('section');
            section.className = 'biome-atlas-category';

            const header = document.createElement('div');
            header.className = 'biome-atlas-category-head';

            const title = document.createElement('h4');
            title.textContent = group.category || 'Concept Biomes';

            const subtitle = document.createElement('p');
            subtitle.textContent = group.blurb || 'Creative biome concepts';

            const count = document.createElement('span');
            count.className = 'biome-atlas-count';
            count.textContent = `${Array.isArray(group.biomes) ? group.biomes.length : 0} display-only`;

            header.appendChild(title);
            header.appendChild(subtitle);
            header.appendChild(count);

            const grid = document.createElement('div');
            grid.className = 'biome-atlas-grid';

            (group.biomes || []).forEach((biome) => {
                const card = document.createElement('article');
                card.className = 'biome-atlas-card';
                card.style.setProperty('--atlas-a', biome.colors?.[0] || '#cbd5e1');
                card.style.setProperty('--atlas-b', biome.colors?.[1] || '#94a3b8');

                const chip = document.createElement('span');
                chip.className = 'biome-atlas-chip';
                chip.textContent = 'Display Only';

                const name = document.createElement('h5');
                name.textContent = biome.name || 'Unnamed Biome';

                const theme = document.createElement('p');
                theme.className = 'biome-atlas-theme';
                theme.textContent = biome.theme || '';

                const identity = document.createElement('p');
                identity.className = 'biome-atlas-identity';
                identity.textContent = biome.identity || '';

                const swatchRow = document.createElement('div');
                swatchRow.className = 'biome-atlas-swatches';

                (biome.colors || []).slice(0, 2).forEach((color) => {
                    const swatch = document.createElement('span');
                    swatch.className = 'biome-atlas-swatch';
                    swatch.style.background = color;
                    swatch.title = color;
                    swatchRow.appendChild(swatch);
                });

                card.appendChild(chip);
                card.appendChild(name);
                card.appendChild(theme);
                card.appendChild(identity);
                card.appendChild(swatchRow);
                grid.appendChild(card);
            });

            section.appendChild(header);
            section.appendChild(grid);
            container.appendChild(section);
        });
    }

    _hexToRgb(hex) {
        const value = String(hex || '').trim();
        const normalized = value.startsWith('#') ? value.slice(1) : value;
        if (!/^[a-fA-F0-9]{6}$/.test(normalized)) {
            return { r: 148, g: 163, b: 184 };
        }

        return {
            r: parseInt(normalized.slice(0, 2), 16),
            g: parseInt(normalized.slice(2, 4), 16),
            b: parseInt(normalized.slice(4, 6), 16)
        };
    }

    _mixRgb(rgbA, rgbB, ratio = 0.5) {
        const clamped = Math.max(0, Math.min(ratio, 1));
        const inv = 1 - clamped;
        return {
            r: Math.round((rgbA.r * inv) + (rgbB.r * clamped)),
            g: Math.round((rgbA.g * inv) + (rgbB.g * clamped)),
            b: Math.round((rgbA.b * inv) + (rgbB.b * clamped))
        };
    }

    _rgba(rgb, alpha = 1) {
        const a = Math.max(0, Math.min(alpha, 1));
        return `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${a})`;
    }

    updateTheme() {
        const biomeKey = this.game.state.location;
        const loc = LOCATIONS[biomeKey] || LOCATIONS.mistvale;
        const colorA = this._hexToRgb(loc.colors?.[0] || '#d6f7ff');
        const colorB = this._hexToRgb(loc.colors?.[1] || '#ffe9ca');
        const colorC = this._mixRgb(colorA, colorB, 0.35);
        const colorD = this._mixRgb(colorA, colorB, 0.7);
        const colorE = this._mixRgb(colorA, colorB, 0.5);
        const defaultProfile = {
            gradient: `radial-gradient(120% 90% at 8% 12%, ${this._rgba(colorA, 0.42)} 0%, rgba(255, 255, 255, 0) 54%),
                radial-gradient(95% 85% at 92% 6%, ${this._rgba(colorB, 0.38)} 0%, rgba(255, 255, 255, 0) 52%),
                radial-gradient(80% 70% at 50% 100%, ${this._rgba(colorC, 0.3)} 0%, rgba(255, 255, 255, 0) 58%),
                conic-gradient(from 210deg at 50% 50%, ${this._rgba(colorD, 0.24)}, ${this._rgba(colorA, 0.16)}, ${this._rgba(colorB, 0.24)}, ${this._rgba(colorD, 0.24)}),
                linear-gradient(135deg, ${this._rgba(colorA, 0.24)}, ${this._rgba(colorB, 0.24)})`,
            shapeA: this._rgba(colorA, 0.7),
            shapeB: this._rgba(colorB, 0.68),
            meshColor: this._rgba(colorC, 0.34),
            veinColor: this._rgba(colorE, 0.12),
            baseAnimation: 'biome-gradient-drift 24s ease-in-out infinite alternate',
            overlayPrimary: `radial-gradient(110% 85% at 20% 30%, ${this._rgba(colorC, 0.34)} 0%, rgba(255, 255, 255, 0) 60%)`,
            overlaySecondary: `repeating-linear-gradient(132deg, ${this._rgba(colorE, 0.12)} 0 2px, rgba(255, 255, 255, 0) 2px 14px)`,
            overlayOpacity: '0.55',
            overlayAnimation: 'biome-mesh-drift 36s linear infinite'
        };

        const specialProfiles = {
            nectar_nexus: {
                gradient: `radial-gradient(95% 75% at 14% 14%, rgba(255, 125, 176, 0.3) 0%, rgba(255, 125, 176, 0) 62%),
                    radial-gradient(90% 70% at 86% 10%, rgba(234, 128, 252, 0.26) 0%, rgba(234, 128, 252, 0) 60%),
                    linear-gradient(132deg, #fff5fa 0%, #ffeef8 42%, #fff8ef 100%)`,
                shapeA: 'rgba(255, 160, 196, 0.46)',
                shapeB: 'rgba(230, 178, 245, 0.42)',
                meshColor: 'rgba(255, 205, 227, 0.2)',
                veinColor: 'rgba(219, 154, 205, 0.08)',
                overlayPrimary: `radial-gradient(42% 34% at 22% 70%, rgba(255, 228, 186, 0.2) 0%, rgba(255, 228, 186, 0) 78%),
                    radial-gradient(34% 28% at 76% 30%, rgba(255, 245, 230, 0.16) 0%, rgba(255, 245, 230, 0) 75%)`,
                overlaySecondary: 'repeating-linear-gradient(136deg, rgba(255, 255, 255, 0.11) 0 1px, rgba(255, 255, 255, 0) 1px 20px)',
                overlayOpacity: '0.4',
                baseAnimation: 'biome-gradient-drift 34s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 48s linear infinite'
            },
            petrified_peat_bog: {
                gradient: `radial-gradient(110% 84% at 12% 14%, rgba(117, 144, 102, 0.28) 0%, rgba(117, 144, 102, 0) 62%),
                    radial-gradient(96% 78% at 88% 8%, rgba(102, 84, 66, 0.26) 0%, rgba(102, 84, 66, 0) 58%),
                    linear-gradient(136deg, #f1f4ee 0%, #e7ece4 44%, #ece5de 100%)`,
                shapeA: 'rgba(117, 144, 102, 0.42)',
                shapeB: 'rgba(128, 104, 82, 0.4)',
                meshColor: 'rgba(173, 184, 161, 0.2)',
                veinColor: 'rgba(112, 99, 85, 0.08)',
                overlayPrimary: `radial-gradient(38% 28% at 24% 74%, rgba(198, 206, 168, 0.15) 0%, rgba(198, 206, 168, 0) 72%),
                    radial-gradient(32% 24% at 78% 62%, rgba(187, 198, 176, 0.14) 0%, rgba(187, 198, 176, 0) 72%)`,
                overlaySecondary: 'repeating-linear-gradient(18deg, rgba(96, 110, 89, 0.12) 0 2px, rgba(96, 110, 89, 0) 2px 22px)',
                overlayOpacity: '0.36',
                baseAnimation: 'biome-gradient-drift 36s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 54s linear infinite'
            },
            thorn_thicket_trench: {
                gradient: `radial-gradient(108% 86% at 10% 16%, rgba(144, 77, 114, 0.26) 0%, rgba(144, 77, 114, 0) 62%),
                    radial-gradient(92% 74% at 88% 10%, rgba(84, 69, 78, 0.24) 0%, rgba(84, 69, 78, 0) 60%),
                    linear-gradient(132deg, #f5eff3 0%, #ece5ea 46%, #e6e3e7 100%)`,
                shapeA: 'rgba(132, 82, 116, 0.42)',
                shapeB: 'rgba(93, 83, 89, 0.38)',
                meshColor: 'rgba(196, 176, 188, 0.18)',
                veinColor: 'rgba(121, 92, 110, 0.08)',
                overlayPrimary: 'linear-gradient(145deg, rgba(203, 157, 183, 0.14) 0%, rgba(203, 157, 183, 0) 46%)',
                overlaySecondary: 'repeating-linear-gradient(138deg, rgba(138, 95, 123, 0.13) 0 2px, rgba(138, 95, 123, 0) 2px 24px)',
                overlayOpacity: '0.38',
                baseAnimation: 'biome-gradient-drift 34s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 50s linear infinite'
            },
            quantum_superposition_sea: {
                gradient: `radial-gradient(108% 84% at 12% 14%, rgba(255, 255, 255, 0.24) 0%, rgba(255, 255, 255, 0) 64%),
                    radial-gradient(104% 78% at 86% 8%, rgba(170, 170, 170, 0.2) 0%, rgba(170, 170, 170, 0) 60%),
                    linear-gradient(128deg, #e8e8e8 0%, #cfcfcf 40%, #909090 58%, #d8d8d8 100%)`,
                shapeA: 'rgba(245, 245, 245, 0.42)',
                shapeB: 'rgba(70, 70, 70, 0.3)',
                meshColor: 'rgba(220, 220, 220, 0.2)',
                veinColor: 'rgba(130, 130, 130, 0.09)',
                overlayPrimary: 'repeating-linear-gradient(0deg, rgba(255, 255, 255, 0.12) 0 1px, rgba(255, 255, 255, 0) 1px 10px)',
                overlaySecondary: 'repeating-linear-gradient(90deg, rgba(255, 255, 255, 0.06) 0 1px, rgba(255, 255, 255, 0) 1px 22px)',
                overlayOpacity: '0.34',
                baseAnimation: 'biome-gradient-drift 40s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 62s linear infinite'
            },
            bathtub_billows: {
                gradient: `radial-gradient(92% 78% at 12% 16%, rgba(202, 241, 246, 0.34) 0%, rgba(202, 241, 246, 0) 62%),
                    radial-gradient(88% 72% at 88% 12%, rgba(255, 255, 255, 0.42) 0%, rgba(255, 255, 255, 0) 58%),
                    linear-gradient(132deg, #f5fdff 0%, #ebf8fc 44%, #fdfefe 100%)`,
                shapeA: 'rgba(222, 246, 249, 0.44)',
                shapeB: 'rgba(255, 255, 255, 0.5)',
                meshColor: 'rgba(226, 244, 248, 0.2)',
                veinColor: 'rgba(147, 196, 207, 0.07)',
                overlayPrimary: `radial-gradient(35% 28% at 18% 24%, rgba(255, 255, 255, 0.18) 0%, rgba(255, 255, 255, 0) 72%),
                    radial-gradient(30% 24% at 74% 62%, rgba(230, 247, 251, 0.18) 0%, rgba(230, 247, 251, 0) 72%)`,
                overlaySecondary: 'repeating-linear-gradient(90deg, rgba(169, 214, 223, 0.1) 0 1px, rgba(169, 214, 223, 0) 1px 78px)',
                overlayOpacity: '0.36',
                baseAnimation: 'biome-gradient-drift 36s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 56s linear infinite'
            },
            somnambulist_shallows: {
                gradient: `radial-gradient(110% 82% at 16% 18%, rgba(179, 136, 255, 0.36) 0%, rgba(179, 136, 255, 0) 60%),
                    radial-gradient(96% 76% at 82% 12%, rgba(96, 51, 164, 0.34) 0%, rgba(96, 51, 164, 0) 58%),
                    conic-gradient(from 220deg at 50% 52%, rgba(74, 20, 140, 0.28), rgba(179, 136, 255, 0.2), rgba(92, 56, 152, 0.3), rgba(74, 20, 140, 0.28)),
                    linear-gradient(140deg, #f0e7ff 0%, #e7ddff 42%, #f8f2ff 100%)`,
                shapeA: 'rgba(179, 136, 255, 0.42)',
                shapeB: 'rgba(98, 63, 166, 0.4)',
                meshColor: 'rgba(200, 175, 241, 0.22)',
                veinColor: 'rgba(122, 95, 166, 0.09)',
                overlayPrimary: 'radial-gradient(55% 36% at 50% 66%, rgba(255, 255, 255, 0.14) 0%, rgba(255, 255, 255, 0) 74%)',
                overlaySecondary: 'repeating-linear-gradient(124deg, rgba(152, 127, 204, 0.12) 0 2px, rgba(152, 127, 204, 0) 2px 26px)',
                overlayOpacity: '0.42',
                baseAnimation: 'biome-gradient-drift 38s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 60s linear infinite'
            },
            tabletop_trench: {
                gradient: `radial-gradient(118% 88% at 14% 14%, rgba(37, 96, 42, 0.38) 0%, rgba(37, 96, 42, 0) 62%),
                    radial-gradient(84% 64% at 88% 10%, rgba(188, 56, 56, 0.34) 0%, rgba(188, 56, 56, 0) 58%),
                    linear-gradient(132deg, #f4f9f4 0%, #e7f0e7 48%, #f7eded 100%)`,
                shapeA: 'rgba(56, 110, 57, 0.4)',
                shapeB: 'rgba(179, 70, 70, 0.36)',
                meshColor: 'rgba(170, 188, 163, 0.18)',
                veinColor: 'rgba(123, 112, 92, 0.08)',
                overlayPrimary: 'repeating-linear-gradient(0deg, rgba(255, 255, 255, 0.1) 0 1px, rgba(255, 255, 255, 0) 1px 28px), repeating-linear-gradient(90deg, rgba(255, 255, 255, 0.08) 0 1px, rgba(255, 255, 255, 0) 1px 28px)',
                overlaySecondary: 'radial-gradient(8% 8% at 22% 34%, rgba(255, 255, 255, 0.14) 0%, rgba(255, 255, 255, 0) 100%), radial-gradient(10% 10% at 76% 62%, rgba(255, 255, 255, 0.12) 0%, rgba(255, 255, 255, 0) 100%)',
                overlayOpacity: '0.34',
                baseAnimation: 'biome-gradient-drift 30s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 44s linear infinite'
            },
            silhouette_strait: {
                gradient: `linear-gradient(124deg, #f8f8f8 0%, #e8e8e8 48%, #ffffff 100%),
                    repeating-linear-gradient(164deg, rgba(0, 0, 0, 0.1) 0 4px, rgba(0, 0, 0, 0) 4px 24px)`,
                shapeA: 'rgba(32, 32, 32, 0.3)',
                shapeB: 'rgba(255, 255, 255, 0.46)',
                meshColor: 'rgba(175, 175, 175, 0.15)',
                veinColor: 'rgba(18, 18, 18, 0.08)',
                overlayPrimary: 'linear-gradient(90deg, rgba(0, 0, 0, 0.16) 0 6%, rgba(255, 255, 255, 0) 20%, rgba(0, 0, 0, 0.16) 44%, rgba(255, 255, 255, 0) 60%, rgba(0, 0, 0, 0.16) 84%, rgba(255, 255, 255, 0) 100%)',
                overlaySecondary: 'repeating-linear-gradient(0deg, rgba(0, 0, 0, 0.08) 0 1px, rgba(0, 0, 0, 0) 1px 14px)',
                overlayOpacity: '0.28',
                baseAnimation: 'biome-gradient-drift 42s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 72s linear infinite'
            },
            typography_trench: {
                gradient: `radial-gradient(106% 82% at 16% 12%, rgba(71, 86, 94, 0.34) 0%, rgba(71, 86, 94, 0) 62%),
                    radial-gradient(94% 76% at 88% 10%, rgba(189, 199, 205, 0.38) 0%, rgba(189, 199, 205, 0) 58%),
                    linear-gradient(136deg, #f2f5f6 0%, #e4ebee 44%, #f9fbfc 100%)`,
                shapeA: 'rgba(77, 91, 98, 0.4)',
                shapeB: 'rgba(201, 210, 214, 0.44)',
                meshColor: 'rgba(171, 183, 190, 0.2)',
                veinColor: 'rgba(88, 98, 103, 0.08)',
                overlayPrimary: 'repeating-linear-gradient(0deg, rgba(38, 50, 56, 0.08) 0 1px, rgba(38, 50, 56, 0) 1px 22px)',
                overlaySecondary: 'repeating-linear-gradient(90deg, rgba(38, 50, 56, 0.09) 0 10px, rgba(38, 50, 56, 0) 10px 14px, rgba(38, 50, 56, 0.08) 14px 17px, rgba(38, 50, 56, 0) 17px 26px)',
                overlayOpacity: '0.34',
                baseAnimation: 'biome-gradient-drift 33s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 52s linear infinite'
            },
            broth_basin: {
                gradient: `radial-gradient(116% 88% at 10% 16%, rgba(216, 107, 64, 0.36) 0%, rgba(216, 107, 64, 0) 64%),
                    radial-gradient(94% 74% at 90% 12%, rgba(255, 192, 120, 0.34) 0%, rgba(255, 192, 120, 0) 58%),
                    linear-gradient(138deg, #fff3ea 0%, #ffe6d2 40%, #fff8ee 100%)`,
                shapeA: 'rgba(218, 101, 55, 0.4)',
                shapeB: 'rgba(246, 193, 124, 0.42)',
                meshColor: 'rgba(237, 170, 122, 0.2)',
                veinColor: 'rgba(159, 91, 54, 0.08)',
                overlayPrimary: 'radial-gradient(18% 16% at 26% 72%, rgba(255, 246, 223, 0.2) 0%, rgba(255, 246, 223, 0) 82%), radial-gradient(14% 12% at 72% 66%, rgba(255, 228, 187, 0.18) 0%, rgba(255, 228, 187, 0) 82%)',
                overlaySecondary: 'repeating-linear-gradient(160deg, rgba(183, 90, 42, 0.1) 0 2px, rgba(183, 90, 42, 0) 2px 20px)',
                overlayOpacity: '0.39',
                baseAnimation: 'biome-gradient-drift 34s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 48s linear infinite'
            },
            ectoplasmic_eddy: {
                gradient: `radial-gradient(110% 88% at 12% 14%, rgba(132, 255, 255, 0.34) 0%, rgba(132, 255, 255, 0) 62%),
                    radial-gradient(94% 76% at 86% 10%, rgba(29, 233, 182, 0.3) 0%, rgba(29, 233, 182, 0) 58%),
                    linear-gradient(134deg, #eaffff 0%, #dcfff7 44%, #f6fffb 100%)`,
                shapeA: 'rgba(132, 255, 255, 0.4)',
                shapeB: 'rgba(29, 233, 182, 0.36)',
                meshColor: 'rgba(155, 241, 223, 0.2)',
                veinColor: 'rgba(94, 176, 157, 0.08)',
                overlayPrimary: 'radial-gradient(46% 30% at 22% 70%, rgba(196, 255, 255, 0.16) 0%, rgba(196, 255, 255, 0) 76%), radial-gradient(36% 24% at 78% 32%, rgba(164, 255, 234, 0.16) 0%, rgba(164, 255, 234, 0) 76%)',
                overlaySecondary: 'repeating-linear-gradient(136deg, rgba(84, 192, 174, 0.1) 0 2px, rgba(84, 192, 174, 0) 2px 24px)',
                overlayOpacity: '0.37',
                baseAnimation: 'biome-gradient-drift 39s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 58s linear infinite'
            },
            mandelbrot_maelstrom: {
                gradient: `radial-gradient(120% 92% at 12% 16%, rgba(98, 0, 234, 0.36) 0%, rgba(98, 0, 234, 0) 62%),
                    radial-gradient(90% 74% at 88% 10%, rgba(0, 191, 255, 0.32) 0%, rgba(0, 191, 255, 0) 58%),
                    linear-gradient(134deg, #efe7ff 0%, #e1f3ff 46%, #f6fbff 100%)`,
                shapeA: 'rgba(112, 36, 230, 0.42)',
                shapeB: 'rgba(0, 186, 246, 0.38)',
                meshColor: 'rgba(148, 171, 240, 0.2)',
                veinColor: 'rgba(84, 104, 180, 0.08)',
                overlayPrimary: 'repeating-conic-gradient(from 0deg at 52% 50%, rgba(130, 95, 246, 0.11) 0deg 8deg, rgba(130, 95, 246, 0) 8deg 20deg)',
                overlaySecondary: 'radial-gradient(42% 32% at 52% 50%, rgba(255, 255, 255, 0.12) 0%, rgba(255, 255, 255, 0) 76%)',
                overlayOpacity: '0.35',
                baseAnimation: 'biome-gradient-drift 46s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 70s linear infinite'
            },
            mobius_strip_stream: {
                gradient: `radial-gradient(118% 86% at 10% 16%, rgba(255, 123, 69, 0.34) 0%, rgba(255, 123, 69, 0) 62%),
                    radial-gradient(86% 68% at 88% 10%, rgba(96, 125, 139, 0.3) 0%, rgba(96, 125, 139, 0) 58%),
                    linear-gradient(134deg, #fff0e8 0%, #e7ecef 44%, #f9fbfc 100%)`,
                shapeA: 'rgba(245, 126, 70, 0.4)',
                shapeB: 'rgba(103, 126, 138, 0.36)',
                meshColor: 'rgba(202, 172, 156, 0.2)',
                veinColor: 'rgba(112, 105, 109, 0.08)',
                overlayPrimary: 'linear-gradient(145deg, rgba(255, 121, 64, 0.12) 0%, rgba(255, 121, 64, 0) 34%, rgba(96, 125, 139, 0.12) 52%, rgba(96, 125, 139, 0) 86%)',
                overlaySecondary: 'repeating-linear-gradient(128deg, rgba(143, 118, 112, 0.11) 0 2px, rgba(143, 118, 112, 0) 2px 18px)',
                overlayOpacity: '0.34',
                baseAnimation: 'biome-gradient-drift 37s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 56s linear infinite'
            },
            fibonacci_floodplain: {
                gradient: `radial-gradient(108% 84% at 14% 14%, rgba(255, 213, 79, 0.36) 0%, rgba(255, 213, 79, 0) 62%),
                    radial-gradient(92% 72% at 86% 10%, rgba(93, 64, 55, 0.28) 0%, rgba(93, 64, 55, 0) 58%),
                    linear-gradient(136deg, #fff9e8 0%, #f6ead9 42%, #fffdf7 100%)`,
                shapeA: 'rgba(241, 198, 68, 0.38)',
                shapeB: 'rgba(122, 91, 78, 0.34)',
                meshColor: 'rgba(215, 182, 130, 0.2)',
                veinColor: 'rgba(138, 114, 84, 0.08)',
                overlayPrimary: 'radial-gradient(2% 2% at 50% 50%, rgba(255, 230, 152, 0.13) 0%, rgba(255, 230, 152, 0) 100%), repeating-radial-gradient(circle at 50% 50%, rgba(157, 119, 81, 0.07) 0 8px, rgba(157, 119, 81, 0) 8px 24px)',
                overlaySecondary: 'repeating-conic-gradient(from 32deg at 50% 50%, rgba(173, 129, 85, 0.08) 0deg 12deg, rgba(173, 129, 85, 0) 12deg 24deg)',
                overlayOpacity: '0.36',
                baseAnimation: 'biome-gradient-drift 41s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 68s linear infinite'
            },
            tesseract_trench: {
                gradient: `radial-gradient(112% 86% at 12% 16%, rgba(0, 230, 118, 0.34) 0%, rgba(0, 230, 118, 0) 62%),
                    radial-gradient(92% 70% at 88% 10%, rgba(26, 35, 126, 0.34) 0%, rgba(26, 35, 126, 0) 58%),
                    linear-gradient(134deg, #eafff3 0%, #e7ecff 44%, #f6f8ff 100%)`,
                shapeA: 'rgba(0, 210, 110, 0.38)',
                shapeB: 'rgba(42, 56, 162, 0.38)',
                meshColor: 'rgba(134, 179, 204, 0.2)',
                veinColor: 'rgba(84, 112, 148, 0.08)',
                overlayPrimary: 'repeating-linear-gradient(0deg, rgba(76, 120, 185, 0.1) 0 1px, rgba(76, 120, 185, 0) 1px 20px), repeating-linear-gradient(90deg, rgba(76, 120, 185, 0.1) 0 1px, rgba(76, 120, 185, 0) 1px 20px)',
                overlaySecondary: 'linear-gradient(145deg, rgba(97, 116, 221, 0.11) 0%, rgba(97, 116, 221, 0) 44%, rgba(54, 213, 148, 0.11) 62%, rgba(54, 213, 148, 0) 100%)',
                overlayOpacity: '0.34',
                baseAnimation: 'biome-gradient-drift 35s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 46s linear infinite'
            },
            attic_dust_sea: {
                gradient: `radial-gradient(108% 82% at 12% 14%, rgba(158, 158, 158, 0.3) 0%, rgba(158, 158, 158, 0) 62%),
                    radial-gradient(94% 74% at 86% 10%, rgba(121, 85, 72, 0.28) 0%, rgba(121, 85, 72, 0) 58%),
                    linear-gradient(136deg, #f2f0ee 0%, #e8e1db 44%, #f7f4f1 100%)`,
                shapeA: 'rgba(166, 161, 156, 0.36)',
                shapeB: 'rgba(128, 99, 86, 0.34)',
                meshColor: 'rgba(188, 175, 165, 0.2)',
                veinColor: 'rgba(123, 102, 90, 0.08)',
                overlayPrimary: 'linear-gradient(158deg, rgba(255, 247, 226, 0.14) 0%, rgba(255, 247, 226, 0) 38%, rgba(255, 247, 226, 0.14) 58%, rgba(255, 247, 226, 0) 100%)',
                overlaySecondary: 'repeating-linear-gradient(132deg, rgba(151, 128, 115, 0.1) 0 2px, rgba(151, 128, 115, 0) 2px 26px)',
                overlayOpacity: '0.37',
                baseAnimation: 'biome-gradient-drift 44s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 64s linear infinite'
            },
            junk_drawer_delta: {
                gradient: `radial-gradient(110% 84% at 12% 16%, rgba(117, 117, 117, 0.34) 0%, rgba(117, 117, 117, 0) 62%),
                    radial-gradient(90% 70% at 86% 10%, rgba(255, 152, 0, 0.3) 0%, rgba(255, 152, 0, 0) 58%),
                    linear-gradient(136deg, #f1f3f4 0%, #ece8e4 46%, #faf8f5 100%)`,
                shapeA: 'rgba(129, 129, 129, 0.4)',
                shapeB: 'rgba(235, 150, 36, 0.36)',
                meshColor: 'rgba(190, 177, 162, 0.2)',
                veinColor: 'rgba(118, 109, 100, 0.08)',
                overlayPrimary: 'repeating-linear-gradient(12deg, rgba(140, 140, 140, 0.11) 0 2px, rgba(140, 140, 140, 0) 2px 16px)',
                overlaySecondary: 'linear-gradient(148deg, rgba(255, 162, 36, 0.1) 0%, rgba(255, 162, 36, 0) 44%, rgba(123, 123, 123, 0.11) 60%, rgba(123, 123, 123, 0) 100%)',
                overlayOpacity: '0.36',
                baseAnimation: 'biome-gradient-drift 29s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 41s linear infinite'
            },
            static_carpet_shallows: {
                gradient: `radial-gradient(112% 82% at 12% 14%, rgba(211, 47, 47, 0.32) 0%, rgba(211, 47, 47, 0) 62%),
                    radial-gradient(92% 74% at 86% 10%, rgba(255, 235, 59, 0.3) 0%, rgba(255, 235, 59, 0) 58%),
                    linear-gradient(136deg, #fff2f2 0%, #fff7cc 44%, #fffdf0 100%)`,
                shapeA: 'rgba(203, 65, 65, 0.4)',
                shapeB: 'rgba(255, 226, 72, 0.36)',
                meshColor: 'rgba(240, 179, 117, 0.2)',
                veinColor: 'rgba(162, 96, 79, 0.08)',
                overlayPrimary: 'repeating-linear-gradient(0deg, rgba(255, 255, 255, 0.08) 0 1px, rgba(255, 255, 255, 0) 1px 5px)',
                overlaySecondary: 'repeating-linear-gradient(90deg, rgba(120, 35, 35, 0.08) 0 1px, rgba(120, 35, 35, 0) 1px 8px)',
                overlayOpacity: '0.42',
                baseAnimation: 'biome-gradient-drift 18s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 24s linear infinite'
            },
            refrigerator_rill: {
                gradient: `radial-gradient(112% 86% at 10% 16%, rgba(178, 235, 242, 0.34) 0%, rgba(178, 235, 242, 0) 62%),
                    radial-gradient(96% 76% at 88% 10%, rgba(197, 225, 165, 0.3) 0%, rgba(197, 225, 165, 0) 58%),
                    linear-gradient(136deg, #effcff 0%, #edf8f1 44%, #fafefc 100%)`,
                shapeA: 'rgba(188, 229, 236, 0.4)',
                shapeB: 'rgba(194, 220, 170, 0.36)',
                meshColor: 'rgba(206, 224, 210, 0.2)',
                veinColor: 'rgba(142, 176, 170, 0.08)',
                overlayPrimary: 'repeating-radial-gradient(circle at 50% 50%, rgba(232, 248, 255, 0.13) 0 3px, rgba(232, 248, 255, 0) 3px 18px)',
                overlaySecondary: 'repeating-linear-gradient(140deg, rgba(170, 198, 210, 0.1) 0 2px, rgba(170, 198, 210, 0) 2px 22px)',
                overlayOpacity: '0.36',
                baseAnimation: 'biome-gradient-drift 45s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 74s linear infinite'
            },
            sea_of_solipsism: {
                gradient: `radial-gradient(100% 82% at 16% 14%, rgba(207, 216, 220, 0.32) 0%, rgba(207, 216, 220, 0) 62%),
                    radial-gradient(92% 76% at 84% 10%, rgba(176, 190, 197, 0.3) 0%, rgba(176, 190, 197, 0) 58%),
                    linear-gradient(136deg, #f8fafb 0%, #eef2f5 44%, #fafcfd 100%)`,
                shapeA: 'rgba(214, 223, 227, 0.4)',
                shapeB: 'rgba(168, 183, 190, 0.36)',
                meshColor: 'rgba(205, 214, 219, 0.2)',
                veinColor: 'rgba(132, 152, 162, 0.08)',
                overlayPrimary: 'linear-gradient(180deg, rgba(255, 255, 255, 0.22) 0%, rgba(255, 255, 255, 0.03) 52%, rgba(115, 132, 141, 0.1) 100%)',
                overlaySecondary: 'repeating-linear-gradient(90deg, rgba(182, 193, 198, 0.08) 0 1px, rgba(182, 193, 198, 0) 1px 30px)',
                overlayOpacity: '0.33',
                baseAnimation: 'biome-gradient-drift 40s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 66s linear infinite'
            },
            utilitarian_utopia: {
                gradient: `radial-gradient(106% 82% at 14% 12%, rgba(207, 231, 250, 0.32) 0%, rgba(207, 231, 250, 0) 62%),
                    radial-gradient(92% 74% at 86% 12%, rgba(236, 245, 252, 0.3) 0%, rgba(236, 245, 252, 0) 58%),
                    linear-gradient(136deg, #fdfefe 0%, #eef6fc 44%, #fbfdff 100%)`,
                shapeA: 'rgba(191, 217, 238, 0.4)',
                shapeB: 'rgba(229, 240, 250, 0.42)',
                meshColor: 'rgba(204, 223, 237, 0.2)',
                veinColor: 'rgba(133, 164, 190, 0.08)',
                overlayPrimary: 'repeating-linear-gradient(0deg, rgba(138, 173, 200, 0.1) 0 1px, rgba(138, 173, 200, 0) 1px 24px), repeating-linear-gradient(90deg, rgba(138, 173, 200, 0.1) 0 1px, rgba(138, 173, 200, 0) 1px 24px)',
                overlaySecondary: 'linear-gradient(140deg, rgba(255, 255, 255, 0.1) 0%, rgba(255, 255, 255, 0) 40%, rgba(176, 209, 232, 0.1) 68%, rgba(176, 209, 232, 0) 100%)',
                overlayOpacity: '0.3',
                baseAnimation: 'biome-gradient-drift 34s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 46s linear infinite'
            },
            nihilists_null: {
                gradient: `linear-gradient(132deg, #2f2f2f 0%, #232323 44%, #141414 100%)`,
                shapeA: 'rgba(88, 88, 88, 0.2)',
                shapeB: 'rgba(52, 52, 52, 0.2)',
                meshColor: 'rgba(96, 96, 96, 0.08)',
                veinColor: 'rgba(132, 132, 132, 0.03)',
                overlayPrimary: 'none',
                overlaySecondary: 'none',
                overlayOpacity: '0.12',
                baseAnimation: 'none',
                overlayAnimation: 'none'
            },
            hedonists_haven: {
                gradient: `radial-gradient(112% 86% at 10% 14%, rgba(255, 51, 107, 0.4) 0%, rgba(255, 51, 107, 0) 62%),
                    radial-gradient(92% 74% at 90% 12%, rgba(170, 0, 255, 0.36) 0%, rgba(170, 0, 255, 0) 58%),
                    conic-gradient(from 20deg at 50% 48%, rgba(255, 63, 63, 0.22), rgba(255, 168, 30, 0.2), rgba(59, 225, 255, 0.18), rgba(186, 59, 255, 0.24), rgba(255, 63, 63, 0.22)),
                    linear-gradient(128deg, #fff1f6 0%, #f6edff 38%, #fff7ea 100%)`,
                shapeA: 'rgba(233, 63, 96, 0.42)',
                shapeB: 'rgba(167, 61, 238, 0.4)',
                meshColor: 'rgba(232, 150, 190, 0.22)',
                veinColor: 'rgba(157, 79, 156, 0.09)',
                overlayPrimary: 'repeating-linear-gradient(152deg, rgba(255, 255, 255, 0.13) 0 1px, rgba(255, 255, 255, 0) 1px 14px)',
                overlaySecondary: 'repeating-linear-gradient(90deg, rgba(198, 86, 240, 0.09) 0 1px, rgba(198, 86, 240, 0) 1px 10px)',
                overlayOpacity: '0.44',
                baseAnimation: 'biome-gradient-drift 16s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 18s linear infinite'
            },
            ship_of_theseus_shoals: {
                gradient: `radial-gradient(108% 84% at 14% 14%, rgba(141, 110, 99, 0.34) 0%, rgba(141, 110, 99, 0) 62%),
                    radial-gradient(92% 74% at 86% 10%, rgba(84, 110, 122, 0.3) 0%, rgba(84, 110, 122, 0) 58%),
                    linear-gradient(136deg, #f0ece8 0%, #e3e9ec 44%, #f9f7f4 100%)`,
                shapeA: 'rgba(144, 117, 104, 0.38)',
                shapeB: 'rgba(97, 122, 133, 0.36)',
                meshColor: 'rgba(181, 170, 160, 0.2)',
                veinColor: 'rgba(121, 111, 108, 0.08)',
                overlayPrimary: 'repeating-linear-gradient(8deg, rgba(146, 117, 95, 0.11) 0 2px, rgba(146, 117, 95, 0) 2px 12px)',
                overlaySecondary: 'repeating-linear-gradient(96deg, rgba(95, 119, 131, 0.1) 0 1px, rgba(95, 119, 131, 0) 1px 20px)',
                overlayOpacity: '0.37',
                baseAnimation: 'biome-gradient-drift 32s ease-in-out infinite alternate',
                overlayAnimation: 'biome-mesh-drift 49s linear infinite'
            }
        };

        const profile = {
            ...defaultProfile,
            ...(specialProfiles[biomeKey] || {})
        };

        document.body.style.setProperty('--bg-gradient', profile.gradient);
        document.body.style.setProperty('--bg-shape-a-color', profile.shapeA);
        document.body.style.setProperty('--bg-shape-b-color', profile.shapeB);
        document.body.style.setProperty('--bg-mesh-color', profile.meshColor);
        document.body.style.setProperty('--bg-vein-color', profile.veinColor);
        document.body.style.setProperty('--bg-base-animation', profile.baseAnimation);
        document.body.style.setProperty('--bg-overlay-primary', profile.overlayPrimary);
        document.body.style.setProperty('--bg-overlay-secondary', profile.overlaySecondary);
        document.body.style.setProperty('--bg-overlay-opacity', profile.overlayOpacity);
        document.body.style.setProperty('--bg-overlay-animation', profile.overlayAnimation);
        document.body.setAttribute('data-biome', biomeKey || 'mistvale');
    }

    updateStatus(msg, type = 'normal') {
        const el = document.getElementById('status-message');
        if (!el) return;

        el.textContent = String(msg ?? '');
        this._applyStatusTone(el, type);
    }

    updateStatusRich(parts, type = 'normal') {
        const el = document.getElementById('status-message');
        if (!el) return;

        el.replaceChildren(this._renderInlineParts(parts));
        this._applyStatusTone(el, type);
    }

    updateStatusWithFish(message, fishName, type = 'normal') {
        const text = String(message ?? '');
        const target = String(fishName || '').trim();
        if (!target) {
            this.updateStatus(text, type);
            return;
        }

        const escaped = target.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const matcher = new RegExp(escaped, 'g');
        const parts = [];
        let cursor = 0;
        let didHighlight = false;
        let match = matcher.exec(text);

        while (match) {
            if (match.index > cursor) {
                parts.push({ text: text.slice(cursor, match.index) });
            }

            parts.push({
                text: match[0],
                className: 'fish-name-token fish-name-status'
            });
            didHighlight = true;
            cursor = matcher.lastIndex;
            match = matcher.exec(text);
        }

        if (!didHighlight) {
            this.updateStatus(text, type);
            return;
        }

        if (cursor < text.length) {
            parts.push({ text: text.slice(cursor) });
        }

        this.updateStatusRich(parts, type);
    }

    _renderInlineParts(parts) {
        const fragment = document.createDocumentFragment();
        if (!Array.isArray(parts)) {
            return fragment;
        }

        parts.forEach((part) => {
            if (part === null || part === undefined) return;

            const descriptor = typeof part === 'string'
                ? { text: part }
                : part;
            const text = String(descriptor.text ?? '');
            if (!text) return;

            if (!descriptor.className && !descriptor.color) {
                fragment.appendChild(document.createTextNode(text));
                return;
            }

            const span = document.createElement('span');
            span.textContent = text;
            if (descriptor.className) {
                span.className = descriptor.className;
            }
            if (descriptor.color) {
                span.style.color = descriptor.color;
            }
            fragment.appendChild(span);
        });

        return fragment;
    }

    _applyStatusTone(el, type = 'normal') {
        el.style.color = type === 'danger'
            ? 'var(--danger)'
            : type === 'success'
                ? 'var(--success)'
                : type === 'warning'
                    ? 'var(--warning)'
                    : 'var(--text)';
    }

    updateLastCatch(fish) {
        const el = document.getElementById('last-catch');
        if (!el) return;

        const rarityColor = RARITY[fish.rarity]?.color || 'var(--theme-success-text)';
        const parts = [
            { text: 'Last Catch: ' }
        ];

        if (fish.variant) {
            const varColor = fish.variant.label === 'Prismatic'
                ? '#e879f9'
                : fish.variant.label === 'Shadow'
                    ? '#6366f1'
                    : '#facc15';
            parts.push({
                text: `${fish.variant.icon} ${fish.variant.label}`,
                className: 'fish-variant-token',
                color: varColor
            });
            parts.push({ text: ' ' });
        }

        parts.push({
            text: fish.name,
            className: 'fish-name-token fish-name-last-catch',
            color: rarityColor
        });
        parts.push({ text: ` (${fish.weight}kg)` });

        el.replaceChildren(this._renderInlineParts(parts));
    }

    showMinigame(show) {
        const el = document.getElementById('minigame-ui');
        if (!el) return;
        el.classList.toggle('active', show);
    }

    updateWeather() {
        const badge = document.getElementById('weather-badge');
        const text = document.getElementById('weather-text');
        const icon = document.querySelector('.weather-icon');
        if (!badge || !text || !icon) return;

        const baseKey = WEATHER_DATA[this.game.weather.current] ? this.game.weather.current : 'clear';
        const baseWeather = WEATHER_DATA[baseKey];
        const activeWeathers = this.game.state.activeWeathers || [];

        const uniqueWeatherKeys = [baseKey];
        activeWeathers.forEach(key => {
            if (!WEATHER_DATA[key]) return;
            if (uniqueWeatherKeys.includes(key)) return;
            uniqueWeatherKeys.push(key);
        });

        const maxIcons = 4;
        let icons = uniqueWeatherKeys
            .slice(0, maxIcons)
            .map(key => WEATHER_DATA[key].icon)
            .join('');

        if (uniqueWeatherKeys.length > maxIcons) {
            icons += `+${uniqueWeatherKeys.length - maxIcons}`;
        }

        icon.textContent = icons || 'Sun';

        const totalLuck = this.game.getWeatherMultiplier();
        const luckPct = Math.round((totalLuck - 1) * 100);
        const luckMod = `${luckPct >= 0 ? '+' : ''}${luckPct}%`;

        if (uniqueWeatherKeys.length > 1) {
            text.textContent = `${uniqueWeatherKeys.length} active weather effects (${luckMod} Luck)`;
        } else {
            text.textContent = baseWeather.luck !== 1 ? `${baseWeather.name} (${luckMod} Luck)` : baseWeather.name;
        }

        if (totalLuck > 1.2) badge.style.borderColor = '#22c55e';
        else if (totalLuck < 1) badge.style.borderColor = 'var(--danger)';
        else if (totalLuck > 1) badge.style.borderColor = 'var(--accent)';
        else badge.style.borderColor = 'var(--border)';
    }

    floatText(msg) {
        this.floatTextStyled(msg, '#f59e0b');
    }

    clearFloatingText() {
        document.querySelectorAll('.floating-text-notification').forEach((el) => {
            el.remove();
        });
    }

    floatTextStyled(msg, color = '#f59e0b') {
        if (this.game.state?.settings?.floatingText === false) {
            return;
        }

        const container = document.querySelector('.action-area') || document.body;
        const el = document.createElement('div');
        el.className = 'floating-text-notification';
        el.textContent = msg;

        Object.assign(el.style, {
            position: 'absolute',
            left: '50%',
            top: '40%',
            transform: 'translateX(-50%)',
            fontSize: '1.2rem',
            fontWeight: '800',
            color,
            textShadow: '0 2px 8px rgba(0,0,0,0.24)',
            pointerEvents: 'none',
            zIndex: '100',
            transition: 'all 1.4s ease-out',
            opacity: '1'
        });

        if (!container.style.position) {
            container.style.position = 'relative';
        }

        container.appendChild(el);

        requestAnimationFrame(() => {
            el.style.top = '12%';
            el.style.opacity = '0';
        });

        setTimeout(() => el.remove(), 1500);
    }
}





